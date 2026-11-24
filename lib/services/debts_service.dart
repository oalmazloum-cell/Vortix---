import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'audit_service.dart';
import 'cash_service.dart';
import 'session.dart';

/// الزبائن والموردون ودفتر الديون.
class DebtsService {
  DebtsService._();

  static AppDb get _db => AppDb.I;

  // ------------------------------------------------------------ الزبائن

  static Future<List<Customer>> customers({String? search}) async {
    final s = search?.trim() ?? '';
    final rows = await _db.query(
        'SELECT * FROM customers WHERE deleted = 0 ${s.isEmpty ? '' : 'AND (name LIKE ? OR phone LIKE ?)'} ORDER BY name',
        s.isEmpty ? [] : ['%$s%', '%$s%']);
    return rows.map(Customer.fromRow).toList();
  }

  static Future<Customer?> customer(String id) async {
    final r = await _db.first('SELECT * FROM customers WHERE id = ?', [id]);
    return r == null ? null : Customer.fromRow(r);
  }

  static Future<Customer> saveCustomer(Customer c, {bool isNew = false, double openingDebt = 0}) async {
    final due = await defaultDueDate();
    await _db.tx((t) async {
      await _db.put(
          'customers',
          {
            'id': c.id,
            'name': c.name.trim(),
            'phone': c.phone,
            'whatsapp': c.whatsapp,
            'note': c.note,
            'credit_limit': c.creditLimit,
            'created_at': nowMs(),
            'deleted': 0,
          },
          tx: t);
      if (isNew && openingDebt > 0) {
        await addEntry(t,
            partyType: 'customer',
            partyId: c.id,
            kind: 'opening',
            debit: openingDebt,
            dueDate: due,
            note: 'رصيد افتتاحي');
      }
      await AuditService.log(isNew ? 'إضافة زبون' : 'تعديل زبون', entity: 'customer', entityId: c.id, details: c.name, tx: t);
    });
    return c;
  }

  static Future<void> deleteCustomer(Customer c) async {
    await _db.patch('customers', c.id, {'deleted': 1});
    await AuditService.log('حذف زبون', entity: 'customer', entityId: c.id, details: c.name);
  }

  // ------------------------------------------------------------ الموردون

  static Future<List<Supplier>> suppliers() async {
    final rows = await _db.query('SELECT * FROM suppliers WHERE deleted = 0 ORDER BY name');
    return rows.map(Supplier.fromRow).toList();
  }

  static Future<void> saveSupplier(Supplier s, {bool isNew = false}) async {
    await _db.put('suppliers', {
      'id': s.id,
      'name': s.name.trim(),
      'phone': s.phone,
      'note': s.note,
      'created_at': nowMs(),
      'deleted': 0,
    });
    await AuditService.log(isNew ? 'إضافة مورد' : 'تعديل مورد', entity: 'supplier', entityId: s.id, details: s.name);
  }

  // ------------------------------------------------------------ الدفتر

  static Future<int> defaultDueDate() async {
    final days = int.tryParse(await _db.getSetting('default_due_days') ?? '30') ?? 30;
    return DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch;
  }

  static Future<void> addEntry(
    DatabaseExecutor t, {
    required String partyType,
    required String partyId,
    required String kind,
    double debit = 0,
    double credit = 0,
    String? refId,
    int? dueDate,
    String? note,
    String? currency,
    double rate = 1,
    String? shiftId,
  }) async {
    await _db.put(
        'ledger',
        {
          'id': newId(),
          'party_type': partyType,
          'party_id': partyId,
          'created_at': nowMs(),
          'kind': kind,
          'ref_id': refId,
          'debit': debit,
          'credit': credit,
          'due_date': dueDate,
          'currency': currency,
          'rate': rate,
          'note': note,
          'user_id': Session.user?.id,
          'user_name': Session.user?.name,
          'shift_id': shiftId,
        },
        tx: t);
  }

  static Future<List<LedgerEntry>> entries(String partyType, String partyId) async {
    final rows = await _db.query(
        'SELECT * FROM ledger WHERE party_type = ? AND party_id = ? ORDER BY created_at', [partyType, partyId]);
    return rows.map(LedgerEntry.fromRow).toList();
  }

  /// رصيد الطرف والمبلغ المتأخر (طريقة الوارد أولاً يُسدد أولاً FIFO).
  static Future<PartyBalance> balance(String partyType, String partyId) async {
    final list = await entries(partyType, partyId);
    return computeBalance(list, isSupplier: partyType == 'supplier');
  }

