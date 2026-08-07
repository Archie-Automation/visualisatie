import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device_control_specs.dart';
import '../../fireplace_step_ranges.dart';
import '../../media_api.dart';
import '../../models.dart';
import '../../scene_entry.dart';
import '../../shading_subtype_glyph.dart';
import '../../theme.dart';
import '../responsive.dart';
import 'device_control_panel.dart';

/// Apparaatnaam, optionele kamerlocatie en samenvatting in scene/tijdschema-editor.
class SceneEntryHeader extends StatelessWidget {
  const SceneEntryHeader({
    super.key,
    required this.deviceName,
    required this.summary,
    this.locationLabel,
  });

  final String deviceName;
  final String summary;
  final String? locationLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (locationLabel != null) ...[
          Text(
            locationLabel!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: LuxeColors.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(deviceName, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(summary, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// Renders the mini-controller for a single [SceneEntry]. The surrounding
/// card (device name, remove button, "take current"-button) is handled
/// by the editor sheet; this widget focuses purely on state input.
class SceneEntryControls extends StatelessWidget {
  const SceneEntryControls({
    super.key,
    required this.entry,
    required this.onChanged,
  });

  final SceneEntry entry;
  final ValueChanged<SceneEntry> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTypeControls(context),
        if (entry.delayMs > 0) ...[
          const SizedBox(height: 12),
          _SceneDelayPicker(
            delayMs: entry.delayMs,
            onChanged: (ms) => onChanged(entry.withDelayMs(ms)),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeControls(BuildContext context) {
    final e = entry;
    if (e is LightSwitchEntry) {
      return _OnOffRow(
        on: e.on,
        onChanged: (v) => onChanged(
            LightSwitchEntry(device: e.device, on: v, delayMs: e.delayMs)),
      );
    }
    if (e is LightDimmerEntry) {
      return _DimmerControls(entry: e, onChanged: onChanged);
    }
    if (e is ShadingEntry) {
      return _ShadingControls(entry: e, onChanged: onChanged);
    }
    if (e is ClimateEntry) {
      return _ClimateControls(entry: e, onChanged: onChanged);
    }
    if (e is FireplaceEntry) {
      return _FireplaceControls(entry: e, onChanged: onChanged);
    }
    if (e is AcEntry) {
      return _AcControls(entry: e, onChanged: onChanged);
    }
    if (e is FanEntry) {
      return _FanControls(entry: e, onChanged: onChanged);
    }
    if (e is RgbwWwEntry) {
      return _RgbwWwSceneControls(entry: e, onChanged: onChanged);
    }
    if (e is MediaEntry) {
      return _MediaControls(entry: e, onChanged: onChanged);
    }
    return const SizedBox.shrink();
  }
}

/// Compact delay on/off control for the device entry header row.
class SceneEntryDelayToggleButton extends StatelessWidget {
  const SceneEntryDelayToggleButton({
    super.key,
    required this.delayMs,
    required this.onChanged,
  });

  final int delayMs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = delayMs > 0;
    return IconButton(
      tooltip: active
          ? 'Vertraging uitzetten (${formatSceneDelay(delayMs)})'
          : 'Vertraging instellen',
      icon: Icon(
        active ? Icons.timer_rounded : Icons.timer_outlined,
        size: 20,
        color: active ? LuxeColors.brassDeep : LuxeColors.inkSoft,
      ),
      onPressed: () {
        if (active) {
          onChanged(0);
        } else {
          onChanged(1000);
        }
      },
    );
  }
}

class _DelayRepeatButton extends StatefulWidget {
  const _DelayRepeatButton({
    required this.icon,
    required this.direction,
    required this.delayMs,
    required this.onChanged,
  });

  final IconData icon;
  /// `-1` = omlaag, `1` = omhoog.
  final int direction;
  final int delayMs;
  final ValueChanged<int> onChanged;

  @override
  State<_DelayRepeatButton> createState() => _DelayRepeatButtonState();
}

class _DelayRepeatButtonState extends State<_DelayRepeatButton> {
  Timer? _holdTimer;
  Timer? _repeatTimer;
  int _repeatTicks = 0;
  bool _repeating = false;
  late int _currentMs;

  @override
  void initState() {
    super.initState();
    _currentMs = widget.delayMs;
  }

  @override
  void didUpdateWidget(covariant _DelayRepeatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_repeating) _currentMs = widget.delayMs;
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  void _cancelAll() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _repeatTicks = 0;
    _repeating = false;
  }

  double _stepSizeSec() {
    final coarse = _currentMs > kSceneDelayHalfStepMaxSec * 1000;
    if (coarse) {
      if (_repeatTicks <= 3) return kSceneDelayCoarseStepSec;
      if (_repeatTicks <= 10) return kSceneDelayCoarseStepSec * 2;
      return kSceneDelayCoarseStepSec * 5;
    }
    if (_repeatTicks <= 3) return kSceneDelayFineStepSec;
    if (_repeatTicks <= 10) return kSceneDelayCoarseStepSec;
    return kSceneDelayCoarseStepSec * 2;
  }

  void _applyStep(double stepSec) {
    final next = adjustSceneDelayMsByDelta(
      _currentMs,
      widget.direction * stepSec,
    );
    _currentMs = next;
    widget.onChanged(next);
  }

  void _fireStep() {
    _applyStep(_stepSizeSec());
    _repeatTicks++;
  }

  void _beginRepeat() {
    _repeating = true;
    _fireStep();
    _scheduleRepeat();
  }

  void _scheduleRepeat() {
    _repeatTimer?.cancel();
    final ms = _repeatTicks <= 3 ? 350 : _repeatTicks <= 10 ? 150 : 80;
    _repeatTimer = Timer(Duration(milliseconds: ms), () {
      if (!mounted || !_repeating) return;
      _fireStep();
      _scheduleRepeat();
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _repeating = false;
    _repeatTicks = 0;
    _currentMs = widget.delayMs;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _beginRepeat();
    });
  }

  void _onPointerUp(PointerEvent event) {
    final shortTap = !_repeating;
    _cancelAll();
    if (shortTap) {
      final next = adjustSceneDelayMs(widget.delayMs, widget.direction);
      _currentMs = next;
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: Material(
        color: LuxeColors.surface,
        shape: CircleBorder(side: BorderSide(color: LuxeColors.line)),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(widget.icon, size: 22, color: LuxeColors.ink),
        ),
      ),
    );
  }
}

class _SceneDelayPicker extends StatefulWidget {
  const _SceneDelayPicker({
    required this.delayMs,
    required this.onChanged,
  });

  final int delayMs;
  final ValueChanged<int> onChanged;

  @override
  State<_SceneDelayPicker> createState() => _SceneDelayPickerState();
}

class _SceneDelayPickerState extends State<_SceneDelayPicker> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatSceneDelayInput(widget.delayMs));
  }

  @override
  void didUpdateWidget(covariant _SceneDelayPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delayMs != widget.delayMs && !_focusNode.hasFocus) {
      _controller.text = formatSceneDelayInput(widget.delayMs);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final ms = parseSceneDelayInput(_controller.text);
    _controller.text = formatSceneDelayInput(ms);
    widget.onChanged(ms);
  }

  void _setDelay(int ms) {
    _controller.text = formatSceneDelayInput(ms);
    widget.onChanged(ms);
  }

  @override
  Widget build(BuildContext context) {
    final touch = context.isPhone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'START NA (SECONDES)',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            color: LuxeColors.inkSoft,
          ),
        ),
        SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _DelayRepeatButton(
              icon: Icons.remove,
              direction: -1,
              delayMs: widget.delayMs,
              onChanged: _setDelay,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                style: Theme.of(context).textTheme.titleMedium,
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: 'sec.',
                  isDense: !touch,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: touch ? 16 : 12,
                  ),
                  filled: true,
                  fillColor: LuxeColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: LuxeColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: LuxeColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: LuxeColors.brass.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                onSubmitted: (_) => _commit(),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ),
            SizedBox(width: 10),
            _DelayRepeatButton(
              icon: Icons.add,
              direction: 1,
              delayMs: widget.delayMs,
              onChanged: _setDelay,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tot 3 secondes in stappen van 0,5 · daarna hele seconden',
          style: TextStyle(fontSize: 11, color: LuxeColors.inkSoft),
        ),
      ],
    );
  }
}

