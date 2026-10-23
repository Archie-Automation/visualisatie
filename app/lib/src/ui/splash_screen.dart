import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../demo/demo_session.dart';
import '../server_route.dart';
import '../theme.dart';
import 'widgets/luxe_backdrop.dart';

const Duration _kPingInterval = Duration(seconds: 2);
const Duration _kPingTimeout = Duration(seconds: 3);

/// Splash-adres dat [uri] na het laden weer opent.
String splashLocationPreserving(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  final current = uri.hasQuery ? '$path?${uri.query}' : path;
  return '/splash?next=${Uri.encodeComponent(current)}';
}

/// Alleen een pad in deze app. Geen schema, host of splash-lus.
String? resumeLocationAfterSplash(String? next) {
  if (next == null || next.isEmpty) return null;
  final uri = Uri.tryParse(next);
  if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return null;
  var path = uri.path;
  if (path.isEmpty) path = '/';
  if (!path.startsWith('/') || path.startsWith('//')) return null;
  if (path == '/splash' || path == '/login' || path == '/pair') return null;
  if (uri.query.isEmpty) return path;
  return '$path?${uri.query}';
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;
  late final Animation<double> _rotAnim;
  late final TextEditingController _server;
  late final TextEditingController _remote;

  bool _backendOk = false;
  bool _navigated = false;
  bool _showServerField = false;
  int _failCount = 0;
  bool _savingServer = false;
  Timer? _retryTimer;

  static const String _logoAsset = 'assets/images/app_icon.png';

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: localApiBase);
    _remote = TextEditingController(text: remoteApiBase ?? '');

    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Face-on ±90° — never flip past the edge to show the back of the logo.
    _rotAnim = Tween<double>(begin: -pi / 2, end: pi / 2).animate(
      CurvedAnimation(parent: _rotCtrl, curve: Curves.easeInOut),
    );

    _pingOnce();
  }

  Future<void> _pingOnce() async {
    final auth = ref.read(authProvider);
    if (!auth.restoreComplete) {
      _retryTimer = Timer(const Duration(milliseconds: 200), _pingOnce);
      return;
    }
    if (isDemoToken(auth.token)) {
      _backendOk = true;
      _failCount = 0;
      _retryTimer?.cancel();
      _tryNavigate();
      return;
    }

    bool ok = false;
    // Na een mislukte poging eerst de andere route proberen (LAN <-> cloud).
    if (_failCount > 0 && !kIsWeb) {
      await chooseServerRoute();
      if (!mounted) return;
    }
    try {
      final res = await http
          .get(Uri.parse('$apiBase/api/health'))
          .timeout(_kPingTimeout);
      ok = res.statusCode < 500;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      _backendOk = true;
      _failCount = 0;
      _retryTimer?.cancel();
      if (_showServerField) setState(() => _showServerField = false);
      _tryNavigate();
    } else {
      _failCount++;
      if (_failCount >= 3 && !_showServerField) {
        setState(() => _showServerField = true);
      }
      _retryTimer = Timer(_kPingInterval, _pingOnce);
    }
  }

  Future<void> _applyServer() async {
    if (_savingServer) return;
    setState(() => _savingServer = true);
    await setApiBase(
      _server.text,
      auth: ref.read(authProvider.notifier),
    );
    await setRemoteApiBase(
      _remote.text.trim().isEmpty ? null : _remote.text,
    );
    await chooseServerRoute();
    if (!mounted) return;
    setState(() {
      _savingServer = false;
      _failCount = 0;
      _backendOk = false;
    });
    _retryTimer?.cancel();
    await _pingOnce();
  }

  void _tryNavigate() {
    if (_navigated) return;
    if (!_backendOk) return;
    final auth = ref.read(authProvider);
    if (!auth.restoreComplete) return;

    _navigated = true;
    _rotCtrl.stop();
    final next = resumeLocationAfterSplash(
      GoRouterState.of(context).uri.queryParameters['next'],
    );
    context.go(auth.isAuthed ? (next ?? '/') : '/login');
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _rotCtrl.dispose();
    _server.dispose();
    _remote.dispose();
    super.dispose();
  }

  Widget _serverField(
    TextEditingController c, {
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.url,
      style: TextStyle(fontSize: 15, color: LuxeColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: LuxeColors.inkSoft),
        filled: true,
        fillColor: LuxeColors.surface.withValues(alpha: 0.6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: LuxeColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: LuxeColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: LuxeColors.ink, width: 1.4),
        ),
      ),
      onSubmitted: (_) => _applyServer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (_, auth) {
      if (auth.restoreComplete) _tryNavigate();
    });

    return Scaffold(
      body: LuxeBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _rotAnim,
                      builder: (context, child) {
                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002)
                            ..rotateY(_rotAnim.value),
                          alignment: Alignment.center,
                          child: child,
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          _logoAsset,
                          width: 128,
                          height: 128,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (_showServerField) ...[
                      const SizedBox(height: 36),
                      Text(
                        'Server niet bereikbaar.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: LuxeColors.inkSoft,
                            ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(height: 16),
                        _serverField(
                          _server,
                          label: 'Server (thuis)',
                          hint: 'http://192.168.1.20:4000',
                        ),
                        const SizedBox(height: 12),
                        _serverField(
                          _remote,
                          label: 'Adres buitenshuis (optioneel)',
                          hint: 'https://huis.archiecloud.nl',
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: LuxeColors.ink,
                          foregroundColor: LuxeColors.onInk,
                          minimumSize: const Size.fromHeight(52),
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                        onPressed: _savingServer
                            ? null
                            : kIsWeb
                                ? () {
                                    setState(() {
                                      _failCount = 0;
                                      _showServerField = false;
                                    });
                                    _retryTimer?.cancel();
                                    _pingOnce();
                                  }
                                : _applyServer,
                        child: _savingServer
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: LuxeColors.onInk,
                                ),
                              )
                            : Text(kIsWeb
                                ? 'Opnieuw proberen'
                                : 'Opnieuw verbinden'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _savingServer
                            ? null
                            : () async {
                                await ref.read(authProvider.notifier).enterDemo();
                                if (!context.mounted) return;
                                _navigated = true;
                                _retryTimer?.cancel();
                                context.go('/');
                              },
                        child: Text(
                          'Demowoning bekijken',
                          style: TextStyle(
                            color: LuxeColors.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
