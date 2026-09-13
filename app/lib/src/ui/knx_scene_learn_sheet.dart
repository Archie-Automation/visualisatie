import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../scene_api.dart';
import '../theme.dart';
import 'widgets/device_widgets.dart';

enum _LearnPhase { listen, confirm, learning, overview, error }

/// Inlezen van een KNX-hardware-scene vanaf een muurknop, daarna live bijstellen.
class KnxSceneLearnSheet extends ConsumerStatefulWidget {
  const KnxSceneLearnSheet({
    super.key,
    required this.roomId,
    required this.config,
    this.existing,
  });

  final String roomId;
  final HouseConfig config;
  final Scene? existing;

  @override
  ConsumerState<KnxSceneLearnSheet> createState() => _KnxSceneLearnSheetState();
}

class _KnxSceneLearnSheetState extends ConsumerState<KnxSceneLearnSheet> {
  _LearnPhase _phase = _LearnPhase.listen;
  String? _error;
  String? _ga;
  int? _number;
  Scene? _scene;
  List<_MemberRow> _members = [];
  bool _storing = false;
  Timer? _listenTimer;
  Timer? _pollTimer;
  List<String> _watching = const [];
  bool _heardHandled = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null && existing.isKnxHardware) {
      _ga = existing.knxGa;
      _number = existing.knxNumber;
      _scene = existing;
      _members = [
        for (final id in existing.members)
          _MemberRow(
            deviceId: id,
            name: widget.config.deviceById(id)?.name ?? id,
            kind: widget.config.deviceById(id)?.type == DeviceType.shading ||
                    widget.config.deviceById(id)?.type ==
                        DeviceType.positionActuator
                ? 'shading'
                : 'light',
            confirmed: true,
          ),
      ];
      _phase = _LearnPhase.overview;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListen());
  }

  @override
  void dispose() {
    _listenTimer?.cancel();
    _pollTimer?.cancel();
    final api = ref.read(sceneApiProvider);
    final roomId = widget.roomId;
    api.stopListen(roomId).catchError((_) {});
    super.dispose();
  }

  void _armListenTimeout() {
    _heardHandled = false;
    _listenTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _pollListen();
    });
    _listenTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      if (_phase != _LearnPhase.listen) return;
      _pollTimer?.cancel();
      setState(() {
        _phase = _LearnPhase.error;
        _error = _listenTimeoutText();
      });
      ref.read(sceneApiProvider).stopListen(widget.roomId).catchError((_) {});
    });
  }

  String _listenTimeoutText({String? reason}) {
    if (reason == 'no_scene_byte') {
      return 'Lampen of jaloezieën in deze kamer gaven terugmelding, '
          'maar er kwam geen 1-byte telegram vlak daarvoor (scene-adres).';
    }
    if (_watching.isEmpty) {
      return 'Geen lampen of jaloezieën in deze kamer om te volgen.';
    }
    return 'Geen scene-knop gehoord. Druk de knop in deze kamer; '
        'we volgen ${_watching.length} groepsadressen van lampen en jaloezieën.';
  }

  Future<void> _startListen() async {
    ref.read(knxSceneHeardProvider.notifier).clear();
    setState(() {
      _phase = _LearnPhase.listen;
      _error = null;
      _heardHandled = false;
    });
    try {
      final started = await ref.read(sceneApiProvider).startListen(widget.roomId);
      if (!mounted) return;
      setState(() {
        _watching = _stringList(started['watching']);
      });
      _armListenTimeout();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LearnPhase.error;
        _error = '$e';
      });
    }
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if ('$e'.trim().isNotEmpty) '$e'.trim(),
    ];
  }

  Future<void> _pollListen() async {
    if (!mounted || _phase != _LearnPhase.listen || _heardHandled) return;
    try {
      final st = await ref.read(sceneApiProvider).listenStatus(widget.roomId);
      if (!mounted || _phase != _LearnPhase.listen || _heardHandled) return;
      final watching = _stringList(st['watching']);
      if (watching.isNotEmpty && watching.join() != _watching.join()) {
        setState(() {
          _watching = watching;
        });
      }
      final heard = st['heard'];
      if (heard is Map) {
        _onHeard(_heardFromMap(heard));
      }
    } catch (_) {}
  }

  KnxSceneHeard _heardFromMap(Map<dynamic, dynamic> heard) {
    return KnxSceneHeard(
      roomId: '${heard['roomId'] ?? ''}',
      ga: '${heard['ga'] ?? ''}',
      number: (heard['number'] as num?)?.toInt() ?? 1,
      trusted: heard['trusted'] == true,
      timeout: heard['timeout'] == true,
      memberIds: [
        for (final id in (heard['memberIds'] as List?) ?? const [])
          if ('$id'.trim().isNotEmpty) '$id'.trim(),
      ],
      reason: heard['reason'] as String?,
    );
  }

  void _onHeard(KnxSceneHeard heard) {
    if (heard.roomId != widget.roomId) return;
    if (_heardHandled) return;
    if (heard.timeout) {
      if (_phase != _LearnPhase.listen) return;
      _heardHandled = true;
      _listenTimer?.cancel();
      _pollTimer?.cancel();
      setState(() {
        _phase = _LearnPhase.error;
        _error = _listenTimeoutText(reason: heard.reason);
      });
      return;
    }
    if (heard.ga.trim().isEmpty) return;
    _heardHandled = true;
    _listenTimer?.cancel();
    _pollTimer?.cancel();
    _ga = heard.ga;
    _number = heard.number;
    _runLearn(members: heard.memberIds);
  }

  Future<void> _runLearn({List<String>? members}) async {
    final ga = _ga;
    final number = _number;
    if (ga == null || number == null) return;
    setState(() => _phase = _LearnPhase.learning);
    try {
      final raw = await ref.read(sceneApiProvider).learn(
            roomId: widget.roomId,
            ga: ga,
            number: number,
            members: members,
          );
      if (!mounted) return;
      final sceneJson = raw['scene'] as Map<String, dynamic>?;
      _scene = sceneJson != null ? Scene.fromJson(sceneJson) : null;
      final list = (raw['members'] as List?) ?? const [];
      _members = [
        for (final m in list)
          if (m is Map)
            _MemberRow(
              deviceId: '${m['deviceId'] ?? ''}',
              name: '${m['name'] ?? ''}',
              kind: '${m['kind'] ?? 'light'}',
              confirmed: m['confirmed'] != false,
            ),
      ];
      setState(() => _phase = _LearnPhase.overview);
      ref.invalidate(configProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LearnPhase.error;
        _error = '$e';
      });
    }
  }

  Future<void> _store() async {
    final id = _scene?.id;
    if (id == null) return;
    setState(() => _storing = true);
    try {
      await ref.read(sceneApiProvider).store(
            id,
            members: [for (final m in _members) m.deviceId],
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LuxeColors.danger,
          behavior: SnackBarBehavior.floating,
          content: Text('Opslaan mislukt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _storing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<KnxSceneHeard?>(knxSceneHeardProvider, (prev, next) {
      if (next == null) return;
      if (_phase == _LearnPhase.listen) _onHeard(next);
    });

    final mq = MediaQuery.of(context);
    final sheetHeight = (mq.size.height * 0.92 - mq.viewInsets.bottom)
        .clamp(320.0, mq.size.height * 0.92);
    return SizedBox(
      height: sheetHeight,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: LuxeColors.cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: LuxeShadows.lift,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'KNX-scene inlezen',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _LearnPhase.listen:
        return _listenBody();
      case _LearnPhase.confirm:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Scene $_number op $_ga — klopt dat?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Dit groepsadres staat niet als scene in de catalogus. Bevestig alleen als u een scene-knop indrukte.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _runLearn,
                child: const Text('Ja, inlezen'),
              ),
              TextButton(
                onPressed: _startListen,
                child: const Text('Nee, opnieuw luisteren'),
              ),
            ],
          ),
        );
      case _LearnPhase.learning:
        return _message(
          'Busverkeer van deze kamer verwerken…',
          progress: true,
        );
      case _LearnPhase.error:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(_error ?? 'Mislukt',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _startListen, child: const Text('Opnieuw')),
            ],
          ),
        );
      case _LearnPhase.overview:
        return _overview();
    }
  }

  Widget _listenBody() {
    final sample = _watching.take(24).join(', ');
    final extra = _watching.length > 24 ? ' …' : '';
    final hint = _watching.isEmpty
        ? 'Geen lampen of jaloezieën in deze kamer.'
        : 'Volgen van ${_watching.length} adressen '
            '(dim stuur/status, schakelbit, jaloezie positie — wat er is). '
            'Het 1-byte telegram vlak vóór de eerste terugmelding is het scene-adres.\n'
            '$sample$extra';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'Druk nu op de scene-knop in deze kamer.\n'
              'Niet elders bedienen tot het overzicht er is.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text, {bool progress = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progress) const CircularProgressIndicator(),
            if (progress) const SizedBox(height: 20),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _overview() {
    final cfg = ref.watch(configProvider).value ?? widget.config;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            _scene == null
                ? 'Scene $_number'
                : '${_scene!.name}  ·  $_ga / $_number',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Alle kanalen op deze scene-knop in KNX worden op de huidige stand gezet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (_members.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Geen lampen herkend. Voeg handmatig toe of leer opnieuw.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (var i = 0; i < _members.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _memberTile(cfg, _members[i]),
              ],
              ..._addableDevices(cfg).map(
                (d) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _members = [
                        ..._members,
                        _MemberRow(
                          deviceId: d.id,
                          name: d.name,
                          kind: d.usesPositionControl ? 'shading' : 'light',
                          confirmed: true,
                        ),
                      ];
                    }),
                    child: Text('Toevoegen: ${d.name}'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _ga == null ? _startListen : _runLearn,
                  child: const Text('Opnieuw leren'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _storing || _scene == null ? null : _store,
                  child: _storing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Opslaan in KNX'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberTile(HouseConfig cfg, _MemberRow m) {
    final d = cfg.deviceById(m.deviceId);
    final unconfirmed = m.kind == 'shading' && !m.confirmed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unconfirmed)
          Text(
            '${m.name} (gordijn — bevestig of het meedoet)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        if (d != null) deviceWidget(d),
        if (d == null) Text(m.name),
      ],
    );
  }

  Iterable<Device> _addableDevices(HouseConfig cfg) {
    Room? room;
    for (final f in cfg.floors) {
      for (final r in f.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (room == null) return const [];
    final have = {for (final m in _members) m.deviceId};
    return room.devices.where((d) {
      if (have.contains(d.id)) return false;
      if (d.isLutronBusControl) return false;
      return d.type == DeviceType.lightSwitch ||
          d.type == DeviceType.lightDimmer ||
          d.type == DeviceType.rgbwWw ||
          d.type == DeviceType.shading ||
          d.type == DeviceType.positionActuator;
    });
  }
}

class _MemberRow {
  const _MemberRow({
    required this.deviceId,
    required this.name,
    required this.kind,
    required this.confirmed,
  });
  final String deviceId;
  final String name;
  final String kind;
  final bool confirmed;
}
