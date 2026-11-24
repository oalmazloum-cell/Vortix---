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
      home: Session.shop == null ? const WelcomeScreen() : const LockScreen(),
    );
  }
}
