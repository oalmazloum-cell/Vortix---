import 'package:intl/intl.dart';

/// أدوات تنسيق الأرقام والتواريخ.
class Fmt {
  Fmt._();

  static final _money = NumberFormat('#,##0.##', 'en');
  static final _qty = NumberFormat('#,##0.###', 'en');

  static String money(num v, [String symbol = '']) {
    final s = _money.format(round2(v.toDouble()));
    return symbol.isEmpty ? s : '$s $symbol';
  }

  static String qty(num v) => _qty.format(v);
  static String _p(int v) => v.toString().padLeft(2, '0');
  static String date(DateTime d) => '${d.year}/${_p(d.month)}/${_p(d.day)}';
  static String time(DateTime d) => '${_p(d.hour)}:${_p(d.minute)}';
  static String dateTime(DateTime d) => '${date(d)}  ${time(d)}';

  static String dateMs(int ms) => date(DateTime.fromMillisecondsSinceEpoch(ms));
  static String dateTimeMs(int ms) => dateTime(DateTime.fromMillisecondsSinceEpoch(ms));

  /// يحول الأرقام العربية/الفارسية إلى إنجليزية ثم يقرأ الرقم.
  static double parse(String s) {
    return double.tryParse(normalizeDigits(s).replaceAll(',', '').trim()) ?? 0;
  }

  static String normalizeDigits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = ar.indexOf(ch);
      final j = fa.indexOf(ch);
      if (i >= 0) {
        b.write(i);
      } else if (j >= 0) {
        b.write(j);
      } else if (ch == '٫') {
        b.write('.');
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  static double round2(double v) => (v * 100).roundToDouble() / 100;
}

/// بداية ونهاية اليوم بالمللي ثانية.
int startOfDay(DateTime d) => DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
int endOfDay(DateTime d) => DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).millisecondsSinceEpoch - 1;
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// يطبّع النص العربي للبحث (يوحّد الألف والياء والتاء المربوطة ويحذف التشكيل).
String normalizeArabic(String s) {
  var r = s.toLowerCase().trim();
  r = r.replaceAll(RegExp('[ً-ْـ]'), '');
  r = r.replaceAll(RegExp('[إأآا]'), 'ا');
  r = r.replaceAll('ى', 'ي').replaceAll('ة', 'ه').replaceAll('ؤ', 'و').replaceAll('ئ', 'ي');
  return Fmt.normalizeDigits(r);
}
