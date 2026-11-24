import 'package:material_ui/material_ui.dart';

/// نظام ألوان فورتكس الصارم.
/// - الأخضر الزمردي: صافي الربح، المبيعات المكتملة، "متاح"، "مدفوع" فقط.
/// - الأحمر المرجاني: التنبيهات والديون المتأخرة والنقص فقط.
class VColors {
  VColors._();

  static const background = Color(0xFFF1F5F9); // رمادي ثلجي
  static const card = Color(0xFFFFFFFF);
  static const navy = Color(0xFF0A192F); // كحلي ليلي عميق
  static const navyLight = Color(0xFF112240);
  static const blue = Color(0xFF1D4ED8); // أزرق كهربائي ملكي
  static const blueBright = Color(0xFF2563EB);
  static const emerald = Color(0xFF059669); // أخضر زمردي
  static const emeraldLight = Color(0xFF10B981);
  static const coral = Color(0xFFF43F5E); // أحمر مرجاني
  static const coralSoft = Color(0xFFFF6B6B);

  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);

  // الوضع الليلي
  static const darkBackground = Color(0xFF020C1B);
  static const darkCard = Color(0xFF112240);
  static const darkBorder = Color(0xFF1E3A5F);
  static const darkText = Color(0xFFE2E8F0);
  static const darkTextSecondary = Color(0xFF94A3B8);
}

class VTheme {
  VTheme._();

  static const font = 'Plex';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final bg = dark ? VColors.darkBackground : VColors.background;
    final card = dark ? VColors.darkCard : VColors.card;
    final text = dark ? VColors.darkText : VColors.textPrimary;
    final text2 = dark ? VColors.darkTextSecondary : VColors.textSecondary;
    final border = dark ? VColors.darkBorder : VColors.border;

    final scheme = ColorScheme(
      brightness: b,
      primary: dark ? VColors.blueBright : VColors.navy,
      onPrimary: Colors.white,
      secondary: VColors.blue,
      onSecondary: Colors.white,
      tertiary: VColors.emerald,
      onTertiary: Colors.white,
      error: VColors.coral,
      onError: Colors.white,
      surface: card,
      onSurface: text,
      surfaceContainerHighest: dark ? VColors.navyLight : const Color(0xFFF8FAFC),
      onSurfaceVariant: text2,
      outline: border,
    );

    final radius = BorderRadius.circular(14);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: VColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamily: font, fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: border)),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? VColors.navyLight : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: VColors.blue, width: 1.6)),
        labelStyle: TextStyle(color: text2),
        hintStyle: TextStyle(color: text2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: VColors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          elevation: 0,
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? VColors.darkText : VColors.navy,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: border),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? VColors.blueBright : VColors.blue,
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: VColors.blue,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: VColors.navy,
        indicatorColor: VColors.blue,
        iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Colors.white : Colors.white70)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: font,
            fontSize: 12,
            color: s.contains(WidgetState.selected) ? Colors.white : Colors.white70,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: VColors.navy),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: border),
        labelStyle: TextStyle(fontFamily: font, color: text),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: VColors.navy,
        contentTextStyle: TextStyle(fontFamily: font, color: Colors.white),
      ),
      listTileTheme: ListTileThemeData(iconColor: text2),
    );
  }
}
