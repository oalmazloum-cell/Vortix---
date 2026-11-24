import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'services/session.dart';
import 'state/app_state.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/welcome_screen.dart';

class VortexApp extends StatelessWidget {
  const VortexApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: VTheme.light(),
      darkTheme: VTheme.dark(),
      themeMode: state.themeMode,
      // على الشاشات العريضة (معاينة الويب) يُعرض التطبيق بحجم جوال في المنتصف.
      builder: (context, child) {
        final w = MediaQuery.sizeOf(context).width;
        if (!kIsWeb || w <= 520) return child!;
        return ColoredBox(
          color: const Color(0xFF020C1B),
          child: Center(
            child: Container(
              width: 420,
              margin: const EdgeInsets.symmetric(vertical: 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF1E3A5F), width: 6),
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: Size(408, MediaQuery.sizeOf(context).height - 44)),
                child: child!,
              ),
            ),
          ),
        );
      },
      home: Session.shop == null ? const WelcomeScreen() : const LockScreen(),
    );
  }
}
