import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vortex/core/theme.dart';
import 'package:vortex/data/db.dart';
import 'package:vortex/data/models.dart';
import 'package:vortex/services/audit_service.dart';
import 'package:vortex/services/currency_service.dart';
import 'package:vortex/services/debts_service.dart';
import 'package:vortex/services/inventory_service.dart';
import 'package:vortex/services/sales_service.dart';
import 'package:vortex/services/session.dart';
import 'package:vortex/state/app_state.dart';
import 'package:vortex/ui/screens/cash_screen.dart';
import 'package:vortex/ui/screens/customers_screen.dart';
import 'package:vortex/ui/screens/dashboard_screen.dart';
import 'package:vortex/ui/screens/item_editor_screen.dart';
import 'package:vortex/ui/screens/items_screen.dart';
import 'package:vortex/ui/screens/pos_screen.dart';
import 'package:vortex/ui/screens/reports_screen.dart';
import 'package:vortex/ui/screens/sales_history_screen.dart';
import 'package:vortex/ui/screens/welcome_screen.dart';
import 'package:vortex/ui/screens/workers_screen.dart';

/// اختبارات دخان: تعرض كل شاشة رئيسية ببيانات حقيقية بحجم جوال،
/// وتفشل عند أي استثناء أو تجاوز في التخطيط (Overflow).
Future<void> seed() async {
  final dir = await Directory.systemTemp.createTemp('vortex_ui');
  await AppDb.open(path: '${dir.path}/v.db');
  await Session.createShop(shopName: 'سوبرماركت النور', ownerName: 'أبو خالد', phone: '0591234567', ownerCode: '123456');
  await AppState.I.load();
  final names = ['سكر أبيض 1كغ', 'أرز بسمتي', 'زيت زيتون', 'حليب طازج', 'خبز عربي', 'شاي أخضر', 'قهوة عربية', 'معكرونة'];
  final items = <Item>[];
  for (var i = 0; i < names.length; i++) {
    final it = Item(id: newId(), name: names[i], cost: 4.0 + i, retail: 6.0 + i * 1.5, wholesale: 5.0 + i, minQty: 5, favorite: i < 3,
        barcode: '20000000000${i}0', expiry: i == 3 ? DateTime.now().add(const Duration(days: 5)) : null);
    await InventoryService.save(it, isNew: true, openingQty: i == 2 ? 2 : 40.0);
    items.add((await InventoryService.byId(it.id))!);
  }
  final c = Customer(id: newId(), name: 'محمد سالم', phone: '0599111222');
  await DebtsService.saveCustomer(c, isNew: true);
  await SalesService.checkout(
      cart: [CartLine(item: items[0], qty: 3, price: items[0].retail)], priceMode: PriceMode.retail, currency: 'ILS', rate: 1, paid: 18);
  await SalesService.checkout(
    cart: [CartLine(item: items[1], qty: 4, price: items[1].retail)],
    priceMode: PriceMode.retail,
    customer: c,
    currency: 'ILS',
    rate: 1,
    paid: 0,
    dueDate: DateTime.now().subtract(const Duration(days: 2)),
  );
}

Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
      theme: VTheme.light(),
      darkTheme: VTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );

Future<void> show(WidgetTester tester, Widget w, {bool dark = false}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(wrap(w, dark: dark));
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDb.onOpen = AuditService.resetCache;

  setUpAll(() async => seed());

  testWidgets('شاشة البداية والدخول', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    await show(t, const WelcomeScreen());
    expect(find.text('فورتكس للمحاسبة'), findsOneWidget);
    expect(find.text('ابدأ الآن مجاناً'), findsOneWidget);
    await t.tap(find.text('عندي حساب').first);
    await t.pumpAndSettle();
    expect(find.text('الدخول واسترجاع المحل'), findsOneWidget);
  });

  final screens = <String, Widget Function()>{
    'لوحة التحكم': () => const Scaffold(body: DashboardScreen()),
    'نقطة البيع': () => const Scaffold(body: PosScreen()),
    'الأصناف': () => const Scaffold(body: ItemsScreen()),
    'الزبائن': () => const Scaffold(body: CustomersScreen()),
    'محرر الصنف': () => const ItemEditorScreen(),
    'سجل المبيعات': () => const SalesHistoryScreen(),
    'الصندوق': () => const CashScreen(),
    'التقارير': () => const ReportsScreen(),
    'العمال': () => const WorkersScreen(),
  };

  for (final e in screens.entries) {
    for (final dark in [false, true]) {
      testWidgets('${e.key}${dark ? ' (ليلي)' : ''}', (t) async {
        t.view.physicalSize = const Size(1080, 2340);
        t.view.devicePixelRatio = 3;
        Session.user = await t.runAsync<AppUser?>(Session.owner);
        if (CurrencyService.all.isEmpty) await t.runAsync(CurrencyService.load);
        await show(t, e.value(), dark: dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}
