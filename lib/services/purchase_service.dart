import '../core/format.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'audit_service.dart';
import 'cash_service.dart';
import 'debts_service.dart';
import 'inventory_service.dart';
import 'session.dart';

/// فواتير الشراء من الموردين: تزيد المخزون وتحدّث متوسط التكلفة.
class PurchaseService {
  PurchaseService._();

  static AppDb get _db => AppDb.I;

  /// متوسط التكلفة المرجّح.
  static double weightedCost({required double oldQty, required double oldCost, required double inQty, required double inCost}) {
    if (inQty <= 0) return oldCost;
    final q = oldQty < 0 ? 0.0 : oldQty;
    if (q + inQty == 0) return inCost;
    return (q * oldCost + inQty * inCost) / (q + inQty);
  }

  static Future<String> save({
    required List<PurchaseLine> lines,
    Supplier? supplier,
    required String currency,
    required double rate,
    required double paid,
    String? note,
    bool updateRetail = false,
  }) async {
    if (lines.isEmpty) throw Exception('أضف أصنافاً للفاتورة');
    final total = Fmt.round2(lines.fold(0.0, (s, l) => s + l.total));
    final paidC = Fmt.round2(paid.clamp(0, total).toDouble());
    if (paidC < total && supplier == null) throw Exception('اختر المورد لتسجيل الباقي ديناً عليك');
    final shift = await CashService.ensureShift();
    final id = newId();
    await _db.tx((t) async {
      final number = await _db.nextNumber('purchase', tx: t);
      await _db.put(
          'purchases',
          {
            'id': id,
            'number': number,
            'created_at': nowMs(),
            'supplier_id': supplier?.id,
            'supplier_name': supplier?.name,
            'currency': currency,
            'rate': rate,
            'total': total,
            'paid': paidC,
            'user_id': Session.user?.id,
            'user_name': Session.user?.name,
            'shift_id': shift.id,
            'note': note,
          },
          tx: t);
      for (final l in lines) {
        final baseQty = l.qty * l.factor;
        final unitCostBase = l.factor == 0 ? l.cost : l.cost / l.factor;
        final fresh = await t.query('items', where: 'id = ?', whereArgs: [l.item.id]);
        final oldQty = (fresh.first['qty'] as num).toDouble();
        final oldCost = (fresh.first['cost'] as num).toDouble();
        final newCost = weightedCost(oldQty: oldQty, oldCost: oldCost, inQty: baseQty, inCost: unitCostBase);
        final upd = <String, Object?>{'cost': Fmt.round2(newCost * 1000) / 1000};
        if (l.expiry != null) upd['expiry'] = l.expiry!.millisecondsSinceEpoch;
        await t.update('items', upd, where: 'id = ?', whereArgs: [l.item.id]);
        await _db.put(
            'purchase_lines',
            {
              'id': newId(),
              'purchase_id': id,
              'item_id': l.item.id,
              'name': l.item.name,
              'unit_name': l.unitName,
              'factor': l.factor,
              'qty': l.qty,
              'cost': l.cost,
              'total': Fmt.round2(l.total),
              'expiry': l.expiry?.millisecondsSinceEpoch,
            },
            tx: t);
        await InventoryService.move(t, l.item.id, baseQty, 'purchase', ref: id);
      }
      if (supplier != null && paidC < total) {
        await DebtsService.addEntry(t,
            partyType: 'supplier',
            partyId: supplier.id,
            kind: 'purchase',
            refId: id,
            credit: Fmt.round2(total - paidC),
            note: 'فاتورة شراء #$number',
            shiftId: shift.id);
      }
      await AuditService.log('فاتورة شراء', entity: 'purchase', entityId: id,
          details: '#$number • ${supplier?.name ?? 'بدون مورد'} • ${Fmt.money(total)} • مدفوع ${Fmt.money(paidC)}', tx: t);
    });
    return id;
  }

  static Future<List<Map<String, Object?>>> list({int limit = 100}) =>
      _db.query('SELECT * FROM purchases ORDER BY created_at DESC LIMIT $limit');

  static Future<List<Map<String, Object?>>> lines(String purchaseId) =>
      _db.query('SELECT * FROM purchase_lines WHERE purchase_id = ?', [purchaseId]);
}
