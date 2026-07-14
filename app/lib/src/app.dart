import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:luxe_knx/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'call_service.dart';
import 'theme.dart';
import 'ui/camera_screen.dart';
import 'ui/cameras_overview_screen.dart';
import 'ui/dashboard_screen.dart';
import 'ui/intercom_screen.dart';
import 'ui/log_screen.dart';
import 'ui/login_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/room_category_screen.dart';
import 'ui/room_screen.dart';
import 'ui/settings_screen.dart';
import 'installer/house_editor_screen.dart';
import 'intercom/intercom_sip_providers.dart';
import 'ui/alarm_screen.dart';
import 'ui/widgets/incoming_call_overlay.dart';
import 'ui/widgets/media_tile.dart';
import 'ui/widgets/satel_entry_delay_layer.dart';

class LuxeKnxApp extends ConsumerStatefulWidget {
  const LuxeKnxApp({super.key});

  @override
  ConsumerState<LuxeKnxApp> createState() => _LuxeKnxAppState();
}

class _LuxeKnxAppState extends ConsumerState<LuxeKnxApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  late final _RouterRefresh _routerRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _routerRefresh = _RouterRefresh(ref);
    _router = _buildRouter();
    // Initialise native call UI bridge.
    Future.microtask(() async {
      await CallService.init(ref, _router);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routerRefresh.dispose();
    super.dispose();
  }

  /// Reconnect WebSocket when the app comes back to the foreground.
  /// On iPhone/Safari the WS often drops while the screen is locked.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(busProvider.notifier).reconnectNow();
    }
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/splash',
      redirect: (ctx, state) {
        final auth = ref.read(authProvider);
        final loc = state.matchedLocation;
        final onSplash = loc == '/splash';
        final onLogin = loc == '/login';
        final installer = loc == '/installer';
        // Splash beheert zijn eigen navigatie; router mag nooit van splash wegsturen.
        if (onSplash) return null;
        // Zolang restore niet klaar is, terug naar splash.
        if (!auth.restoreComplete && !onLogin) return '/splash';
        if (!auth.isAuthed && !onLogin) return '/login';
        if (auth.isAuthed && onLogin) return '/';
        if (installer && auth.isAuthed && !auth.isAdmin) return '/';
        return null;
      },
      refreshListenable: _routerRefresh,
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: '/floor/:floorId/room/:roomId/category/:category',
          pageBuilder: (_, s) => CustomTransitionPage(
            child: RoomCategoryScreen(
              floorId: s.pathParameters['floorId']!,
              roomId: s.pathParameters['roomId']!,
              categorySlug: s.pathParameters['category']!,
            ),
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            transitionsBuilder: (_, anim, __, child) {
              final curved = CurvedAnimation(
                parent: anim,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(opacity: curved, child: child);
            },
          ),
        ),
        GoRoute(
          path: '/floor/:floorId/room/:roomId',
          pageBuilder: (_, s) => CustomTransitionPage(
            child: RoomScreen(
              floorId: s.pathParameters['floorId']!,
              roomId: s.pathParameters['roomId']!,
            ),
            transitionDuration: const Duration(milliseconds: 320),
            reverseTransitionDuration: const Duration(milliseconds: 260),
            transitionsBuilder: (_, anim, __, child) {
              final curved = CurvedAnimation(
                parent: anim,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(opacity: curved, child: child);
            },
          ),
        ),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
          path: '/installer',
          builder: (_, __) =>
              const HouseEditorScreen(useCustomerSession: true),
        ),
        GoRoute(
          path: '/cameras',
          pageBuilder: (_, __) => CustomTransitionPage(
            child: const CamerasOverviewScreen(),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity:
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              child: child,
            ),
          ),
        ),
        GoRoute(
          path: '/camera/:id',
          pageBuilder: (_, s) => CustomTransitionPage(
            child: CameraScreen(cameraId: s.pathParameters['id']!),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity:
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              child: child,
            ),
          ),
        ),
        GoRoute(
          path: '/media/:id',
          pageBuilder: (_, s) => CustomTransitionPage(
            child: MediaPlayerScreen(deviceId: s.pathParameters['id']!),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity:
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              child: child,
            ),
          ),
        ),
        GoRoute(
          path: '/alarm',
          pageBuilder: (_, __) => CustomTransitionPage(
            child: const AlarmScreen(),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity:
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              child: child,
            ),
          ),
        ),
        GoRoute(
          path: '/log/:id',
          pageBuilder: (_, s) => CustomTransitionPage(
            child: LogScreen(
              logId: s.pathParameters['id']!,
              title: s.uri.queryParameters['title'],
              mode: s.uri.queryParameters['mode'],
            ),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity:
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              child: child,
            ),
          ),
        ),
        GoRoute(
          path: '/intercom/:id',
          pageBuilder: (_, s) => CustomTransitionPage(
            child: IntercomScreen(intercomId: s.pathParameters['id']!),
            transitionDuration: const Duration(milliseconds: 320),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity:
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              child: child,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Activate the CallKit listener lifecycle for the app's lifetime.
    ref.watch(callServiceListenerProvider);
    // Auto-start SIP registration when config is available with SIP intercoms.
    ref.watch(sipStartupProvider);

    return MaterialApp.router(
      title: 'Luxe KNX',
      theme: buildLuxeTheme(),
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScrollBehavior(),
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
      builder: (context, child) => SatelEntryDelayLayer(
        child: SipIncomingCallLayer(
          child: IncomingCallOverlay(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Nudges GoRouter's redirect to re-run when auth changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(WidgetRef ref) {
    _sub = ref.listenManual<AuthState>(
      authProvider,
      (_, __) => notifyListeners(),
    );
  }
  late final ProviderSubscription<AuthState> _sub;
  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

/// Custom scroll behaviour for Flutter web on mobile:
/// - Enables touch + mouse + trackpad drag scrolling.
/// - Removes the overscroll glow indicator (looks bad on glass UI).
/// - Uses clamping physics so there is no rubber-band bounce jank.
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child; // No glow — it flickers on web.
}
