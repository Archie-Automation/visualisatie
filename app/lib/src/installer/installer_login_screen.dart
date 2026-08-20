import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:archie_os/l10n/app_localizations.dart';

import '../theme.dart';
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
    setState(() {
      _busy = false;
      if (!ok) {
        _err = l10n.installerLoginAdminOnlyError;
      }
    });
    if (ok && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
