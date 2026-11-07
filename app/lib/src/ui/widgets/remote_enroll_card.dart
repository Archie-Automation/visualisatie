import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../api.dart';
import '../../theme.dart';
import 'glass_card.dart';

class RemoteEnrollStatus {
  const RemoteEnrollStatus({
    required this.state,
    required this.message,
    required this.remoteUrl,
  });

  final String state;
  final String message;
  final String? remoteUrl;

  bool get busy => state == 'queued' || state == 'running';

  factory RemoteEnrollStatus.fromJson(Map<String, dynamic> j) {
    return RemoteEnrollStatus(
      state: (j['state'] as String?) ?? 'idle',
      message: (j['message'] as String?) ?? '',
      remoteUrl: (j['remoteUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : (j['remoteUrl'] as String).trim(),
    );
  }
}

/// Installer: eenmalige Archie Cloud-code, onder Project.
class RemoteEnrollCard extends ConsumerStatefulWidget {
  const RemoteEnrollCard({super.key});

  @override
  ConsumerState<RemoteEnrollCard> createState() => _RemoteEnrollCardState();
}

class _RemoteEnrollCardState extends ConsumerState<RemoteEnrollCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  RemoteEnrollStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<RemoteEnrollStatus> _fetch(String token) async {
    final res = await http
        .get(
          Uri.parse('$apiBase/api/installer/remote'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 8));
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw StateError('Ongeldig antwoord');
    }
    if (res.statusCode != 200) {
      throw StateError((body['message'] as String?) ?? 'Status ophalen mislukt');
    }
    return RemoteEnrollStatus.fromJson(body);
  }

  Future<void> _load() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    try {
      final s = await _fetch(token);
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final token = ref.read(authProvider).token;
    final code = _code.text.trim();
    if (token == null || code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/api/installer/remote'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);
      if (res.statusCode != 200 || body is! Map<String, dynamic>) {
        final msg = body is Map ? body['message'] as String? : null;
        throw StateError(msg ?? 'Koppelen geweigerd (${res.statusCode})');
      }
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final s = await _fetch(token);
        if (!mounted) return;
        setState(() => _status = s);
        if (!s.busy) {
          if (s.state == 'error') {
            throw StateError(
              s.message.isEmpty ? 'Koppelen mislukt.' : s.message,
            );
          }
          _code.clear();
          return;
        }
      }
      throw StateError(
        'De server reageert niet. Werk de server eerst bij en probeer opnieuw.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = _status?.remoteUrl;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Remote verbinding', style: Theme.of(context).textTheme.titleSmall),
          if (linked != null) ...[
            const SizedBox(height: 6),
            Text(
              'Gekoppeld: $linked',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Koppelcode',
              hintText: 'W4NA-E5CB',
            ),
            enabled: !_busy,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if ((_status?.message.isNotEmpty ?? false) && _error == null) ...[
            const SizedBox(height: 8),
            Text(_status!.message, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Koppelen…' : 'Koppelen'),
            ),
          ),
        ],
      ),
    );
  }
}
