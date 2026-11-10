import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config/app_texts.dart';
import 'config/app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/api_client.dart';
import 'services/session_store.dart';
import 'state/app_state.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');
  final state = AppState(api: ApiClient(), store: DeviceSessionStore());
  runApp(ContentHubApp(state: state));
  await state.start();
}

class ContentHubApp extends StatelessWidget {
  const ContentHubApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: T.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const _Root(),
      ),
    );
  }
}

/// Entscheidet zwischen Startanzeige, Anmeldung und App.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.starting) return const Scaffold(body: LoadingView());
    if (state.loadError != null && state.me == null) {
      return Scaffold(
        body: ErrorView(error: state.loadError!, onRetry: state.reload),
      );
    }
    if (!state.signedIn) return const AuthScreen();
    return const HomeShell();
  }
}
