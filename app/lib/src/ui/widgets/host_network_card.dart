import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../api.dart';
import '../../theme.dart';
import 'glass_card.dart';

/// Installer: DHCP of een vast adres voor de server zelf. Niet de KNX-gateway.
class HostNetworkCard extends ConsumerStatefulWidget {
  const HostNetworkCard({super.key});

  @override
  ConsumerState<HostNetworkCard> createState() => _HostNetworkCardState();
}

class _HostNetworkCardState extends ConsumerState<HostNetworkCard> {
  bool _loading = true;
  bool _busy = false;
  bool _static = false;
  bool _pending = false;
  String? _error;
  String? _info;
  String _iface = '';
  final _address = TextEditingController();
  final _prefix = TextEditingController(text: '24');
  final _gateway = TextEditingController();
  final _dns = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    _prefix.dispose();
    _gateway.dispose();
    _dns.dispose();
    super.dispose();
  }

  Map<String, String> _headers() {
    final token = ref.read(authProvider).token ?? '';
    return {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    };
  }

  Future<Map<String, dynamic>?> _fetch() async {
    final res = await http
        .get(Uri.parse('$apiBase/api/admin/host-network'), headers: _headers())
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return null;
    return body;
  }

  void _apply(Map<String, dynamic> body) {
    final mode = body['mode'];
    final dns = body['dns'];
    _static = mode == 'static';
    _pending = body['pending'] == true;
    _iface = '${body['iface'] ?? ''}';
    _address.text = '${body['address'] ?? ''}';
    final prefix = body['prefix'];
    if (prefix is num) _prefix.text = '${prefix.toInt()}';
    _gateway.text = '${body['gateway'] ?? ''}';
    if (dns is List && dns.isNotEmpty) {
      _dns.text = dns.map((d) => '$d').join(', ');
    }
    _info = body['message'] is String ? body['message'] as String : null;
  }

  Future<void> _load() async {
    try {
      final body = await _fetch();
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (body == null) {
          _error = 'Netwerkstatus ophalen mislukt.';
        } else if (body['available'] != true) {
          _error = (body['message'] as String?) ??
              'Dit paneel werkt alleen op de server zelf.';
        } else {
          _error = null;
          _apply(body);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Netwerkstatus ophalen mislukt.';
      });
    }
  }

  int? _port() {
    final p = Uri.parse(apiBase).port;
    if (p > 0) return p;
    return 4000;
  }

  Future<void> _save() async {
    final token = ref.read(authProvider).token;
    if (token == null || _busy) return;
    final prefix = int.tryParse(_prefix.text.trim());
    final address = _address.text.trim();
    final gateway = _gateway.text.trim();
    if (_static) {
      if (address.isEmpty || gateway.isEmpty || prefix == null) {
        setState(() => _error = 'Vul adres, netmasker en gateway in.');
        return;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Serveradres wijzigen?'),
        content: Text(
          _static
              ? 'De server gaat naar $address. Open daarna http://$address:${_port()} '
                  'binnen 2 minuten. Lukt dat niet, dan gaat het vorige adres terug.'
              : 'De server vraagt een adres aan de router. Blijft het adres hetzelfde, '
                  'dan is er niets te doen. Verandert het, open het nieuwe adres binnen '
                  '2 minuten, anders gaat het vorige terug.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Toepassen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dns = _dns.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(2)
          .toList();
      final res = await http
          .post(
            Uri.parse('$apiBase/api/admin/host-network'),
            headers: _headers(),
            body: jsonEncode({
              'mode': _static ? 'static' : 'dhcp',
              if (_static) 'address': address,
              if (_static) 'prefix': prefix,
              if (_static) 'gateway': gateway,
              if (dns.isNotEmpty) 'dns': dns,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body);
        final message = body is Map ? body['message'] : null;
        throw StateError(
          message is String && message.isNotEmpty
              ? message
              : 'Netwerk wijzigen mislukt (${res.statusCode}).',
        );
      }
      if (_static) {
        await _followStatic(address);
      } else {
        await _followDhcp();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _followStatic(String address) async {
    final next = 'http://$address:${_port()}';
    if (kIsWeb) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Open het nieuwe adres'),
          content: Text(
            'Deze pagina valt zo weg. Open $next binnen 2 minuten. '
            'Doe je dat niet, dan gaat het vorige adres terug.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Openen'),
            ),
          ],
        ),
      );
      final uri = Uri.parse(next);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      }
      return;
    }
    final previous = localApiBase;
    await setApiBase(next);
    final reached = await _waitUntilReached();
    if (!mounted) return;
    if (reached) {
      setState(() => _info = 'De server staat op $address. Dit tablet gebruikt dat adres.');
      return;
    }
    await setApiBase(previous);
    setState(() {
      _error = 'Dit tablet kreeg $address niet te pakken. '
          'Open $next binnen 2 minuten. Lukt dat niet, dan gaat het vorige adres terug.';
    });
  }

  Future<void> _followDhcp() async {
    final body = await _waitForBody();
    if (!mounted) return;
    if (body == null) {
      setState(() {
        _error = 'Het adres is waarschijnlijk veranderd. Kijk op de router welk '
            'adres de server heeft en open dat binnen 2 minuten.';
      });
      return;
    }
    setState(() => _apply(body));
  }

  Future<bool> _waitUntilReached() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final body = await _fetch();
        if (body != null && body['available'] == true) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<Map<String, dynamic>?> _waitForBody() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final body = await _fetch();
        if (body != null) return body;
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lan_outlined, color: LuxeColors.brassDeep, size: 22),
              const SizedBox(width: 10),
              Text('SERVERADRES', style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _iface.isEmpty
                ? 'DHCP of een vast adres voor deze server. Niet het KNX-adres.'
                : 'Netwerkkaart $_iface. DHCP of een vast adres. Niet het KNX-adres.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('DHCP')),
                ButtonSegment(value: true, label: Text('Vast adres')),
              ],
              selected: {_static},
              onSelectionChanged: (next) {
                if (_busy || _pending || next.isEmpty) return;
                setState(() => _static = next.first);
              },
            ),
            if (_static) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Adres'),
                keyboardType: TextInputType.number,
                enabled: !_busy && !_pending,
              ),
              TextField(
                controller: _prefix,
                decoration: const InputDecoration(labelText: 'Netmasker (8–30)'),
                keyboardType: TextInputType.number,
                enabled: !_busy && !_pending,
              ),
              TextField(
                controller: _gateway,
                decoration: const InputDecoration(labelText: 'Gateway'),
                keyboardType: TextInputType.number,
                enabled: !_busy && !_pending,
              ),
              TextField(
                controller: _dns,
                decoration: const InputDecoration(
                  labelText: 'DNS (optioneel, komma)',
                ),
                enabled: !_busy && !_pending,
              ),
            ],
            if (_info != null && _info!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_info!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || _pending || _loading ? null : _save,
                child: Text(_busy ? 'Bezig…' : 'Adres toepassen'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
