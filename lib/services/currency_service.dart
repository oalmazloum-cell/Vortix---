import '../data/db.dart';
import '../data/models.dart';
import 'audit_service.dart';

/// تعدد العملات: عملة أساسية + عملات أخرى بسعر صرف يومي.
class CurrencyService {
  CurrencyService._();

  static List<Currency> _cache = [];
  static List<Currency> get all => _cache;

  static Currency get base =>
      _cache.firstWhere((c) => c.isBase, orElse: () => Currency(code: 'ILS', name: 'شيكل', symbol: '₪', rate: 1, isBase: true));

  static Currency byCode(String code) => _cache.firstWhere((c) => c.code == code, orElse: () => base);

  static Future<List<Currency>> load() async {
    final rows = await AppDb.I.query('SELECT * FROM currencies WHERE active = 1 ORDER BY is_base DESC, id');
    return _cache = rows.map(Currency.fromRow).toList();
  }

  static Future<void> setRate(String code, double rate) async {
    if (rate <= 0) return;
    final old = byCode(code).rate;
    await AppDb.I.patch('currencies', code, {'rate': rate});
    await AuditService.log('تعديل سعر صرف', entity: 'currency', entityId: code, details: '$code: $old ← $rate');
    await load();
  }

  static Future<void> add(String code, String name, String symbol, double rate) async {
    await AppDb.I.put('currencies', {
      'id': code.toUpperCase(),
      'name': name,
      'symbol': symbol,
      'rate': rate,
      'is_base': 0,
      'active': 1,
    });
    await AuditService.log('إضافة عملة', entity: 'currency', entityId: code, details: '$name ($rate)');
    await load();
  }

  /// صيغة عرض مبلغ (بالعملة الأساسية) في عملة معينة.
  static String format(double baseAmount, [String? code]) {
    final c = code == null ? base : byCode(code);
    final v = c.fromBase(baseAmount);
    final s = v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    return '${_group(s)} ${c.symbol}';
  }

  static String _group(String s) {
    final neg = s.startsWith('-');
    if (neg) s = s.substring(1);
    final parts = s.split('.');
    final b = StringBuffer();
    final ip = parts[0];
    for (var i = 0; i < ip.length; i++) {
      if (i > 0 && (ip.length - i) % 3 == 0) b.write(',');
      b.write(ip[i]);
    }
    final r = parts.length > 1 ? '$b.${parts[1]}' : b.toString();
    return neg ? '-$r' : r;
  }
}

/// اختصار لتنسيق المبالغ بالعملة الأساسية.
String money(double baseAmount, [String? code]) => CurrencyService.format(baseAmount, code);