/* --------------------------- shared inputs ---------------------------- */

class _OnOffRow extends StatelessWidget {
  const _OnOffRow({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: true, label: Text('AAN')),
        ButtonSegment(value: false, label: Text('UIT')),
      ],
      selected: {on},
      onSelectionChanged: (sel) => onChanged(sel.first),
      style: ButtonStyle(
        side: WidgetStateProperty.all(
            BorderSide(color: LuxeColors.line)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? LuxeColors.onInk
              : LuxeColors.ink,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? LuxeColors.ink
              : LuxeColors.surface,
        ),
      ),
    );
  }
}

class _ValueSlider extends StatelessWidget {
  _ValueSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    Color? accent,
    this.suffix = '%',
  }) : accent = accent ?? LuxeColors.ink;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;
  final Color accent;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max);
    final right = '${v.round()}$suffix';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(
                  color: LuxeColors.inkSoft,
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                )),
            Spacer(),
            Text(right,
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: accent,
            inactiveTrackColor: LuxeColors.line,
            thumbColor: LuxeColors.brass,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: v,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SetpointAdjuster extends StatelessWidget {
  const _SetpointAdjuster({
    required this.label,
    required this.value,
    required this.spec,
    required this.onChanged,
  });

  final String label;
  final double value;
  final SetpointSpec spec;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = spec.snap(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: LuxeColors.inkSoft,
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundStepButton(
              icon: Icons.remove,
              onTap: () => onChanged(spec.snap(v - spec.step)),
            ),
            Text(
              spec.format(v),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 40,
                  ),
            ),
            _RoundStepButton(
              icon: Icons.add,
              onTap: () => onChanged(spec.snap(v + spec.step)),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundStepButton extends StatelessWidget {
  const _RoundStepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LuxeColors.surface,
      shape: CircleBorder(side: BorderSide(color: LuxeColors.line)),
      child: InkWell(
        customBorder: CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: LuxeColors.ink),
        ),
      ),
    );
  }
}

