import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'currency_service.dart';
import 'debts_service.dart';
import 'inventory_service.dart';

/// القفل بالبصمة أو الوجه للمالك.
class BiometricService {
  BiometricService._();
  static final _auth = LocalAuthentication();

  static Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enabled() async => (await AppDb.I.getSetting('biometric')) == '1';
  static Future<void> setEnabled(bool v) => AppDb.I.setSetting('biometric', v ? '1' : '0', sync: false);

  static Future<bool> authenticate([String reason = 'تأكيد هوية المالك']) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: false, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('biometric: $e');
      return false;
    }
  }
}

/// البحث الصوتي عن الأصناف (بالعربية).
class VoiceService {
  VoiceService._();
  static final _stt = SpeechToText();
  static bool _ready = false;
  static String? _locale;

  static Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize();
      if (_ready) {
        final locales = await _stt.locales();
        final ar = locales.where((l) => l.localeId.toLowerCase().startsWith('ar')).toList();
        _locale = ar.isEmpty ? null : ar.first.localeId;
      }
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  static bool get isListening => _stt.isListening;

  static Future<bool> listen(void Function(String text, bool isFinal) onText) async {
    if (!await init()) return false;
    await _stt.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: _locale ?? 'ar_SA',
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      ),
    );
    return true;
  }

  static Future<void> stop() => _stt.stop();
}

/// إشعارات محلية: نقص المخزون، قرب انتهاء الصلاحية، الديون المتأخرة.
class NotificationService {
  NotificationService._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('notifications: $e');
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('vortex_alerts', 'تنبيهات فورتكس',
        channelDescription: 'نقص المخزون والصلاحية والديون المتأخرة',
        importance: Importance.high,
        priority: Priority.high),
    iOS: DarwinNotificationDetails(),
  );

  /// يفحص التنبيهات ويرسل إشعاراً واحداً ملخصاً مرة كل 12 ساعة كحد أقصى.
  static Future<void> checkAndNotify() async {
    if (!_ready || !AppDb.isOpen) return;
    final db = AppDb.I;
    if (await db.getSetting('shop_name') == null) return;
    final last = int.tryParse(await db.getSetting('notif_last') ?? '') ?? 0;
    if (nowMs() - last < const Duration(hours: 12).inMilliseconds) return;

    final low = await InventoryService.lowStock();
    final exp = await InventoryService.expiring();
    final debts = await DebtsService.totals();
    var id = 100;
    if (low.isNotEmpty) {
      await _plugin.show(
          id: id++,
          title: 'نقص في المخزون (${low.length})',
          body: low.take(4).map((i) => '${i.name}: ${Fmt.qty(i.qty)}').join('، '),
          notificationDetails: _details);
    }
    if (exp.isNotEmpty) {
      await _plugin.show(
          id: id++,
          title: 'أصناف قاربت على الانتهاء (${exp.length})',
          body: exp.take(4).map((i) => '${i.name}: ${Fmt.date(i.expiry!)}').join('، '),
          notificationDetails: _details);
    }
    if (debts.overdueCount > 0) {
      await _plugin.show(
          id: id++,
          title: 'ديون متأخرة على ${debts.overdueCount} زبون',
          body: 'إجمالي المتأخر: ${money(debts.overdue)} — أرسل تذكيراً عبر واتساب',
          notificationDetails: _details);
    }
    await db.setSetting('notif_last', '${nowMs()}', sync: false);
  }
}
