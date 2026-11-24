import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../services/currency_service.dart';
import '../services/session.dart';
import '../services/subscription_service.dart';
import '../services/sync_service.dart';

/// الحالة العامة للتطبيق. [version] يزيد بعد كل تعديل فتُعاد قراءة الشاشات.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  int version = 0;
  ThemeMode themeMode = ThemeMode.light;
  SubStatus? sub;

  Future<void> load() async {
    final t = await AppDb.I.getSetting('theme');
    themeMode = t == 'dark' ? ThemeMode.dark : (t == 'system' ? ThemeMode.system : ThemeMode.light);
    await Session.loadShop();
    await CurrencyService.load();
    sub = await SubscriptionService.status();
    notifyListeners();
  }

  /// يُستدعى بعد أي تعديل على البيانات.
  void bump() {
    version++;
    notifyListeners();
    SyncService.schedule();
  }

  Future<void> refreshSub() async {
    sub = await SubscriptionService.status();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await AppDb.I.setSetting('theme', m == ThemeMode.dark ? 'dark' : (m == ThemeMode.system ? 'system' : 'light'),
        sync: false);
    notifyListeners();
  }

  Future<void> reloadAll() async {
    await load();
    bump();
  }
}