/* ------------------------------ dimmer -------------------------------- */

class _DimmerControls extends StatelessWidget {
  const _DimmerControls({required this.entry, required this.onChanged});
  final LightDimmerEntry entry;
  final ValueChanged<SceneEntry> onChanged;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OnOffRow(
          on: entry.on,
          onChanged: (v) => onChanged(LightDimmerEntry(
              device: entry.device,
              on: v,
              percent: entry.percent,
              delayMs: entry.delayMs)),
        ),
        if (entry.on) ...[
          const SizedBox(height: 14),
          _ValueSlider(
            label: 'NIVEAU',
            value: entry.percent.toDouble(),
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(LightDimmerEntry(
                device: entry.device,
                on: true,
                percent: v.round(),
                delayMs: entry.delayMs)),
          ),
        ],
      ],
    );
  }
}

/* ------------------------------ shading ------------------------------- */

class _ShadingControls extends StatelessWidget {
  const _ShadingControls({required this.entry, required this.onChanged});
  final ShadingEntry entry;
  final ValueChanged<SceneEntry> onChanged;
  @override
  Widget build(BuildContext context) {
    final hasSlats = entry.device.ga['slat'] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ValueSlider(
          label: 'POSITIE (100 = DICHT)',
          value: entry.position.toDouble(),
          min: 0,
          max: 100,
          onChanged: (v) => onChanged(ShadingEntry(
              device: entry.device,
              position: v.round(),
              slats: entry.slats,
              delayMs: entry.delayMs)),
        ),
        if (hasSlats) ...[
          SizedBox(height: 10),
          _ValueSlider(
            accent: LuxeColors.brass,
            label: 'LAMELLEN',
            value: (entry.slats ?? 50).toDouble(),
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(ShadingEntry(
                device: entry.device,
                position: entry.position,
                slats: v.round(),
                delayMs: entry.delayMs)),
          ),
        ],
      ],
    );
  }
}

/* ------------------------------ climate ------------------------------- */

class _ClimateControls extends StatelessWidget {
  const _ClimateControls({required this.entry, required this.onChanged});
  final ClimateEntry entry;
  final ValueChanged<SceneEntry> onChanged;
  @override
  Widget build(BuildContext context) {
    final spec = climateSetpointSpec(entry.device);
    return _SetpointAdjuster(
      label: 'SETPOINT',
      value: entry.setpoint,
      spec: spec,
      onChanged: (v) => onChanged(ClimateEntry(
        device: entry.device,
        setpoint: v,
        delayMs: entry.delayMs,
      )),
    );
  }
}

/* ----------------------------- fireplace ------------------------------ */