  static PartyBalance computeBalance(List<LedgerEntry> list, {bool isSupplier = false, DateTime? now}) {
    final today = now ?? DateTime.now();
    // للمورد نعكس: الدائن (علينا) هو الدين.
    double owe(LedgerEntry e) => isSupplier ? e.credit : e.debit;
    double pay(LedgerEntry e) => isSupplier ? e.debit : e.credit;

    var paid = list.fold<double>(0, (s, e) => s + pay(e));
    final debts = list.where((e) => owe(e) > 0).toList()
      ..sort((a, b) => (a.dueDate ?? a.createdAt).compareTo(b.dueDate ?? b.createdAt));
    final total = list.fold<double>(0, (s, e) => s + owe(e));
    var overdue = 0.0;
    DateTime? oldest;
    for (final d in debts) {
      var amount = owe(d);
      final covered = paid >= amount ? amount : paid;
      paid -= covered;
      amount -= covered;
      if (amount > 0.009 && d.dueDate != null && d.dueDate!.isBefore(today)) {
        overdue += amount;
        oldest ??= d.dueDate;
      }
    }
    return PartyBalance(balance: Fmt.round2(total - list.fold<double>(0, (s, e) => s + pay(e))), overdue: Fmt.round2(overdue), oldestDue: oldest);
  }

  /// قائمة الزبائن مع أرصدتهم (للشاشة والتنبيهات).
  static Future<List<(Customer, PartyBalance)>> customersWithBalances({String? search, bool onlyDebtors = false}) async {
    final list = await customers(search: search);
    final rows = await _db.query("SELECT * FROM ledger WHERE party_type = 'customer' ORDER BY created_at");
    final byParty = <String, List<LedgerEntry>>{};
    for (final r in rows) {
      byParty.putIfAbsent('${r['party_id']}', () => []).add(LedgerEntry.fromRow(r));
    }
    final out = <(Customer, PartyBalance)>[];
    for (final c in list) {
      final b = computeBalance(byParty[c.id] ?? []);
      if (onlyDebtors && b.balance <= 0.009) continue;
      out.add((c, b));
    }
    out.sort((a, b) {
      final o = b.$2.overdue.compareTo(a.$2.overdue);
      return o != 0 ? o : b.$2.balance.compareTo(a.$2.balance);
    });
    return out;
  }

  static Future<List<(Supplier, PartyBalance)>> suppliersWithBalances() async {
    final list = await suppliers();
    final out = <(Supplier, PartyBalance)>[];
    for (final s in list) {
      out.add((s, await balance('supplier', s.id)));
    }
    return out;
  }

  static Future<({double total, double overdue, int overdueCount})> totals() async {
    final list = await customersWithBalances(onlyDebtors: true);
    var total = 0.0, overdue = 0.0, count = 0;
    for (final (_, b) in list) {
      total += b.balance;
      overdue += b.overdue;
      if (b.isOverdue) count++;
    }
    return (total: total, overdue: overdue, overdueCount: count);
  }

  /// تسجيل دفعة من زبون (تدخل الصندوق).
  static Future<void> receivePayment(Customer c, double amountBase, {String? note, String currency = 'ILS', double rate = 1}) async {
    if (amountBase <= 0) return;
    final shift = await CashService.currentShift();
    await _db.tx((t) async {
      await addEntry(t,
          partyType: 'customer',
          partyId: c.id,
          kind: 'payment',
          credit: amountBase,
          note: note,
          currency: currency,
          rate: rate,
          shiftId: shift?.id);
      await AuditService.log('استلام دفعة', entity: 'customer', entityId: c.id,
          details: '${c.name}: ${Fmt.money(amountBase)}${note == null ? '' : ' ($note)'}', tx: t);
    });
  }

  /// تسجيل دين يدوي على زبون (مثلاً دين قديم).
  static Future<void> addManualDebt(Customer c, double amountBase, {String? note, int? dueDate}) async {
    final due = dueDate ?? await defaultDueDate();
    await _db.tx((t) async {
      await addEntry(t,
          partyType: 'customer',
          partyId: c.id,
          kind: 'adjust',
          debit: amountBase,
          dueDate: due,
          note: note);
      await AuditService.log('تسجيل دين يدوي', entity: 'customer', entityId: c.id,
          details: '${c.name}: ${Fmt.money(amountBase)}', tx: t);
    });
  }

  /// دفعة لمورد (تخرج من الصندوق).
  static Future<void> paySupplier(Supplier s, double amountBase, {String? note}) async {
    if (amountBase <= 0) return;
    final shift = await CashService.currentShift();
    await _db.tx((t) async {
      await addEntry(t, partyType: 'supplier', partyId: s.id, kind: 'payment', debit: amountBase, note: note, shiftId: shift?.id);
      await AuditService.log('دفعة لمورد', entity: 'supplier', entityId: s.id,
          details: '${s.name}: ${Fmt.money(amountBase)}', tx: t);
    });
  }
}
