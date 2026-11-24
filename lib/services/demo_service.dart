import '../data/db.dart';
import '../data/models.dart';
import 'cash_service.dart';
import 'debts_service.dart';
import 'inventory_service.dart';
import 'sales_service.dart';
import 'session.dart';

/// بيانات تجريبية لمعاينة التطبيق (تُستخدم في نسخة الويب فقط).
/// رمز المالك التجريبي: 123456
class DemoService {
  DemoService._();

  static const ownerCode = '123456';

  static Future<void> seed() async {
    await Session.createShop(
      shopName: 'سوبرماركت النور',
      ownerName: 'أبو خالد',
      phone: '0599000000',
      ownerCode: ownerCode,
    );
    Session.user = await Session.owner();
    await CashService.openShift(200);

    final data = <(String, String, double, double, double, double, String?)>[
      // الاسم، الباركود، التكلفة، المفرق، الجملة، الكمية، التصنيف
      ('سكر أبيض 1كغ', '6251000000014', 4, 6, 5.5, 60, 'مواد تموينية'),
      ('أرز بسمتي 5كغ', '6251000000021', 28, 35, 32, 25, 'مواد تموينية'),
      ('زيت زيتون 1لتر', '6251000000038', 30, 40, 36, 3, 'مواد تموينية'),
      ('حليب طازج', '6251000000045', 4.5, 6, 5.5, 30, 'ألبان'),
      ('لبنة 500غ', '6251000000052', 7, 10, 9, 18, 'ألبان'),
      ('خبز عربي', '6251000000069', 3, 5, 4, 40, 'مخبوزات'),
      ('شاي أخضر', '6251000000076', 9, 13, 11.5, 22, 'مشروبات'),
      ('قهوة عربية 250غ', '6251000000083', 18, 25, 22, 14, 'مشروبات'),
      ('مياه معدنية 1.5لتر', '6251000000090', 1, 2, 1.5, 120, 'مشروبات'),
      ('معكرونة', '6251000000106', 2.5, 4, 3.5, 2, 'مواد تموينية'),
      ('شيبس', '6251000000113', 1.5, 3, 2.5, 50, 'تسالي'),
      ('صابون غسيل', '6251000000120', 12, 18, 16, 9, 'منظفات'),
    ];
    final items = <Item>[];
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final it = Item(
        id: newId(),
        name: d.$1,
        barcode: d.$2,
        cost: d.$3,
        retail: d.$4,
        wholesale: d.$5,
        category: d.$7,
        minQty: 5,
        favorite: i < 8,
        expiry: i == 3
            ? DateTime.now().add(const Duration(days: 4))
            : (i == 4 ? DateTime.now().add(const Duration(days: 20)) : null),
      );
      if (d.$1.startsWith('مياه')) {
        it.units = [ItemUnit(id: newId(), itemId: it.id, name: 'شدّة', factor: 6, barcode: '6251000000991', retail: 10, wholesale: 8)];
      }
      await InventoryService.save(it, isNew: true, openingQty: d.$6);
      items.add((await InventoryService.byId(it.id))!);
    }

    final customers = <Customer>[];
    for (final (name, phone) in [('محمد سالم', '0599111222'), ('أم أحمد', '0598333444'), ('سامي يوسف', '0597555666')]) {
      final c = Customer(id: newId(), name: name, phone: phone, whatsapp: phone, creditLimit: 500);
      await DebtsService.saveCustomer(c, isNew: true);
      customers.add(c);
    }

    // مبيعات آخر 7 أيام للرسوم البيانية
    final now = DateTime.now();
    var n = 0;
    for (var day = 6; day >= 0; day--) {
      final count = day == 0 ? 7 : 2 + (day * 3) % 4;
      for (var k = 0; k < count; k++) {
        final a = items[(n * 3) % items.length];
        final b = items[(n * 5 + 1) % items.length];
        final cart = [
          CartLine(item: a, qty: 1 + (n % 3), price: a.retail),
          CartLine(item: b, qty: 1, price: b.retail),
        ];
        final total = cart.fold<double>(0, (s, l) => s + l.total);
        final credit = n % 6 == 2;
        final cust = credit ? customers[n % customers.length] : null;
        final sale = await SalesService.checkout(
          cart: cart,
          priceMode: PriceMode.retail,
          customer: cust,
          currency: 'ILS',
          rate: 1,
          paid: credit ? 0 : total,
          dueDate: credit ? now.subtract(Duration(days: day == 6 ? 3 : -10)) : null,
        );
        final at = DateTime(now.year, now.month, now.day, 8 + k, 15 + k * 5).subtract(Duration(days: day));
        await AppDb.I.patch('sales', sale.id, {'created_at': at.millisecondsSinceEpoch});
        n++;
      }
    }
    await CashService.addExpense('كهرباء', 45, note: 'فاتورة الشهر');
  }
}
