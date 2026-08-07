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
import 'responsive.dart';
import 'widgets/back_pill.dart';
import 'widgets/luxe_backdrop.dart';

class AlarmScreen extends ConsumerWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: SafeArea(
          child: _AlarmBody(),
        ),
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

  Future<void> _toggleBypass(SatelZone zone) async {
    if (_busy) return;
    final token = ref.read(authProvider).token;
    setState(() { _busy = true; _feedback = null; });
    final result = await satelBypass(
      [zone.zoneNumber],
      bypass: !zone.bypassed,
      pin: _pin.isNotEmpty ? _pin : null,
      token: token,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _feedback = result.ok ? null : (result.error ?? 'Overbruggen mislukt.');
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
        _AlarmHeader(onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hp),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Partition tabs
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

                // Status card
                _PartitionCard(
                  partition: partition ??
                      const SatelPartitionInfo(
                        number: 1,
                        name: '—',
                        state: SatelPartitionState.disarmed,
                      ),
                ),
                const SizedBox(height: 28),

                // PIN pad — enter code, then arm/disarm via the real Satel API.
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
                const SizedBox(height: 36),

                // Zone master list
                _ZoneList(status: status, onToggleBypass: _toggleBypass),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _AlarmHeader extends StatelessWidget {
  const _AlarmHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.82),
        border: Border(
          bottom: BorderSide(color: LuxeColors.line, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          BackPill(onTap: onBack),
          Expanded(
            child: Text(
              'Alarm',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: LuxeColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(partitions.length, (i) {
          final p        = partitions[i];
          final selected = i == selectedIdx;
          final cfg      = _stateConfig(p.state);
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? cfg.color.withValues(alpha: 0.12)
                    : LuxeColors.surfaceDim,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? cfg.color.withValues(alpha: 0.40)
                      : LuxeColors.line,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? cfg.color : LuxeColors.inkSoft,
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
    final cfg = _stateConfig(partition.state);

    return AnimatedContainer(
      duration: Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: cfg.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cfg.color.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: cfg.color.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cfg.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cfg.color.withValues(alpha: 0.35)),
            ),
            child: Icon(cfg.icon, color: cfg.color, size: 26),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cfg.label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cfg.color,
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

_StateCfg _stateConfig(SatelPartitionState s) => switch (s) {
      SatelPartitionState.disarmed =>
        const _StateCfg('Uitgeschakeld', Icons.lock_open_outlined, Color(0xFF4CAF50)),
      SatelPartitionState.armed =>
        const _StateCfg('Ingeschakeld', Icons.security_outlined, Color(0xFFD64545)),
      SatelPartitionState.exitDelay =>
        const _StateCfg('Uitlooptijd…', Icons.directions_run_rounded, Color(0xFFE07A3F)),
      SatelPartitionState.entryDelay =>
        const _StateCfg('Inlooptijd!', Icons.warning_amber_rounded, Color(0xFFD64545)),
    };

// ---------------------------------------------------------------------------
// Zone master list
// ---------------------------------------------------------------------------

class _ZoneList extends StatefulWidget {
  const _ZoneList({required this.status, this.onToggleBypass});
  final SatelStatus status;
  final void Function(SatelZone zone)? onToggleBypass;

  @override
  State<_ZoneList> createState() => _ZoneListState();
}

class _ZoneListState extends State<_ZoneList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final zones   = widget.status.allZones;
    if (zones.isEmpty) return const SizedBox.shrink();
    final violated = zones.where((z) => z.violated).toList();
    final shown    = _expanded ? zones : violated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Text(
                'ZONES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                  color: LuxeColors.inkSoft,
                ),
              ),
              SizedBox(width: 8),
              if (violated.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD64545).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${violated.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD64545),
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                _expanded ? 'Verbergen' : 'Alles tonen (${zones.length})',
                style: TextStyle(
                  fontSize: 12,
                  color: LuxeColors.brass,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: LuxeColors.brass,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!_expanded && shown.isEmpty)
          _EmptyZones()
        else
          ...(_buildGrouped(shown)),
      ],
    );
  }

  List<Widget> _buildGrouped(List<SatelZone> zones) {
    final byRoom = <String, List<SatelZone>>{};
    for (final z in zones) {
      (byRoom[z.room] ??= []).add(z);
    }
    return [
      for (final entry in byRoom.entries) ...[
        _RoomGroupHeader(room: entry.key),
        const SizedBox(height: 6),
        for (final z in entry.value) ...[
          _ZoneRow(zone: z, onToggleBypass: widget.onToggleBypass),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 6),
      ],
    ];
  }
}

class _EmptyZones extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 16, color: LuxeColors.inkFaint),
          SizedBox(width: 8),
          Text(
            'Alle zones gesloten',
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
      padding: EdgeInsets.only(bottom: 2),
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
  const _ZoneRow({required this.zone, this.onToggleBypass});
  final SatelZone zone;
  final void Function(SatelZone zone)? onToggleBypass;

  static const _amber = Color(0xFFB8860B);

  @override
  Widget build(BuildContext context) {
    final cfg = satelDeviceConfig(zone.deviceType, zone.violated);
    final dim = zone.bypassed;

    return Opacity(
      opacity: dim ? 0.6 : 1.0,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: zone.violated
              ? cfg.color.withValues(alpha: 0.07)
              : LuxeColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: zone.violated
                ? cfg.color.withValues(alpha: 0.25)
                : LuxeColors.line,
            width: 0.5,
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
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zone.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: LuxeColors.ink,
                    ),
                  ),
                  Text(
                    zone.bypassed ? '${cfg.label} · overbrugd' : cfg.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: LuxeColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (zone.bypassed)
              _Pill(text: 'Overbrugd', color: _amber)
            else if (zone.violated)
              _Pill(text: cfg.alertLabel, color: cfg.color)
            else
              Icon(Icons.check_rounded,
                  size: 16,
                  color: LuxeColors.inkFaint.withValues(alpha: 0.50)),
            if (onToggleBypass != null) ...[
              SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: zone.bypassed ? 'Activeren' : 'Overbruggen',
                icon: Icon(
                  zone.bypassed
                      ? Icons.block_rounded
                      : Icons.block_outlined,
                  size: 18,
                  color: zone.bypassed ? _amber : LuxeColors.inkFaint,
                ),
                onPressed: () => onToggleBypass!(zone),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
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
