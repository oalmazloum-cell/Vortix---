import '../core/format.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'audit_service.dart';
import 'session.dart';

/// الصندوق اليومي (الورديات) والمصاريف.
class CashService {
  CashService._();

  static AppDb get _db => AppDb.I;

  static const expenseCategories = ['إيجار', 'كهرباء', 'ماء', 'رواتب', 'مواصلات', 'إنترنت واتصالات', 'صيانة', 'أخرى'];

  static Future<Shift?> currentShift() async {
    final r = await _db.first('SELECT * FROM shifts WHERE closed_at IS NULL ORDER BY opened_at DESC LIMIT 1');
    return r == null ? null : Shift.fromRow(r);
  }

  static Future<Shift> openShift(double opening) async {
    final id = newId();
    await _db.put('shifts', {
      'id': id,
      'user_id': Session.user?.id,
      'user_name': Session.user?.name,
      'opened_at': nowMs(),
      'opening': opening,
    });
    await AuditService.log('فتح الصندوق', entity: 'shift', entityId: id, details: 'رصيد افتتاحي ${Fmt.money(opening)}');
    return (await currentShift())!;
  }

  /// يضمن وجود وردية مفتوحة (تُفتح تلقائياً برصيد صفر عند أول عملية).
  static Future<Shift> ensureShift() async => await currentShift() ?? await openShift(0);

  static Future<CashSummary> summary(Shift s) async {
    Future<double> sum(String sql) => _db.scalar(sql, [s.id]);
    return CashSummary(
      opening: s.opening,
      cashSales: await sum("SELECT COALESCE(SUM(paid),0) FROM sales WHERE kind = 'sale' AND shift_id = ?"),
      refunds: await sum(
          "SELECT COALESCE(SUM(paid),0) FROM sales WHERE kind = 'return' AND refund_mode = 'cash' AND shift_id = ?"),
      debtCollections: await sum(
          "SELECT COALESCE(SUM(credit),0) FROM ledger WHERE party_type = 'customer' AND kind = 'payment' AND shift_id = ?"),
      purchasesPaid: await sum('SELECT COALESCE(SUM(paid),0) FROM purchases WHERE shift_id = ?'),
      supplierPayments: await sum(
          "SELECT COALESCE(SUM(debit),0) FROM ledger WHERE party_type = 'supplier' AND kind = 'payment' AND shift_id = ?"),
      expenses: await sum('SELECT COALESCE(SUM(amount),0) FROM expenses WHERE shift_id = ?'),
    );
  }

  /// إقفال الصندوق: يحفظ المتوقع والفعلي والفرق.
  static Future<double> closeShift(Shift s, double actual, {String? note}) async {
    final sm = await summary(s);
    final diff = Fmt.round2(actual - sm.expected);
    await _db.patch('shifts', s.id, {
      'closed_at': nowMs(),
      'expected': sm.expected,
      'actual': actual,
      'diff': diff,
      'note': note,
    });
    await AuditService.log('إقفال الصندوق', entity: 'shift', entityId: s.id,
        details: 'المتوقع ${Fmt.money(sm.expected)} • الفعلي ${Fmt.money(actual)} • الفرق ${Fmt.money(diff)}');
    return diff;
  }

  static Future<List<Shift>> history({int limit = 60}) async {
    final rows = await _db.query('SELECT * FROM shifts ORDER BY opened_at DESC LIMIT $limit');
    return rows.map(Shift.fromRow).toList();
  }

  // ------------------------------------------------------------ المصاريف

  static Future<void> addExpense(String category, double amount, {String? note}) async {
    final shift = await ensureShift();
    final id = newId();
    await _db.put('expenses', {
      'id': id,
      'created_at': nowMs(),
      'category': category,
      'amount': amount,
      'note': note,
      'user_id': Session.user?.id,
      'user_name': Session.user?.name,
      'shift_id': shift.id,
    });
    await AuditService.log('تسجيل مصروف', entity: 'expense', entityId: id, details: '$category: ${Fmt.money(amount)}');
  }

  static Future<List<Map<String, Object?>>> expenses({required int from, required int to}) =>
      _db.query('SELECT * FROM expenses WHERE created_at BETWEEN ? AND ? ORDER BY created_at DESC', [from, to]);
}
