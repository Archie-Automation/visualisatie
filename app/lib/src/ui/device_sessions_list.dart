import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../sessions_api.dart';
import '../theme.dart';

/// Gekoppelde apparaten van één gebruiker, met "Afmelden" per apparaat.
/// [userId] null = de ingelogde gebruiker zelf.
class DeviceSessionsList extends ConsumerStatefulWidget {
  const DeviceSessionsList({super.key, this.userId, this.compact = false});
  final String? userId;
  /// Zonder kop en met minder witruimte (in de gebruikerseditor).
  final bool compact;

  @override
  ConsumerState<DeviceSessionsList> createState() => _DeviceSessionsListState();
}

class _DeviceSessionsListState extends ConsumerState<DeviceSessionsList> {
  List<DeviceSession>? _items;
  String? _err;
  String? _mySessionId;
  bool _loading = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DeviceSessionsList old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        fetchDeviceSessions(token: token, userId: widget.userId),
        storedSessionId(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<DeviceSession>;
        _mySessionId = results[1] as String?;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(DeviceSession s) async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    final isMe = s.id == _mySessionId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMe ? 'Dit apparaat afmelden?' : 'Apparaat afmelden?'),
        content: Text(
          isMe
              ? 'Je wordt op dit apparaat uitgelogd.'
              : '${_label(s)} moet daarna opnieuw inloggen of gekoppeld worden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Afmelden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(s.id));
    try {
      final done = await revokeDeviceSession(token: token, id: s.id);
      if (!mounted) return;
      if (!done) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Afmelden mislukt')),
        );
        return;
      }
      if (isMe) {
        await ref.read(authProvider.notifier).logout();
        return;
      }
      setState(() => _items = _items?.where((x) => x.id != s.id).toList());
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  static String _label(DeviceSession s) {
    switch (s.device.toLowerCase()) {
      case 'android':
        return 'Android-telefoon';
      case 'ios':
        return 'iPhone';
      case 'browser':
        return 'Browser';
      case 'windows':
      case 'macos':
      case 'linux':
        return 'Computer';
      default:
        return s.device.isEmpty ? 'Apparaat' : s.device;
    }
  }

  static IconData _icon(DeviceSession s) {
    switch (s.device.toLowerCase()) {
      case 'android':
      case 'ios':
        return Icons.phone_iphone_outlined;
      case 'browser':
        return Icons.language_outlined;
      case 'windows':
      case 'macos':
      case 'linux':
        return Icons.laptop_outlined;
      default:
        return Icons.devices_other_outlined;
    }
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 2) return 'zojuist';
    if (d.inHours < 1) return '${d.inMinutes} min geleden';
    if (d.inDays < 1) return '${d.inHours} uur geleden';
    if (d.inDays < 30) return '${d.inDays} dagen geleden';
    return '${t.day}-${t.month}-${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact)
          Row(
            children: [
              Expanded(
                child: Text('Gekoppelde apparaten', style: t.titleMedium),
              ),
              IconButton(
                tooltip: 'Vernieuwen',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        if (_loading && items == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_err != null)
          Text(_err!, style: TextStyle(color: LuxeColors.danger))
        else if (items == null || items.isEmpty)
          Text(
            widget.userId == null
                ? 'Alleen dit apparaat (ingelogd met wachtwoord vóór de koppelfunctie).'
                : 'Nog geen apparaat gekoppeld.',
            style: t.bodySmall?.copyWith(color: LuxeColors.inkSoft),
          )
        else
          for (final s in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(_icon(s), size: 20, color: LuxeColors.inkSoft),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(_label(s),
                                  style: t.bodyMedium,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (s.id == _mySessionId) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: LuxeColors.ink,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'dit apparaat',
                                  style: t.labelSmall
                                      ?.copyWith(color: LuxeColors.onInk),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          'Actief ${_ago(s.lastUsedAt)} · gekoppeld ${_ago(s.createdAt)}',
                          style: t.bodySmall
                              ?.copyWith(color: LuxeColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  _busy.contains(s.id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => _revoke(s),
                          style: TextButton.styleFrom(
                              foregroundColor: LuxeColors.danger),
                          child: const Text('Afmelden'),
                        ),
                ],
              ),
            ),
      ],
    );
  }
}
