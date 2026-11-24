// أداة توليد أكواد التفعيل (للمالك/المطوّر فقط).
// الاستخدام: dart run tool/gen_activation.dart 0591234567 12
// (رقم جوال المحل، عدد الأشهر)
// تأكد أن المفتاح هنا مطابق لـ AppConfig.activationSecret.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const secret = 'CHANGE-ME-vortex-secret-2026';

void main(List<String> args) {
  if (args.length < 2) {
    stdout.writeln('الاستخدام: dart run tool/gen_activation.dart <رقم الجوال> <عدد الأشهر>');
    exit(1);
  }
  var phone = args[0].replaceAll(RegExp(r'[^0-9]'), '');
  if (phone.length > 9) phone = phone.substring(phone.length - 9);
  final months = int.parse(args[1]);
  final now = DateTime.now();
  final until = DateTime(now.year, now.month + months, now.day);
  final ymd = '${until.year}${until.month.toString().padLeft(2, '0')}${until.day.toString().padLeft(2, '0')}';
  final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$phone|$ymd')).toString().substring(0, 8).toUpperCase();
  stdout.writeln('كود التفعيل: $ymd-$sig  (صالح حتى ${until.toIso8601String().substring(0, 10)})');
}
