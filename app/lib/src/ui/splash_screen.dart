import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import 'widgets/luxe_backdrop.dart';

const Duration _kPingInterval = Duration(seconds: 2);
const Duration _kPingTimeout  = Duration(seconds: 3);

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;
  late final Animation<double>   _rotAnim;

  bool _backendOk = false;
  bool _navigated  = false;
  Timer? _retryTimer;

  static const String _logoAsset = 'assets/images/logo.png';

  @override
  void initState() {
    super.initState();

    // Y-as rotatie — draait onbeperkt door
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _rotAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotCtrl, curve: Curves.linear),
    );

    // Direct eerste ping, daarna elke 2s opnieuw als geen verbinding
    _pingOnce();
  }

  Future<void> _pingOnce() async {
    bool ok = false;
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
      _retryTimer?.cancel();
      _tryNavigate();
    } else {
      // Opnieuw proberen na 2 seconden
      _retryTimer = Timer(_kPingInterval, _pingOnce);
    }
  }

  void _tryNavigate() {
    if (_navigated) return;
    if (!_backendOk) return;
    final auth = ref.read(authProvider);
    if (!auth.restoreComplete) return;

    _navigated = true;
    _rotCtrl.stop();
    context.go(auth.isAuthed ? '/' : '/login');
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _rotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Zodra auth restore klaar is én backend OK → navigeer direct
    ref.listen<AuthState>(authProvider, (_, auth) {
      if (auth.restoreComplete) _tryNavigate();
    });

    return Scaffold(
      body: LuxeBackdrop(
        child: Center(
          child: AnimatedBuilder(
            animation: _rotAnim,
            builder: (context, child) {
              final angle = _rotAnim.value * 2 * pi;
              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002)
                  ..rotateY(angle),
                alignment: Alignment.center,
                child: child,
              );
            },
            child: Image.asset(
              _logoAsset,
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
