import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../scene_api.dart';
import '../theme.dart';
import 'widgets/device_widgets.dart';

enum _LearnPhase { warn, listen, learning, duplicate, overview, error }

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
  _LearnPhase _phase = _LearnPhase.warn;
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
  String? _duplicateName;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _confirmWarn());
  }

  @override
  void dispose() {
    _listenTimer?.cancel();
    _pollTimer?.cancel();
    _nameCtrl.dispose();
    final api = ref.read(sceneApiProvider);
    final roomId = widget.roomId;
    api.stopListen(roomId).catchError((_) {});
    super.dispose();
  }

  Future<void> _confirmWarn() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verlichting gaat uit en aan'),
        content: const Text(
          'Om de scene in te lezen gaat alleen de verlichting in deze kamer even uit. '
          'Andere kamers blijven ongemoeid. Daarna drukt u de muurknop. '
          'De app zet ontbrekende lampen in deze kamer op 100% '
          'en roept de scene zelf nog eens op.\n\n'
          'U past daarna de waarden aan. Opslaan in KNX werkt alleen als '
          'scene opslaan in ETS is vrijgegeven.\n\nVerder?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verder'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      Navigator.of(context).pop();
      return;
    }
    await _startListen();
  }

  void _armListenTimeout() {
    _heardHandled = false;
    _listenTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _pollListen();
    });
    _listenTimer = Timer(const Duration(seconds: 22), () {
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
    if (reason == 'wizard_failed') {
      return 'Inlezen mislukt tijdens de analyse. '
          'Als de KNX-verbinding wegviel, verbind opnieuw in de installer en probeer het nog eens.';
    }
    if (_watching.isEmpty) {
      return 'Geen scene-adres voor deze kamer. Koppel een scene-GA aan deze ruimte in de installer (KNX).';
    }
    return 'Geen scene-knop gehoord. Druk de knop in deze kamer; '
        'we luisteren op ${_watching.length} scene-adressen.';
  }

  Future<void> _startListen() async {
    ref.read(knxSceneHeardProvider.notifier).clear();
    setState(() {
      _phase = _LearnPhase.listen;
      _error = null;
      _heardHandled = false;
    });
    try {
      final started =
          await ref.read(sceneApiProvider).startListen(widget.roomId);
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
    if (!mounted || _heardHandled) return;
    if (_phase != _LearnPhase.listen && _phase != _LearnPhase.learning) {
      return;
    }
    try {
      final st = await ref.read(sceneApiProvider).listenStatus(widget.roomId);
      if (!mounted || _heardHandled) return;
      if (_phase != _LearnPhase.listen && _phase != _LearnPhase.learning) {
        return;
      }
      final watching = _stringList(st['watching']);
      if (watching.isNotEmpty && watching.join() != _watching.join()) {
        setState(() => _watching = watching);
      }
      if (st['phase'] == 'busy' && _phase == _LearnPhase.listen) {
        _listenTimer?.cancel();
        setState(() => _phase = _LearnPhase.learning);
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
      existingId: heard['existingId'] as String?,
      existingName: heard['existingName'] as String?,
      learnedMembers: [
        for (final m in (heard['members'] as List?) ?? const [])
          if (m is Map) Map<String, dynamic>.from(m),
      ],
    );
  }

  List<_MemberRow> _membersFromHeard(KnxSceneHeard heard) {
    if (heard.learnedMembers.isNotEmpty) {
      return [
        for (final m in heard.learnedMembers)
          _MemberRow(
            deviceId: '${m['deviceId'] ?? ''}',
            name: '${m['name'] ?? ''}',
            kind: '${m['kind'] ?? 'light'}',
            confirmed: m['confirmed'] != false,
          ),
      ];
    }
    return [
      for (final id in heard.memberIds)
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
  }

  void _onHeard(KnxSceneHeard heard) {
    if (heard.roomId != widget.roomId) return;
    if (_heardHandled) return;
    if (heard.timeout) {
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
    _members = _membersFromHeard(heard);
    final dup = heard.existingName?.trim();
    if (dup != null && dup.isNotEmpty) {
      _duplicateName = dup;
      if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = dup;
      setState(() => _phase = _LearnPhase.duplicate);
      return;
    }
    setState(() => _phase = _LearnPhase.overview);
  }

  Future<void> _forgetExisting() async {
    final id = _scene?.id ?? widget.existing?.id;
    if (id == null || id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inlezing verwijderen?'),
        content: const Text(
          'Deze knop verdwijnt uit de app. De KNX-scene in ETS blijft bestaan. '
          'Daarna kunt u opnieuw inlezen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _storing = true);
    try {
      await ref.read(sceneApiProvider).forgetKnx(widget.roomId, id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LuxeColors.danger,
          behavior: SnackBarBehavior.floating,
          content: Text('Verwijderen mislukt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _storing = false);
    }
  }

  Future<void> _persistAndStore() async {
    final ga = _ga;
    final number = _number;
    final name = _nameCtrl.text.trim();
    if (ga == null || number == null) return;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geef deze knop een naam.')),
      );
      return;
    }
    setState(() => _storing = true);
    try {
      final raw = await ref.read(sceneApiProvider).learn(
            roomId: widget.roomId,
            ga: ga,
            number: number,
            members: [for (final m in _members) m.deviceId],
            name: name,
          );
      if (!mounted) return;
      final sceneJson = raw['scene'] as Map<String, dynamic>?;
      _scene = sceneJson != null ? Scene.fromJson(sceneJson) : _scene;
      final id = _scene?.id;
      if (id != null) {
        await ref.read(sceneApiProvider).store(
              id,
              members: [for (final m in _members) m.deviceId],
              name: name,
            );
      }
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
      if (_phase == _LearnPhase.listen || _phase == _LearnPhase.learning) {
        _onHeard(next);
      }
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
      case _LearnPhase.warn:
        return _message('Even geduld…', progress: true);
      case _LearnPhase.listen:
        return _listenBody();
      case _LearnPhase.learning:
        return _message(
          'Lampen analyseren, daarna 100% en scene opnieuw oproepen…',
          progress: true,
        );
      case _LearnPhase.duplicate:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Scene-adres $_ga nummer $_number bestaat al als “$_duplicateName”. '
                'Meerdere knoppen kunnen hetzelfde KNX-slot delen. '
                'Doorgaan overschrijft die scene.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() => _phase = _LearnPhase.overview),
                child: const Text('Doorgaan'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuleren'),
              ),
            ],
          ),
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
                  onPressed: _confirmWarn, child: const Text('Opnieuw')),
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
        ? 'Geen scene-adressen geconfigureerd.'
        : 'Luisteren op ${_watching.length} scene-adressen:\n$sample$extra';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'Verlichting is uit. Druk nu op de scene-knop in deze kamer.\n'
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Naam schakelaar',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Avond, diner, …',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            _ga == null ? '' : '$_ga  ·  scene $_number',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Stel de waardes bij. Opslaan zet alle KNX-kanalen op dit scene-slot.',
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
                    'Geen lampen of jaloezieën herkend bij deze scene.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (var i = 0; i < _members.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _memberTile(cfg, _members[i]),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _storing ? null : _confirmWarn,
                      child: const Text('Opnieuw inlezen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _storing || _ga == null ? null : _persistAndStore,
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
              if ((_scene?.id ?? widget.existing?.id) != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _storing ? null : _forgetExisting,
                  child: const Text('Inlezing verwijderen'),
                ),
              ],
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
