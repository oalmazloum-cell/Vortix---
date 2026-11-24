import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/db.dart';
import 'platform/web_setup.dart';
import 'services/audit_service.dart';
import 'services/device_services.dart';
import 'services/sync_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  }
  configurePlatform();
  AppDb.onOpen = AuditService.resetCache;
  await AppDb.open();
  await SyncService.init();
  await NotificationService.init();
  await AppState.I.load();
  runApp(ChangeNotifierProvider.value(value: AppState.I, child: const VortexApp()));
}
