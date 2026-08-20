import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:archie_os/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'call_service.dart';
import 'kiosk_system_ui.dart';
import 'theme.dart';
import 'theme_mode.dart';
import 'ui/responsive.dart';
import 'ui/camera_screen.dart';
import 'ui/cameras_overview_screen.dart';
import 'ui/dashboard_screen.dart';
import 'ui/intercom_screen.dart';
import 'ui/log_screen.dart';
import 'ui/login_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/room_category_screen.dart';
import 'ui/room_screen.dart';
import 'ui/system_screen.dart';
import 'ui/settings_screen.dart';
import 'installer/house_editor_screen.dart';
import 'intercom/intercom_sip_providers.dart';
import 'ui/alarm_screen.dart';
import 'ui/widgets/incoming_call_overlay.dart';
import 'ui/widgets/inactivity_layer.dart';
import 'ui/widgets/media_tile.dart';
import 'ui/widgets/satel_entry_delay_layer.dart';
import 'ui/widgets/software_update_banner.dart';
import 'software_version.dart';

class ArchieOsApp extends ConsumerStatefulWidget {
  const ArchieOsApp({super.key});

  @override
  ConsumerState<ArchieOsApp> createState() => _ArchieOsAppState();
}

class _ArchieOsAppState extends ConsumerState<ArchieOsApp>
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
      applyAndroidKioskSystemUi();
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
        GoRoute(
          path: '/system/:slug',
          pageBuilder: (_, s) => CustomTransitionPage(
            child: SystemScreen(slug: s.pathParameters['slug']!),
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 240),
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

    final themeMode = ref.watch(effectiveThemeModeProvider);

    return MaterialApp.router(
      title: 'Archie OS',
      theme: buildLuxeTheme(Brightness.light),
      darkTheme: buildLuxeTheme(Brightness.dark),
      themeMode: themeMode,
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
      builder: (context, child) {
        final palette = Theme.of(context).extension<LuxePalette>();
        if (palette != null) LuxeColors.bind(palette);
        // Warm the version check (server + GitHub latest) early.
        ref.watch(softwareVersionStatusProvider);
        final layered = SatelEntryDelayLayer(
          child: SipIncomingCallLayer(
            child: IncomingCallOverlay(
              child: InactivityLayer(
                router: _router,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
        final content = Column(
          children: [
            const SoftwareUpdateBanner(),
            Expanded(child: layered),
          ],
        );
        // Tablet: slightly larger for wall readability.
        // Phone: near-native scale + slightly lighter weights (finer / chic).
        final phone = context.isPhone;
        final themed = phone
            ? Theme(
                data: _phoneTextPolish(Theme.of(context)),
                child: content,
              )
            : content;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(phone ? 1.0 : 1.14),
          ),
          child: themed,
        );
      },
    );
  }
}

/// Soften Inter weights on phone without changing layout or tablet look.
ThemeData _phoneTextPolish(ThemeData base) {
  final t = base.textTheme;
  TextStyle? soft(TextStyle? s, FontWeight w, {double? tracking}) =>
      s?.copyWith(fontWeight: w, letterSpacing: tracking ?? s.letterSpacing);

  final lightNardo = base.brightness == Brightness.light;
  return base.copyWith(
    scaffoldBackgroundColor:
        lightNardo ? LuxePalette.phoneCream : base.scaffoldBackgroundColor,
    textTheme: t.copyWith(
      titleLarge: soft(t.titleLarge, FontWeight.w600),
      titleMedium: soft(t.titleMedium, FontWeight.w600),
      bodyLarge: soft(t.bodyLarge, FontWeight.w500),
      bodyMedium: soft(t.bodyMedium, FontWeight.w500),
      bodySmall: soft(t.bodySmall, FontWeight.w500),
      labelLarge: soft(t.labelLarge, FontWeight.w600, tracking: 1.15),
      labelMedium: soft(t.labelMedium, FontWeight.w600, tracking: 0.9),
      labelSmall: soft(t.labelSmall, FontWeight.w600, tracking: 0.8),
    ),
  );
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