class _FireplaceControls extends StatelessWidget {
  const _FireplaceControls({required this.entry, required this.onChanged});
  final FireplaceEntry entry;
  final ValueChanged<SceneEntry> onChanged;
  @override
  Widget build(BuildContext context) {
    final fp = entry.device.raw['fireplace'] as Map?;
    final discrete = fp != null && fp['controlMode'] == 'discrete';

    if (discrete) {
      return _OnOffRow(
        on: entry.on,
        onChanged: (v) => onChanged(FireplaceEntry(
            device: entry.device,
            on: v,
            flame: entry.flame,
            delayMs: entry.delayMs)),
      );
    }

    FireplaceEntry copy({bool? on, int? flame}) => FireplaceEntry(
          device: entry.device,
          on: on ?? entry.on,
          flame: flame ?? entry.flame,
          delayMs: entry.delayMs,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OnOffRow(
          on: entry.on,
          onChanged: (v) => onChanged(copy(on: v)),
        ),
        if (entry.on) ...[
          const SizedBox(height: 14),
          _SceneFireplaceFlameBar(
            entry: entry,
            onStep: (v) => onChanged(copy(on: true, flame: v)),
          ),
        ],
      ],
    );
  }
}

class _SceneFireplaceFlameBar extends StatelessWidget {
  const _SceneFireplaceFlameBar({
    required this.entry,
    required this.onStep,
  });

  final FireplaceEntry entry;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final fp = entry.device.raw['fireplace'] as Map?;
    final flame = (fp?['flame'] as Map?)?.cast<String, dynamic>();
    final stepRanges = parseFireplaceStepRanges(flame);
    final legacySteps = (flame?['steps'] as num?)?.toInt();
    final levelDisplay = flame?['levelDisplay'] as String?;
    final usePctBands = stepRanges != null && stepRanges.length >= 2;

    final List<DeviceControlItem> items;
    if (usePctBands) {
      items = [
        for (var i = 0; i < stepRanges.length; i++)
          DeviceControlItem(
            label: fireplaceStepLabel(
              ranges: stepRanges,
              step1Based: i + 1,
            ),
            active: entry.flame == i + 1,
            onTap: () => onStep(i + 1),
          ),
      ];
    } else if (legacySteps != null && legacySteps >= 2) {
      items = [
        for (var i = 1; i <= legacySteps; i++)
          DeviceControlItem(
            label: 'Stand $i',
            active: entry.flame == i,
            onTap: () => onStep(i),
          ),
      ];
    } else {
      items = [
        for (var i = 0; i < kDefaultFlameStepPercents.length; i++)
          DeviceControlItem(
            label: 'Stand ${i + 1}',
            active: entry.flame == kDefaultFlameStepPercents[i],
            onTap: () => onStep(kDefaultFlameStepPercents[i]),
          ),
      ];
    }

    String headerValue;
    if (levelDisplay == 'volt_10') {
      headerValue = '${(entry.flame * 0.1).toStringAsFixed(1)} V';
    } else if (levelDisplay == 'volt_3') {
      headerValue = '${(entry.flame * 0.03).toStringAsFixed(2)} V';
    } else if (usePctBands) {
      headerValue = fireplaceStepLabel(
        ranges: stepRanges,
        step1Based: entry.flame.clamp(1, stepRanges.length),
      );
    } else if (legacySteps != null) {
      headerValue = 'Stand ${entry.flame}';
    } else {
      headerValue = '${entry.flame}%';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'VLAMSTAND',
                style: TextStyle(
                  color: LuxeColors.inkSoft,
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(headerValue, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 10),
        DeviceControlBar.grid(context, items),
      ],
    );
  }
}

/* -------------------------------- ac ---------------------------------- */

