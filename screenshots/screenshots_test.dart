// توليد لقطات شاشة حقيقية للتطبيق (بالخط العربي والأيقونات).
// التشغيل:
//   flutter test screenshots/screenshots_test.dart --update-goldens
// تُحفظ الصور في screenshots/out/
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vortex/data/db.dart';
import 'package:vortex/data/models.dart';
import 'package:vortex/services/audit_service.dart';
import 'package:vortex/services/session.dart';
import 'package:vortex/state/app_state.dart';
import 'package:vortex/ui/screens/customers_screen.dart';
import 'package:vortex/ui/screens/item_editor_screen.dart';
import 'package:vortex/ui/screens/reports_screen.dart';
import 'package:vortex/ui/screens/shell.dart';
import 'package:vortex/ui/screens/welcome_screen.dart';

import '../test/ui_smoke_test.dart' show seed, wrap;

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(File(f).readAsBytesSync()).buffer)));
  }
  await loader.load();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDb.onOpen = AuditService.resetCache;

  setUpAll(() async {
    await _font('Plex', [
      'assets/fonts/IBMPlexSansArabic-Regular.ttf',
      'assets/fonts/IBMPlexSansArabic-Medium.ttf',
      'assets/fonts/IBMPlexSansArabic-Bold.ttf',
    ]);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/home/user/tools/flutter';
    await _font('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    await seed();
  });

  Future<void> shot(WidgetTester t, String name, Widget w, {bool dark = false, Future<void> Function()? act}) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    Session.user ??= await t.runAsync<AppUser?>(Session.owner);
    await t.runAsync(() async {
      await t.pumpWidget(ChangeNotifierProvider.value(
          value: AppState.I, child: RepaintBoundary(key: const ValueKey('shot'), child: wrap(w, dark: dark))));
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await t.pump();
      }
      if (act != null) {
        await act();
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await t.pump();
        }
      }
    });
    await t.pump(const Duration(milliseconds: 500));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/$name.png'));
  }

  testWidgets('01-welcome', (t) => shot(t, '01-welcome', const WelcomeScreen()));
  testWidgets('02-dashboard', (t) => shot(t, '02-dashboard', const Shell()));
  testWidgets('03-pos', (t) => shot(t, '03-pos', const Shell(), act: () async {
        await t.tap(find.text('البيع').last);
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await t.pump();
        await t.tap(find.text('سكر أبيض 1كغ').first);
        await t.tap(find.text('أرز بسمتي').first);
        await t.tap(find.text('أرز بسمتي').first);
      }));
  testWidgets('04-items', (t) => shot(t, '04-items', const Shell(), act: () async {
        await t.tap(find.text('الأصناف').last);
      }));
  testWidgets('05-customers', (t) => shot(t, '05-customers', const Scaffold(body: CustomersScreen())));
  testWidgets('06-item-editor', (t) => shot(t, '06-item-editor', const ItemEditorScreen()));
  testWidgets('07-reports', (t) => shot(t, '07-reports', const ReportsScreen()));
  testWidgets('08-dashboard-dark', (t) => shot(t, '08-dashboard-dark', const Shell(), dark: true));
}
