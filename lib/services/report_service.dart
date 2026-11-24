import '../core/format.dart';
import '../data/db.dart';

class DayPoint {
  DayPoint(this.day, this.sales, this.profit);
  final DateTime day;
  final double sales;
  final double profit;
}

class ItemStat {
  ItemStat(this.itemId, this.name, this.qty, this.revenue, this.profit);
  final String? itemId;
  final String name;
  final double qty;
  final double revenue;
  final double profit;
}

class PeriodSummary {
  PeriodSummary({
    required this.sales,
    required this.returns,
    required this.cost,
    required this.returnsCost,
    required this.expenses,
    required this.invoices,
    required this.discounts,
    required this.creditSales,
  });

  final double sales;
  final double returns;
  final double cost;
  final double returnsCost;
  final double expenses;
  final int invoices;
  final double discounts;
  final double creditSales;

  double get netSales => sales - returns;
  double get grossProfit => netSales - (cost - returnsCost);
  double get netProfit => grossProfit - expenses;
  double get avgInvoice => invoices == 0 ? 0 : sales / invoices;
}

/// التقارير ولوحة التحكم.
class ReportService {
  ReportService._();

  static AppDb get _db => AppDb.I;

  static Future<PeriodSummary> summary(int from, int to) async {
    Future<double> s(String sql) => _db.scalar(sql, [from, to]);
    final invoices = await s("SELECT COUNT(*) FROM sales WHERE kind = 'sale' AND created_at BETWEEN ? AND ?");
    return PeriodSummary(
      sales: await s("SELECT COALESCE(SUM(total),0) FROM sales WHERE kind = 'sale' AND created_at BETWEEN ? AND ?"),
      returns: await s("SELECT COALESCE(SUM(total),0) FROM sales WHERE kind = 'return' AND created_at BETWEEN ? AND ?"),
      cost: await s("SELECT COALESCE(SUM(cost),0) FROM sales WHERE kind = 'sale' AND created_at BETWEEN ? AND ?"),
      returnsCost: await s("SELECT COALESCE(SUM(cost),0) FROM sales WHERE kind = 'return' AND created_at BETWEEN ? AND ?"),
      expenses: await s('SELECT COALESCE(SUM(amount),0) FROM expenses WHERE created_at BETWEEN ? AND ?'),
      invoices: invoices.toInt(),
      discounts: await s("SELECT COALESCE(SUM(discount),0) FROM sales WHERE kind = 'sale' AND created_at BETWEEN ? AND ?"),
      creditSales:
          await s("SELECT COALESCE(SUM(total - paid),0) FROM sales WHERE kind = 'sale' AND created_at BETWEEN ? AND ?"),
    );
  }

  static Future<PeriodSummary> today() {
    final n = DateTime.now();
    return summary(startOfDay(n), endOfDay(n));
  }

  /// سلسلة يومية للمبيعات والربح (الربح قبل المصاريف).
  static Future<List<DayPoint>> daily(int days) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final rows = await _db.query('''
      SELECT created_at, kind, total, cost FROM sales WHERE created_at >= ?''', [start.millisecondsSinceEpoch]);
    final map = <int, List<double>>{};
    for (var i = 0; i < days; i++) {
      map[i] = [0, 0];
    }
    for (final r in rows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int);
      final idx = DateTime(d.year, d.month, d.day).difference(start).inDays;
      if (!map.containsKey(idx)) continue;
      final sign = r['kind'] == 'return' ? -1 : 1;
      final total = (r['total'] as num).toDouble();
      final cost = (r['cost'] as num).toDouble();
      map[idx]![0] += sign * total;
      map[idx]![1] += sign * (total - cost);
    }
    return [
      for (var i = 0; i < days; i++) DayPoint(start.add(Duration(days: i)), Fmt.round2(map[i]![0]), Fmt.round2(map[i]![1])),
    ];
  }

  /// الأصناف الأكثر مبيعاً أو ربحاً.
  static Future<List<ItemStat>> topItems(int from, int to, {bool byProfit = false, int limit = 10}) async {
    final rows = await _db.query('''
      SELECT l.item_id, l.name,
        SUM(CASE WHEN s.kind = 'return' THEN -l.qty * l.factor ELSE l.qty * l.factor END) AS q,
        SUM(CASE WHEN s.kind = 'return' THEN -l.total ELSE l.total END) * 1.0 AS rev,
        SUM(CASE WHEN s.kind = 'return' THEN -(l.total - l.cost * l.qty) ELSE (l.total - l.cost * l.qty) END) AS pr
      FROM sale_lines l JOIN sales s ON s.id = l.sale_id
      WHERE s.created_at BETWEEN ? AND ?
      GROUP BY l.item_id ORDER BY ${byProfit ? 'pr' : 'q'} DESC LIMIT ?''', [from, to, limit]);
    return rows
        .map((r) => ItemStat(r['item_id'] as String?, '${r['name']}', (r['q'] as num?)?.toDouble() ?? 0,
            (r['rev'] as num?)?.toDouble() ?? 0, (r['pr'] as num?)?.toDouble() ?? 0))
        .toList();
  }

  /// الأصناف الراكدة: في المخزون ولم تُبع خلال [days] يوماً.
  static Future<List<Map<String, Object?>>> slowItems({int days = 30, int limit = 20}) {
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return _db.query('''
      SELECT i.id, i.name, i.qty, i.cost, i.unit FROM items i
      WHERE i.deleted = 0 AND i.track_stock = 1 AND i.qty > 0 AND i.id NOT IN (
        SELECT DISTINCT l.item_id FROM sale_lines l JOIN sales s ON s.id = l.sale_id
        WHERE s.kind = 'sale' AND s.created_at >= ? AND l.item_id IS NOT NULL)
      ORDER BY i.qty * i.cost DESC LIMIT ?''', [since, limit]);
  }

  static Future<Map<String, double>> expensesByCategory(int from, int to) async {
    final rows = await _db.query(
        'SELECT category, SUM(amount) AS a FROM expenses WHERE created_at BETWEEN ? AND ? GROUP BY category ORDER BY a DESC',
        [from, to]);
    return {for (final r in rows) '${r['category']}': (r['a'] as num).toDouble()};
  }

  static Future<List<Map<String, Object?>>> salesByUser(int from, int to) => _db.query('''
      SELECT COALESCE(user_name, '-') AS user_name,
        SUM(CASE WHEN kind = 'sale' THEN total ELSE -total END) AS total, COUNT(*) AS n
      FROM sales WHERE created_at BETWEEN ? AND ? GROUP BY user_name ORDER BY total DESC''', [from, to]);
}
