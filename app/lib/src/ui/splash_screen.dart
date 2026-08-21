import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../theme.dart';
import 'widgets/luxe_backdrop.dart';

const Duration _kPingInterval = Duration(seconds: 2);
const Duration _kPingTimeout = Duration(seconds: 3);

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
    _server = TextEditingController(text: apiBase);

    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _rotAnim = Tween<double>(begin: 0, end: pi).animate(
      CurvedAnimation(parent: _rotCtrl, curve: Curves.easeInOut),
    );

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
      _failCount = 0;
      _retryTimer?.cancel();
      if (_showServerField) setState(() => _showServerField = false);
      _tryNavigate();
    } else {
      _failCount++;
      if (!kIsWeb && _failCount >= 2 && !_showServerField) {
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
    context.go(auth.isAuthed ? '/' : '/login');
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _rotCtrl.dispose();
    _server.dispose();
    super.dispose();
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
                        'Server niet bereikbaar. Controleer het adres.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: LuxeColors.inkSoft,
                            ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        style: TextStyle(fontSize: 15, color: LuxeColors.ink),
                        decoration: InputDecoration(
                          labelText: 'Server',
                          hintText: 'http://192.168.1.20:4000',
                          labelStyle: TextStyle(color: LuxeColors.inkSoft),
                          filled: true,
                          fillColor: LuxeColors.surface.withValues(alpha: 0.6),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 18),
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
                            borderSide: BorderSide(
                                color: LuxeColors.ink, width: 1.4),
                          ),
                        ),
                        onSubmitted: (_) => _applyServer(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: LuxeColors.ink,
                          foregroundColor: LuxeColors.onInk,
                          minimumSize: const Size.fromHeight(52),
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                        onPressed: _savingServer ? null : _applyServer,
                        child: _savingServer
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: LuxeColors.onInk,
                                ),
                              )
                            : const Text('Opnieuw verbinden'),
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
