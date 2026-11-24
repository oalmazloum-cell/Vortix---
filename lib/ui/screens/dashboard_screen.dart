import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/debts_service.dart';
import '../../services/inventory_service.dart';
import '../../services/report_service.dart';
import '../../services/session.dart';
import '../../state/app_state.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'alerts_screen.dart';
import 'cash_screen.dart';
import 'sales_history_screen.dart';
import 'shell.dart';

class _DashData {
  _DashData(this.today, this.debts, this.low, this.expiring, this.week);
  final PeriodSummary today;
  final ({double total, double overdue, int overdueCount}) debts;
  final int low;
  final int expiring;
  final List<DayPoint> week;
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<_DashData> _load() async => _DashData(
        await ReportService.today(),
        await DebtsService.totals(),
        (await InventoryService.lowStock()).length,
        (await InventoryService.expiring()).length,
        await ReportService.daily(7),
      );

  @override
  Widget build(BuildContext context) {
    final canProfit = Session.can(Perm.viewProfits);
    return DataBuilder<_DashData>(
      load: _load,
      builder: (context, d) {
        final alerts = d.low + d.expiring + d.debts.overdueCount;
        return RefreshIndicator(
          onRefresh: () async => AppState.I.bump(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('أهلاً ${Session.user?.name ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('ملخص اليوم', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              TwoColumnGrid(
                columns: 2,
                spacing: 12,
                children: [
                  StatCard(
                    title: 'مبيعات اليوم',
                    value: money(d.today.netSales),
                    icon: Icons.trending_up_rounded,
                    color: VColors.emerald,
                    subtitle: '${d.today.invoices} فاتورة',
                    onTap: () => Shell.open(context, const SalesHistoryScreen()),
                  ),
                  StatCard(
                    title: 'صافي الربح',
                    value: canProfit ? money(d.today.netProfit) : '••••',
                    icon: Icons.savings_outlined,
                    color: canProfit && d.today.netProfit < 0 ? VColors.coral : VColors.emerald,
                    subtitle: canProfit ? (d.today.netProfit < 0 ? 'خسارة بعد المصاريف' : 'بعد المصاريف') : 'محمي برمز المالك',
                    onTap: canProfit ? null : () => requireOwner(context, reason: 'عرض الأرباح يحتاج رمز المالك'),
                  ),
                  StatCard(
                    title: 'ديون الزبائن',
                    value: money(d.debts.total),
                    icon: Icons.account_balance_outlined,
                    onTap: () => ShellState.of(context)?.goTab(3),
                  ),
                  StatCard(
                    title: d.debts.overdueCount > 0 ? 'ديون متأخرة' : 'الديون المتأخرة',
                    value: d.debts.overdueCount > 0 ? money(d.debts.overdue) : 'لا يوجد',
                    icon: Icons.warning_amber_rounded,
                    color: d.debts.overdueCount > 0 ? VColors.coral : null,
                    subtitle: d.debts.overdueCount > 0 ? '${d.debts.overdueCount} زبون' : null,
                    onTap: () => ShellState.of(context)?.goTab(3),
                  ),
                ],
              ),
              if (alerts > 0) ...[
                const SizedBox(height: 12),
                VCard(
                  onTap: () => Shell.open(context, const AlertsScreen()),
                  color: VColors.coral.withValues(alpha: 0.08),
                  child: Row(children: [
                    const Icon(Icons.notifications_active_outlined, color: VColors.coral),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [
                          if (d.low > 0) '${d.low} صنف ناقص',
                          if (d.expiring > 0) '${d.expiring} قارب على الانتهاء',
                          if (d.debts.overdueCount > 0) '${d.debts.overdueCount} دين متأخر',
                        ].join(' • '),
                        style: const TextStyle(color: VColors.coral, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.chevron_left, color: VColors.coral),
                  ]),
                ),
              ],
              const SectionTitle('وصول سريع'),
              TwoColumnGrid(
                columns: 4,
                spacing: 10,
                children: [
                  _Quick(Icons.point_of_sale, 'البيع', VColors.blue, () => ShellState.of(context)?.goTab(1)),
                  _Quick(Icons.inventory_2_outlined, 'الأصناف', VColors.navy, () => ShellState.of(context)?.goTab(2)),
                  _Quick(Icons.people_alt_outlined, 'الديون', VColors.navy, () => ShellState.of(context)?.goTab(3)),
                  _Quick(Icons.receipt_long_outlined, 'سجل المبيعات', VColors.navy,
                      () => Shell.open(context, const SalesHistoryScreen())),
                ],
              ),
              const SectionTitle('مبيعات آخر 7 أيام'),
              VCard(
                child: SizedBox(height: 190, child: SalesBarChart(points: d.week, showProfit: canProfit)),
              ),
              const SizedBox(height: 12),
              VCard(
                onTap: () => Shell.open(context, const CashScreen()),
                child: const Row(children: [
                  Icon(Icons.account_balance_wallet_outlined, color: VColors.blue),
                  SizedBox(width: 10),
                  Expanded(child: Text('الصندوق اليومي — فتح وإقفال الوردية', style: TextStyle(fontWeight: FontWeight.w600))),
                  Icon(Icons.chevron_left),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => VCard(
        onTap: onTap,
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}
