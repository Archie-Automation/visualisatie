import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../pairing_api.dart';
import '../theme.dart';
import 'widgets/glass_card.dart';

/// Instellingen → Telefoon koppelen: QR + code voor een nieuwe telefoon van
/// dezelfde gebruiker. Tien minuten geldig, eenmalig.
class PairingSection extends ConsumerStatefulWidget {
  const PairingSection({super.key});

  @override
  ConsumerState<PairingSection> createState() => _PairingSectionState();
}

class _PairingSectionState extends ConsumerState<PairingSection> {
  PairStart? _pair;
  bool _busy = false;
  String? _err;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final p = await startPairing(token: token);
      if (!mounted) return;
      setState(() => _pair = p);
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final cur = _pair;
        if (cur == null || DateTime.now().isAfter(cur.expiresAt)) {
          _tick?.cancel();
          setState(() => _pair = null);
          return;
        }
        setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _pair;
    final remaining = p == null
        ? Duration.zero
        : p.expiresAt.difference(DateTime.now());
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Zet een nieuwe telefoon op dit huis zonder wachtwoord. '
              'Scan de QR met de camera van de telefoon, of typ de code in de app '
              'bij "Ik heb een koppelcode". De telefoon blijft daarna ingelogd, '
              'thuis én onderweg.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 18),
            if (p == null)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.ink,
                  foregroundColor: LuxeColors.onInk,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                onPressed: _busy ? null : _create,
                child: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: LuxeColors.onInk),
                      )
                    : const Text('Nieuwe koppelcode'),
              )
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: QrImageView(
                    data: p.qr,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF111111),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF111111),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: SelectableText(
                  p.code,
                  style: t.displayMedium?.copyWith(
                    letterSpacing: 4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Nog $mm:$ss geldig · eenmalig',
                  style: t.bodySmall?.copyWith(color: LuxeColors.inkSoft),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: p.qr));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link gekopieerd')),
                        );
                      },
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Link kopiëren'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _create,
                      child: const Text('Nieuwe code'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                p.remoteUrl != null
                    ? 'Werkt thuis (${p.localUrl}) en onderweg (${p.remoteUrl}).'
                    : 'Alleen thuis: ${p.localUrl}. Buitenshuis vraagt om Archie Cloud op de server.',
                style: t.bodySmall?.copyWith(color: LuxeColors.inkSoft),
              ),
            ],
            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(_err!, style: TextStyle(color: LuxeColors.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
