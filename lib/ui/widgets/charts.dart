import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/report_service.dart';

const _weekdays = ['إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'];

/// أعمدة المبيعات (أزرق) والربح (أخضر زمردي) يومياً.
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.points, this.showProfit = true});
  final List<DayPoint> points;
  final bool showProfit;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final grid = Theme.of(context).colorScheme.outline;
    final maxY = points.fold<double>(0, (m, p) => p.sales > m ? p.sales : m);
    if (maxY <= 0) {
      return Center(child: Text('لا توجد مبيعات في هذه الفترة بعد', style: TextStyle(color: muted)));
    }
    final many = points.length > 10;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const _Legend(VColors.blue, 'المبيعات'),
        if (showProfit) ...[const SizedBox(width: 16), const _Legend(VColors.emerald, 'الربح')],
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: BarChart(
            BarChartData(
              maxY: maxY * 1.15,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(color: grid.withValues(alpha: 0.5), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: maxY / 4,
                    getTitlesWidget: (v, m) => Text(_compact(v), style: TextStyle(fontSize: 10, color: muted)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      if (many && i % 5 != 0 && i != points.length - 1) return const SizedBox.shrink();
                      final d = points[i].day;
                      final label = many ? '${d.day}/${d.month}' : _weekdays[d.weekday - 1];
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(label, style: TextStyle(fontSize: 10, color: muted)),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => VColors.navy,
                  getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                    '${ri == 0 ? 'مبيعات' : 'ربح'}: ${Fmt.money(rod.toY)}\n${Fmt.date(points[gi].day)}',
                    const TextStyle(color: Colors.white, fontFamily: VTheme.font, fontSize: 12),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(x: i, barsSpace: 2, barRods: [
                    BarChartRodData(
                      toY: points[i].sales < 0 ? 0 : points[i].sales,
                      color: VColors.blue,
                      width: many ? 5 : 12,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    if (showProfit)
                      BarChartRodData(
                        toY: points[i].profit < 0 ? 0 : points[i].profit,
                        color: VColors.emerald,
                        width: many ? 5 : 12,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  static String _compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}K';
    return v.toStringAsFixed(0);
  }
}

/// أعمدة أفقية لترتيب الأصناف أو المصاريف (لون واحد، القيمة مكتوبة).
class RankBars extends StatelessWidget {
  const RankBars({super.key, required this.rows, this.color = VColors.blue, this.format});
  final List<(String, double)> rows;
  final Color color;
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('لا توجد بيانات', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    final max = rows.fold<double>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(children: [
      for (final (label, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (c, k) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    height: 14,
                    width: max <= 0 ? 0 : (k.maxWidth * (v / max)).clamp(2, k.maxWidth),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(format?.call(v) ?? Fmt.money(v), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}
