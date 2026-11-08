import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../theme.dart';
import '../web_remote_handoff.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';

/// Eerste login. Blijft staan tot het fabriekswachtwoord vervangen is.
class PasswordChangeScreen extends ConsumerWidget {
  const PasswordChangeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FirstPasswordForm(
                  onSave: (password) async {
                    final err = await ref
                        .read(authProvider.notifier)
                        .changePassword(password);
                    if (err == null && context.mounted) {
                      final left = await handoffWebToRemote(
                        ref.read(authProvider).token,
                      );
                      if (!left && context.mounted) context.go('/');
                    }
                    return err;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FirstPasswordForm extends StatefulWidget {
  const FirstPasswordForm({super.key, required this.onSave});

  /// null als het wachtwoord staat. Anders de fouttekst.
  final Future<String?> Function(String password) onSave;

  @override
  State<FirstPasswordForm> createState() => _FirstPasswordFormState();
}

class _FirstPasswordFormState extends State<FirstPasswordForm> {
  final _pass = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _pass.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _pass.text;
    if (password.length < 8) {
      setState(() => _err = 'Kies minstens 8 tekens.');
      return;
    }
    if (password != _again.text) {
      setState(() => _err = 'De twee wachtwoorden zijn niet gelijk.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final err = await widget.onSave(password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 44),
      radius: 32,
      shadows: LuxeShadows.lift,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ARCHIE OS', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 14),
            Text(
              'Kies een wachtwoord',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Dit is de eerste keer. Het meegeleverde wachtwoord werkt daarna niet meer. '
              'Kies minstens 8 tekens. Bewaar het. Een ander beheeraccount kan het '
              'later wijzigen. Lukt dat niet, dan zet je het op de NUC met '
              'docker/wachtwoord.sh.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 36),
            TextField(
              controller: _pass,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nieuw wachtwoord'),
              onSubmitted: (_) {
                if (!_busy) _submit();
              },
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _again,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Herhaal wachtwoord'),
              onSubmitted: (_) {
                if (!_busy) _submit();
              },
            ),
            const SizedBox(height: 36),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LuxeColors.ink,
                foregroundColor: LuxeColors.onInk,
                minimumSize: const Size.fromHeight(60),
                shape: const StadiumBorder(),
                elevation: 0,
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LuxeColors.onInk,
                      ),
                    )
                  : const Text(
                      'Opslaan',
                      style: TextStyle(
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
            ),
            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(
                _err!,
                textAlign: TextAlign.center,
                style: TextStyle(color: LuxeColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
