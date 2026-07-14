import 'package:flutter/material.dart';
import 'package:luxe_knx/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'house_editor_screen.dart';
import 'installer_auth.dart';
import 'installer_login_screen.dart';

class _InstallerRouterRefresh extends ChangeNotifier {
  _InstallerRouterRefresh(WidgetRef ref) {
    _sub = ref.listenManual<InstallerAuthState>(
      installerAuthProvider,
      (_, __) => notifyListeners(),
    );
  }
  late final ProviderSubscription<InstallerAuthState> _sub;
  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

class LuxeKnxInstallerApp extends ConsumerStatefulWidget {
  const LuxeKnxInstallerApp({super.key});

  @override
  ConsumerState<LuxeKnxInstallerApp> createState() =>
      _LuxeKnxInstallerAppState();
}

class _LuxeKnxInstallerAppState extends ConsumerState<LuxeKnxInstallerApp> {
  late final GoRouter _router;
  late final _InstallerRouterRefresh _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = _InstallerRouterRefresh(ref);
    _router = GoRouter(
      initialLocation: '/login',
      refreshListenable: _refresh,
      redirect: (ctx, state) {
        final auth = ref.read(installerAuthProvider);
        final loggingIn = state.matchedLocation == '/login';
        if (!auth.isAuthed && !loggingIn) return '/login';
        if (auth.isAuthed && loggingIn) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const InstallerLoginScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const HouseEditorScreen(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Luxe KNX Installateur',
      theme: buildLuxeTheme(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) {
        if (locale != null) {
          for (final l in supported) {
            if (l.languageCode == locale.languageCode) return l;
          }
        }
        return const Locale('nl');
      },
      routerConfig: _router,
    );
  }
}
