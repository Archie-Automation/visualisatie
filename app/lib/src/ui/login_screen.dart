import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luxe_knx/l10n/app_localizations.dart';

import '../api.dart';
import '../theme.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController(text: 'admin');
  bool _busy = false;
  String? _err;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _err = null;
    });
    bool ok = false;
    try {
      ok = await ref.read(authProvider.notifier).login(
            _user.text.trim(),
            _pass.text,
          );
    } on FormatException catch (_) {
      ok = false;
    } on TypeError catch (_) {
      ok = false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('login error: $e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = l10n.loginErrorNetwork;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _err = l10n.loginErrorBadCredentials;
      }
    });
    if (ok && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(40, 44, 40, 44),
                  radius: 32,
                  shadows: LuxeShadows.lift,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('LUXE KNX',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 14),
                        Text(l10n.loginWelcomeTitle,
                            style: Theme.of(context).textTheme.displayMedium),
                        const SizedBox(height: 10),
                        Text(
                          l10n.loginSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 40),
                        _field(_user, l10n.loginUserLabel),
                        const SizedBox(height: 22),
                        _field(_pass, l10n.loginPasswordLabel, obscure: true),
                        const SizedBox(height: 36),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: LuxeColors.ink,
                            minimumSize: const Size.fromHeight(60),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  l10n.loginAction,
                                  style: const TextStyle(
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                        if (_err != null) ...[
                          const SizedBox(height: 20),
                          Text(_err!,
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(color: LuxeColors.danger)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15, color: LuxeColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: LuxeColors.inkSoft),
        filled: true,
        fillColor: LuxeColors.surface.withValues(alpha: 0.6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: LuxeColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: LuxeColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: LuxeColors.ink, width: 1.4),
        ),
      ),
    );
  }
}
