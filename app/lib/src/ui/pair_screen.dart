import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../pairing_api.dart';
import '../server_route.dart';
import '../theme.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';

/// Telefoon koppelen met een code of gescande link. Geen wachtwoord nodig.
/// Via QR op web komt dit scherm binnen als `/#/pair?code=…&local=…&remote=…`.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key, this.code, this.localUrl, this.remoteUrl});

  final String? code;
  final String? localUrl;
  final String? remoteUrl;

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  late final TextEditingController _input;
  late final TextEditingController _server;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.code ?? '');
    _server = TextEditingController(text: widget.localUrl ?? localApiBase);
    if (widget.code != null && widget.code!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsed = PairInput.parse(_input.text);
    if (parsed == null) {
      setState(() => _err = 'Voer een code als ABCD-2345 in, of plak de link.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });

    // Kandidaten: thuis eerst, dan cloud. Op web alleen de eigen origin.
    final bases = <String>[];
    if (kIsWeb && kReleaseMode) {
      bases.add(localApiBase);
    } else {
      final local = parsed.localUrl ??
          widget.localUrl ??
          normalizeApiBase(_server.text);
      final remote = parsed.remoteUrl ?? widget.remoteUrl;
      if (local.isNotEmpty) bases.add(normalizeApiBase(local));
      if (remote != null && remote.isNotEmpty) {
        final r = normalizeRemoteBase(remote);
        if (r != null && !bases.contains(r)) bases.add(r);
      }
    }

    PairClaim? claim;
    String? lastErr;
    for (final base in bases) {
      try {
        claim = await claimPairCode(base: base, code: parsed.code);
        break;
      } catch (e) {
        lastErr = '$e'.replaceFirst('Bad state: ', '');
        // Een ongeldige code is op elke route ongeldig: niet verder proberen.
        if (lastErr.contains('ongeldig')) break;
      }
    }
    if (!mounted) return;
    if (claim == null) {
      setState(() {
        _busy = false;
        _err = lastErr ?? 'Server niet bereikbaar.';
      });
      return;
    }

    if (!kIsWeb) {
      await setApiBase(claim.localUrl);
      await setRemoteApiBase(claim.remoteUrl);
      await chooseServerRoute();
    }
    await ref.read(authProvider.notifier).applySession(claim.session);
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final showServer = !kIsWeb && (widget.localUrl == null);
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
                        Text('ARCHIE OS',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 14),
                        Text('Telefoon koppelen',
                            style: Theme.of(context).textTheme.displayMedium),
                        const SizedBox(height: 10),
                        Text(
                          'Vraag op een ingelogd scherm (Instellingen → Telefoon '
                          'koppelen) een koppelcode. Scan de QR of typ de code.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 32),
                        if (showServer) ...[
                          _field(_server, 'Server (thuis)',
                              hint: 'http://192.168.1.20:4000',
                              keyboardType: TextInputType.url),
                          const SizedBox(height: 18),
                        ],
                        _field(_input, 'Koppelcode of link',
                            hint: 'ABCD-2345',
                            autofocus: widget.code == null),
                        const SizedBox(height: 32),
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
                                      strokeWidth: 2, color: LuxeColors.onInk),
                                )
                              : Text(
                                  'Koppelen',
                                  style: TextStyle(
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: LuxeColors.onInk,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: _busy ? null : () => context.go('/login'),
                          child: Text('Inloggen met wachtwoord',
                              style: TextStyle(color: LuxeColors.inkSoft)),
                        ),
                        if (_err != null) ...[
                          const SizedBox(height: 12),
                          Text(_err!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: LuxeColors.danger)),
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

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    bool autofocus = false,
  }) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => _submit(),
      style: TextStyle(fontSize: 15, color: LuxeColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: LuxeColors.inkSoft),
        hintStyle: TextStyle(color: LuxeColors.inkSoft.withValues(alpha: 0.7)),
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
    );
  }
}
