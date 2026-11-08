import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:archie_os/l10n/app_localizations.dart';

import '../api.dart' show apiBase;
import '../theme.dart';
import '../ui/password_change_screen.dart';
import 'installer_auth.dart';

class InstallerLoginScreen extends ConsumerStatefulWidget {
  const InstallerLoginScreen({super.key});

  @override
  ConsumerState<InstallerLoginScreen> createState() =>
      _InstallerLoginScreenState();
}

class _InstallerLoginScreenState extends ConsumerState<InstallerLoginScreen> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;
  String? _pendingToken;
  String? _pendingUser;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _err = null;
    });
    bool ok = false;
    try {
      ok = await ref.read(installerAuthProvider.notifier).login(
            _user.text.trim(),
            _pass.text,
          );
    } on FormatException catch (_) {
      ok = false;
    } on TypeError catch (_) {
      ok = false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('installer login error: $e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = l10n.loginErrorNetwork;
      });
      return;
    }
    if (!mounted) return;
    final pending = ref.read(installerAuthProvider.notifier).pendingToken;
    if (!ok && pending != null) {
      setState(() {
        _busy = false;
        _err = null;
        _pendingToken = pending;
        _pendingUser = ref.read(installerAuthProvider.notifier).pendingUsername;
      });
      return;
    }
    setState(() {
      _busy = false;
      if (!ok) {
        _err = l10n.installerLoginAdminOnlyError;
      }
    });
    if (ok && mounted) context.go('/');
  }

  Future<String?> _savePassword(String password) async {
    final token = _pendingToken;
    if (token == null) return 'Niet ingelogd.';
    final res = await http.post(
      Uri.parse('$apiBase/api/auth/password'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode != 200) {
      try {
        final err = (jsonDecode(res.body) as Map)['error'];
        if (err is String && err.isNotEmpty) return err;
      } catch (_) {}
      return 'Wachtwoord niet opgeslagen.';
    }
    await ref
        .read(installerAuthProvider.notifier)
        .adopt(token, _pendingUser ?? 'admin');
    if (mounted) context.go('/');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_pendingToken != null) {
      return Scaffold(
        backgroundColor: LuxeColors.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FirstPasswordForm(onSave: _savePassword),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: LuxeColors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: LuxeColors.line),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'ARCHIE OS',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.installerLoginTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.installerLoginDescription,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _user,
                        decoration: InputDecoration(
                          labelText: l10n.loginUserLabel,
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pass,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.loginPasswordLabel,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _busy ? null : _submit(),
                      ),
                      if (_err != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _err!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(l10n.loginAction),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
