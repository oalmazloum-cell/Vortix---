import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../data/models.dart';
import 'currency_service.dart';
import 'session.dart';

/// واتساب: تذكير الديون، إرسال الفواتير وكشوف الحساب، وطلب التفعيل.
class WhatsappService {
  WhatsappService._();

  /// تحويل رقم محلي (059...) إلى دولي (97059...). مفتاح الدولة الافتراضي من الإعدادات.
  static String international(String phone, {String countryCode = '970'}) {
    var d = Fmt.normalizeDigits(phone).replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00')) return d.substring(2);
    if (d.startsWith('0')) return '$countryCode${d.substring(1)}';
    if (d.length <= 9) return '$countryCode$d';
    return d;
  }

  static Future<bool> openChat(String phone, String message) async {
    final uri = Uri.parse('https://wa.me/${international(phone)}?text=${Uri.encodeComponent(message)}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String debtReminderText(Customer c, PartyBalance b) {
    final shop = Session.shop?.name ?? '';
    final lines = <String>[
      'مرحباً ${c.name} 👋',
      'نود تذكيركم بأن الرصيد المستحق عليكم لدى $shop هو: *${money(b.balance)}*',
      if (b.isOverdue) 'منه مبلغ متأخر: *${money(b.overdue)}*${b.oldestDue != null ? ' (مستحق منذ ${Fmt.date(b.oldestDue!)})' : ''}',
      'نرجو التكرم بالسداد في أقرب وقت. شكراً لتعاملكم معنا 🌹',
      if ((Session.shop?.phone ?? '').isNotEmpty) 'للتواصل: ${Session.shop!.phone}',
    ];
    return lines.join('\n');
  }

  static Future<bool> sendDebtReminder(Customer c, PartyBalance b) async {
    final number = c.contactNumber;
    if (number == null || number.isEmpty) return false;
    return openChat(number, debtReminderText(c, b));
  }

  static String invoiceText(Sale s) {
    final cur = CurrencyService.byCode(s.currency);
    String m(double v) => '${Fmt.money(s.rate == 0 ? v : v / s.rate)} ${cur.symbol}';
    final b = StringBuffer()
      ..writeln('*${Session.shop?.name ?? ''}*')
      ..writeln('${s.isReturn ? 'مرتجع' : 'فاتورة'} رقم #${s.number} — ${Fmt.dateTime(s.createdAt)}')
      ..writeln('──────────');
    for (final l in s.lines) {
      b.writeln('• ${l.name} × ${Fmt.qty(l.qty)} ${l.unitName} = ${m(l.total)}');
    }
    b.writeln('──────────');
    if (s.discount > 0) b.writeln('الخصم: ${m(s.discount)}');
    b.writeln('*الإجمالي: ${m(s.total)}*');
    if (!s.isReturn) {
      b.writeln('المدفوع: ${m(s.paid)}');
      if (s.remaining > 0) b.writeln('المتبقي: ${m(s.remaining)}');
    }
    b.writeln(Session.shop?.footer?.isNotEmpty == true ? Session.shop!.footer : 'شكراً لزيارتكم 🌹');
    return b.toString();
  }

  /// يشارك ملف PDF عبر قائمة المشاركة (يختار المستخدم واتساب).
  static Future<void> sharePdf(Uint8List bytes, String fileName, {String? text}) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], text: text));
  }

  static Future<bool> requestActivation() {
    final s = Session.shop;
    return openChat(AppConfig.supportWhatsapp,
        'مرحباً، أريد تفعيل اشتراك فورتكس للمحاسبة\nالمحل: ${s?.name ?? ''}\nرقم الجوال: ${s?.phone ?? ''}\nالمالك: ${s?.ownerName ?? ''}');
  }
}
