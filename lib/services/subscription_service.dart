import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../data/db.dart';
import 'audit_service.dart';

enum SubState { trial, active, expired }

class SubStatus {
  SubStatus(this.state, this.daysLeft, this.until);
  final SubState state;
  final int daysLeft;
  final DateTime until;
}

/// التجربة المجانية (6 أيام) وأكواد التفعيل.
///
/// كود التفعيل يعمل بدون إنترنت: `YYYYMMDD-XXXXXXXX` حيث الجزء الثاني
/// HMAC-SHA256 لرقم جوال المحل + تاريخ الانتهاء بالمفتاح السري.
/// ولّد الأكواد بالأداة: `dart run tool/gen_activation.dart <phone> <months>`.
class SubscriptionService {
  SubscriptionService._();

  static String signature(String phone, String yyyymmdd) {
    final h = Hmac(sha256, utf8.encode(AppConfig.activationSecret));
    return h.convert(utf8.encode('${normalizePhone(phone)}|$yyyymmdd')).toString().substring(0, 8).toUpperCase();
  }

  static String normalizePhone(String p) {
    final d = Fmt.normalizeDigits(p).replaceAll(RegExp(r'[^0-9]'), '');
    return d.length > 9 ? d.substring(d.length - 9) : d;
  }

  static String makeCode(String phone, DateTime until) {
    final ymd = '${until.year}${until.month.toString().padLeft(2, '0')}${until.day.toString().padLeft(2, '0')}';
    return '$ymd-${signature(phone, ymd)}';
  }

  /// يعيد تاريخ الانتهاء إن كان الكود صحيحاً.
  static DateTime? parseCode(String phone, String code) {
    final c = Fmt.normalizeDigits(code).trim().toUpperCase().replaceAll(' ', '');
    final m = RegExp(r'^(\d{8})-([0-9A-F]{8})$').firstMatch(c);
    if (m == null) return null;
    if (signature(phone, m.group(1)!) != m.group(2)) return null;
    final s = m.group(1)!;
    return DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)), 23, 59);
  }

  static Future<SubStatus> status() async {
    final db = AppDb.I;
    final now = DateTime.now();
    final paidUntil = int.tryParse(await db.getSetting('paid_until') ?? '');
    if (paidUntil != null) {
      final u = DateTime.fromMillisecondsSinceEpoch(paidUntil);
      if (u.isAfter(now)) return SubStatus(SubState.active, u.difference(now).inDays + 1, u);
    }
    final start = DateTime.fromMillisecondsSinceEpoch(int.tryParse(await db.getSetting('trial_start') ?? '') ?? nowMs());
    final end = start.add(const Duration(days: AppConfig.trialDays));
    if (end.isAfter(now)) {
      final left = (end.difference(now).inHours / 24).ceil();
      return SubStatus(SubState.trial, left, end);
    }
    return SubStatus(paidUntil != null ? SubState.expired : SubState.expired, 0, end);
  }

  static Future<bool> activate(String phone, String code) async {
    final until = parseCode(phone, code);
    if (until == null || until.isBefore(DateTime.now())) return false;
    await AppDb.I.setSetting('paid_until', '${until.millisecondsSinceEpoch}');
    await AuditService.log('تفعيل الاشتراك', entity: 'subscription', details: 'حتى ${Fmt.date(until)}');
    return true;
  }
}
