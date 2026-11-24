import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vortex/core/format.dart';
import 'package:vortex/data/db.dart';
import 'package:vortex/data/models.dart';
import 'package:vortex/services/audit_service.dart';
import 'package:vortex/services/backup_service.dart';
import 'package:vortex/services/cash_service.dart';
import 'package:vortex/services/currency_service.dart';
import 'package:vortex/services/debts_service.dart';
import 'package:vortex/services/inventory_service.dart';
import 'package:vortex/services/purchase_service.dart';
import 'package:vortex/services/report_service.dart';
import 'package:vortex/services/sales_service.dart';
import 'package:vortex/services/session.dart';
import 'package:vortex/services/subscription_service.dart';

late String dbPath;

Future<Item> addItem(String name, {double cost = 5, double retail = 10, double wholesale = 8, double qty = 100, String? barcode}) async {
  final it = Item(id: newId(), name: name, cost: cost, retail: retail, wholesale: wholesale, barcode: barcode, minQty: 5);
  await InventoryService.save(it, isNew: true, openingQty: qty);
  return (await InventoryService.byId(it.id))!;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDb.onOpen = AuditService.resetCache;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('vortex_test');
    dbPath = '${dir.path}/vortex.db';
    await AppDb.open(path: dbPath);
    await Session.createShop(shopName: 'بقالة الأمل', ownerName: 'أحمد', phone: '0591234567', ownerCode: '123456');
    await CurrencyService.load();
  });

  tearDown(() async => AppDb.close());

  test('إنشاء المحل والمالك والعملات والدخول بالرمز', () async {
    expect(Session.shop!.name, 'بقالة الأمل');
    final owner = (await Session.owner())!;
    expect(await Session.login(owner, '123456'), isTrue);
    expect(await Session.login(owner, '000000'), isFalse);
    expect(await Session.verifyOwnerCode('١٢٣٤٥٦'), isTrue, reason: 'يقبل الأرقام العربية');
    expect(CurrencyService.base.code, 'ILS');
    expect(CurrencyService.all.length, 3);
  });

  test('بيع نقدي ينقص المخزون ويسجل الربح', () async {
    final it = await addItem('سكر', cost: 4, retail: 6);
    final sale = await SalesService.checkout(
      cart: [CartLine(item: it, qty: 3, price: 6)],
      priceMode: PriceMode.retail,
      currency: 'ILS',
      rate: 1,
      paid: 18,
    );
    expect(sale.status, 'paid');
    expect(sale.total, 18);
    expect(sale.cost, 12);
    expect((await InventoryService.byId(it.id))!.qty, 97);
    final s = await ReportService.today();
    expect(s.netSales, 18);
    expect(s.grossProfit, 6);
  });

  test('البيع بالوحدات المتعددة وسعر الجملة', () async {
    final it = await addItem('مياه', cost: 1, retail: 2, wholesale: 1.5, qty: 240);
    final box = ItemUnit(id: newId(), itemId: it.id, name: 'كرتونة', factor: 24, barcode: '7290000000017', retail: 40, wholesale: 34);
    it.units = [box];
    await InventoryService.save(it);
    final hit = (await InventoryService.findByBarcode('7290000000017'))!;
    expect(hit.unit!.name, 'كرتونة');
    final price = CartLine.priceFor(hit.item, hit.unit, PriceMode.wholesale);
    expect(price, 34);
    await SalesService.checkout(
      cart: [CartLine(item: hit.item, unit: hit.unit, qty: 2, price: price)],
      priceMode: PriceMode.wholesale,
      currency: 'ILS',
      rate: 1,
      paid: 68,
    );
    expect((await InventoryService.byId(it.id))!.qty, 240 - 48);
  });

  test('البيع بالدين والدفعات والديون المتأخرة', () async {
    final it = await addItem('أرز', retail: 20);
    final c = Customer(id: newId(), name: 'أبو محمد', phone: '0599999999');
    await DebtsService.saveCustomer(c, isNew: true);
    expect(
      () => SalesService.checkout(cart: [CartLine(item: it, qty: 1, price: 20)], priceMode: PriceMode.retail, currency: 'ILS', rate: 1, paid: 0),
      throwsA(isA<SaleException>()),
      reason: 'الدين يحتاج زبوناً',
    );
    final sale = await SalesService.checkout(
      cart: [CartLine(item: it, qty: 5, price: 20)],
      priceMode: PriceMode.retail,
      customer: c,
      currency: 'ILS',
      rate: 1,
      paid: 30,
      dueDate: DateTime.now().subtract(const Duration(days: 3)),
    );
    expect(sale.status, 'partial');
    var b = await DebtsService.balance('customer', c.id);
    expect(b.balance, 70);
    expect(b.overdue, 70);
    await DebtsService.receivePayment(c, 50);
    b = await DebtsService.balance('customer', c.id);
    expect(b.balance, 20);
    expect(b.overdue, 20);
    final t = await DebtsService.totals();
    expect(t.overdueCount, 1);
  });

  test('الدين غير المستحق بعد لا يظهر متأخراً', () async {
    final now = DateTime(2026, 6, 1);
    final entries = [
      LedgerEntry(id: '1', createdAt: now, kind: 'sale', debit: 100, credit: 0, dueDate: now.add(const Duration(days: 10))),
      LedgerEntry(id: '2', createdAt: now, kind: 'sale', debit: 50, credit: 0, dueDate: now.subtract(const Duration(days: 1))),
      LedgerEntry(id: '3', createdAt: now, kind: 'payment', debit: 0, credit: 30),
    ];
    final b = DebtsService.computeBalance(entries, now: now);
    expect(b.balance, 120);
    expect(b.overdue, 20, reason: 'الدفعة تسدد الأقدم استحقاقاً أولاً');
  });

  test('المرتجع يعيد المخزون ويخصم من الدين ويمنع تجاوز الكمية', () async {
    final it = await addItem('زيت', cost: 15, retail: 25);
    final c = Customer(id: newId(), name: 'سامي');
    await DebtsService.saveCustomer(c, isNew: true);
    final sale = await SalesService.checkout(
      cart: [CartLine(item: it, qty: 4, price: 25)],
      priceMode: PriceMode.retail,
      customer: c,
      currency: 'ILS',
      rate: 1,
      paid: 0,
    );
    final lineId = sale.lines.first.id;
    final r = await SalesService.returnSale(sale, {lineId: 1}, refundMode: 'debt');
    expect(r.total, 25);
    expect((await InventoryService.byId(it.id))!.qty, 97);
    expect((await DebtsService.balance('customer', c.id)).balance, 75);
    expect(() => SalesService.returnSale(sale, {lineId: 4}, refundMode: 'debt'), throwsA(isA<SaleException>()));
    final s = await ReportService.today();
    expect(s.netSales, 75);
    expect(s.grossProfit, 75 - 45);
  });

  test('فاتورة الشراء تحدّث متوسط التكلفة والمخزون ودين المورد', () async {
    final it = await addItem('طحين', cost: 10, qty: 10);
    final sup = Supplier(id: newId(), name: 'مورد الشمال');
    await DebtsService.saveSupplier(sup, isNew: true);
    await PurchaseService.save(
      lines: [PurchaseLine(item: it, qty: 10, cost: 20)],
      supplier: sup,
      currency: 'ILS',
      rate: 1,
      paid: 50,
    );
    final fresh = (await InventoryService.byId(it.id))!;
    expect(fresh.qty, 20);
    expect(fresh.cost, 15);
    expect((await DebtsService.balance('supplier', sup.id)).balance, 150);
  });

  test('إقفال الصندوق: المتوقع = الافتتاحي + المبيعات النقدية + التحصيل - المصاريف', () async {
    final shift = await CashService.openShift(100);
    final it = await addItem('خبز', retail: 5);
    final c = Customer(id: newId(), name: 'ليلى');
    await DebtsService.saveCustomer(c, isNew: true);
    await SalesService.checkout(cart: [CartLine(item: it, qty: 10, price: 5)], priceMode: PriceMode.retail, currency: 'ILS', rate: 1, paid: 50);
    await SalesService.checkout(
        cart: [CartLine(item: it, qty: 4, price: 5)], priceMode: PriceMode.retail, customer: c, currency: 'ILS', rate: 1, paid: 0);
    await DebtsService.receivePayment(c, 10);
    await CashService.addExpense('كهرباء', 30);
    final sm = await CashService.summary(shift);
    expect(sm.expected, 100 + 50 + 10 - 30);
    final diff = await CashService.closeShift(shift, 125);
    expect(diff, -5);
    expect(await CashService.currentShift(), isNull);
  });

  test('تعدد العملات: البيع بالدولار يُخزّن بالعملة الأساسية', () async {
    final it = await addItem('شاحن', retail: 37);
    final usd = CurrencyService.byCode('USD');
    final sale = await SalesService.checkout(
      cart: [CartLine(item: it, qty: 1, price: 37)],
      priceMode: PriceMode.retail,
      currency: 'USD',
      rate: usd.rate,
      paid: 37,
    );
    expect(sale.total, 37);
    expect(usd.fromBase(sale.total), closeTo(10, 0.001));
    expect(CurrencyService.format(37, 'USD'), '10 \$');
  });

  test('سجل العمليات لا يقبل التعديل أو الحذف وسلسلته سليمة', () async {
    await addItem('حليب');
    expect(await AuditService.verify(), 0);
    expect(() => AppDb.I.db.rawDelete('DELETE FROM audit_log'), throwsA(anything));
    expect(() => AppDb.I.db.rawUpdate("UPDATE audit_log SET details = 'x'"), throwsA(anything));
    final n = await AppDb.I.scalar('SELECT COUNT(*) FROM audit_log');
    expect(n, greaterThan(1));
  });

  test('الباركود الداخلي EAN-13 صالح وفريد', () async {
    expect(InventoryService.ean13Checksum('590123412345'), 7);
    final a = await InventoryService.generateInternalBarcode();
    final b = await InventoryService.generateInternalBarcode();
    expect(a.length, 13);
    expect(a.startsWith('200'), isTrue);
    expect(a, isNot(b));
    expect(int.parse(a[12]), InventoryService.ean13Checksum(a.substring(0, 12)));
  });

  test('الجرد يعدّل الكميات ويحسب قيمة الفرق', () async {
    final it = await addItem('صابون', cost: 3, qty: 50);
    final diff = await InventoryService.saveCount({it: 45});
    expect(diff, -15);
    expect((await InventoryService.byId(it.id))!.qty, 45);
  });

  test('تنبيهات النقص', () async {
    await addItem('ملح', qty: 3);
    await addItem('فلفل', qty: 30);
    final low = await InventoryService.lowStock();
    expect(low.map((e) => e.name), ['ملح']);
  });

  test('كود التفعيل يعمل بدون إنترنت ومرتبط برقم المحل', () async {
    final until = DateTime.now().add(const Duration(days: 30));
    final code = SubscriptionService.makeCode('0591234567', until);
    expect(SubscriptionService.parseCode('+970591234567', code), isNotNull);
    expect(SubscriptionService.parseCode('0597777777', code), isNull);
    expect((await SubscriptionService.status()).state, SubState.trial);
    expect(await SubscriptionService.activate('0591234567', code), isTrue);
    expect((await SubscriptionService.status()).state, SubState.active);
  });

  test('النسخ الاحتياطي والاسترجاع الكامل', () async {
    final it = await addItem('قهوة', qty: 12);
    final data = await BackupService.exportData();
    await AppDb.I.db.rawUpdate('UPDATE items SET qty = 0');
    await BackupService.restoreData(data, dbPath: dbPath);
    expect((await InventoryService.byId(it.id))!.qty, 12);
    expect(await AuditService.verify(), 0);
    expect((await Session.loadShop())!.name, 'بقالة الأمل');
  });

  test('تنسيق الأرقام العربية', () {
    expect(Fmt.parse('١٢٫٥'), 12.5);
    expect(normalizeArabic('أحمد'), normalizeArabic('احمد'));
  });
}
