/// Dedicated alarm page: partition status, Arm/Disarm buttons, and a
/// full master-list of all configured Satel zones.
///
/// The arm/disarm PIN is stored server-side (set by the installer) and is
/// never transmitted from the Flutter app — just press the button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../satel_api.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'responsive.dart';
import 'widgets/function_screen_header.dart';
import 'widgets/luxe_backdrop.dart';

class AlarmScreen extends ConsumerWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: _AlarmBody(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _AlarmBody extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AlarmBody> createState() => _AlarmBodyState();
}

class _AlarmBodyState extends ConsumerState<_AlarmBody> {
  int _selectedPartitionIdx = 0;
  String _pin = '';
  bool _busy = false;
  String? _feedback;

  static const int _minPinLen = 4;
  static const int _maxPinLen = 8;

  void _digit(String d) {
    if (_pin.length >= _maxPinLen) return;
    setState(() { _pin += d; _feedback = null; });
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  /// Arm modes configured for a partition (from the Satel service config).
  List<SatelArmMode> _armModesFor(int number) {
    final svc = ref.read(satelServiceConfigProvider).value;
    if (svc != null) {
      for (final p in svc.partitions) {
        if (p.number == number) return p.armModes;
      }
    }
    return const [SatelArmMode(mode: 0, name: 'Volledig')];
  }

  Future<void> _toggleArm(SatelPartitionInfo partition) async {
    if (_pin.length < _minPinLen) return;
    final token = ref.read(authProvider).token;
    final doArm = partition.isDisarmed || partition.isExitDelay;

    if (!doArm) {
      await _runAction(
          () => satelDisarm(partition.number, pin: _pin, token: token));
      return;
    }

    // Arming: let the user pick a mode when more than one is configured.
    final modes = _armModesFor(partition.number);
    int mode = modes.isNotEmpty ? modes.first.mode : 0;
    if (modes.length > 1) {
      final chosen = await _pickArmMode(modes);
      if (chosen == null) return; // cancelled
      mode = chosen;
    }
    await _runAction(
        () => satelArm(partition.number, mode: mode, pin: _pin, token: token));
  }

  Future<int?> _pickArmMode(List<SatelArmMode> modes) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: LuxeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('Kies inschakelmodus',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: LuxeColors.ink)),
            ),
            for (final m in modes)
              ListTile(
                leading: Icon(Icons.shield_outlined,
                    color: LuxeColors.brass),
                title: Text(m.name,
                    style: TextStyle(color: LuxeColors.ink)),
                onTap: () => Navigator.of(ctx).pop(m.mode),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _runAction(
      Future<({bool ok, String? error})> Function() action) async {
    setState(() { _busy = true; _feedback = null; });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin  = '';
      _feedback = result.ok ? null : (result.error ?? 'Onbekende fout.');
    });
    if (result.ok) HapticFeedback.lightImpact();
  }

  Future<void> _toggleBypass(SatelZone zone) =>
      _bypassZones([zone], bypass: !zone.bypassed);

  Future<void> _bypassZones(
    List<SatelZone> zones, {
    required bool bypass,
  }) async {
    if (_busy || zones.isEmpty) return;
    final token = ref.read(authProvider).token;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    final result = await satelBypass(
      zones.map((z) => z.zoneNumber).toList(),
      bypass: bypass,
      pin: _pin.isNotEmpty ? _pin : null,
      token: token,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _feedback = result.ok
          ? null
          : (result.error ??
              (bypass ? 'Overbruggen mislukt.' : 'Herstellen mislukt.'));
    });
    if (result.ok) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(satelStatusProvider);

    // Use live partitions when connected; otherwise fall back to the
    // installer-configured partition names (house.json) so the screen still
    // shows the correct structure before/without a live connection.
    List<SatelPartitionInfo> partitions = status.partitions;
    if (partitions.isEmpty) {
      final mainParts = ref.watch(satelMainConfigProvider).value?.partitions;
      final svcParts  = ref.watch(satelServiceConfigProvider).value?.partitions;
      final cfgParts  = (mainParts != null && mainParts.isNotEmpty)
          ? mainParts
          : svcParts;
      if (cfgParts != null && cfgParts.isNotEmpty) {
        partitions = cfgParts
            .map((p) => SatelPartitionInfo(
                  number: p.number,
                  name: p.name,
                  state: SatelPartitionState.disarmed,
                ))
            .toList();
      }
    }
    final hp = context.hPad;

    if (_selectedPartitionIdx >= partitions.length && partitions.isNotEmpty) {
      _selectedPartitionIdx = 0;
    }
    final partition =
        partitions.isNotEmpty ? partitions[_selectedPartitionIdx] : null;

    return Column(
      children: [
        FunctionScreenHeader(
          onBack: () => appBack(context),
          title: 'Alarm',
        ),
        Expanded(
          child: SafeArea(
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  if (partitions.length > 1) ...[
                    _PartitionTabBar(
                      partitions: partitions,
                      selectedIdx: _selectedPartitionIdx,
                      onSelect: (i) => setState(() {
                        _selectedPartitionIdx = i;
                        _feedback = null;
                        _pin = '';
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _PartitionCard(
                    partition: partition ??
                        const SatelPartitionInfo(
                          number: 1,
                          name: '—',
                          state: SatelPartitionState.disarmed,
                        ),
                  ),
                  const SizedBox(height: 28),
                  _PinSection(
                    pin: _pin,
                    busy: _busy,
                    feedback: _feedback,
                    canConfirm: _pin.length >= _minPinLen,
                    partition: partition,
                    onDigit: _digit,
                    onBackspace: _backspace,
                    onConfirm: partition != null
                        ? () => _toggleArm(partition)
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        _ZoneDock(
          status: status,
          busy: _busy,
          onToggleBypass: _toggleBypass,
          onBypassAll: (zones) => _bypassZones(zones, bypass: true),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Partition tab bar
// ---------------------------------------------------------------------------

class _PartitionTabBar extends StatelessWidget {
  const _PartitionTabBar({
    required this.partitions,
    required this.selectedIdx,
    required this.onSelect,
  });

  final List<SatelPartitionInfo> partitions;
  final int selectedIdx;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(partitions.length, (i) {
          final p        = partitions[i];
          final selected = i == selectedIdx;
          final cfg      = _stateConfig(p.state, dark: dark);
          final fill = selected
              ? Color.alphaBlend(
                  cfg.color.withValues(alpha: dark ? 0.22 : 0.12),
                  LuxeColors.surface,
                )
              : LuxeColors.surface;
          final rim = selected
              ? LuxeBorders.solid(
                  cfg.color.withValues(alpha: dark ? 0.75 : 0.55),
                )
              : LuxeBorders.solid(
                  LuxeColors.ink.withValues(alpha: dark ? 0.22 : 0.14),
                );
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: rim, width: selected ? 1.5 : 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? LuxeColors.ink : LuxeColors.inkSoft,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    cfg.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? cfg.color : LuxeColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Partition status card
// ---------------------------------------------------------------------------

class _PartitionCard extends StatelessWidget {
  const _PartitionCard({required this.partition});
  final SatelPartitionInfo partition;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cfg = _stateConfig(partition.state, dark: dark);
    final fill = LuxeColors.surface.withValues(alpha: dark ? 0.34 : 0.46);
    final rim = dark
        ? LuxeColors.glassRim
        : LuxeBorders.solid(LuxeColors.ink.withValues(alpha: 0.16));
    final discFill = Color.alphaBlend(
      cfg.color.withValues(alpha: dark ? 0.28 : 0.14),
      LuxeColors.surface.withValues(alpha: dark ? 0.55 : 0.72),
    );
    final discRim = LuxeBorders.solid(
      cfg.color.withValues(alpha: dark ? 0.75 : 0.50),
    );

    return LuxeRimBox(
      radius: 22,
      rimWidth: 1.25,
      fillColor: fill,
      rimColor: rim,
      shadows: LuxeShadows.chip(context),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(color: cfg.color, child: const SizedBox(width: 5)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 22, 20),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: discFill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: discRim),
                      ),
                      child: Icon(cfg.icon, color: cfg.color, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cfg.label,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: LuxeColors.ink,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            partition.name.trim().isNotEmpty
                                ? partition.name
                                : 'Partitie ${partition.number}',
                            style: TextStyle(
                              fontSize: 12,
                              color: LuxeColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN entry panel (real mode)
// ---------------------------------------------------------------------------

class _PinSection extends StatelessWidget {
  const _PinSection({
    required this.pin,
    required this.busy,
    required this.feedback,
    required this.canConfirm,
    required this.partition,
    required this.onDigit,
    required this.onBackspace,
    required this.onConfirm,
  });

  final String pin;
  final bool busy;
  final String? feedback;
  final bool canConfirm;
  final SatelPartitionInfo? partition;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final doArm = partition == null ||
        partition!.isDisarmed ||
        partition!.isExitDelay;
    final label = doArm ? 'Inschakelen' : 'Uitschakelen';
    final color = doArm
        ? const Color(0xFFD64545)
        : const Color(0xFF4CAF50);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 320),
      child: Column(
        children: [
          // PIN dots display
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: LuxeColors.surfaceDim,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LuxeColors.line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(8, (i) {
                final filled = i < pin.length;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? color
                          : LuxeColors.inkFaint.withValues(alpha: 0.3),
                    ),
                  ),
                );
              }),
            ),
          ),
          SizedBox(height: 16),

          // Numeric keypad
          _NumPad(onDigit: onDigit, onBackspace: onBackspace),
          const SizedBox(height: 16),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: Material(
              color: canConfirm
                  ? color.withValues(alpha: 0.12)
                  : LuxeColors.surfaceDim,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: (busy || !canConfirm || onConfirm == null)
                    ? null
                    : onConfirm,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: canConfirm
                          ? color.withValues(alpha: 0.40)
                          : LuxeColors.line,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: color,
                          ),
                        )
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: canConfirm ? color : LuxeColors.inkFaint,
                          ),
                        ),
                ),
              ),
            ),
          ),

          if (feedback != null) ...[
            const SizedBox(height: 10),
            Text(
              feedback!,
              style: const TextStyle(
                color: Color(0xFFD64545),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Numeric keypad widget
// ---------------------------------------------------------------------------

class _NumPad extends StatelessWidget {
  const _NumPad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: row.map((key) {
              final isEmpty = key.isEmpty;
              final isBack  = key == '⌫';
              return Expanded(
                child: isEmpty
                    ? const SizedBox()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _PadKey(
                          label: key,
                          isBackspace: isBack,
                          onTap: isBack
                              ? onBackspace
                              : () => onDigit(key),
                        ),
                      ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.isBackspace,
    required this.onTap,
  });

  final String label;
  final bool isBackspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LuxeColors.surfaceDim,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LuxeColors.line),
          ),
          alignment: Alignment.center,
          child: isBackspace
              ? Icon(Icons.backspace_outlined,
                  size: 20, color: LuxeColors.inkSoft)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: LuxeColors.ink,
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State helper
// ---------------------------------------------------------------------------

class _StateCfg {
  const _StateCfg(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

_StateCfg _stateConfig(SatelPartitionState s, {required bool dark}) =>
    switch (s) {
      SatelPartitionState.disarmed => _StateCfg(
          'Uitgeschakeld',
          Icons.lock_open_outlined,
          dark ? const Color(0xFF8FCB9B) : const Color(0xFF2C5A40),
        ),
      SatelPartitionState.armed => _StateCfg(
          'Ingeschakeld',
          Icons.security_outlined,
          dark ? const Color(0xFFFF8A8A) : const Color(0xFF9B2E2E),
        ),
      SatelPartitionState.exitDelay => _StateCfg(
          'Uitlooptijd…',
          Icons.directions_run_rounded,
          dark ? const Color(0xFFFFB074) : const Color(0xFFB45A1F),
        ),
      SatelPartitionState.entryDelay => _StateCfg(
          'Inlooptijd!',
          Icons.warning_amber_rounded,
          dark ? const Color(0xFFFF8A8A) : const Color(0xFF9B2E2E),
        ),
    };

// ---------------------------------------------------------------------------
// Zone dock — always at the bottom of the alarm panel
// ---------------------------------------------------------------------------

class _ZoneDock extends StatefulWidget {
  const _ZoneDock({
    required this.status,
    required this.busy,
    required this.onToggleBypass,
    required this.onBypassAll,
  });

  final SatelStatus status;
  final bool busy;
  final void Function(SatelZone zone) onToggleBypass;
  final void Function(List<SatelZone> zones) onBypassAll;

  @override
  State<_ZoneDock> createState() => _ZoneDockState();
}

class _ZoneDockState extends State<_ZoneDock> {
  bool _showAll = false;

  static const _alert = Color(0xFFD64545);
  static const _amber = Color(0xFFB8860B);

  @override
  Widget build(BuildContext context) {
    final zones = widget.status.allZones;
    final violated = zones.where((z) => z.violated && !z.bypassed).toList();
    final bypassed = zones.where((z) => z.bypassed).toList();
    final phone = context.isPhone;
    final maxH = MediaQuery.sizeOf(context).height * (phone ? 0.34 : 0.38);

    return Material(
      color: LuxeColors.surface.withValues(alpha: 0.94),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(height: 1, color: LuxeColors.line),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.hPad, 12, context.hPad, 10,
                ),
                child: _header(violated, bypassed, zones),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                    context.hPad, 0, context.hPad, 12,
                  ),
                  children: [
                    if (violated.isEmpty && bypassed.isEmpty && !_showAll)
                      _EmptyZones(
                        label: zones.isEmpty
                            ? 'Geen zones gekoppeld'
                            : 'Geen zones in overtreding',
                      )
                    else ...[
                      if (violated.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BypassAllButton(
                            enabled: !widget.busy,
                            onTap: () => widget.onBypassAll(violated),
                          ),
                        ),
                      if (violated.isNotEmpty) ...[
                        _SectionLabel(
                          'In overtreding',
                          count: violated.length,
                          color: _alert,
                        ),
                        const SizedBox(height: 6),
                        for (final z in violated) ...[
                          _ZoneRow(
                            zone: z,
                            busy: widget.busy,
                            onToggleBypass: widget.onToggleBypass,
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],
                      if (bypassed.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _SectionLabel(
                          'Overbrugd',
                          count: bypassed.length,
                          color: _amber,
                        ),
                        const SizedBox(height: 6),
                        for (final z in bypassed) ...[
                          _ZoneRow(
                            zone: z,
                            busy: widget.busy,
                            onToggleBypass: widget.onToggleBypass,
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],
                      if (_showAll) ...[
                        const SizedBox(height: 8),
                        ..._buildGrouped(
                          zones
                              .where((z) => !z.violated && !z.bypassed)
                              .toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    List<SatelZone> violated,
    List<SatelZone> bypassed,
    List<SatelZone> zones,
  ) {
    final n = violated.length;
    final title = n > 0
        ? (n == 1 ? '1 zone in overtreding' : '$n zones in overtreding')
        : bypassed.isNotEmpty
            ? 'Zones overbrugd'
            : 'Zones';
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: n > 0 ? _alert : LuxeColors.inkSoft,
            ),
          ),
        ),
        if (zones.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _showAll = !_showAll),
            child: Row(
              children: [
                Text(
                  _showAll ? 'Minder' : 'Alle zones (${zones.length})',
                  style: TextStyle(
                    fontSize: 12,
                    color: LuxeColors.brass,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  _showAll
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  size: 18,
                  color: LuxeColors.brass,
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildGrouped(List<SatelZone> zones) {
    if (zones.isEmpty) return const [];
    final byRoom = <String, List<SatelZone>>{};
    for (final z in zones) {
      (byRoom[z.room.isEmpty ? 'Overig' : z.room] ??= []).add(z);
    }
    return [
      _SectionLabel('Overige zones', count: zones.length),
      const SizedBox(height: 6),
      for (final entry in byRoom.entries) ...[
        _RoomGroupHeader(room: entry.key),
        const SizedBox(height: 6),
        for (final z in entry.value) ...[
          _ZoneRow(
            zone: z,
            busy: widget.busy,
            onToggleBypass: widget.onToggleBypass,
          ),
          const SizedBox(height: 6),
        ],
      ],
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.count, this.color});
  final String label;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? LuxeColors.inkFaint;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.6,
            color: c,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ],
    );
  }
}

class _BypassAllButton extends StatelessWidget {
  const _BypassAllButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFB8860B);
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              'Alles overbruggen',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: enabled ? color : color.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyZones extends StatelessWidget {
  const _EmptyZones({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 16, color: LuxeColors.inkFaint),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: LuxeColors.inkFaint, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _RoomGroupHeader extends StatelessWidget {
  const _RoomGroupHeader({required this.room});
  final String room;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, top: 4),
      child: Text(
        room.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.8,
          color: LuxeColors.inkFaint,
        ),
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.onToggleBypass,
    this.busy = false,
  });
  final SatelZone zone;
  final void Function(SatelZone zone) onToggleBypass;
  final bool busy;

  static const _amber = Color(0xFFB8860B);

  @override
  Widget build(BuildContext context) {
    final cfg = satelDeviceConfig(zone.deviceType, zone.violated);
    final actionLabel = zone.bypassed ? 'Herstel' : 'Overbrug';
    final actionColor = zone.bypassed ? _amber : cfg.color;
    final room = zone.room.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: zone.bypassed
            ? _amber.withValues(alpha: 0.07)
            : zone.violated
                ? cfg.color.withValues(alpha: 0.07)
                : LuxeColors.surfaceDim,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: zone.bypassed
              ? _amber.withValues(alpha: 0.28)
              : zone.violated
                  ? cfg.color.withValues(alpha: 0.28)
                  : LuxeColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cfg.color.withValues(alpha: zone.violated ? 0.15 : 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(cfg.icon, size: 18, color: cfg.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zone.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LuxeColors.ink,
                  ),
                ),
                Text(
                  [
                    if (room.isNotEmpty) room,
                    zone.bypassed
                        ? 'overbrugd'
                        : zone.violated
                            ? cfg.alertLabel
                            : cfg.label,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: LuxeColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: actionColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: busy ? null : () => onToggleBypass(zone),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96, minHeight: 40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: busy
                            ? actionColor.withValues(alpha: 0.4)
                            : actionColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device type → icon / colour / label
// ---------------------------------------------------------------------------

class _DeviceCfg {
  const _DeviceCfg(this.icon, this.color, this.label, this.alertLabel);
  final IconData icon;
  final Color color;
  final String label;
  final String alertLabel;
}

_DeviceCfg satelDeviceConfig(String type, bool violated) {
  const red    = Color(0xFFD64545);
  const orange = Color(0xFFE07A3F);
  const blue   = Color(0xFF5BA7E0);
  final muted  = LuxeColors.inkSoft;

  return switch (type) {
    'magneetcontact' => _DeviceCfg(
        Icons.sensor_door_outlined, violated ? red : muted,
        'Deur- / raamcontact', 'Open'),
    'pir_beweging' => _DeviceCfg(
        Icons.directions_run_rounded, violated ? red : muted,
        'Bewegingsmelder', 'Beweging'),
    'trilcontact' => _DeviceCfg(
        Icons.vibration_rounded, violated ? orange : muted,
        'Trilcontact', 'Trilling'),
    'glasbreuk' => _DeviceCfg(
        Icons.broken_image_outlined, violated ? orange : muted,
        'Glasbreukdetector', 'Glasbreuk'),
    'rookmelder' => _DeviceCfg(
        Icons.local_fire_department_outlined, violated ? red : muted,
        'Rookmelder', 'Rook!'),
    'watermelder' => _DeviceCfg(
        Icons.water_damage_outlined, violated ? blue : muted,
        'Watermelder', 'Water!'),
    'gasmelder' => _DeviceCfg(
        Icons.masks_outlined, violated ? orange : muted,
        'Gasdetector', 'Gas!'),
    'paniekknop' => _DeviceCfg(
        Icons.warning_amber_rounded, violated ? red : muted,
        'Paniekknop', 'Alarm!'),
    _ => _DeviceCfg(
        Icons.sensors_outlined, violated ? orange : muted,
        type, 'Actief'),
  };
}
