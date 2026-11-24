/// إعدادات فورتكس العامة. عدّل هذا الملف قبل النشر.
class AppConfig {
  AppConfig._();

  static const appName = 'فورتكس للمحاسبة';
  static const appNameEn = 'Vortex';

  /// مدة التجربة المجانية بالأيام.
  static const trialDays = 6;

  /// رقم واتساب الدعم/المبيعات لطلب تفعيل الاشتراك (بالصيغة الدولية بدون +).
  static const supportWhatsapp = '972599331547';

  /// المفتاح السري لتوليد أكواد التفعيل. غيّره، ولا تنشره، واستخدم نفس القيمة
  /// في أداة tool/gen_activation.dart.
  static const activationSecret = 'CHANGE-ME-vortex-secret-2026';

  /// بيانات Supabase للمزامنة والاسترجاع (اتركها فارغة للعمل محلياً فقط).
  /// يمكن تمريرها وقت البناء:
  /// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get cloudEnabled => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// بادئة الباركود الداخلي (EAN-13 يبدأ بـ 2 مخصص للاستخدام داخل المحل).
  static const internalBarcodePrefix = '200';

  /// عدد النسخ الاحتياطية المحلية التي يُحتفظ بها.
  static const keepBackups = 14;

  /// عدد أيام التنبيه قبل انتهاء الصلاحية.
  static const expiryWarnDays = 30;
}
