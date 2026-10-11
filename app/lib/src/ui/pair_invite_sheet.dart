import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../pairing_api.dart';
import '../theme.dart';

/// Koppellink voor een gebruiker die alleen een telefoon heeft: de beheerder
/// stuurt de link per sms/WhatsApp/mail. Tikken opent de app en logt in.
/// Ter plekke kan de QR ook gewoon gescand worden.
Future<void> showPairInviteSheet(
  BuildContext context, {
  required String userId,
  required String label,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PairInviteSheet(userId: userId, label: label),
  );
}

class _PairInviteSheet extends ConsumerStatefulWidget {
  const _PairInviteSheet({required this.userId, required this.label});
  final String userId;
  final String label;

  @override
  ConsumerState<_PairInviteSheet> createState() => _PairInviteSheetState();
}

class _PairInviteSheetState extends ConsumerState<_PairInviteSheet> {
  PairStart? _pair;
  String? _err;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() => _err = null);
    try {
      final p = await startPairing(token: token, userId: widget.userId);
      if (!mounted) return;
      setState(() => _pair = p);
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (DateTime.now().isAfter(p.expiresAt)) {
          _tick?.cancel();
          setState(() => _pair = null);
          return;
        }
        setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  String _message(PairStart p) =>
      'Archie OS – telefoon koppelen voor ${widget.label}.\n'
      'Tik op deze link (10 minuten geldig):\n${p.qr}\n\n'
      'Of open de app, kies "Ik heb een koppelcode" en typ: ${p.code}';

  Future<void> _open(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('geen app');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kon geen app openen; gebruik Kopiëren.')),
      );
    }
  }

  Uri _smsUri(String body) {
    // iOS wil `sms:&body=`, Android `sms:?body=`.
    final sep = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ? '&' : '?';
    return Uri.parse('sms:${sep}body=${Uri.encodeComponent(body)}');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _pair;
    final remaining = p == null ? Duration.zero : p.expiresAt.difference(DateTime.now());
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Material(
        color: LuxeColors.surface,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Koppellink voor ${widget.label}',
                          style: t.titleLarge),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Heeft deze persoon alleen een telefoon? Stuur de link. '
                  'Tikken opent de app en logt in, thuis en onderweg. '
                  'Staat de persoon naast je, laat dan de QR scannen.',
                  style: t.bodyMedium?.copyWith(color: LuxeColors.inkSoft),
                ),
                const SizedBox(height: 18),
                if (p == null && _err == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_err != null) ...[
                  Text(_err!, style: TextStyle(color: LuxeColors.danger)),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _create, child: const Text('Opnieuw')),
                ],
                if (p != null) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: LuxeColors.ink,
                          foregroundColor: LuxeColors.onInk,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () => _open(_smsUri(_message(p))),
                        icon: const Icon(Icons.sms_outlined, size: 18),
                        label: const Text('Sms'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: LuxeColors.ink,
                          foregroundColor: LuxeColors.onInk,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () => _open(Uri.parse(
                            'https://wa.me/?text=${Uri.encodeComponent(_message(p))}')),
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _open(Uri(
                          scheme: 'mailto',
                          query: 'subject=${Uri.encodeComponent('Archie OS koppelen')}'
                              '&body=${Uri.encodeComponent(_message(p))}',
                        )),
                        icon: const Icon(Icons.mail_outline, size: 18),
                        label: const Text('E-mail'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _message(p)));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bericht gekopieerd')),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Kopiëren'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: p.qr,
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: SelectableText(
                      p.code,
                      style: t.headlineMedium?.copyWith(letterSpacing: 4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Nog $mm:$ss geldig · eenmalig',
                      style: t.bodySmall?.copyWith(color: LuxeColors.inkSoft),
                    ),
                  ),
                  if (p.remoteUrl == null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Let op: Archie Cloud staat niet aan op deze server. De link '
                      'werkt alleen op de huis-wifi.',
                      style: t.bodySmall?.copyWith(color: LuxeColors.danger),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