class _AcControls extends StatelessWidget {
  const _AcControls({required this.entry, required this.onChanged});
  final AcEntry entry;
  final ValueChanged<SceneEntry> onChanged;
  @override
  Widget build(BuildContext context) {
    final cfg = (entry.device.raw['ac'] as Map).cast<String, dynamic>();
    final modes = ((cfg['mode'] as Map?)?['options'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    final fans = ((cfg['fanSpeed'] as Map?)?['options'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];

    AcEntry copy({
      bool? on,
      double? sp,
      int? mode,
      bool clearMode = false,
      int? fan,
      bool clearFan = false,
    }) =>
        AcEntry(
          device: entry.device,
          on: on ?? entry.on,
          setpoint: sp ?? entry.setpoint,
          mode: clearMode ? null : (mode ?? entry.mode),
          fanSpeed: clearFan ? null : (fan ?? entry.fanSpeed),
          delayMs: entry.delayMs,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OnOffRow(
          on: entry.on,
          onChanged: (v) => onChanged(copy(on: v)),
        ),
        if (entry.on) ...[
          const SizedBox(height: 12),
          _SetpointAdjuster(
            label: 'SETPOINT',
            value: entry.setpoint,
            spec: acSetpointSpec(entry.device),
            onChanged: (v) => onChanged(copy(sp: v)),
          ),
          if (modes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _OptionRow(
              label: 'MODUS',
              options: modes,
              active: entry.mode,
              onTap: (v) => onChanged(copy(mode: v)),
              clearable: true,
              onClear: () => onChanged(copy(clearMode: true)),
            ),
          ],
          if (fans.isNotEmpty) ...[
            const SizedBox(height: 10),
            _OptionRow(
              label: 'VENTILATOR',
              options: fans,
              active: entry.fanSpeed,
              onTap: (v) => onChanged(copy(fan: v)),
              clearable: true,
              onClear: () => onChanged(copy(clearFan: true)),
            ),
          ],
        ],
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.options,
    required this.onTap,
    this.active,
    this.clearable = false,
    this.onClear,
  });
  final String label;
  final List<Map<String, dynamic>> options;
  final int? active;
  final ValueChanged<int> onTap;
  final bool clearable;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(
                  color: LuxeColors.inkSoft,
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                )),
            Spacer(),
            if (clearable && active != null)
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('negeren',
                    style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              GestureDetector(
                onTap: () => onTap((o['value'] as num).toInt()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: (o['value'] as num).toInt() == active
                        ? LuxeColors.ink
                        : LuxeColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: (o['value'] as num).toInt() == active
                          ? LuxeColors.ink
                          : LuxeColors.line,
                    ),
                  ),
                  child: Text(
                    o['label'] as String,
                    style: TextStyle(
                      color: (o['value'] as num).toInt() == active
                          ? LuxeColors.brassGlow
                          : LuxeColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/* -------------------------------- fan --------------------------------- */

class _FanControls extends StatelessWidget {
  const _FanControls({required this.entry, required this.onChanged});
  final FanEntry entry;
  final ValueChanged<SceneEntry> onChanged;
  @override
  Widget build(BuildContext context) {
    final cfg = (entry.device.raw['fan'] as Map).cast<String, dynamic>();
    final hasOscillate = cfg['oscillate'] != null;
    final speedSpec = fanSpeedSpec(entry.device);

    FanEntry copy({
      bool? on,
      int? speed,
      bool? osc,
      bool clearOsc = false,
    }) =>
        FanEntry(
          device: entry.device,
          on: on ?? entry.on,
          speed: speed ?? entry.speed,
          oscillate: clearOsc ? null : (osc ?? entry.oscillate),
          delayMs: entry.delayMs,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OnOffRow(
          on: entry.on,
          onChanged: (v) => onChanged(copy(on: v)),
        ),
        if (entry.on) ...[
          SizedBox(height: 12),
          _SceneFanSpeedBar(
            spec: speedSpec,
            active: entry.speed,
            onSelect: (v) => onChanged(copy(speed: v.round())),
          ),
          if (hasOscillate) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('OSCILLATIE',
                    style: TextStyle(
                      color: LuxeColors.inkSoft,
                      fontSize: 11,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                    )),
                const Spacer(),
                _TriStateChip(
                  value: entry.oscillate,
                  onChanged: (v) => onChanged(
                      v == null ? copy(clearOsc: true) : copy(osc: v)),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class _SceneFanSpeedBar extends StatelessWidget {
  const _SceneFanSpeedBar({
    required this.spec,
    required this.active,
    required this.onSelect,
  });

  final FanSpeedSpec spec;
  final int active;
  final ValueChanged<double> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<DeviceControlItem> items;
    if (spec.isSteps) {
      items = [
        for (int i = 1; i <= spec.steps; i++)
          DeviceControlItem(
            label: (spec.stepLabels != null &&
                    i - 1 < spec.stepLabels!.length &&
                    spec.stepLabels![i - 1].isNotEmpty)
                ? spec.stepLabels![i - 1]
                : 'Stand $i',
            active: active == i,
            onTap: () => onSelect(i.toDouble()),
          ),
      ];
    } else {
      final levels = spec.isByte ? kFanByteLevels : kFanPercentLevels;
      final nearest = nearestFanLevel(active, byteMode: spec.isByte);
      items = [
        for (final lvl in levels)
          DeviceControlItem(
            label: spec.isByte ? '$lvl' : '$lvl%',
            active: lvl == nearest,
            onTap: () => onSelect(lvl.toDouble()),
          ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          spec.isSteps ? 'STAND' : 'SNELHEID',
          style: TextStyle(
            color: LuxeColors.inkSoft,
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        DeviceControlBar.grid(context, items),
      ],
    );
  }
}

/* -------------------------------- media ------------------------------- */

class _MediaControls extends ConsumerWidget {
  const _MediaControls({required this.entry, required this.onChanged});
  final MediaEntry entry;
  final ValueChanged<SceneEntry> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mediaStateProvider)[entry.device.id];
    final presets = state?.presets ?? const <MediaPreset>[];

    String? transport = entry.transport;
    if (entry.presetId != null && entry.presetId!.isNotEmpty) {
      transport = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACTIE',
          style: TextStyle(
            color: LuxeColors.inkSoft,
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String?>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: null, label: Text('GEEN')),
            ButtonSegment(value: 'play', label: Text('SPELEN')),
            ButtonSegment(value: 'pause', label: Text('PAUZE')),
            ButtonSegment(value: 'stop', label: Text('STOP')),
          ],
          selected: {transport},
          onSelectionChanged: (sel) {
            onChanged(entry.copyWith(
              transport: sel.first,
              clearTransport: sel.first == null,
              clearPreset: true,
            ));
          },
          style: ButtonStyle(
            side: WidgetStateProperty.all(
                BorderSide(color: LuxeColors.line)),
            foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? LuxeColors.onInk
                  : LuxeColors.ink,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? LuxeColors.ink
                  : LuxeColors.surface,
            ),
          ),
        ),
        if (presets.isNotEmpty) ...[
          SizedBox(height: 14),
          Text(
            'FAVORIET',
            style: TextStyle(
              color: LuxeColors.inkSoft,
              fontSize: 11,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButton<String?>(
            isExpanded: true,
            value: entry.presetId,
            hint: const Text('Geen favoriet'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Geen favoriet'),
              ),
              for (final p in presets)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              if (id == null) {
                onChanged(entry.copyWith(clearPreset: true));
                return;
              }
              final p = presets.firstWhere((x) => x.id == id);
              onChanged(entry.copyWith(
                presetId: p.id,
                presetName: p.name,
                presetUri: p.uri,
                clearTransport: true,
              ));
            },
          ),
        ],
        SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Volume instellen'),
          value: entry.setVolume,
          activeThumbColor: LuxeColors.brass,
          onChanged: (v) => onChanged(entry.copyWith(
            setVolume: v,
            volume: v ? (entry.volume ?? state?.volume ?? 25) : null,
            clearVolume: !v,
          )),
        ),
        if (entry.setVolume)
          _ValueSlider(
            label: 'VOLUME',
            suffix: '%',
            value: (entry.volume ?? 25).toDouble(),
            min: 0,
            max: 100,
            onChanged: (v) => onChanged(entry.copyWith(
              volume: v.round(),
              setVolume: true,
            )),
          ),
      ],
    );
  }
}

/* ------------------------------ rgbw_ww ------------------------------ */

const _rgbwChOrder = ['r', 'g', 'b', 'w', 'ww', 'cw'];

class _RgbwWwSceneControls extends StatelessWidget {
  const _RgbwWwSceneControls({required this.entry, required this.onChanged});
  final RgbwWwEntry entry;
  final ValueChanged<SceneEntry> onChanged;

  @override
  Widget build(BuildContext context) {
    final mode = entry.mode;
    if (mode == 'channels') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final k in _rgbwChOrder)
            if (entry.device.ga[k] != null) ...[
              _ValueSlider(
                label: k.toUpperCase(),
                value: (entry.channels[k] ?? 0).toDouble(),
                min: 0,
                max: 255,
                suffix: '',
                onChanged: (v) {
                  final next = Map<String, int>.from(entry.channels);
                  next[k] = v.round().clamp(0, 255);
                  onChanged(RgbwWwEntry(
                    device: entry.device,
                    mode: mode,
                    channels: next,
                    delayMs: entry.delayMs,
                  ));
                },
              ),
              const SizedBox(height: 4),
            ],
        ],
      );
    }
    if (mode == 'composite') {
      final list = entry.composite;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < list.length; i++) ...[
            _ValueSlider(
              label: 'B$i',
              value: list[i].toDouble(),
              min: 0,
              max: 255,
              suffix: '',
              onChanged: (v) {
                final next = List<int>.from(list);
                next[i] = v.round().clamp(0, 255);
                onChanged(RgbwWwEntry(
                  device: entry.device,
                  mode: mode,
                  composite: next,
                  delayMs: entry.delayMs,
                ));
              },
            ),
            if (i < list.length - 1) const SizedBox(height: 4),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ValueSlider(
          label: 'R',
          value: entry.red.toDouble(),
          min: 0,
          max: 255,
          suffix: '',
          onChanged: (v) => onChanged(RgbwWwEntry(
                device: entry.device,
                mode: mode,
                red: v.round().clamp(0, 255),
                green: entry.green,
                blue: entry.blue,
                delayMs: entry.delayMs)),
        ),
        const SizedBox(height: 4),
        _ValueSlider(
          label: 'G',
          value: entry.green.toDouble(),
          min: 0,
          max: 255,
          suffix: '',
          onChanged: (v) => onChanged(RgbwWwEntry(
                device: entry.device,
                mode: mode,
                red: entry.red,
                green: v.round().clamp(0, 255),
                blue: entry.blue,
                delayMs: entry.delayMs)),
        ),
        const SizedBox(height: 4),
        _ValueSlider(
          label: 'B',
          value: entry.blue.toDouble(),
          min: 0,
          max: 255,
          suffix: '',
          onChanged: (v) => onChanged(RgbwWwEntry(
                device: entry.device,
                mode: mode,
                red: entry.red,
                green: entry.green,
                blue: v.round().clamp(0, 255),
                delayMs: entry.delayMs)),
        ),
      ],
    );
  }
}

class _TriStateChip extends StatelessWidget {
  const _TriStateChip({required this.value, required this.onChanged});
  final bool? value;
  final ValueChanged<bool?> onChanged;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        _pill(context, 'Aan', value == true, () => onChanged(true)),
        _pill(context, 'Uit', value == false, () => onChanged(false)),
        _pill(context, 'Negeren', value == null, () => onChanged(null)),
      ],
    );
  }

  Widget _pill(BuildContext context, String label, bool active,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? LuxeColors.ink : LuxeColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? LuxeColors.ink : LuxeColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? LuxeColors.brassGlow : LuxeColors.ink,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/* ---------------------- room grouping (editor + picker) ---------------- */

class SceneEntryRoomGroup {
  const SceneEntryRoomGroup({required this.title, required this.indices});
  final String title;
  final List<int> indices;
}

/// Groepeert scene-items in dezelfde volgorde als [pickDevicesForScene].
List<SceneEntryRoomGroup> groupSceneEntriesByRoom(
  HouseConfig config,
  List<SceneEntry> entries,
) {
  if (entries.isEmpty) return const [];

  final indexByDevice = <String, int>{
    for (int i = 0; i < entries.length; i++) entries[i].device.id: i,
  };
  final used = <int>{};
  final groups = <SceneEntryRoomGroup>[];

  for (final f in config.floors) {
    for (final r in f.rooms) {
      final indices = <int>[];
      for (final d in r.devices) {
        final i = indexByDevice[d.id];
        if (i != null) indices.add(i);
      }
      if (indices.isNotEmpty) {
        groups.add(SceneEntryRoomGroup(title: '${f.name} · ${r.name}', indices: indices));
        used.addAll(indices);
      }
    }
  }

  final remaining = <int>[];
  for (int i = 0; i < entries.length; i++) {
    if (!used.contains(i)) remaining.add(i);
  }
  if (remaining.isNotEmpty) {
    final byLabel = <String, List<int>>{};
    for (final i in remaining) {
      final label =
          config.locationLabelForDevice(entries[i].device.id) ?? 'Overig';
      byLabel.putIfAbsent(label, () => []).add(i);
    }
    for (final e in byLabel.entries) {
      groups.add(SceneEntryRoomGroup(title: e.key, indices: e.value));
    }
  }
  return groups;
}

/// Kamerkop + witte kaart — gedeeld door picker en scene-editor.
class SceneDeviceRoomSection extends StatelessWidget {
  const SceneDeviceRoomSection({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 6),
    this.separateCards = false,
  });

  final String title;
  final List<Widget> children;
  final EdgeInsets padding;
  /// Losse kaarten met kleine tussenruimte (scene-editor) i.p.v. één gegroepeerde lijst.
  final bool separateCards;

  static const _cardGap = 6.0;

  BoxDecoration _cardDecoration(bool phone) => BoxDecoration(
        color: LuxeColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxeColors.lineSoft),
        boxShadow: phone ? LuxeShadows.soft : null,
      );

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: 4,
              bottom: phone ? 6 : 4,
              top: phone ? 12 : 8,
            ),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: LuxeColors.inkSoft,
                fontSize: phone ? 11.5 : 10.5,
                letterSpacing: phone ? 1.6 : 2.0,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          if (separateCards)
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: _cardGap),
              Container(
                width: double.infinity,
                decoration: _cardDecoration(phone),
                child: children[i],
              ),
            ]
          else
            Container(
              width: double.infinity,
              decoration: _cardDecoration(phone),
              child: Column(
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 2,
                        thickness: 1.5,
                        color: LuxeColors.line,
                        indent: 16,
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          SizedBox(height: phone ? 6 : 2),
        ],
      ),
    );
  }
}

