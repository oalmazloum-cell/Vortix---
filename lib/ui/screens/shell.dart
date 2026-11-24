import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/backup_service.dart';
import '../../services/device_services.dart';
import '../../services/session.dart';
import '../../services/subscription_service.dart';
import '../../services/sync_service.dart';
import '../../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'alerts_screen.dart';
import 'audit_screen.dart';
import 'cash_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'items_screen.dart';
import 'lock_screen.dart';
import 'pos_screen.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'sales_history_screen.dart';
import 'settings_screen.dart';
import 'stock_count_screen.dart';
import 'subscription_screen.dart';
import 'workers_screen.dart';

/// الهيكل الرئيسي: هيدر كحلي + قائمة جانبية + تنقل سفلي.
class Shell extends StatefulWidget {
  const Shell({super.key});

  static void open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;

  static ShellState? of(BuildContext context) => context.findAncestorStateOfType<ShellState>();

  void goTab(int i) => setState(() => _tab = i);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _background();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _background();
  }

  /// مهام الخلفية: نسخة احتياطية يومية، إشعارات، مزامنة، حالة الاشتراك.
  Future<void> _background() async {
    // كل مهمة مستقلة: فشل إحداها لا يوقف الباقي ولا يعطل التطبيق.
    for (final task in <Future<void> Function()>[
      AppState.I.refreshSub,
      () async => BackupService.autoBackupIfDue(),
      NotificationService.checkAndNotify,
      SyncService.syncNow,
    ]) {
      try {
        await task();
      } catch (e) {
        debugPrint('background task failed: $e');
      }
    }
  }

  Future<void> _switchUser() async {
    await Session.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LockScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<AppState>().sub;
    final pages = [
      const DashboardScreen(),
      const PosScreen(),
      const ItemsScreen(),
      const CustomersScreen(),
    ];
    const titles = ['لوحة التحكم', 'نقطة البيع', 'الأصناف والمخزون', 'الزبائن والديون'];
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? (Session.shop?.name ?? 'فورتكس') : titles[_tab]),
        actions: [
          if (sub != null) _TrialBadge(sub),
          const _SyncIcon(),
        ],
      ),
      drawer: _drawer(context),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: goTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'البيع'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'الأصناف'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'الديون'),
        ],
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    final u = Session.user;
    Widget item(IconData icon, String title, VoidCallback onTap, {bool show = true}) => !show
        ? const SizedBox.shrink()
        : ListTile(
            leading: Icon(icon, color: Colors.white70),
            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              onTap();
            },
          );
    void open(Widget w) => Shell.open(context, w);
    return Drawer(
      child: SafeArea(
        child: ListView(padding: EdgeInsets.zero, children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const VortexLogo(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Session.shop?.name ?? '', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  Text('${u?.name ?? ''} • ${u?.isOwner == true ? 'المالك' : 'وضع العامل'}',
                      style: const TextStyle(color: Colors.white60, fontSize: 13)),
                ]),
              ),
            ]),
          ),
          const Divider(color: Colors.white12),
          item(Icons.dashboard_outlined, 'لوحة التحكم', () => goTab(0)),
          item(Icons.point_of_sale_outlined, 'نقطة البيع', () => goTab(1)),
          item(Icons.receipt_long_outlined, 'سجل المبيعات والمرتجعات', () => open(const SalesHistoryScreen())),
          item(Icons.inventory_2_outlined, 'الأصناف والمخزون', () => goTab(2)),
          item(Icons.fact_check_outlined, 'الجرد السريع بالباركود', () => open(const StockCountScreen()),
              show: Session.can(Perm.stockCount)),
          item(Icons.local_shipping_outlined, 'المشتريات والموردون', () => open(const PurchasesScreen()),
              show: Session.can(Perm.purchases)),
          item(Icons.people_alt_outlined, 'الزبائن والديون', () => goTab(3)),
          item(Icons.account_balance_wallet_outlined, 'الصندوق اليومي والمصاريف', () => open(const CashScreen())),
          item(Icons.notifications_active_outlined, 'التنبيهات', () => open(const AlertsScreen())),
          item(Icons.insights_outlined, 'التقارير والرسوم البيانية', () async {
            if (Session.can(Perm.viewReports) || await requireOwner(context, reason: 'التقارير تحتاج رمز المالك')) {
              if (context.mounted) open(const ReportsScreen());
            }
          }),
          const Divider(color: Colors.white12),
          item(Icons.groups_2_outlined, 'العمال والصلاحيات', () => open(const WorkersScreen()), show: Session.isOwner),
          item(Icons.history_edu_outlined, 'سجل العمليات', () => open(const AuditScreen()), show: Session.isOwner),
          item(Icons.workspace_premium_outlined, 'الاشتراك', () => open(const SubscriptionScreen())),
          item(Icons.settings_outlined, 'الإعدادات والنسخ الاحتياطي', () => open(const SettingsScreen())),
          item(Icons.switch_account_outlined, 'تبديل المستخدم / قفل', _switchUser),
        ]),
      ),
    );
  }
}

class _TrialBadge extends StatelessWidget {
  const _TrialBadge(this.sub);
  final SubStatus sub;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (sub.state) {
      SubState.trial => ('تجربة: ${sub.daysLeft} ${sub.daysLeft <= 2 && sub.daysLeft != 0 ? (sub.daysLeft == 1 ? 'يوم' : 'يومان') : 'أيام'}', VColors.blueBright),
      SubState.active => ('مفعّل', VColors.emerald),
      SubState.expired => ('انتهت التجربة', VColors.coral),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Shell.open(context, const SubscriptionScreen()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              if (sub.state != SubState.active) ...[
                const SizedBox(width: 6),
                const Text('تفعيل', style: TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.underline)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _SyncIcon extends StatelessWidget {
  const _SyncIcon();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncState>(
        valueListenable: SyncService.state,
        builder: (c, s, _) {
          final (icon, tip) = switch (s) {
            SyncState.disabled => (Icons.phone_android, 'يعمل محلياً'),
            SyncState.idle => (Icons.cloud_done_outlined, 'متزامن'),
            SyncState.syncing => (Icons.cloud_sync_outlined, 'جاري المزامنة'),
            SyncState.offline => (Icons.cloud_off_outlined, 'بدون إنترنت — البيانات محفوظة على الجهاز'),
            SyncState.error => (Icons.sync_problem_outlined, 'تعذرت المزامنة، ستُعاد المحاولة'),
          };
          return IconButton(
            tooltip: tip,
            icon: Icon(icon),
            onPressed: () {
              toast(context, tip);
              SyncService.syncNow();
            },
          );
        },
      );
}
