import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/currency_service.dart';
import '../../services/report_service.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class _ReportData {
  _ReportData(this.summary, this.daily, this.top, this.topProfit, this.slow, this.expenses, this.byUser);
  final PeriodSummary summary;
  final List<DayPoint> daily;
  final List<ItemStat> top;
  final List<ItemStat> topProfit;
  final List<Map<String, Object?>> slow;
  final Map<String, double> expenses;
  final List<Map<String, Object?>> byUser;
}

/// التقارير والرسوم البيانية (محمية برمز المالك أو صلاحية التقارير).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 7;

  Future<_ReportData> _load() async {
    final now = DateTime.now();
    final from = startOfDay(now.subtract(Duration(days: _days - 1)));
    final to = endOfDay(now);
    return _ReportData(
      await ReportService.summary(from, to),
      await ReportService.daily(_days),
      await ReportService.topItems(from, to),
      await ReportService.topItems(from, to, byProfit: true),
      await ReportService.slowItems(days: _days < 30 ? 30 : _days),
      await ReportService.expensesByCategory(from, to),
      await ReportService.salesByUser(from, to),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('اليوم')),
              ButtonSegment(value: 7, label: Text('7 أيام')),
              ButtonSegment(value: 30, label: Text('30 يوم')),
              ButtonSegment(value: 90, label: Text('3 أشهر')),
            ],
            selected: {_days},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
        ),
        Expanded(
          child: DataBuilder<_ReportData>(
            deps: [_days],
            load: _load,
            builder: (c, d) {
              final s = d.summary;
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                TwoColumnGrid(
                  columns: 2,
                  spacing: 10,
                  children: [
                    StatCard(title: 'صافي المبيعات', value: money(s.netSales), icon: Icons.trending_up, color: VColors.emerald),
                    StatCard(title: 'صافي الربح', value: money(s.netProfit), icon: Icons.savings_outlined, color: VColors.emerald),
                    StatCard(title: 'مجمل الربح', value: money(s.grossProfit), icon: Icons.stacked_line_chart),
                    StatCard(title: 'المصاريف', value: money(s.expenses), icon: Icons.receipt_outlined),
                    StatCard(title: 'عدد الفواتير', value: '${s.invoices}', icon: Icons.receipt_long_outlined,
                        subtitle: 'متوسط ${money(s.avgInvoice)}'),
                    StatCard(title: 'المرتجعات', value: money(s.returns), icon: Icons.undo),
                  ],
                ),
                const SizedBox(height: 10),
                VCard(
                  child: Column(children: [
                    KeyValueRow('إجمالي المبيعات', money(s.sales)),
                    KeyValueRow('- المرتجعات', money(s.returns)),
                    KeyValueRow('- تكلفة البضاعة المباعة', money(s.cost - s.returnsCost)),
                    KeyValueRow('= مجمل الربح', money(s.grossProfit), bold: true),
                    KeyValueRow('- المصاريف', money(s.expenses)),
                    KeyValueRow('= صافي الربح', money(s.netProfit), bold: true, color: VColors.emerald),
                    const Divider(),
                    KeyValueRow('الخصومات الممنوحة', money(s.discounts)),
                    KeyValueRow('مبيعات آجلة (دين)', money(s.creditSales)),
                  ]),
                ),
                if (_days > 1) ...[
                  const SectionTitle('المبيعات والربح يومياً'),
                  VCard(child: SizedBox(height: 220, child: SalesBarChart(points: d.daily))),
                ],
                const SectionTitle('الأكثر مبيعاً (بالكمية)'),
                VCard(
                  child: RankBars(
                    rows: [for (final t in d.top) (t.name, t.qty)],
                    format: Fmt.qty,
                  ),
                ),
                const SectionTitle('الأكثر ربحاً'),
                VCard(child: RankBars(rows: [for (final t in d.topProfit) (t.name, t.profit)], color: VColors.emerald)),
                if (d.expenses.isNotEmpty) ...[
                  const SectionTitle('المصاريف حسب البند'),
                  VCard(child: RankBars(rows: [for (final e in d.expenses.entries) (e.key, e.value)], color: VColors.navy)),
                ],
                if (d.byUser.length > 1) ...[
                  const SectionTitle('المبيعات حسب العامل'),
                  VCard(
                    child: RankBars(rows: [
                      for (final u in d.byUser) ('${u['user_name']}', (u['total'] as num?)?.toDouble() ?? 0),
                    ]),
                  ),
                ],
                const SectionTitle('أصناف راكدة (لم تُبع منذ 30 يوماً)'),
                VCard(
                  padding: const EdgeInsets.all(8),
                  child: d.slow.isEmpty
                      ? const Padding(padding: EdgeInsets.all(8), child: Text('لا توجد أصناف راكدة'))
                      : Column(children: [
                          for (final r in d.slow)
                            ListTile(
                              dense: true,
                              title: Text('${r['name']}'),
                              subtitle: Text('الكمية ${Fmt.qty(r['qty'] as num)} ${r['unit']}'),
                              trailing: Text(money((r['qty'] as num).toDouble() * (r['cost'] as num).toDouble())),
                            ),
                        ]),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