/* ---------------------------- device picker --------------------------- */

/// Returns a list of device IDs the user wants to add to the scene.
Future<List<Device>?> pickDevicesForScene(
  BuildContext context, {
  required HouseConfig config,
  required Set<String> excludeIds,
}) async {
  final selected = <String>{};
  return await showModalBottomSheet<List<Device>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollCtl) => Container(
              decoration: BoxDecoration(
                color: LuxeColors.cream,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 5,
                    margin: EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      color: LuxeColors.inkFaint.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Kies apparaten',
                            style:
                                Theme.of(ctx).textTheme.displayMedium,
                          ),
                        ),
                        Text(
                          '${selected.length} gekozen',
                          style:
                              Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollCtl,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        for (final f in config.floors)
                          for (final r in f.rooms)
                            _RoomSection(
                              title: '${f.name} · ${r.name}',
                              devices: r.devices.where((d) {
                                if (excludeIds.contains(d.id)) return false;
                                return d.defaultSceneEntry() != null;
                              }).toList(),
                              selected: selected,
                              onToggle: (id) => setState(() {
                                if (selected.contains(id)) {
                                  selected.remove(id);
                                } else {
                                  selected.add(id);
                                }
                              }),
                            ),
                        _RoomSection(
                          title: 'Diverse',
                          devices: config.globalDevices.where((d) {
                            if (excludeIds.contains(d.id)) return false;
                            return d.defaultSceneEntry() != null;
                          }).toList(),
                          selected: selected,
                          onToggle: (id) => setState(() {
                            if (selected.contains(id)) {
                              selected.remove(id);
                            } else {
                              selected.add(id);
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(const <Device>[]),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text('Annuleren'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    final devices = [
                                      for (final f in config.floors)
                                        for (final r in f.rooms)
                                          for (final d in r.devices)
                                            if (selected.contains(d.id)) d,
                                      for (final d in config.globalDevices)
                                        if (selected.contains(d.id)) d,
                                    ];
                                    Navigator.of(ctx).pop(devices);
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: LuxeColors.ink,
                              foregroundColor: LuxeColors.onInk,
                              minimumSize: const Size.fromHeight(48),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(selected.isEmpty
                                ? 'Kies apparaten'
                                : '${selected.length} toevoegen'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _RoomSection extends StatelessWidget {
  const _RoomSection({
    required this.title,
    required this.devices,
    required this.selected,
    required this.onToggle,
  });
  final String title;
  final List<Device> devices;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) return const SizedBox.shrink();
    return SceneDeviceRoomSection(
      title: title,
      children: [
        for (final d in devices)
          _DeviceCheckbox(
            device: d,
            selected: selected.contains(d.id),
            onTap: () => onToggle(d.id),
          ),
      ],
    );
  }
}

class _DeviceCheckbox extends StatelessWidget {
  const _DeviceCheckbox({
    required this.device,
    required this.selected,
    required this.onTap,
  });
  final Device device;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (device.type) {
        DeviceType.lightSwitch => Icons.lightbulb_outline,
        DeviceType.lightDimmer => Icons.lightbulb,
        DeviceType.rgbwWw => Icons.gradient,
        DeviceType.shading => Icons.blinds_outlined,
        DeviceType.positionActuator => Icons.vertical_split_outlined,
        DeviceType.climate => Icons.thermostat_outlined,
        DeviceType.fireplace => Icons.local_fire_department_outlined,
        DeviceType.ac => Icons.ac_unit,
        DeviceType.fan => Icons.air,
        DeviceType.mediaSonos || DeviceType.mediaBluesound => Icons.speaker_outlined,
        DeviceType.lutronHomeworks => Icons.home_work_outlined,
        _ => Icons.bolt_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? LuxeColors.brass.withValues(alpha: 0.18)
                    : LuxeColors.surfaceDim,
                border: Border.all(
                  color: selected ? LuxeColors.brass : LuxeColors.line,
                ),
              ),
              child: device.type == DeviceType.shading
                  ? ShadingSubtypeGlyph(
                      subtype: device.shadingSubtype,
                      size: 18,
                      color: selected ? LuxeColors.brass : LuxeColors.ink,
                    )
                  : Icon(_icon,
                      size: 18,
                      color: selected ? LuxeColors.brass : LuxeColors.ink),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                device.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: selected ? LuxeColors.brass : LuxeColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}
