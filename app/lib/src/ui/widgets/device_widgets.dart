import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ac_mode_config.dart';
import '../../api.dart';
import '../../camera_api.dart';
import '../../fireplace_status.dart';
import '../../fireplace_step_ranges.dart';
import '../../fireplace_virtual.dart';
import '../../hvac_switch_lock.dart';
import '../../models.dart';
import '../../shading_subtype_glyph.dart';
import '../../room_control_category.dart';
import '../../theme.dart';
import '../responsive.dart';
import 'camera_snapshot.dart';
import 'confirm_dialog.dart';
import 'device_card_scale.dart';
import 'device_control_panel.dart';
import 'device_tile_shell.dart';
import 'heater_icon.dart';
import 'glass_card.dart';
import 'media_tile.dart';

/// Factory: pick the correct luxe widget per device type.
Widget deviceWidget(Device d) => DeviceCardListItem(
      child: switch (d.type) {
      DeviceType.lightSwitch => LightSwitchTile(device: d),
      DeviceType.lightDimmer => LightDimmerTile(device: d),
      DeviceType.rgbwWw => RgbwWwTile(device: d),
      DeviceType.shading => ShadingTile(device: d),
      DeviceType.positionActuator => ShadingTile(device: d),
      DeviceType.climate => ClimateTile(device: d),
      DeviceType.mediaSonos => MediaTile(device: d),
      DeviceType.mediaBluesound => MediaTile(device: d),
      DeviceType.camera => CameraTile(device: d),
      DeviceType.intercom => IntercomTile(device: d),
      DeviceType.fireplace => FireplaceTile(device: d),
      DeviceType.ac => AcTile(device: d),
      DeviceType.fan => FanTile(device: d),
      DeviceType.universal => UniversalTile(device: d),
      DeviceType.wtw => WtwTile(device: d),
      DeviceType.melding => MeldingTile(device: d),
      DeviceType.lutronHomeworks => LutronHomeworksTile(device: d),
      DeviceType.unknown => _Placeholder(name: d.name, hint: 'Onbekend type'),
    },
    );

/* --------------------------------------------------------------------- */
/*  Base shell — see [DeviceTileShell] in device_tile_shell.dart         */
/* --------------------------------------------------------------------- */

/* --------------------------------------------------------------------- */
/*  Light switch / dimmer — gedeelde header                              */
/* --------------------------------------------------------------------- */

class _LightTileHeader extends StatelessWidget {
  const _LightTileHeader({
    required this.name,
    required this.status,
    required this.on,
    required this.onChanged,
  });

  final String name;
  final String status;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DeviceTileLayout.headerRow(
      context: context,
      leading: DeviceTileIconBadge(
        icon: on ? Icons.lightbulb : Icons.lightbulb_outline,
        active: on,
        onTap: () => onChanged(!on),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: DeviceTileLayout.titleStatusGap),
          Text(status, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      trailing: DeviceTileLayout.trailingSwitch(
        context: context,
        value: on,
        onChanged: onChanged,
      ),
    );
  }
}

class LightSwitchTile extends ConsumerWidget {
  const LightSwitchTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bus = ref.watch(busProvider);
    final statusGA = device.ga['switch_status'] ?? device.ga['switch'];
    final v = statusGA == null ? null : bus.values[statusGA];
    final on = v == true || v == 1;

    return DeviceTileShell(
      glow: on,
      child: _LightTileHeader(
        name: device.name,
        status: on ? 'Aan' : 'Uit',
        on: on,
        onChanged: (x) {
          ref.read(busProvider.notifier).send({
            'kind': 'light.switch',
            'deviceId': device.id,
            'on': x,
          });
        },
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Dimmer                                                               */
/* --------------------------------------------------------------------- */

class _DimmerSlider extends StatefulWidget {
  const _DimmerSlider({
    required this.value,
    required this.onDim,
    this.onDisplayChanged,
    this.onDragEnd,
  });

  final double value;
  final ValueChanged<int> onDim;
  final ValueChanged<double>? onDisplayChanged;
  final VoidCallback? onDragEnd;

  @override
  State<_DimmerSlider> createState() => _DimmerSliderState();
}

class _DimmerSliderState extends State<_DimmerSlider> {
  static const _throttle = Duration(milliseconds: 100);

  bool _dragging = false;
  double _local = 0;
  Timer? _throttleTimer;
  DateTime? _lastSendAt;
  int? _lastSent;

  @override
  void initState() {
    super.initState();
    _local = widget.value.clamp(0.0, 100.0);
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DimmerSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) {
      _local = widget.value.clamp(0.0, 100.0);
    }
  }

  void _notifyDisplay(double v) => widget.onDisplayChanged?.call(v);

  void _emit(int percent) {
    if (_lastSent == percent) return;
    _lastSent = percent;
    _lastSendAt = DateTime.now();
    widget.onDim(percent);
  }

  void _schedule(int percent) {
    final now = DateTime.now();
    if (_lastSendAt == null ||
        now.difference(_lastSendAt!) >= _throttle) {
      _emit(percent);
      return;
    }
    _throttleTimer?.cancel();
    final wait = _throttle - now.difference(_lastSendAt!);
    _throttleTimer = Timer(wait, () => _emit(_local.round()));
  }

  void _onStart(double v) {
    _lastSent = null;
    setState(() {
      _dragging = true;
      _local = v;
    });
    _notifyDisplay(v);
    _emit(v.round());
  }

  void _onUpdate(double v) {
    setState(() => _local = v);
    _notifyDisplay(v);
    _schedule(v.round());
  }

  void _onEnd(double v) {
    _throttleTimer?.cancel();
    _emit(v.round());
    setState(() {
      _dragging = false;
      _local = v;
    });
    _notifyDisplay(v);
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: LuxeColors.brass.withValues(alpha: 0.55),
        inactiveTrackColor: LuxeColors.line,
        thumbColor: LuxeColors.brass,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: _local.clamp(0.0, 100.0),
        min: 0,
        max: 100,
        onChangeStart: _onStart,
        onChanged: _onUpdate,
        onChangeEnd: _onEnd,
      ),
    );
  }
}

class LightDimmerTile extends ConsumerStatefulWidget {
  const LightDimmerTile({super.key, required this.device});
  final Device device;

  @override
  ConsumerState<LightDimmerTile> createState() => _LightDimmerTileState();
}

class _LightDimmerTileState extends ConsumerState<LightDimmerTile> {
  double? _dragLabel;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final bus = ref.watch(busProvider);
    final switchGA = d.ga['switch_status'] ?? d.ga['switch'];
    final dimGA = d.ga['dim_status'] ?? d.ga['dim_value'];
    final on = bus.values[switchGA] == true || bus.values[switchGA] == 1;
    final dimVal = dimGA == null ? null : bus.values[dimGA];
    final busPct = dimVal is num
        ? dimVal.toDouble().clamp(0.0, 100.0)
        : (on ? 100.0 : 0.0);
    final current = _dragLabel ?? busPct;

    return DeviceTileShell(
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LightTileHeader(
            name: d.name,
            status: on ? '${current.round()}%' : 'Uit',
            on: on,
            onChanged: (x) {
              ref.read(busProvider.notifier).send({
                'kind': 'light.switch',
                'deviceId': d.id,
                'on': x,
              });
            },
          ),
          SizedBox(height: DeviceControlBar.sectionSpacing(context)),
          DeviceCardBody(
            child: DeviceCardSliderWrap(
              child: _DimmerSlider(
                value: busPct,
                onDisplayChanged: (v) => setState(() => _dragLabel = v),
                onDragEnd: () => setState(() => _dragLabel = null),
                onDim: (pct) {
                  if (dimGA == null) return;
                  ref.read(busProvider.notifier).sendLightDim(
                        deviceId: d.id,
                        dimGa: dimGA,
                        percent: pct,
                      );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  RGBW / WW (KNX)                                                      */
/* --------------------------------------------------------------------- */

class RgbwWwTile extends ConsumerStatefulWidget {
  const RgbwWwTile({super.key, required this.device});
  final Device device;

  @override
  ConsumerState<RgbwWwTile> createState() => _RgbwWwTileState();
}

class _RgbwWwTileState extends ConsumerState<RgbwWwTile> {
  // HSV colour wheel state
  double _hue = 30;
  double _sat = 1.0;
  double _val = 0.8; // brightness  0‑1

  // Individual KNX channels (0‑255)
  double _white = 0;
  double _ww    = 128;
  double _cw    = 0;

  // warmCoolRatio for tunable_white: 0=warm, 1=cool
  double _warmCool = 0.0;

  bool _synced = false;

  // Composite mode draft
  List<int>? _compositeDraft;

  // ── helpers ──────────────────────────────────────────────────────────────

  String get _mode {
    final m = widget.device.raw['rgbwWw'];
    if (m is Map && m['mode'] is String) return m['mode'] as String;
    return 'channels';
  }

  int get _payloadBytes {
    final m = widget.device.raw['rgbwWw'];
    if (m is Map && m['payloadBytes'] is num) {
      return (m['payloadBytes'] as num).toInt().clamp(1, 14);
    }
    return 14;
  }

  bool _hasRgb(Device d) =>
      d.ga['r'] != null && d.ga['g'] != null && d.ga['b'] != null;
  bool _hasW(Device d)  => d.ga['w']  != null;
  bool _hasWw(Device d) => d.ga['ww'] != null;
  bool _hasCw(Device d) => d.ga['cw'] != null;

  Color get _currentColor =>
      HSVColor.fromAHSV(1.0, _hue, _sat, _val).toColor();

  // Sync once from KNX bus on first build
  void _syncFromBus(BusState bus, Device d) {
    if (_synced) return;
    num? pick(String k) {
      final ga = d.ga[k];
      if (ga == null) return null;
      final v = bus.values[ga];
      return v is num ? v : null;
    }

    if (_mode == 'channels' && _hasRgb(d)) {
      final r = pick('r') ?? 0;
      final g = pick('g') ?? 0;
      final b = pick('b') ?? 0;
      if (r > 0 || g > 0 || b > 0) {
        final hsv = HSVColor.fromColor(
            Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()));
        _hue = hsv.hue;
        _sat = hsv.saturation;
        _val = hsv.value;
        _synced = true;
      }
      final wv = pick('w');  if (wv != null) _white = wv.toDouble();
      final wwv = pick('ww'); if (wwv != null) _ww = wwv.toDouble();
      final cwv = pick('cw'); if (cwv != null) _cw = cwv.toDouble();
    } else if (_mode == 'rgb232') {
      final ga = d.ga['rgb232'];
      if (ga != null) {
        final cur = bus.values[ga];
        if (cur is Map) {
          final r = (cur['red']   as num?)?.toDouble() ?? 0;
          final g = (cur['green'] as num?)?.toDouble() ?? 0;
          final b = (cur['blue']  as num?)?.toDouble() ?? 0;
          if (r > 0 || g > 0 || b > 0) {
            final hsv = HSVColor.fromColor(
                Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()));
            _hue = hsv.hue;
            _sat = hsv.saturation;
            _val = hsv.value;
            _synced = true;
          }
        }
      }
    } else if (_mode == 'tunable_white' || (!_hasRgb(d) && (_hasWw(d) || _hasCw(d)))) {
      final wwv = pick('ww') ?? 0;
      final cwv = pick('cw') ?? 0;
      final total = wwv + cwv;
      if (total > 0) {
        _val = (total / 510).clamp(0.0, 1.0);
        _warmCool = (cwv / total).clamp(0.0, 1.0);
        _synced = true;
      }
    }
  }

  // ── on/off helper ────────────────────────────────────────────────────────

  bool _isOn(BusState bus, Device d) {
    final ga = d.ga['on'];
    if (ga == null) return _val > 0.01;
    final v = bus.values[ga];
    return v == true || v == 1;
  }

  void _toggleLight(Device d, bool on, {required bool hasOnGa}) {
    if (hasOnGa) {
      ref.read(busProvider.notifier).send({
        'kind': 'light.switch',
        'deviceId': d.id,
        'on': !on,
      });
      return;
    }
    setState(() {
      if (on) {
        _val = 0;
      } else if (_val < 0.01) {
        _val = 0.8;
      }
    });
    if (_mode == 'tunable_white') {
      _sendTunableWhite(d);
    } else {
      _sendRgbChannels(d);
    }
  }

  Widget _rgbHeaderIcon({
    required IconData icon,
    required bool on,
    VoidCallback? onTap,
  }) =>
      DeviceTileIconBadge(icon: icon, active: on, onTap: onTap);

  Widget _lightOnOffSwitch(BuildContext context, Device d, bool on) =>
      DeviceTileLayout.trailingSwitch(
        context: context,
        value: on,
        onChanged: (x) => ref.read(busProvider.notifier).send({
          'kind': 'light.switch',
          'deviceId': d.id,
          'on': x,
        }),
      );

  // ── send helpers ─────────────────────────────────────────────────────────

  void _sendRgbChannels(Device d) {
    final c = _currentColor;
    final n = ref.read(busProvider.notifier);
    void ch(String k, int v) {
      if (d.ga[k] != null) {
        n.send({'kind': 'rgbw_ww.channel', 'deviceId': d.id, 'channel': k, 'value': v});
      }
    }
    ch('r', c.red);
    ch('g', c.green);
    ch('b', c.blue);
  }

  void _sendChannel(Device d, String channel, double value) {
    ref.read(busProvider.notifier).send({
      'kind': 'rgbw_ww.channel',
      'deviceId': d.id,
      'channel': channel,
      'value': value.round().clamp(0, 255),
    });
  }

  void _sendTunableWhite(Device d) {
    ref.read(busProvider.notifier).send({
      'kind': 'rgbw_ww.tunable_white',
      'deviceId': d.id,
      'brightness': (_val * 255).round().clamp(0, 255),
      'warmCoolRatio': _warmCool,
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d   = widget.device;
    final bus = ref.watch(busProvider);
    _syncFromBus(bus, d);

    final mode = _mode;

    // Composite: raw byte sliders (too low-level for a wheel)
    if (mode == 'composite') return _buildCompositeTile(context, d, bus);

    // Tunable white only
    if (mode == 'tunable_white') return _buildCctTile(context, d);

    if (mode == 'channels') {
      if (!_hasRgb(d) && (_hasWw(d) || _hasCw(d))) {
        return _buildCctTile(context, d);
      }
      if (_hasRgb(d)) {
        return _buildColorWheelTile(context, d,
            hasWhite: _hasW(d), hasCct: _hasWw(d) || _hasCw(d));
      }
    }

    if (mode == 'rgb232') return _buildColorWheelTile(context, d);

    return _Placeholder(name: d.name, hint: 'Modus: $mode');
  }

  // ── RGB colour wheel tile ─────────────────────────────────────────────────

  Widget _buildColorWheelTile(
    BuildContext context,
    Device d, {
    bool hasWhite = false,
    bool hasCct   = false,
  }) {
    final bus    = ref.watch(busProvider);
    final mode   = _mode;
    final label  = mode == 'rgb232' ? 'RGB·DPT232' : (hasWhite ? 'RGBW' : hasCct ? 'RGB+WW/CW' : 'RGB');
    final on     = _isOn(bus, d);
    final hasOnGa = d.ga['on'] != null;

    return DeviceTileShell(
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          DeviceTileLayout.headerRow(
            context: context,
            leading: _rgbHeaderIcon(
              icon: on ? Icons.palette : Icons.palette_outlined,
              on: on,
              onTap: () => _toggleLight(d, on, hasOnGa: hasOnGa),
            ),
            content: Row(
              children: [
                Expanded(
                  child: Text(
                    d.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: LuxeColors.inkSoft),
                ),
              ],
            ),
            trailing: hasOnGa ? _lightOnOffSwitch(context, d, on) : null,
          ),
          DeviceCardHero(
            child: _HsvWheelPicker(
              hue: _hue,
              saturation: _sat,
              diameter: DeviceCardScale.colorWheelSize(context),
              onChanged: (h, s) => setState(() {
                _hue = h;
                _sat = s;
              }),
              onChangeEnd: (_, __) => _sendRgbChannels(d),
            ),
          ),
          DeviceCardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DeviceCardSliderWrap(
                  child: _LuxeGradientBar(
                    value: _val,
                    label: 'Helderheid',
                    colors: [Colors.black, _currentColor],
                    onChanged: (v) => setState(() => _val = v),
                    onChangeEnd: (v) {
                      setState(() => _val = v);
                      _sendRgbChannels(d);
                    },
                  ),
                ),
                if (hasWhite) ...[
                  const SizedBox(height: 12),
                  DeviceCardSliderWrap(
                    child: _LuxeGradientBar(
                      value: _white / 255,
                      label: 'Wit (W)',
                      colors: [Colors.black, Colors.white],
                      onChanged: (v) => setState(() => _white = v * 255),
                      onChangeEnd: (v) {
                        setState(() => _white = v * 255);
                        _sendChannel(d, 'w', _white);
                      },
                    ),
                  ),
                ],
                if (hasCct) ...[
                  const SizedBox(height: 12),
                  DeviceCardSliderWrap(
                    child: _LuxeGradientBar(
                      value: _ww / 255,
                      label: 'Warm Wit (WW)',
                      colors: [Colors.black, const Color(0xFFFFD080)],
                      onChanged: (v) => setState(() => _ww = v * 255),
                      onChangeEnd: (v) {
                        setState(() => _ww = v * 255);
                        _sendChannel(d, 'ww', _ww);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  DeviceCardSliderWrap(
                    child: _LuxeGradientBar(
                      value: _cw / 255,
                      label: 'Koud Wit (CW)',
                      colors: [Colors.black, const Color(0xFFCCE8FF)],
                      onChanged: (v) => setState(() => _cw = v * 255),
                      onChangeEnd: (v) {
                        setState(() => _cw = v * 255);
                        _sendChannel(d, 'cw', _cw);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tunable white tile ────────────────────────────────────────────────────

  Widget _buildCctTile(BuildContext context, Device d) {
    final bus     = ref.watch(busProvider);
    final on      = _isOn(bus, d);
    final hasOnGa = d.ga['on'] != null;
    return DeviceTileShell(
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: _rgbHeaderIcon(
              icon: on ? Icons.wb_incandescent : Icons.wb_incandescent_outlined,
              on: on,
              onTap: () => _toggleLight(d, on, hasOnGa: hasOnGa),
            ),
            content: Row(
              children: [
                Expanded(
                  child: Text(
                    d.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Tunable White',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: LuxeColors.inkSoft),
                ),
              ],
            ),
            trailing: hasOnGa ? _lightOnOffSwitch(context, d, on) : null,
          ),
          const SizedBox(height: 20),

          // CCT gradient strip (warm → cool)
          _LuxeGradientBar(
            value: _warmCool,
            label: 'Kleurtemperatuur (warm → koud)',
            colors: const [Color(0xFFFF9A3C), Color(0xFFFFEFCF), Color(0xFFCCE8FF)],
            onChanged:  (v) => setState(() => _warmCool = v),
            onChangeEnd: (v) {
              setState(() => _warmCool = v);
              _sendTunableWhite(d);
            },
            thumbColor: const Color(0xFFFFD88A),
          ),
          const SizedBox(height: 16),

          // Brightness
          _LuxeGradientBar(
            value: _val,
            label: 'Helderheid',
            colors: const [Colors.black, Color(0xFFFFEFCF)],
            onChanged:  (v) => setState(() => _val = v),
            onChangeEnd: (v) {
              setState(() => _val = v);
              _sendTunableWhite(d);
            },
          ),
        ],
      ),
    );
  }

  // ── Composite tile (raw bytes, unchanged) ─────────────────────────────────

  Widget _buildCompositeTile(BuildContext context, Device d, BusState bus) {
    final n       = _payloadBytes;
    final draft   = _compositeDraft ?? List<int>.filled(n, 0);
    final on      = _isOn(bus, d);
    final hasOnGa = d.ga['on'] != null;
    return DeviceTileShell(
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: _rgbHeaderIcon(
              icon: on ? Icons.gradient : Icons.gradient_outlined,
              on: on,
              onTap: hasOnGa
                  ? () => _toggleLight(d, on, hasOnGa: true)
                  : null,
            ),
            content: Row(
              children: [
                Expanded(
                  child: Text(
                    d.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '$n B',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: LuxeColors.inkSoft),
                ),
              ],
            ),
            trailing: hasOnGa ? _lightOnOffSwitch(context, d, on) : null,
          ),
          SizedBox(height: 8),
          Text('Ruwe bytes op één GA.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: LuxeColors.inkSoft)),
          const SizedBox(height: 12),
          for (int i = 0; i < n; i++)
            _LuxeGradientBar(
              value:  draft[i] / 255,
              label:  'B$i',
              colors: [Colors.black, LuxeColors.ink],
              onChanged: (v) => setState(() {
                _compositeDraft = List<int>.from(draft);
                _compositeDraft![i] = (v * 255).round().clamp(0, 255);
              }),
              onChangeEnd: (_) {},
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                ref.read(busProvider.notifier).send({
                  'kind': 'rgbw_ww.composite',
                  'deviceId': d.id,
                  'bytes': draft,
                });
              },
              child: const Text('Zend telegram'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── HSV Colour Wheel ──────────────────────────────────────────────────────────

class _HsvWheelPicker extends StatefulWidget {
  const _HsvWheelPicker({
    required this.hue,
    required this.saturation,
    required this.onChanged,
    required this.onChangeEnd,
    this.diameter = 200,
  });

  final double hue;         // 0–360
  final double saturation;  // 0–1
  final void Function(double hue, double sat) onChanged;
  final void Function(double hue, double sat) onChangeEnd;
  final double diameter;

  @override
  State<_HsvWheelPicker> createState() => _HsvWheelPickerState();
}

class _HsvWheelPickerState extends State<_HsvWheelPicker> {
  void _handle(Offset local, bool isEnd) {
    final r  = widget.diameter / 2;
    final dx = local.dx - r;
    final dy = local.dy - r;
    final dist = math.sqrt(dx * dx + dy * dy);
    final sat  = (dist / r).clamp(0.0, 1.0);
    final angle = math.atan2(dy, dx);
    final hue = (angle * 180 / math.pi + 360) % 360;
    if (isEnd) {
      widget.onChangeEnd(hue, sat);
    } else {
      widget.onChanged(hue, sat);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart:  (e) => _handle(e.localPosition, false),
      onPanUpdate: (e) => _handle(e.localPosition, false),
      onPanEnd:    (e) => widget.onChangeEnd(widget.hue, widget.saturation),
      onTapDown:   (e) => _handle(e.localPosition, true),
      child: CustomPaint(
        size: Size(widget.diameter, widget.diameter),
        painter: _HsvWheelPainter(
          hue:        widget.hue,
          saturation: widget.saturation,
        ),
      ),
    );
  }
}

class _HsvWheelPainter extends CustomPainter {
  _HsvWheelPainter({required this.hue, required this.saturation});
  final double hue;
  final double saturation;

  // 12 hue stops + wrap-around (colours generated at compile-time)
  static const _hueColors = [
    Color(0xFFFF0000), // 0°   red
    Color(0xFFFF8000), // 30°  orange
    Color(0xFFFFFF00), // 60°  yellow
    Color(0xFF80FF00), // 90°  chartreuse
    Color(0xFF00FF00), // 120° green
    Color(0xFF00FF80), // 150° spring green
    Color(0xFF00FFFF), // 180° cyan
    Color(0xFF0080FF), // 210° azure
    Color(0xFF0000FF), // 240° blue
    Color(0xFF8000FF), // 270° violet
    Color(0xFFFF00FF), // 300° magenta
    Color(0xFFFF0080), // 330° rose
    Color(0xFFFF0000), // 360° red (close loop)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final r      = size.width / 2;
    final center = Offset(r, r);
    final rect   = Rect.fromCircle(center: center, radius: r);

    // 1 — hue sweep gradient
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = SweepGradient(colors: _hueColors).createShader(rect),
    );

    // 2 — white radial overlay (centre = white, edge = pure hue)
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // 3 — subtle outer dark ring
    canvas.drawCircle(
      center,
      r - 1,
      Paint()
        ..color = const Color(0x30000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 4 — picker indicator
    final angle    = hue * math.pi / 180;
    final pickerPos = center +
        Offset(math.cos(angle) * saturation * r,
               math.sin(angle) * saturation * r);
    final indicatorColor =
        HSVColor.fromAHSV(1, hue, saturation, 1).toColor();

    canvas.drawCircle(pickerPos, 13, Paint()..color = Colors.white);
    canvas.drawCircle(pickerPos, 11, Paint()..color = indicatorColor);
    canvas.drawCircle(
      pickerPos,
      13,
      Paint()
        ..color = const Color(0x50000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_HsvWheelPainter old) =>
      hue != old.hue || saturation != old.saturation;
}

// ── Luxe gradient bar (brightness / channel / CCT) ───────────────────────────

class _LuxeGradientBar extends StatefulWidget {
  const _LuxeGradientBar({
    required this.value,
    required this.colors,
    required this.onChanged,
    required this.onChangeEnd,
    this.label,
    this.thumbColor,
    this.height = 22,
  });

  final double value;       // 0–1
  final List<Color> colors; // gradient stops
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final String? label;
  final Color?  thumbColor;
  final double  height;

  @override
  State<_LuxeGradientBar> createState() => _LuxeGradientBarState();
}

class _LuxeGradientBarState extends State<_LuxeGradientBar> {
  bool _dragging = false;

  void _tap(double x, double w, bool end) {
    final v = (x / w).clamp(0.0, 1.0);
    if (end) {
      widget.onChangeEnd(v);
    } else {
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              widget.label!,
              style: TextStyle(
                color: LuxeColors.inkSoft,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (ctx, bc) {
            final w = bc.maxWidth;
            final h = widget.height;
            final thumbR = h / 2 + 2;
            final barLeft  = thumbR;
            final barWidth = w - thumbR * 2;
            final thumbX   = barLeft + widget.value * barWidth;

            return GestureDetector(
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: (e) => _tap(e.localPosition.dx - barLeft, barWidth, false),
              onHorizontalDragEnd:   (_) {
                setState(() => _dragging = false);
                widget.onChangeEnd(widget.value);
              },
              onTapDown: (e) => _tap(e.localPosition.dx - barLeft, barWidth, true),
              child: SizedBox(
                width: w,
                height: h + 8,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Track
                    Positioned(
                      left: barLeft,
                      width: barWidth,
                      child: Container(
                        height: h,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: widget.colors),
                          borderRadius: BorderRadius.circular(h / 2),
                          border: Border.all(
                            color: LuxeColors.line,
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                    // Thumb
                    Positioned(
                      left: thumbX - thumbR,
                      child: AnimatedContainer(
                        duration: _dragging
                            ? Duration.zero
                            : Duration(milliseconds: 80),
                        width:  thumbR * 2,
                        height: thumbR * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.thumbColor ?? Colors.white,
                          border: Border.all(
                            color: LuxeColors.ink.withValues(alpha: 0.18),
                            width: 1.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Lutron Homeworks → KNX (telnet monitoring + test)                    */
/* --------------------------------------------------------------------- */

class LutronHomeworksTile extends ConsumerWidget {
  const LutronHomeworksTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = device.raw['lutronHomeworks'] as Map?;
    final zone = cfg?['zoneAddress'] as String?;
    final bridge = cfg?['bridgeHost'] as String?;
    final tel = cfg?['telnet'] as Map?;
    final telEnabled = tel?['enabled'] == true;
    final telHost = (tel?['host'] as String?)?.trim();
    final hostLine = (telHost != null && telHost.isNotEmpty)
        ? telHost
        : (bridge?.trim().isNotEmpty == true ? bridge!.trim() : null);
    final maps = (cfg?['buttonToKnx'] as List?) ?? [];

    Future<void> fireTest(String mappingId) async {
      await ref.read(busProvider.notifier).send({
        'kind': 'lutron.fireMapping',
        'deviceId': device.id,
        'mappingId': mappingId,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test: mapping "$mappingId" naar KNX verstuurd')),
      );
    }

    final mapRows = <Widget>[];
    for (final raw in maps) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final id = m['id'] as String? ?? '';
      final label = m['label'] as String? ?? id;
      final knx = m['knx'];
      final ga = knx is Map ? (knx['ga'] as String? ?? '') : '';
      if (id.isEmpty) continue;
      mapRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$label${ga.isNotEmpty ? ' → $ga' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              OutlinedButton(
                onPressed: () => fireTest(id),
                child: const Text('Test'),
              ),
            ],
          ),
        ),
      );
    }

    final sub = [
      if (zone != null && zone.isNotEmpty) 'Zone: $zone',
      if (hostLine != null) 'Host: $hostLine',
      if (telEnabled) 'Telnet: aan',
    ].join(' · ');

    return DeviceTileShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeviceTileIconBadge(
            icon: Icons.home_work_outlined,
            active: telEnabled && hostLine != null,
          ),
          SizedBox(width: DeviceTileLayout.iconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  sub.isEmpty
                      ? 'Lutron Homeworks — configureer telnet + knop→KNX in de installateur-app.'
                      : sub,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: LuxeColors.inkSoft,
                      ),
                ),
                if (mapRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Knop → KNX',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  ...mapRows,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Shading                                                              */
/* --------------------------------------------------------------------- */

/// Fixed width for shading control bars on PC/tablet (both rows match).
enum _ShadingPosVisual { open, half, closed }

_ShadingPosVisual _shadingPosVisual(double percent) {
  if (percent <= 2) return _ShadingPosVisual.open;
  if (percent >= 98) return _ShadingPosVisual.closed;
  return _ShadingPosVisual.half;
}

const _kShadingPosVisualClosing = [
  _ShadingPosVisual.open,
  _ShadingPosVisual.half,
  _ShadingPosVisual.closed,
];

const _kShadingPosVisualOpening = [
  _ShadingPosVisual.closed,
  _ShadingPosVisual.half,
  _ShadingPosVisual.open,
];

/// `up` = openen, `down` = sluiten; `stop` / onbekend → `null`.
bool? _shadingMoveIsClosing(String? direction) {
  return switch (direction) {
    'down' => true,
    'up' => false,
    _ => null,
  };
}

/// Parse 0–100 % from bus payload (handles int/double/string and 0–255 actuators).
double? _parseShadingPercent(dynamic raw) {
  if (raw == null) return null;
  num? n;
  if (raw is num) {
    n = raw;
  } else if (raw is String) {
    n = num.tryParse(raw);
  }
  if (n == null) return null;
  var v = n.toDouble();
  if (v > 100 && v <= 255) v = (v / 255) * 100;
  return v.clamp(0.0, 100.0);
}

/// Best available shading position: actuator feedback, else last command echo.
double _shadingPositionPercent(Map<String, dynamic> values, Map<String, String> ga) {
  final statusGa = ga['position_status'];
  final cmdGa = ga['position'];
  final status =
      statusGa != null ? _parseShadingPercent(values[statusGa]) : null;
  final cmd = cmdGa != null ? _parseShadingPercent(values[cmdGa]) : null;
  if (statusGa != null && values.containsKey(statusGa) && status != null) {
    return status;
  }
  if (cmdGa != null && values.containsKey(cmdGa) && cmd != null) {
    return cmd;
  }
  return status ?? cmd ?? 0.0;
}

bool _shadingIsMoving(Map<String, dynamic> values, Map<String, String> ga) {
  final gaAddr = ga['moving'];
  if (gaAddr == null || gaAddr.isEmpty) return false;
  final v = values[gaAddr];
  return v == true || v == 1;
}

/// Custom 3-state icon (open / half / closed) — visually distinct per state.
class _ShadingPosIconGraphic extends StatelessWidget {
  const _ShadingPosIconGraphic({
    super.key,
    required this.subtype,
    required this.state,
    required this.color,
    this.size = 22,
  });

  final ShadingSubtype subtype;
  final _ShadingPosVisual state;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ShadingPosIconPainter(
        subtype: subtype,
        state: state,
        color: color,
      ),
    );
  }
}

class _ShadingPosIconPainter extends CustomPainter {
  _ShadingPosIconPainter({
    required this.subtype,
    required this.state,
    required this.color,
  });

  final ShadingSubtype subtype;
  final _ShadingPosVisual state;
  final Color color;

  ShadingArtState get _artState => switch (state) {
        _ShadingPosVisual.open => ShadingArtState.open,
        _ShadingPosVisual.half => ShadingArtState.half,
        _ShadingPosVisual.closed => ShadingArtState.closed,
      };

  @override
  void paint(Canvas canvas, Size size) {
    ShadingSubtypeGlyphPainter(
      style: subtype.positionIconStyle,
      state: _artState,
      color: color,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ShadingPosIconPainter old) =>
      old.state != state || old.subtype != subtype || old.color != color;
}

/// Positie-icoon links op de tegel: open / half / dicht, cyclisch tijdens beweging.
class _ShadingPositionStateIcon extends StatefulWidget {
  const _ShadingPositionStateIcon({
    required this.subtype,
    required this.position,
    this.isMoving = false,
    this.closingWhileMoving,
  });

  final ShadingSubtype subtype;
  final double position;
  final bool isMoving;
  /// `true` = sluiten, `false` = openen, `null` = afleiden uit positiewijziging.
  final bool? closingWhileMoving;

  @override
  State<_ShadingPositionStateIcon> createState() =>
      _ShadingPositionStateIconState();
}

class _ShadingPositionStateIconState extends State<_ShadingPositionStateIcon>
    with SingleTickerProviderStateMixin {
  static const _stepMs = 550;

  late final AnimationController _cycle;
  double? _positionAtMoveStart;
  bool? _inferredClosing;

  @override
  void initState() {
    super.initState();
    _cycle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _stepMs * 3),
    );
    if (widget.isMoving) _startCycle();
  }

  void _startCycle() {
    _positionAtMoveStart = widget.position;
    _inferredClosing = null;
    _cycle.repeat();
  }

  void _stopCycle() {
    _cycle.stop();
    _cycle.value = 0;
    _positionAtMoveStart = null;
    _inferredClosing = null;
  }

  @override
  void didUpdateWidget(covariant _ShadingPositionStateIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMoving && !oldWidget.isMoving) {
      _startCycle();
    } else if (!widget.isMoving && oldWidget.isMoving) {
      _stopCycle();
    }

    if (widget.isMoving &&
        _inferredClosing == null &&
        widget.closingWhileMoving == null &&
        _positionAtMoveStart != null) {
      final delta = widget.position - _positionAtMoveStart!;
      if (delta > 0.5) _inferredClosing = true;
      if (delta < -0.5) _inferredClosing = false;
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  bool get _closing {
    if (widget.closingWhileMoving != null) return widget.closingWhileMoving!;
    if (_inferredClosing != null) return _inferredClosing!;
    // Nog geen richting: cyclisch sluiten vanaf huidige stand.
    return true;
  }

  _ShadingPosVisual get _restState => _shadingPosVisual(widget.position);

  _ShadingPosVisual get _movingState {
    final states = _closing ? _kShadingPosVisualClosing : _kShadingPosVisualOpening;
    final step =
        (_cycle.value * states.length).floor().clamp(0, states.length - 1);
    return states[step];
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.isMoving ? _movingState : _restState;
    final tooltip = switch (state) {
      _ShadingPosVisual.open => 'Open',
      _ShadingPosVisual.half => 'Half open',
      _ShadingPosVisual.closed => 'Dicht',
    };
    final movingHint = widget.isMoving
        ? (_closing ? ' — sluit' : ' — opent')
        : '';

    return Tooltip(
      message: '$tooltip$movingHint',
      child: AnimatedBuilder(
        animation: _cycle,
        builder: (context, _) {
          final visual = widget.isMoving ? _movingState : _restState;
          return Container(
            width: DeviceControlBar.tileIconSize,
            height: DeviceControlBar.tileIconSize,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(DeviceControlBar.tileIconRadius),
              color: LuxeColors.surfaceDim.withValues(alpha: 0.7),
              border: Border.all(
                color: widget.isMoving
                    ? LuxeColors.brass.withValues(alpha: 0.45)
                    : LuxeColors.line,
              ),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: 120),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _ShadingPosIconGraphic(
                  key: ValueKey(visual),
                  subtype: widget.subtype,
                  state: visual,
                  color: LuxeColors.ink,
                  size: DeviceControlBar.tileGlyphSize,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ShadingTile extends ConsumerStatefulWidget {
  const ShadingTile({super.key, required this.device});
  final Device device;

  @override
  ConsumerState<ShadingTile> createState() => _ShadingTileState();
}

class _ShadingTileState extends ConsumerState<ShadingTile> {
  String? _lastMoveDirection;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final bus = ref.watch(busProvider);
    final isPositionActuator = d.type == DeviceType.positionActuator;
    final subtype = d.shadingSubtype;

    final hasPosition = d.ga['position'] != null || d.isLutronShade;
    final position = _shadingPositionPercent(bus.values, d.ga);

    final hasStopGa = d.ga['stop_step'] != null || d.isLutronShade;
    final hasUpDown = d.ga['up_down'] != null || d.isLutronShade;
    final hasSlat = d.ga['slat'] != null;
    final isJalousie = !isPositionActuator && subtype == ShadingSubtype.jalousie;
    final isMoving = _shadingIsMoving(bus.values, d.ga);

    final horizontalControls =
        !isPositionActuator && subtype.usesHorizontalOpenClose;

    final slatGa = d.ga['slat_status'] ?? d.ga['slat'];
    final slatRaw = slatGa == null ? null : bus.values[slatGa];
    final slatPct = slatRaw is num ? slatRaw.toDouble().clamp(0, 100) : 0.0;

    void move(String dir) {
      setState(() => _lastMoveDirection = dir);
      ref.read(busProvider.notifier).send({
        'kind': 'shading.move',
        'deviceId': d.id,
        'direction': dir,
      });
    }

    void nudgeSlat(int delta) {
      final next = (slatPct + delta).round().clamp(0, 100);
      ref.read(busProvider.notifier).send({
        'kind': 'shading.slats',
        'deviceId': d.id,
        'percent': next,
      });
    }

    void openPopup() {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black38,
        builder: (_) => _ShadingPopup(device: d),
      );
    }

    // Gordijn: open/sluit-pijlen; jaloezie/rol: pijl omhoog/omlaag.
    final moveUpArrow = horizontalControls
        ? DeviceArrowDirection.horizontalOpen
        : DeviceArrowDirection.up;
    final moveDownArrow = horizontalControls
        ? DeviceArrowDirection.horizontalClose
        : DeviceArrowDirection.down;

    final moveItems = <DeviceControlItem>[
      if (hasUpDown)
        DeviceControlItem(
          arrow: moveUpArrow,
          label: 'Open',
          labelMode: DeviceControlLabelMode.iconOnly,
          onTap: () => move('up'),
        ),
      if (hasStopGa)
        DeviceControlItem(
          icon: Icons.stop_circle_outlined,
          label: 'Stop',
          labelMode: DeviceControlLabelMode.iconOnly,
          onTap: () => move('stop'),
        ),
      if (hasUpDown)
        DeviceControlItem(
          arrow: moveDownArrow,
          label: 'Dicht',
          labelMode: DeviceControlLabelMode.iconOnly,
          onTap: () => move('down'),
        ),
    ];

    final tiltItems = <DeviceControlItem>[
      DeviceControlItem(
        icon: Icons.rotate_left,
        label: 'Tuimel open',
        labelMode: DeviceControlLabelMode.iconOnly,
        onTap: () => nudgeSlat(-5),
      ),
      DeviceControlItem(
        icon: Icons.rotate_right,
        label: 'Tuimel dicht',
        labelMode: DeviceControlLabelMode.iconOnly,
        onTap: () => nudgeSlat(5),
      ),
    ];

    final header = Row(
      crossAxisAlignment: DeviceTileLayout.iconRowAlignment,
      children: [
        GestureDetector(
          onLongPress: openPopup,
          child: isPositionActuator
              ? DeviceTileIconBadge(icon: Icons.vertical_split_outlined)
              : hasPosition
                  ? _ShadingPositionStateIcon(
                      subtype: subtype,
                      position: position,
                      isMoving: isMoving,
                      closingWhileMoving: isMoving
                          ? _shadingMoveIsClosing(_lastMoveDirection)
                          : null,
                    )
                  : DeviceTileIconBadge(
                      glyph: ShadingSubtypeGlyph(
                        subtype: subtype,
                        size: DeviceControlBar.tileGlyphSize,
                        color: LuxeColors.ink,
                      ),
                    ),
        ),
        SizedBox(width: DeviceTileLayout.iconGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (isPositionActuator) ...[
                const SizedBox(height: DeviceTileLayout.titleStatusGap),
                Text(
                  hasPosition
                      ? 'Positie · ${position.round()}%'
                      : 'Positie-aansturing',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        if (hasPosition)
          GestureDetector(
            onTap: openPopup,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.tune_rounded,
                size: DeviceControlIcons.size,
                color: LuxeColors.ink,
              ),
            ),
          ),
      ],
    );

    final hasMoveBar = moveItems.isNotEmpty;
    final hasTiltBar = (isJalousie || isPositionActuator) && hasSlat;

    final controlGap = DeviceControlBar.sectionSpacing(context);

    return DeviceTileShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (hasMoveBar || hasTiltBar) ...[
            SizedBox(height: controlGap),
            DeviceCardBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasMoveBar && hasTiltBar)
                    DeviceControlBar.moveAndTiltBlock(
                      moveItems: moveItems,
                      tiltItems: tiltItems,
                      rowGap: controlGap,
                    )
                  else ...[
                    if (hasMoveBar)
                      DeviceControlBar.singleRow(context, moveItems),
                    if (hasMoveBar && hasTiltBar)
                      SizedBox(height: controlGap),
                    if (hasTiltBar)
                      DeviceControlBar.tiltRow(context, tiltItems),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Shading popup (slider dialog)                                       */
/* ------------------------------------------------------------------ */

class _ShadingPopup extends ConsumerStatefulWidget {
  const _ShadingPopup({required this.device});
  final Device device;

  @override
  ConsumerState<_ShadingPopup> createState() => _ShadingPopupState();
}

class _ShadingPopupState extends ConsumerState<_ShadingPopup> {
  double? _dragPos;
  double? _dragSlat;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final bus = ref.watch(busProvider);
    final isPositionActuator = d.type == DeviceType.positionActuator;
    final subtype = d.shadingSubtype;
    final horizontalSlider =
        !isPositionActuator && subtype.usesHorizontalPositionSlider;

    final hasPosition = d.ga['position'] != null || d.isLutronShade;
    final position =
        _dragPos ?? _shadingPositionPercent(bus.values, d.ga);

    final slatGa = d.ga['slat_status'] ?? d.ga['slat'];
    final hasSlat = d.ga['slat'] != null;
    final slatRaw = slatGa == null ? null : bus.values[slatGa];
    final slatPct =
        _dragSlat ?? (slatRaw is num ? slatRaw.toDouble().clamp(0, 100) : 0.0);

    final hasStopGa = d.ga['stop_step'] != null || d.isLutronShade;
    final hasUpDown = d.ga['up_down'] != null || d.isLutronShade;

    void move(String dir) => ref.read(busProvider.notifier).send({
          'kind': 'shading.move',
          'deviceId': d.id,
          'direction': dir,
        });

    void commitPosition(double v) {
      ref.read(busProvider.notifier).send({
        'kind': 'shading.position',
        'deviceId': d.id,
        'percent': v.round(),
      });
      setState(() => _dragPos = null);
    }

    void commitSlat(double v) {
      ref.read(busProvider.notifier).send({
        'kind': 'shading.slats',
        'deviceId': d.id,
        'percent': v.round(),
      });
      setState(() => _dragSlat = null);
    }

    void nudgeSlat(int delta) {
      final next = (slatPct + delta).round().clamp(0, 100);
      ref.read(busProvider.notifier).send({
        'kind': 'shading.slats',
        'deviceId': d.id,
        'percent': next,
      });
    }

    // Curtain: horizontal slider (left = 0%, right = 100%)
    // Other: vertical slider (top = 0% open, bottom = 100% closed)
    Widget positionSlider;
    if (horizontalSlider) {
      positionSlider = _buildHSlider(
        value: position,
        onChanged: (v) => setState(() => _dragPos = v),
        onChangeEnd: commitPosition,
        accent: LuxeColors.brass,
      );
    } else {
      // Vertical: top = open (0%), bottom = closed (100%)
      // RotatedBox quarterTurns:1 maps left→top, right→bottom
      // Labels placed outside the slider to avoid overlapping the thumb
      positionSlider = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Open',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: LuxeColors.inkFaint)),
          SizedBox(height: 4),
          RotatedBox(
            quarterTurns: 1,
            child: SizedBox(
              width: 200,
              child: _buildHSlider(
                value: position,
                onChanged: (v) => setState(() => _dragPos = v),
                onChangeEnd: commitPosition,
                accent: LuxeColors.brass,
              ),
            ),
          ),
          SizedBox(height: 4),
          Text('Gesloten',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: LuxeColors.inkFaint)),
        ],
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 24, offset: Offset(0, 8))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  isPositionActuator
                      ? Icon(Icons.vertical_split_outlined,
                          size: DeviceControlIcons.size, color: LuxeColors.ink)
                      : ShadingSubtypeGlyph(
                          subtype: subtype,
                          size: DeviceControlIcons.size,
                          color: LuxeColors.ink,
                        ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(d.name,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Position %
            if (hasPosition)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${position.round()}%',
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(
                          color: LuxeColors.brass,
                          fontWeight: FontWeight.w600),
                ),
              ),
            // Slider
            if (hasPosition)
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: positionSlider,
              ),
            // Slat controls
            if (hasSlat) ...[
              const Divider(height: 24, indent: 20, endIndent: 20),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('Lamellen',
                        style: Theme.of(context).textTheme.labelLarge),
                    const Spacer(),
                    Text('${slatPct.round()}%',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: _buildHSlider(
                  value: slatPct,
                  onChanged: (v) => setState(() => _dragSlat = v),
                  onChangeEnd: commitSlat,
                  accent: LuxeColors.brassDeep,
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  static Widget _buildHSlider({
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    Color? accent,
  }) {
    final accentColor = accent ?? LuxeColors.brass;
    return Builder(
      builder: (context) => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: accentColor.withValues(alpha: 0.6),
          inactiveTrackColor: LuxeColors.line,
          thumbColor: LuxeColors.brass,
          overlayShape: SliderComponentShape.noOverlay,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
        ),
        child: Slider(
          value: value.clamp(0, 100),
          min: 0,
          max: 100,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: LuxeColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LuxeColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: DeviceControlIcons.size, color: LuxeColors.ink),
            SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: LuxeColors.ink,
                )),
          ],
        ),
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Climate                                                              */
/* --------------------------------------------------------------------- */

bool _climateDemandActive(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value > 0;
  return false;
}

/// DPT 1.100: 1 = verwarmen, 0 = koelen.
bool _climateIsHeating(dynamic hvacRaw, {required bool defaultHeat}) {
  if (hvacRaw == null) return defaultHeat;
  if (hvacRaw is bool) return hvacRaw;
  if (hvacRaw is num) return hvacRaw != 0;
  if (hvacRaw is String) {
    final s = hvacRaw.trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'heat') return true;
    if (s == '0' || s == 'false' || s == 'cool') return false;
  }
  return defaultHeat;
}

String _hvacSwitchNotice(HvacSwitchLockDuration lockDuration) {
  final lockText = lockDuration.formatForDialog();
  return lockDuration.hasLock
      ? 'Let op: omschakelen kan niet direct ongedaan worden gemaakt. '
          'Na omschakeling wordt de functie voor $lockText vergrendeld '
          'om het systeem te beschermen.'
      : 'Let op: omschakelen kan niet direct ongedaan worden gemaakt. '
          'Het is niet efficiënt om meerdere keren per etmaal om te schakelen.';
}

class ClimateTile extends ConsumerStatefulWidget {
  const ClimateTile({super.key, required this.device});
  final Device device;

  @override
  ConsumerState<ClimateTile> createState() => _ClimateTileState();
}

class _ClimateTileState extends ConsumerState<ClimateTile> {
  double? _pending;
  Timer? _pendingTimer;
  Timer? _hvacLockTimer;

  @override
  void initState() {
    super.initState();
    _hvacLockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(hvacLockProvider.notifier).pruneExpired();
      if (mounted) setState(() {});
    });
  }

  DateTime? _hvacLockUntil(Map<String, int> locks) {
    final ms = locks[widget.device.id];
    if (ms == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    if (!dt.isAfter(DateTime.now())) return null;
    return dt;
  }

  Duration? _hvacLockRemaining(DateTime? until) {
    if (until == null) return null;
    final rem = until.difference(DateTime.now());
    if (rem.isNegative || rem.inSeconds <= 0) return null;
    return rem;
  }

  Future<void> _confirmAndSwitchHvac({
    required bool toHeat,
    required bool currentlyHeating,
    required HvacSwitchLockDuration lockDuration,
    required bool hvacSwitchLocked,
  }) async {
    if (toHeat == currentlyHeating || hvacSwitchLocked) return;

    final target = toHeat ? 'Verwarmen' : 'Koelen';
    final confirmed = await showHvacSwitchConfirmDialog(
      context,
      target: target,
      notice: _hvacSwitchNotice(lockDuration),
    );
    if (confirmed != true || !mounted) return;

    ref.read(busProvider.notifier).send({
      'kind': 'climate.mode',
      'deviceId': widget.device.id,
      'heat': toHeat,
    });
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _hvacLockTimer?.cancel();
    super.dispose();
  }

  void _adjustSetpoint(double delta, double min, double max) {
    final bus = ref.read(busProvider);
    final d = widget.device;
    final spV = bus.values[d.ga['setpoint_status'] ?? d.ga['setpoint']];
    final current = _pending ?? (spV is num ? spV.toDouble() : 21.0);
    final next = (current + delta).clamp(min, max);
    final rounded = double.parse(next.toStringAsFixed(1));
    _pendingTimer?.cancel();
    setState(() => _pending = rounded);
    ref.read(busProvider.notifier).send({
      'kind': 'climate.setpoint',
      'deviceId': d.id,
      'celsius': rounded,
    });
    // Reset pending after 4s so bus value takes over again.
    _pendingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _pending = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d   = widget.device;
    final bus = ref.watch(busProvider);
    final hvacLocks = ref.watch(hvacLockProvider);

    // Temperatures
    final actualV  = bus.values[d.ga['actual_temp']];
    final spV      = bus.values[d.ga['setpoint_status'] ?? d.ga['setpoint']];
    final actual   = actualV is num ? actualV.toDouble() : null;
    final setpoint = _pending ?? (spV is num ? spV.toDouble() : 21.0);

    // Capabilities + limits from installer config
    final climateCfg    = d.raw['climate'] as Map<String, dynamic>?;
    final canHeat       = climateCfg?['canHeat'] as bool? ?? true;
    final canCool       = climateCfg?['canCool'] as bool? ?? false;
    final userCanSwitch = climateCfg?['userCanSwitchMode'] as bool? ?? false;
    final hvacLockDuration =
        HvacSwitchLockDuration.fromClimateConfig(climateCfg);
    final hasHvacControl = canHeat && canCool;
    final minTemp = (climateCfg?['minTemp'] as num?)?.toDouble() ?? 5.0;
    final maxTemp = (climateCfg?['maxTemp'] as num?)?.toDouble() ?? 35.0;
    final stepRaw = climateCfg?['tempStep'];
    final step    = stepRaw is num ? stepRaw.toDouble() : 0.5;

    // Operating modes (DPT 20.102: 1=Comfort 2=Standby 3=Economy 4=BuildingProtection)
    final modesMap = climateCfg?['modes'] as Map<String, dynamic>?;
    final modeGa       = d.ga['mode'];
    final modeStatusGa = d.ga['mode_status'] ?? modeGa;
    final modeRaw      = modeStatusGa != null ? bus.values[modeStatusGa] : null;
    final currentMode  = modeRaw is num ? modeRaw.toInt() : null;
    final showModes    = modeGa != null;

    // HVAC mode status — 1/true = heating, 0/false = cooling
    final hvacStatusGa = d.ga['hvac_mode_status'] ?? d.ga['hvac_mode'];
    final hvacRaw      = hvacStatusGa != null ? bus.values[hvacStatusGa] : null;
    final isHeating = _climateIsHeating(hvacRaw, defaultHeat: canHeat);

    // Warmte-/koudevraag — bit 1 of byte > 0, icoon volgt hvac-modus.
    final heatDemandGa = d.ga['heat_demand'];
    final coolDemandGa = d.ga['cool_demand'];
    final demandGa = isHeating ? heatDemandGa : coolDemandGa;
    final demandActive =
        _climateDemandActive(demandGa != null ? bus.values[demandGa] : null);
    final showDemandIcon = demandGa != null;

    final hvacLockUntil = _hvacLockUntil(hvacLocks);
    final hvacLockRemaining = _hvacLockRemaining(hvacLockUntil);
    final hvacSwitchLocked = hvacLockRemaining != null;

    void sendMode(int value) {
      ref.read(busProvider.notifier).send({
        'kind': 'climate.opmode',
        'deviceId': d.id,
        'mode': value,
      });
    }

    // Build list of enabled operating modes
    final List<({int value, String label, IconData icon})> opModes = [];
    void addMode(int v, String key, String label, IconData icon) {
      final enabled = modesMap == null || modesMap[key] != false;
      if (enabled) opModes.add((value: v, label: label, icon: icon));
    }
    addMode(1, 'comfort',   'Comfort',   Icons.wb_sunny_outlined);
    addMode(2, 'standby',   'Standby',   Icons.pause_circle_outline_rounded);
    addMode(3, 'economy',   'Economy',   Icons.eco_outlined);
    addMode(4, 'buildingProtection', 'Beveiliging', Icons.shield_outlined);

    Widget? hvacTrailing;
    if (hasHvacControl && userCanSwitch) {
      hvacTrailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HvacModeButton(
            icon: Icons.local_fire_department_outlined,
            color: _HvacColors.heat,
            selected: isHeating,
            locked: hvacSwitchLocked,
            onTap: hvacSwitchLocked || isHeating
                ? null
                : () => _confirmAndSwitchHvac(
                      toHeat: true,
                      currentlyHeating: isHeating,
                      lockDuration: hvacLockDuration,
                      hvacSwitchLocked: hvacSwitchLocked,
                    ),
          ),
          const SizedBox(width: DeviceControlBar.gap),
          _HvacModeButton(
            icon: Icons.ac_unit_outlined,
            color: _HvacColors.cool,
            selected: !isHeating,
            locked: hvacSwitchLocked,
            onTap: hvacSwitchLocked || !isHeating
                ? null
                : () => _confirmAndSwitchHvac(
                      toHeat: false,
                      currentlyHeating: isHeating,
                      lockDuration: hvacLockDuration,
                      hvacSwitchLocked: hvacSwitchLocked,
                    ),
          ),
        ],
      );
    } else if (canHeat || canCool) {
      hvacTrailing = _HvacModeButton(
        icon: isHeating
            ? Icons.local_fire_department_outlined
            : Icons.ac_unit_outlined,
        color: isHeating ? _HvacColors.heat : _HvacColors.cool,
        selected: true,
      );
    }

    return DeviceTileShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                DeviceTileIconBadge(
                  icon: Icons.thermostat_outlined,
                  onTap: () => context.push(
                    '/log/thermostat-${d.id}'
                    '?title=${Uri.encodeComponent(d.name)}'
                    '&mode=${isHeating ? 'heat' : 'cool'}',
                  ),
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: LuxeColors.brass,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: LuxeColors.surface,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.show_chart_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (hvacSwitchLocked) ...[
                  const SizedBox(height: DeviceTileLayout.titleStatusGap),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${isHeating ? 'Koel' : 'Verwarm'} blokkade · ${HvacLockStore.formatRemaining(hvacLockRemaining!)}',
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: LuxeColors.inkSoft,
                          ),
                    ),
                  ),
                ],
              ],
            ),
            trailing: hvacTrailing == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: hvacTrailing,
                  ),
          ),

          if (actual != null || showDemandIcon) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            _ClimateMeasuredStatusRow(
              actual: actual,
              isHeating: isHeating,
              showDemandIcon: showDemandIcon,
              demandActive: demandActive,
            ),
          ],

          SizedBox(height: DeviceControlBar.sectionSpacing(context)),
          DeviceControlSetpointRow(
            value: setpoint,
            onDecrease: () => _adjustSetpoint(-step, minTemp, maxTemp),
            onIncrease: () => _adjustSetpoint(step, minTemp, maxTemp),
            decimals: step < 1 ? 1 : 0,
          ),

          if (showModes && opModes.isNotEmpty) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            DeviceControlSection(
              title: 'MODUS',
              child: DeviceControlBar.gridAuto(
                context,
                [
                  for (final m in opModes)
                    DeviceControlItem(
                      icon: m.icon,
                      label: m.label,
                      labelMode: DeviceControlLabelMode.iconOnly,
                      active: currentMode == m.value,
                      onTap: () => sendMode(m.value),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Vierkante verwarm/koel-knop rechtsbovenin de thermostaat-tegel — zelfde
/// formaat (56×56) en stijl als de andere apparaatknoppen.
///
/// • Tikbaar (onTap != null): keuzeknop. Geselecteerde modus krijgt de
///   moduskleur (oranje = verwarmen, blauw = koelen), inactief is wit chrome.
/// • Niet tikbaar (onTap == null): status-weergave wanneer de gebruiker niet
///   zelf mag omschakelen — toont alleen de huidige stand met de moduskleur.
/// • Vergrendeld (locked): grijs, niet bedienbaar.
class _HvacModeButton extends StatefulWidget {
  const _HvacModeButton({
    required this.icon,
    required this.color,
    required this.selected,
    this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final bool locked;

  @override
  State<_HvacModeButton> createState() => _HvacModeButtonState();
}

class _HvacModeButtonState extends State<_HvacModeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final size = DeviceControlBar.buttonSizeFor(context);
    const radius = DeviceControlBar.buttonRadius;
    final bool highlight = widget.selected && !widget.locked;
    final glyphSize = DeviceControlBar.glyphSizeFor(context);

    final Color iconColor = widget.locked
        ? (widget.selected
            ? widget.color
            : LuxeColors.inkSoft.withValues(alpha: 0.35))
        : widget.selected
            ? widget.color
            : LuxeColors.ink;

    final Widget glyph = Icon(widget.icon, size: glyphSize, color: iconColor);

    Widget square;
    if (highlight) {
      // Geselecteerde modus: gekleurde tint met dezelfde knop-schaduw.
      square = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: DeviceControlBar.buttonShadows(active: true),
        ),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: widget.color.withValues(alpha: 0.12),
            border: Border.all(color: widget.color.withValues(alpha: 0.45)),
          ),
          child: glyph,
        ),
      );
    } else {
      // Inactief of vergrendeld: standaard witte knop-chrome.
      square = DeviceControlButtonSurface(
        locked: widget.locked,
        pressed: _pressed,
        width: size,
        height: size,
        child: Center(child: glyph),
      );
    }

    if (widget.onTap == null) {
      return SizedBox(width: size, height: size, child: square);
    }
    return SizedBox(
      width: size,
      height: size,
      child: PressScale(
        onTap: widget.onTap!,
        radius: radius,
        onPressedChanged: (pressed) => setState(() => _pressed = pressed),
        child: square,
      ),
    );
  }
}

/// Subtiele tints voor verwarmen/koelen — gedeeld door de keuzeknoppen en
/// de warmte-/koudevraag-indicatoren.
abstract final class _HvacColors {
  /// Subtiele warme tint voor verwarmen.
  static const Color heat = Color(0xFFE07A3F);
  /// Subtiele lichtblauwe tint voor koelen.
  static const Color cool = Color(0xFF5BA7E0);
}

/// Tussenregel: gemeten temperatuur + warmte-/koudevraag.
class _ClimateMeasuredStatusRow extends StatelessWidget {
  const _ClimateMeasuredStatusRow({
    required this.actual,
    required this.isHeating,
    required this.showDemandIcon,
    required this.demandActive,
    this.showMeasuredSlot = false,
    this.accessoryIcon,
    this.accessoryTooltip,
  });

  final double? actual;
  final bool isHeating;
  final bool showDemandIcon;
  final bool demandActive;
  /// Toon thermometer + waarde (of `--°` bij ontbrekende meting).
  final bool showMeasuredSlot;
  /// Icoon achter de meting (bijv. airco-modus).
  final IconData? accessoryIcon;
  final String? accessoryTooltip;

  @override
  Widget build(BuildContext context) {
    final btn = DeviceControlBar.buttonSizeFor(context);
    final glyph = DeviceControlBar.glyphSizeFor(context);

    return Center(
      child: DeviceControlButtonSurface(
        width: DeviceCardScale.climateChipWidth(context),
        height: btn,
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (showMeasuredSlot || actual != null) ...[
              Icon(
                Icons.device_thermostat_outlined,
                size: glyph + 2,
                color: LuxeColors.inkSoft,
              ),
              SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    actual != null
                        ? '${actual!.toStringAsFixed(1)}°'
                        : '--°',
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize:
                              DeviceCardScale.measuredTempFontSize(context),
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                  ),
                ),
              ),
            ],
            if (showDemandIcon) ...[
              if (showMeasuredSlot || actual != null) const SizedBox(width: 8),
              Tooltip(
                message: demandActive
                    ? (isHeating
                        ? 'Warmtevraag actief'
                        : 'Koudevraag actief')
                    : (isHeating
                        ? 'Geen warmtevraag'
                        : 'Geen koudevraag'),
                child: _HvacDemandGlyph(
                  heating: isHeating,
                  active: demandActive,
                ),
              ),
            ] else if (accessoryIcon != null) ...[
              if (showMeasuredSlot || actual != null) const SizedBox(width: 8),
              Tooltip(
                message: accessoryTooltip ?? '',
                child: Icon(
                  accessoryIcon,
                  size: glyph,
                  color: LuxeColors.inkSoft,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Warmte-/koudevraag — alleen icoonkleur, geen apart vakje.
class _HvacDemandGlyph extends StatelessWidget {
  const _HvacDemandGlyph({
    required this.heating,
    required this.active,
  });

  final bool heating;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = heating ? _HvacColors.heat : _HvacColors.cool;
    final icon = heating
        ? Icons.local_fire_department_outlined
        : Icons.ac_unit_outlined;

    return Icon(
      icon,
      size: DeviceControlBar.glyphSizeFor(context),
      color: active ? color : LuxeColors.inkSoft.withValues(alpha: 0.35),
    );
  }
}

class CameraTile extends ConsumerWidget {
  const CameraTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(cameraInfoProvider(device.id));
    return GlassCard(
      padding: DeviceTileLayout.padding(context),
      radius: 26,
      onTap: () => context.push('/camera/${device.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Icon(Icons.videocam_outlined,
                    color: LuxeColors.inkSoft, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(device.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.open_in_full,
                    size: 18, color: LuxeColors.inkSoft),
              ],
            ),
          ),
          Hero(
            tag: 'cam-${device.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: info.when(
                loading: () => _placeholderBox(16 / 9),
                error: (_, __) => _errorBox(16 / 9),
                data: (i) => CameraSnapshot(
                  cameraId: i.id,
                  aspectRatio: i.aspectRatio,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Intercom                                                             */
/* --------------------------------------------------------------------- */

class IntercomTile extends ConsumerWidget {
  const IntercomTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: DeviceTileLayout.padding(context),
      radius: 26,
      onTap: () => context.push('/intercom/${device.id}'),
      shadows: LuxeShadows.brassGlow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Icon(Icons.doorbell_outlined,
                    color: LuxeColors.brass, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(device.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                FilledButton.tonal(
                  onPressed: () => context.push('/intercom/${device.id}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: LuxeColors.ink,
                    foregroundColor: LuxeColors.onInk,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('OPNEMEN'),
                ),
              ],
            ),
          ),
          Hero(
            tag: 'intercom-${device.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CameraSnapshot(
                cameraId: device.id,
                aspectRatio: 4 / 3,
                kind: SnapshotKind.intercom,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Shared small UI primitives                                           */
/* --------------------------------------------------------------------- */

/* ---------------------------------------------------------------------- */
/*  Fireplace flame bar (step buttons replacing the slider)               */
/* ---------------------------------------------------------------------- */

/// Default 5-step mapping when no stepRanges / legacySteps are configured.
const _kDefaultFlameSteps = [20, 40, 60, 80, 100];

int _pctToDefaultStep(int pct) {
  for (var i = 0; i < _kDefaultFlameSteps.length; i++) {
    if (pct <= _kDefaultFlameSteps[i]) return i + 1;
  }
  return _kDefaultFlameSteps.length;
}

/// Renders the flame-level control as a [DeviceControlBar] of step buttons.
class _FireplaceFlameBar extends StatelessWidget {
  const _FireplaceFlameBar({
    required this.stepRanges,
    required this.legacySteps,
    required this.activeStep,
    required this.currentPct,
    required this.levelDisplay,
    required this.onStep,
    this.enabled = true,
  });

  final List<Map<String, dynamic>>? stepRanges;
  final int? legacySteps;
  final int activeStep;
  final int currentPct;
  final String? levelDisplay;
  final ValueChanged<int> onStep;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final List<DeviceControlItem> items;

    if (stepRanges != null && stepRanges!.length >= 2) {
      items = [
        for (var i = 0; i < stepRanges!.length; i++)
          DeviceControlItem(
            icon: Icons.local_fire_department_outlined,
            label: fireplaceStepLabel(
              ranges: stepRanges,
              step1Based: i + 1,
            ),
            labelMode: DeviceControlLabelMode.iconOnly,
            active: activeStep == i + 1,
            onTap: enabled ? () => onStep(i + 1) : null,
          ),
      ];
    } else if (legacySteps != null && legacySteps! >= 2) {
      items = [
        for (var i = 1; i <= legacySteps!; i++)
          DeviceControlItem(
            label: '$i',
            labelMode: DeviceControlLabelMode.numeric,
            active: activeStep == i,
            onTap: enabled ? () => onStep(i) : null,
          ),
      ];
    } else {
      items = [
        for (var i = 0; i < _kDefaultFlameSteps.length; i++)
          DeviceControlItem(
            label: '${i + 1}',
            labelMode: DeviceControlLabelMode.numeric,
            active: activeStep == i + 1,
            onTap: enabled ? () => onStep(_kDefaultFlameSteps[i]) : null,
          ),
      ];
    }

    final headerValue = (levelDisplay == 'volt_10' || levelDisplay == 'volt_3')
        ? _fireplaceFlameValueLabel(currentPct, levelDisplay)
        : fireplaceStepLabel(ranges: stepRanges, step1Based: activeStep);

    void bumpStep(int delta) {
      if (!enabled || items.isEmpty) return;
      var idx = items.indexWhere((e) => e.active);
      if (idx < 0) idx = 0;
      final next = idx + delta;
      if (next < 0 || next >= items.length) return;
      items[next].onTap?.call();
    }

    final stepControls = DeviceControlBar.singleRow(
      context,
      [
        DeviceControlItem(
          icon: Icons.remove,
          label: 'Lager',
          labelMode: DeviceControlLabelMode.iconOnly,
          onTap: enabled ? () => bumpStep(-1) : null,
        ),
        DeviceControlItem(
          icon: Icons.add,
          label: 'Hoger',
          labelMode: DeviceControlLabelMode.iconOnly,
          onTap: enabled ? () => bumpStep(1) : null,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'VLAMSTAND',
                style: DeviceControlBar.sectionTitleStyle(context),
              ),
            ),
            Text(
              headerValue,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        SizedBox(height: DeviceControlBar.sectionTitleGap),
        stepControls,
        if (!context.isPhone) ...[
          SizedBox(height: DeviceControlBar.sectionSpacing(context)),
          DeviceControlBar.gridAuto(context, items),
        ],
      ],
    );
  }
}

Widget _placeholderBox(double ar) => AspectRatio(
      aspectRatio: ar,
      child: Container(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LuxeColors.brass,
            ),
          ),
        ),
      ),
    );

Widget _errorBox(double ar) => AspectRatio(
      aspectRatio: ar,
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.videocam_off_outlined, color: Colors.white54),
        ),
      ),
    );

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name, required this.hint});
  final String name;
  final String hint;
  @override
  Widget build(BuildContext context) => DeviceTileShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(hint, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

/* --------------------------------------------------------------------- */
/*  Fireplace                                                            */
/* --------------------------------------------------------------------- */

bool _fireplaceIsDiscrete(Map<String, dynamic> cfg) =>
    cfg['controlMode'] == 'discrete' && cfg['discreteLevel'] is Map;

Map<String, dynamic>? _fireplacePulse(
    Map<String, dynamic>? discrete, String key) {
  final m = discrete?[key];
  return m is Map ? m.cast<String, dynamic>() : null;
}

String _fireplaceFlameLevelLabel(String? levelDisplay) {
  switch (levelDisplay) {
    case 'volt_10':
      return 'NIVEAU (0–10 V)';
    case 'volt_3':
      return 'NIVEAU (0–3 V)';
    default:
      return 'VLAMHOOGTE';
  }
}

String _fireplaceFlameValueLabel(int level, String? levelDisplay) {
  switch (levelDisplay) {
    case 'volt_10':
      return '${(level * 0.1).toStringAsFixed(1)} V';
    case 'volt_3':
      return '${(level * 0.03).toStringAsFixed(2)} V';
    default:
      return '$level%';
  }
}

/// Openhaard uit: vlam met schuine streep.
class _FireplaceHeaderGlyph extends StatelessWidget {
  const _FireplaceHeaderGlyph({
    required this.on,
    required this.size,
    required this.color,
  });

  final bool on;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      on ? Icons.local_fire_department : Icons.local_fire_department_outlined,
      size: size,
      color: color,
    );
    if (on) return icon;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          icon,
          CustomPaint(
            size: Size(size, size),
            painter: _IconSlashPainter(
              color: color.withValues(alpha: 0.92),
              strokeWidth: DeviceControlIcons.graphicStrokeFor(size) * 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconSlashPainter extends CustomPainter {
  const _IconSlashPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final pad = size.shortestSide * 0.12;
    canvas.drawLine(
      Offset(pad, size.height - pad),
      Offset(size.width - pad, pad),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _IconSlashPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

class FireplaceTile extends ConsumerStatefulWidget {
  const FireplaceTile({super.key, required this.device});

  final Device device;

  @override
  ConsumerState<FireplaceTile> createState() => _FireplaceTileState();
}

class _FireplaceTileState extends ConsumerState<FireplaceTile> {
  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final cfg = device.raw['fireplace'] as Map<String, dynamic>?;
    if (cfg == null) {
      return _Placeholder(name: device.name, hint: 'Config ontbreekt');
    }
    final bus = ref.watch(busProvider);
    final fireplaceVirtual = ref.watch(fireplaceVirtualProvider);

    final onOff = (cfg['onOff'] as Map).cast<String, dynamic>();
    final discreteMode = _fireplaceIsDiscrete(cfg);
    final statusBits = fireplaceStatusBitsMap(cfg);
    final hasStatusBits = fireplaceHasStatusBits(cfg);
    final onStatusGa = onOff['statusGa'] as String? ?? onOff['ga'] as String;
    final busOn = bus.values[onStatusGa] == true || bus.values[onStatusGa] == 1;
    final workingOn = fireplaceWorkingOn(cfg, bus.values);
    final on = workingOn ??
        FireplaceVirtualStore.resolveOn(
          discreteMode: discreteMode,
          virtual: fireplaceVirtual,
          deviceId: device.id,
          busOn: busOn,
        );
    final statusLabel = hasStatusBits
        ? fireplaceComposeStatusLabel(bus.values, statusBits)
        : (on ? 'Aan' : 'Uit');

    final discreteLevel =
        cfg['discreteLevel'] as Map<String, dynamic>?;
    final flame = cfg['flame'] as Map<String, dynamic>?;
    final stepRanges = parseFireplaceStepRanges(flame);
    final legacySteps = (flame?['steps'] as num?)?.toInt();
    final usePctBands =
        stepRanges != null && stepRanges.length >= 2 && flame != null;
    final levelDisplay = flame?['levelDisplay'] as String?;
    final flameStatusGa =
        (flame?['statusGa'] as String?) ?? (flame?['ga'] as String?);
    final flameVal = flameStatusGa == null ? null : bus.values[flameStatusGa];
    final flameRaw = flameVal is num ? flameVal.toInt() : 0;
    final stepUiValue = usePctBands
        ? busPercentToFlameStep(stepRanges, flameRaw.clamp(0, 100))
        : flameRaw;
    final sliderPct =
        (!usePctBands && (legacySteps == null)) ? flameRaw.clamp(0, 100) : 0;
    final legacyBarValue = (!usePctBands && legacySteps != null)
        ? flameRaw.clamp(1, legacySteps)
        : 1;

    // Altijd dezelfde waarschuwing bij aanzetten (analog, discrete, vlamstand).
    Future<bool> confirmFireplaceOn() =>
        maybeConfirm(context, ConfirmPrompt.fireplaceOn);

    Future<void> setOn(bool v) async {
      if (v) {
        if (!await confirmFireplaceOn()) return;
      } else {
        final ok = await maybeConfirm(context, device.confirm?.off);
        if (!ok) return;
      }
      ref.read(busProvider.notifier).send({
        'kind': 'fireplace.on',
        'deviceId': device.id,
        'on': v,
      });
    }

    Future<void> setFlame(int v) async {
      if (!on) return;
      final notifier = ref.read(busProvider.notifier);
      if (flameStatusGa != null) {
        if (usePctBands && stepRanges != null) {
          notifier.patchDimPercent(
            flameStatusGa,
            writePercentForFlameStep(
              stepRanges,
              v.clamp(1, stepRanges.length),
            ),
          );
        } else if (legacySteps == null) {
          notifier.patchDimPercent(flameStatusGa, v.clamp(0, 100));
        }
      }
      await notifier.send({
        'kind': 'fireplace.flame',
        'deviceId': device.id,
        'value': v,
      });
    }

    Future<void> sendDiscrete(String action) async {
      if (action == 'on') {
        if (!await confirmFireplaceOn()) return;
      }
      ref.read(busProvider.notifier).send({
        'kind': 'fireplace.discrete',
        'deviceId': device.id,
        'action': action,
      });
    }

    Future<void> toggleOn(bool v) async {
      if (discreteMode) {
        if (v) {
          await sendDiscrete('on');
        } else {
          await sendDiscrete('off');
        }
      } else {
        await setOn(v);
      }
    }

    Widget fireplaceControlBar(List<DeviceControlItem> items) =>
        DeviceControlBar.singleRow(context, items);

    return DeviceTileShell(
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: DeviceTileIconBadge(
              active: on,
              onTap: () => toggleOn(!on),
              glyph: _FireplaceHeaderGlyph(
                on: on,
                size: DeviceCardScale.glyphSize(context),
                color: on ? LuxeColors.brass : LuxeColors.ink,
              ),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: DeviceTileLayout.titleStatusGap),
                Text(
                  statusLabel ?? (on ? 'Aan' : 'Uit'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            trailing: DeviceTileLayout.trailingSwitch(
              context: context,
              value: on,
              onChanged: toggleOn,
            ),
          ),
          if (discreteMode && discreteLevel != null) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            fireplaceControlBar([
              if (_fireplacePulse(discreteLevel, 'down') != null)
                DeviceControlItem(
                  icon: Icons.remove,
                  label: 'Lager',
                  labelMode: DeviceControlLabelMode.iconOnly,
                  onTap: () => sendDiscrete('down'),
                ),
              if (_fireplacePulse(discreteLevel, 'up') != null)
                DeviceControlItem(
                  icon: Icons.add,
                  label: 'Hoger',
                  labelMode: DeviceControlLabelMode.iconOnly,
                  onTap: () => sendDiscrete('up'),
                ),
            ]),
          ],
          if (!discreteMode && flame != null) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            Opacity(
              opacity: on ? 1.0 : 0.45,
              child: _FireplaceFlameBar(
                stepRanges: stepRanges,
                legacySteps: legacySteps,
                activeStep: usePctBands
                    ? stepUiValue.clamp(1, stepRanges!.length)
                    : legacySteps != null
                        ? legacyBarValue
                        : _pctToDefaultStep(sliderPct),
                currentPct: flameRaw,
                levelDisplay: levelDisplay,
                enabled: on,
                onStep: setFlame,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  AC                                                                   */
/* --------------------------------------------------------------------- */

class AcTile extends ConsumerStatefulWidget {
  const AcTile({super.key, required this.device});
  final Device device;

  @override
  ConsumerState<AcTile> createState() => _AcTileState();
}

class _AcTileState extends ConsumerState<AcTile> {
  double? _pendingSp;

  @override
  Widget build(BuildContext context) {
    final cfg = widget.device.raw['ac'] as Map<String, dynamic>?;
    if (cfg == null) {
      return _Placeholder(name: widget.device.name, hint: 'AC-config ontbreekt');
    }
    final bus = ref.watch(busProvider);

    final onOff = (cfg['onOff'] as Map).cast<String, dynamic>();
    final onStatusGa = onOff['statusGa'] as String? ?? onOff['ga'] as String;
    final on = bus.values[onStatusGa] == true || bus.values[onStatusGa] == 1;

    final sp = (cfg['setpoint'] as Map).cast<String, dynamic>();
    final spStatusGa = sp['statusGa'] as String? ?? sp['ga'] as String;
    final spVal = bus.values[spStatusGa];
    final setpoint =
        _pendingSp ?? (spVal is num ? spVal.toDouble() : 21.0);
    final spMin = (sp['min'] as num?)?.toDouble() ?? 16.0;
    final spMax = (sp['max'] as num?)?.toDouble() ?? 30.0;

    final actualGa = (cfg['actualTemp'] as Map?)?['ga'] as String?;
    final actualV = actualGa == null ? null : bus.values[actualGa];
    final actual = actualV is num ? actualV.toDouble() : null;

    final mode = cfg['mode'] as Map<String, dynamic>?;
    final modeOptions = (mode?['options'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final modeVisibility =
        (cfg['modeVisibility'] as Map?)?.cast<String, dynamic>();
    final visibleModeOptions =
        acVisibleModeOptions(modeOptions, modeVisibility);
    final modeStatusGa =
        mode?['statusGa'] as String? ?? mode?['ga'] as String?;
    final modeVal = modeStatusGa == null ? null : bus.values[modeStatusGa];
    final activeMode = modeVal is num ? modeVal.toInt() : null;

    final heatModeValue = acHvacModeValue(visibleModeOptions, heat: true);
    final coolModeValue = acHvacModeValue(visibleModeOptions, heat: false);
    final isHeating = activeMode != null && activeMode == heatModeValue;
    final isCooling = activeMode != null && activeMode == coolModeValue;
    final inHvacMode = isHeating || isCooling;

    final fanSpeed = cfg['fanSpeed'] as Map<String, dynamic>?;
    final fanStatusGa =
        fanSpeed?['statusGa'] as String? ?? fanSpeed?['ga'] as String?;
    final fanVal = fanStatusGa == null ? null : bus.values[fanStatusGa];
    final activeFan = fanVal is num ? fanVal.toInt() : null;

    void commitSp(double v) {
      ref.read(busProvider.notifier).send({
        'kind': 'ac.setpoint',
        'deviceId': widget.device.id,
        'celsius': double.parse(v.toStringAsFixed(1)),
      });
      setState(() => _pendingSp = null);
    }

    final showDemandIcon = on && inHvacMode;
    final demandActive = showDemandIcon;

    IconData acHeaderIcon = Icons.ac_unit_outlined;
    String? acActiveModeLabel;
    if (activeMode != null) {
      for (final o in modeOptions) {
        if ((o['value'] as num).toInt() == activeMode) {
          acActiveModeLabel = o['label'] as String?;
          acHeaderIcon = deviceControlOptionIcon(
            iconKey: o['icon'] as String?,
            label: o['label'] as String,
          );
          break;
        }
      }
    }

    final hasMeasuredTempConfig = actualGa != null;

    return DeviceTileShell(
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: DeviceTileIconBadge(
              icon: acHeaderIcon,
              active: on,
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: DeviceTileLayout.titleStatusGap),
                Text(
                  on ? 'Aan' : 'Uit',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            trailing: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: DeviceTileLayout.trailingSwitch(
                context: context,
                value: on,
                onChanged: (v) {
                  ref.read(busProvider.notifier).send({
                    'kind': 'ac.on',
                    'deviceId': widget.device.id,
                    'on': v,
                  });
                },
              ),
            ),
          ),
          SizedBox(height: DeviceControlBar.sectionSpacing(context)),
          _ClimateMeasuredStatusRow(
            actual: hasMeasuredTempConfig ? actual : null,
            showMeasuredSlot: true,
            isHeating: isHeating,
            showDemandIcon: showDemandIcon,
            demandActive: demandActive,
            accessoryIcon:
                !showDemandIcon && activeMode != null && !inHvacMode
                    ? acHeaderIcon
                    : null,
            accessoryTooltip: acActiveModeLabel,
          ),
          SizedBox(height: DeviceControlBar.sectionSpacing(context)),
          DeviceControlSetpointRow(
            value: setpoint,
            onDecrease: () {
              final v = (setpoint - 0.5).clamp(spMin, spMax).toDouble();
              setState(() => _pendingSp = v);
              commitSp(v);
            },
            onIncrease: () {
              final v = (setpoint + 0.5).clamp(spMin, spMax).toDouble();
              setState(() => _pendingSp = v);
              commitSp(v);
            },
          ),
          if (visibleModeOptions.isNotEmpty || fanSpeed != null) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            DeviceCardBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (visibleModeOptions.isNotEmpty)
                    DeviceControlSection(
                      title: 'MODUS',
                      child: DeviceControlBar.gridAuto(
                        context,
                        [
                          for (final o in visibleModeOptions)
                            DeviceControlItem(
                              icon: deviceControlOptionIcon(
                                iconKey: o['icon'] as String?,
                                label: o['label'] as String,
                              ),
                              label: o['label'] as String,
                              labelMode: DeviceControlLabelMode.iconOnly,
                              active: (o['value'] as num).toInt() == activeMode,
                              onTap: () {
                                ref.read(busProvider.notifier).send({
                                  'kind': 'ac.mode',
                                  'deviceId': widget.device.id,
                                  'value': (o['value'] as num).toInt(),
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  if (visibleModeOptions.isNotEmpty && fanSpeed != null)
                    SizedBox(height: DeviceControlBar.sectionSpacing(context)),
                  if (fanSpeed != null)
                    DeviceControlSection(
                      title: 'VENTILATOR',
                      child: DeviceControlBar.gridAuto(
                        context,
                        [
                          for (final o in (fanSpeed['options'] as List)
                              .cast<Map<String, dynamic>>())
                            () {
                              final fanLabel = o['label'] as String;
                              final numeric = deviceControlNumericLabel(fanLabel);
                              return DeviceControlItem(
                                icon: numeric == null
                                    ? deviceControlOptionIcon(label: fanLabel)
                                    : null,
                                label: numeric ?? fanLabel,
                                labelMode: numeric != null
                                    ? DeviceControlLabelMode.numeric
                                    : DeviceControlLabelMode.iconOnly,
                                active: (o['value'] as num).toInt() == activeFan,
                                onTap: () {
                                  ref.read(busProvider.notifier).send({
                                    'kind': 'ac.fanSpeed',
                                    'deviceId': widget.device.id,
                                    'value': (o['value'] as num).toInt(),
                                  });
                                },
                              );
                            }(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Fan                                                                  */
/* --------------------------------------------------------------------- */

class FanTile extends ConsumerWidget {
  const FanTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d   = device;
    final cfg = d.raw['fan'] as Map<String, dynamic>?;
    if (cfg == null) {
      return _Placeholder(name: d.name, hint: 'Fan-config ontbreekt');
    }

    final bus       = ref.watch(busProvider);
    final onOff     = (cfg['onOff'] as Map).cast<String, dynamic>();
    final statusGa  = onOff['statusGa'] as String? ?? onOff['ga'] as String;
    final on        = bus.values[statusGa] == true || bus.values[statusGa] == 1;

    final speedCfg      = cfg['speed'] as Map?;
    final speedMode     = speedCfg?['speedMode'] as String? ??
        ((speedCfg?['steps'] != null) ? 'steps' : 'percent');
    final steps         = (speedCfg?['steps'] as num?)?.toInt() ?? 3;
    final stepLabels    = (speedCfg?['stepLabels'] as List?)
        ?.map((e) => e?.toString() ?? '')
        .toList();
    final speedStatusGa = speedCfg?['statusGa'] as String? ?? speedCfg?['ga'] as String?;
    final busLevel      = speedStatusGa == null
        ? 0.0
        : (bus.values[speedStatusGa] is num
            ? (bus.values[speedStatusGa] as num).toDouble()
            : 0.0);
    final maxSpeed      = speedMode == 'steps' ? steps.toDouble()
                        : speedMode == 'byte'  ? 255.0
                        :                        100.0;
    final level         = busLevel.clamp(0.0, maxSpeed);

    void sendOn(bool v) {
      ref.read(busProvider.notifier).send({
        'kind': 'fan.on',
        'deviceId': d.id,
        'on': v,
      });
    }

    void sendSpeed(double v) {
      ref.read(busProvider.notifier).send({
        'kind': 'fan.speed',
        'deviceId': d.id,
        'value': v.round(),
      });
    }

    return DeviceTileShell(
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: DeviceTileIconBadge(
              icon: Icons.air,
              active: on,
              onTap: () => sendOn(!on),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: DeviceTileLayout.titleStatusGap),
                Text(
                  on ? 'Aan' : 'Uit',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            trailing: DeviceTileLayout.trailingSwitch(
              context: context,
              value: on,
              onChanged: sendOn,
            ),
          ),

          if (speedCfg != null) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            DeviceControlSection(
              title: 'SNELHEID',
              enabled: on,
              child: speedMode == 'steps'
                  ? _FanStepBar(
                      steps: steps,
                      labels: stepLabels,
                      active: level.round(),
                      onSelect: sendSpeed,
                    )
                  : _FanPercentBar(
                      active: level.round(),
                      max: maxSpeed.round(),
                      byteMode: speedMode == 'byte',
                      onSelect: sendSpeed,
                    ),
            ),
          ],

          if (cfg['oscillate'] != null || cfg['direction'] != null) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            DeviceControlSection(
              title: 'OPTIES',
              enabled: on,
              child: Builder(
                builder: (context) {
                  final items = <DeviceControlItem>[];
                  if (cfg['oscillate'] != null) {
                    final ga = (cfg['oscillate'] as Map)['statusGa'] as String? ??
                        (cfg['oscillate'] as Map)['ga'] as String;
                    final v = bus.values[ga];
                    final oscOn = v == true || v == 1;
                    items.add(
                      DeviceControlItem(
                        label: 'Oscilleren',
                        icon: Icons.swap_horiz,
                        labelMode: DeviceControlLabelMode.iconOnly,
                        active: oscOn,
                        onTap: () => ref.read(busProvider.notifier).send({
                          'kind': 'fan.oscillate',
                          'deviceId': d.id,
                          'on': !oscOn,
                        }),
                      ),
                    );
                  }
                  if (cfg['direction'] != null) {
                    final ga = (cfg['direction'] as Map)['statusGa'] as String? ??
                        (cfg['direction'] as Map)['ga'] as String;
                    final v = bus.values[ga];
                    final revOn = v == true || v == 1;
                    items.add(
                      DeviceControlItem(
                        label: 'Omgekeerd',
                        icon: Icons.loop,
                        labelMode: DeviceControlLabelMode.iconOnly,
                        active: revOn,
                        onTap: () => ref.read(busProvider.notifier).send({
                          'kind': 'fan.direction',
                          'deviceId': d.id,
                          'reverse': !revOn,
                        }),
                      ),
                    );
                  }
                  return DeviceControlBar.singleRow(context, items);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fan speed step bar — zelfde witte [DeviceControlBar] als haard/zonwering.
class _FanStepBar extends StatelessWidget {
  const _FanStepBar({
    required this.steps,
    required this.active,
    required this.onSelect,
    this.labels,
  });

  final int steps;
  final int active;
  final ValueChanged<double> onSelect;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final items = <DeviceControlItem>[
      DeviceControlItem(
        icon: Icons.power_off_outlined,
        label: 'Uit',
        labelMode: DeviceControlLabelMode.iconOnly,
        onTap: () => onSelect(0),
      ),
      for (int i = 1; i <= steps; i++)
        () {
          final stepLabel = (labels != null &&
                  i - 1 < labels!.length &&
                  labels![i - 1].isNotEmpty)
              ? labels![i - 1]
              : '$i';
          final numeric = deviceControlNumericLabel(stepLabel) ?? '$i';
          return DeviceControlItem(
            label: numeric,
            labelMode: DeviceControlLabelMode.numeric,
            active: active == i,
            onTap: () => onSelect(i.toDouble()),
          );
        }(),
    ];

    return DeviceControlBar.gridAuto(context, items);
  }
}

/// Percentage / byte snelheid als wit knoppenpaneel (i.p.v. slider).
class _FanPercentBar extends StatelessWidget {
  const _FanPercentBar({
    required this.active,
    required this.max,
    required this.byteMode,
    required this.onSelect,
  });

  final int active;
  final int max;
  final bool byteMode;
  final ValueChanged<double> onSelect;

  static const _percentLevels = [0, 25, 50, 75, 100];
  static const _byteLevels = [0, 64, 128, 192, 255];

  @override
  Widget build(BuildContext context) {
    final levels = byteMode ? _byteLevels : _percentLevels;
    final nearest = levels.reduce(
      (a, b) => (active - a).abs() <= (active - b).abs() ? a : b,
    );
    final items = [
      for (final lvl in levels)
        DeviceControlItem(
          label: byteMode ? '$lvl' : '$lvl%',
          labelMode: DeviceControlLabelMode.numeric,
          active: lvl == nearest,
          onTap: () => onSelect(lvl.toDouble()),
        ),
    ];
    return DeviceControlBar.gridAuto(context, items);
  }
}

class UniversalTile extends ConsumerWidget {
  const UniversalTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = device.raw['universal'] as Map<String, dynamic>?;
    if (cfg == null) {
      return _Placeholder(
          name: device.name, hint: 'Universeel config ontbreekt');
    }
    final allButtons =
        (cfg['buttons'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final iconName = cfg['icon'] as String?;
    final iconData = universalIconData(iconName);
    final headerGlyph = universalIconGlyph(
          iconName,
          size: DeviceCardScale.glyphSize(context),
          color: LuxeColors.ink,
        ) ??
        iconWidgetForData(
          iconData,
          size: DeviceCardScale.glyphSize(context),
          color: LuxeColors.ink,
        );
    final bus = ref.watch(busProvider);

    Future<void> press(Map<String, dynamic> b, {bool? on}) async {
      final id = b['id'] as String;
      final prompt =
          ConfirmPrompt.fromJson(b['confirm']) ?? device.confirm?.actions[id];
      final ok = await maybeConfirm(context, prompt);
      if (!ok) return;
      ref.read(busProvider.notifier).send({
        'kind': 'universal.press',
        'deviceId': device.id,
        'buttonId': id,
        if (on != null) 'on': on,
      });
    }

    // Single button → behave like a switchable lamp: tile-wide header with an
    // on/off switch on the right. The leading badge uses the button's icon
    // (falling back to the device icon).
    if (allButtons.length == 1) {
      final b = allButtons.first;
      final on = _isButtonOn(b, bus);
      final btnIcon = b['icon'] as String?;
      final leadingIcon =
          btnIcon != null ? universalIconData(btnIcon) : iconData;
      final leadingGlyph = universalIconGlyph(
            btnIcon ?? iconName,
            size: DeviceCardScale.glyphSize(context),
            color: on ? LuxeColors.brass : LuxeColors.ink,
          ) ??
          iconWidgetForData(
            leadingIcon,
            size: DeviceCardScale.glyphSize(context),
            color: on ? LuxeColors.brass : LuxeColors.ink,
          );
      return DeviceTileShell(
        glow: on,
        child: DeviceTileLayout.headerRow(
          context: context,
          leading: DeviceTileIconBadge(
            icon: leadingGlyph == null ? leadingIcon : null,
            glyph: leadingGlyph,
            active: on,
            onTap: () => press(b, on: !on),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(device.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: DeviceTileLayout.titleStatusGap),
              Text(on ? 'AAN' : 'UIT',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          trailing: DeviceTileLayout.trailingSwitch(
            context: context,
            value: on,
            onChanged: (want) => press(b, on: want),
          ),
        ),
      );
    }

    // Multiple buttons → grid of buttons. A button shows its icon (and hides
    // the label when it is left empty, so an icon can replace the text).
    final buttonItems = [
      for (final b in allButtons)
        DeviceControlItem(
          label: b['label'] as String? ?? '',
          icon: b['icon'] != null
              ? universalIconData(b['icon'] as String)
              : deviceControlOptionIcon(label: b['label'] as String?),
          labelMode: DeviceControlLabelMode.iconOnly,
          active: _isButtonOn(b, bus),
          onTap: () => press(b),
        ),
    ];

    return DeviceTileShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: DeviceTileIconBadge(
              icon: headerGlyph == null ? iconData : null,
              glyph: headerGlyph,
            ),
            content: Text(device.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (buttonItems.isNotEmpty) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            DeviceControlBar.gridAuto(context, buttonItems),
          ] else
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Geen knoppen geconfigureerd.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: LuxeColors.inkSoft),
              ),
            ),
        ],
      ),
    );
  }

  bool _isButtonOn(Map<String, dynamic> b, BusState bus) {
    final ga = b['statusGa'] as String?;
    if (ga == null) return false;
    final v = bus.values[ga];
    if (v == null) return false;
    final expected = b['statusOnValue'];
    if (expected == null) return v == true || v == 1;
    if (expected is bool) return v == expected || v == (expected ? 1 : 0);
    return v == expected;
  }
}

class _UniversalButton extends StatelessWidget {
  const _UniversalButton({
    required this.label,
    required this.onTap,
    required this.active,
    this.icon,
    this.style,
  });
  final String label;
  final String? icon;
  final String? style;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(style);
    final bg = active ? palette.activeBg : palette.bg;
    final fg = active ? palette.activeFg : palette.fg;
    final iconData = _iconOf(icon);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
          boxShadow: active ? LuxeShadows.brassGlow : LuxeShadows.soft,
        ),
        child: Row(
          children: [
            if (iconData != null) ...[
              Icon(iconData, size: DeviceControlIcons.size, color: fg),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData? _iconOf(String? name) => switch (name) {
        'power' => Icons.power_settings_new,
        'travel' => Icons.luggage_outlined,
        'volume' => Icons.volume_up_outlined,
        'bell' => Icons.notifications_active_outlined,
        'home' => Icons.home_outlined,
        'door' => Icons.door_front_door_outlined,
        'star' => Icons.star_outline,
        'flame' => Icons.local_fire_department_outlined,
        'fan' => Icons.air,
        'snow' => Icons.ac_unit,
        'lamp' => Icons.lightbulb_outline,
        null => null,
        _ => Icons.bolt_rounded,
      };

  static _BtnPalette _palette(String? style) => switch (style) {
        'primary' => _BtnPalette(
            bg: LuxeColors.ink,
            fg: Colors.white,
            activeBg: LuxeColors.ink,
            activeFg: LuxeColors.brassGlow,
            border: LuxeColors.ink,
          ),
        'brass' => _BtnPalette(
            bg: LuxeColors.surface,
            fg: LuxeColors.brassDeep,
            activeBg: LuxeColors.brass,
            activeFg: Colors.white,
            border: LuxeColors.brass,
          ),
        'danger' => _BtnPalette(
            bg: LuxeColors.surface,
            fg: LuxeColors.danger,
            activeBg: LuxeColors.danger,
            activeFg: Colors.white,
            border: LuxeColors.danger,
          ),
        _ => _BtnPalette(
            bg: LuxeColors.surface,
            fg: LuxeColors.ink,
            activeBg: LuxeColors.ink,
            activeFg: Colors.white,
            border: LuxeColors.line,
          ),
      };
}

class _BtnPalette {
  const _BtnPalette({
    required this.bg,
    required this.fg,
    required this.activeBg,
    required this.activeFg,
    required this.border,
  });
  final Color bg;
  final Color fg;
  final Color activeBg;
  final Color activeFg;
  final Color border;
}

/* --------------------------------------------------------------------- */
/*  Shared bits used by the new tiles                                    */
/* --------------------------------------------------------------------- */

class _StepBar extends StatelessWidget {
  const _StepBar({
    required this.steps,
    required this.value,
    required this.onChanged,
    this.allowZero = false,
    this.labels,
  });
  final int steps;
  final int value;
  final ValueChanged<int> onChanged;

  /// When true we include a "0" stop at the start – fans need an explicit off.
  final bool allowZero;

  /// Optional label per step (length must match [steps] when [allowZero] is false).
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final start = allowZero ? 0 : 1;
    final lbl = labels;
    final effectiveLabels =
        lbl != null && lbl.length == steps ? lbl : null;
    return Row(
      children: [
        for (int i = start; i <= steps; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 160),
                height: 48,
                decoration: BoxDecoration(
                  color: i == value ? LuxeColors.ink : LuxeColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: i == value ? LuxeColors.ink : LuxeColors.line,
                  ),
                ),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  (effectiveLabels != null &&
                          !allowZero &&
                          i >= 1 &&
                          i <= effectiveLabels.length)
                      ? effectiveLabels[i - 1]
                      : '$i',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize:
                        effectiveLabels != null &&
                                !allowZero &&
                                i >= 1 &&
                                i <= effectiveLabels.length
                            ? 10.5
                            : 14,
                    color:
                        i == value ? LuxeColors.brassGlow : LuxeColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (i < steps) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WTW / HRV ventilatie tile
// ─────────────────────────────────────────────────────────────────────────────

class WtwTile extends ConsumerWidget {
  const WtwTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = device.raw['wtw'] as Map<String, dynamic>?;
    if (cfg == null) {
      return _Placeholder(name: device.name, hint: 'WTW config ontbreekt');
    }
    final buttons =
        (cfg['buttons'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final statusItems =
        (cfg['status'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final bus = ref.watch(busProvider);

    final buttonItems = [
      for (final b in buttons)
        () {
          final lbl = b['label'] as String? ?? '';
          final numeric = deviceControlNumericLabel(lbl);
          return DeviceControlItem(
            icon: numeric == null ? deviceControlOptionIcon(label: lbl) : null,
            label: numeric ?? lbl,
            labelMode: numeric != null
                ? DeviceControlLabelMode.numeric
                : DeviceControlLabelMode.iconOnly,
            active: _wtwButtonActive(b, bus),
            onTap: () {
              ref.read(busProvider.notifier).send({
                'kind': 'wtw.press',
                'deviceId': device.id,
                'buttonId': b['id'],
              });
            },
          );
        }(),
    ];

    return DeviceTileShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: DeviceTileIconBadge(icon: Icons.air_outlined),
            content: Text(device.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),

          if (buttonItems.isNotEmpty) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            DeviceControlSection(
              title: 'STAND',
              child: DeviceControlBar.gridAuto(context, buttonItems),
            ),
          ],

          if (statusItems.isNotEmpty) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...statusItems.map((s) => _WtwStatusRow(item: s, bus: bus)),
          ],
        ],
      ),
    );
  }

  static bool _wtwButtonActive(Map<String, dynamic> b, BusState bus) {
    final statusGa = b['statusGa'] as String?;
    if (statusGa == null) return false;
    final current = bus.values[statusGa];
    if (current == null) return false;
    final onValue = b['statusOnValue'] ?? b['value'];
    final n = num.tryParse(current.toString());
    final onN = num.tryParse(onValue.toString());
    return n != null && onN != null
        ? n == onN
        : current.toString() == onValue.toString();
  }
}

class _WtwStatusRow extends StatelessWidget {
  const _WtwStatusRow({required this.item, required this.bus});
  final Map<String, dynamic> item;
  final BusState bus;

  @override
  Widget build(BuildContext context) {
    final label = item['label'] as String? ?? '';
    final ga = item['ga'] as String? ?? '';
    final dpt = item['dpt'] as String? ?? '1.001';
    final unit = item['unit'] as String? ?? '';
    final iconKey = item['icon'] as String?;
    final icon0Key = item['icon0'] as String?;
    final icon1Key = item['icon1'] as String?;
    final rawValue = bus.values[ga];

    final (display, isAlert) = _formatWtwStatus(dpt, rawValue, unit);

    // Resolve value icon for bit types when icon0/icon1 are configured.
    final isBit = dpt.startsWith('1.');
    final bitActive = isBit &&
        (rawValue == true || rawValue == 1 || rawValue?.toString() == '1');
    final valueIconKey =
        isBit && (icon0Key != null || icon1Key != null)
            ? (bitActive ? icon1Key : icon0Key)
            : null;
    final useIconBadge = valueIconKey != null && rawValue != null;

    // Leading: icon from `icon` field OR animated dot.
    final leadingIconData = iconKey != null
        ? (kUniversalIconMap[iconKey] ?? Icons.circle_outlined)
        : null;

    final dotColor = isAlert ? LuxeColors.danger : LuxeColors.brass;

    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Leading indicator: icon or dot
          if (leadingIconData != null)
            Icon(leadingIconData, size: 16, color: dotColor)
          else
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isAlert ? LuxeColors.danger : LuxeColors.inkSoft,
                    fontWeight: isAlert ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ),
          // Value badge: icon or text
          if (useIconBadge)
            _WtwIconBadge(
              iconKey: valueIconKey!,
              isAlert: isAlert,
            )
          else
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isAlert
                    ? LuxeColors.danger.withValues(alpha: 0.10)
                    : LuxeColors.surfaceDim.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isAlert
                      ? LuxeColors.danger.withValues(alpha: 0.30)
                      : LuxeColors.line,
                ),
              ),
              child: Text(
                rawValue == null ? '—' : display,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isAlert ? LuxeColors.danger : LuxeColors.inkSoft,
                  letterSpacing: 0.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Returns (displayString, isAlert).
  static (String, bool) _formatWtwStatus(
      String dpt, dynamic raw, String unit) {
    if (raw == null) return ('—', false);
    final suffix = unit.isNotEmpty ? ' $unit' : '';
    // All 1-bit DPTs: active/inactive
    if (dpt.startsWith('1.')) {
      final active = raw == true || raw == 1 || raw.toString() == '1';
      return (active ? 'Actief' : 'OK', active);
    }
    switch (dpt) {
      case '5.001':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw}%$suffix', false);
      case '5.010':
      case '7.001':
      case '12.001':
        final n = num.tryParse(raw.toString());
        return ('${n?.toInt() ?? raw}$suffix', false);
      case '6.001':
      case '8.001':
      case '13.001':
        final n = num.tryParse(raw.toString());
        return ('${n?.toInt() ?? raw}$suffix', false);
      case '9.001':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(1) ?? raw} °C$suffix', false);
      case '9.002':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(1) ?? raw} K$suffix', false);
      case '9.004':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw} lux$suffix', false);
      case '9.005':
      case '14.068':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(1) ?? raw} m/s$suffix', false);
      case '9.006':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw} Pa$suffix', false);
      case '9.007':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw} %RH$suffix', false);
      case '9.008':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw} ppm$suffix', false);
      case '9.009':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw} m³/h$suffix', false);
      case '9.020':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw} mV$suffix', false);
      case '9.021':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(0) ?? raw} mA$suffix', false);
      case '14.019':
        final n = num.tryParse(raw.toString());
        return ('${n?.toStringAsFixed(1) ?? raw} W$suffix', false);
      case 'hex':
        final n = int.tryParse(raw.toString());
        final hexStr = n != null
            ? '0x${n.toRadixString(16).padLeft(2, '0').toUpperCase()}'
            : raw.toString();
        return ('$hexStr$suffix', false);
      default:
        return ('$raw$suffix', false);
    }
  }
}

/// Small icon pill badge used in WTW status rows when icon0/icon1 are configured.
class _WtwIconBadge extends StatelessWidget {
  const _WtwIconBadge({required this.iconKey, required this.isAlert});
  final String iconKey;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    final iconData = kUniversalIconMap[iconKey] ?? Icons.circle;
    final color = isAlert ? LuxeColors.danger : LuxeColors.brass;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(iconData, size: 16, color: color),
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Meldingen tile – KNX alarm/notification monitor
   ══════════════════════════════════════════════════════════════════════════ */

class MeldingTile extends ConsumerWidget {
  const MeldingTile({super.key, required this.device});
  final Device device;

  static Color _urgencyColor(String urgency) => switch (urgency) {
        'urgent' => const Color(0xFFD32F2F),
        'belangrijk' => const Color(0xFFD97706),
        _ => const Color(0xFFC08500),
      };

  static Color _urgencyBg(String urgency) => switch (urgency) {
        'urgent' => const Color(0xFFFFEBEE),
        'belangrijk' => const Color(0xFFFFF3E0),
        _ => const Color(0xFFFFFDE7),
      };

  static String _urgencyLabel(String urgency) => switch (urgency) {
        'urgent' => 'URGENT',
        'belangrijk' => 'BELANGRIJK',
        _ => 'INFO',
      };

  static IconData _urgencyIcon(String urgency) => switch (urgency) {
        'urgent' => Icons.error_rounded,
        'belangrijk' => Icons.warning_rounded,
        _ => Icons.info_outline_rounded,
      };

  /// Returns true if the KNX bus value means the alert is active.
  static bool isItemActive(
    Map<String, dynamic> item,
    dynamic busVal,
  ) =>
      _isActive(
        item['dpt'] as String? ?? '1.001',
        busVal,
        item,
      );

  static List<Map<String, dynamic>> configuredItems(Device device) {
    final cfg = device.raw['melding'] as Map<String, dynamic>? ?? {};
    return (cfg['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  static int activeItemCount(Device device, Map<String, dynamic> busValues) {
    var n = 0;
    for (final item in configuredItems(device)) {
      final ga = item['ga'] as String? ?? '';
      if (isItemActive(item, busValues[ga])) n++;
    }
    return n;
  }

  /// Returns true if the KNX bus value means the alert is active.
  static bool _isActive(String dpt, dynamic busVal, Map<String, dynamic> item) {
    if (busVal == null) return false;
    final activeVal = item['activeValue'];
    if (dpt.startsWith('1.')) {
      // 1-bit: active when true/1
      final target = activeVal ?? 1;
      if (busVal is bool) return busVal == (target == 1 || target == true);
      final n = num.tryParse(busVal.toString());
      return n != null && n == (activeVal != null ? num.tryParse(activeVal.toString()) : 1);
    }
    if (activeVal != null) {
      final n = num.tryParse(busVal.toString());
      final t = num.tryParse(activeVal.toString());
      return n != null && t != null && n == t;
    }
    // Default: active when value != 0
    final n = num.tryParse(busVal.toString());
    return n != null && n != 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bus = ref.watch(busProvider);
    final cfg = device.raw['melding'] as Map<String, dynamic>? ?? {};
    final rawItems = (cfg['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final urgent = <Map<String, dynamic>>[];
    final belangrijk = <Map<String, dynamic>>[];
    final minderBelangrijk = <Map<String, dynamic>>[];

    for (final item in rawItems) {
      final ga = item['ga'] as String? ?? '';
      final dpt = item['dpt'] as String? ?? '1.001';
      final urgency = item['urgency'] as String? ?? 'minder_belangrijk';
      final busVal = bus.values[ga];
      if (_isActive(dpt, busVal, item)) {
        switch (urgency) {
          case 'urgent':
            urgent.add(item);
          case 'belangrijk':
            belangrijk.add(item);
          default:
            minderBelangrijk.add(item);
        }
      }
    }

    final anyUrgent = urgent.isNotEmpty;
    final anyBelangrijk = belangrijk.isNotEmpty;
    final anyMinder = minderBelangrijk.isNotEmpty;
    final anyActive = anyUrgent || anyBelangrijk || anyMinder;

    // Worst urgency drives the header accent.
    final worstUrgency = anyUrgent
        ? 'urgent'
        : anyBelangrijk
            ? 'belangrijk'
            : anyMinder
                ? 'minder_belangrijk'
                : null;

    final accentColor =
        worstUrgency != null ? _urgencyColor(worstUrgency) : LuxeColors.brass;

    // All active alerts in order of severity.
    final activeAll = [...urgent, ...belangrijk, ...minderBelangrijk];

    return DeviceTileShell(
      glow: anyUrgent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceTileLayout.headerRow(
            context: context,
            leading: _MeldingIconBadge(
              urgency: worstUrgency,
              accentColor: accentColor,
            ),
            content: Text(
              device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            trailing: DeviceTileLayout.statusIconSlot(
              context,
              child: Align(
                alignment: Alignment.centerRight,
                child: anyActive
                    ? _MeldingActiveButton(
                        urgency: worstUrgency!,
                        count: activeAll.length,
                      )
                    : _MeldingOkButton(),
              ),
            ),
          ),
          if (rawItems.isEmpty) ...[
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            Text(
              'Geen meldingen geconfigureerd.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LuxeColors.inkSoft,
                  ),
            ),
          ] else ...[
            if (anyActive) ...[
              SizedBox(height: DeviceControlBar.sectionSpacing(context)),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (anyUrgent)
                    _MeldingChip(urgency: 'urgent', count: urgent.length),
                  if (anyBelangrijk)
                    _MeldingChip(
                        urgency: 'belangrijk', count: belangrijk.length),
                  if (anyMinder)
                    _MeldingChip(
                        urgency: 'minder_belangrijk',
                        count: minderBelangrijk.length),
                ],
              ),
            ],
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            for (final item in rawItems)
              _MeldingAlertRow(
                item: item,
                active: isItemActive(
                  item,
                  bus.values[item['ga'] as String? ?? ''],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Vierkant meldingen-icoon — zelfde maat als andere apparaatbadges.
class _MeldingIconBadge extends StatelessWidget {
  const _MeldingIconBadge({
    required this.urgency,
    required this.accentColor,
  });

  final String? urgency;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final size = DeviceCardScale.iconBadgeSize(context);
    final outerR = DeviceCardScale.iconRadius(context);
    const rim = 1.5;
    final innerR = (outerR - rim).clamp(0.0, outerR);
    final glyph = DeviceCardScale.glyphSize(context);
    final active = urgency != null;
    final rimColor = active ? accentColor : LuxeColors.line;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = active
        ? accentColor.withValues(alpha: 0.14)
        : LuxeColors.surfaceDim.withValues(alpha: isDark ? 0.7 : 0.45);

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerR),
          color: rimColor,
        ),
        child: Padding(
          padding: const EdgeInsets.all(rim),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(innerR),
              color: fillColor,
            ),
            child: Center(
              child: Icon(
                urgency != null
                    ? MeldingTile._urgencyIcon(urgency!)
                    : Icons.notifications_outlined,
                size: glyph,
                color: active ? accentColor : LuxeColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Groene OK-indicator — zelfde 56×56 als aan/uit-knop.
class _MeldingOkButton extends StatelessWidget {
  const _MeldingOkButton();

  static const _ok = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final size = DeviceControlBar.buttonSizeFor(context);
    final glyph = DeviceControlBar.glyphSizeFor(context);

    return SizedBox(
      width: size,
      height: size,
      child: DeviceControlButtonSurface(
        width: size,
        height: size,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_rounded, size: glyph, color: _ok),
            const SizedBox(height: 2),
            Text(
              'OK',
              style: TextStyle(
                fontSize: glyph * 0.45,
                fontWeight: FontWeight.w700,
                color: _ok,
                height: 1,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Actieve meldingen — zelfde 56×56 als aan/uit-knop.
class _MeldingActiveButton extends StatelessWidget {
  const _MeldingActiveButton({
    required this.urgency,
    required this.count,
  });

  final String urgency;
  final int count;

  @override
  Widget build(BuildContext context) {
    final size = DeviceControlBar.buttonSizeFor(context);
    final glyph = DeviceControlBar.glyphSizeFor(context);
    final color = MeldingTile._urgencyColor(urgency);

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DeviceControlBar.buttonRadius),
          boxShadow: DeviceControlBar.buttonShadows(active: true),
        ),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DeviceControlBar.buttonRadius),
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(MeldingTile._urgencyIcon(urgency), size: glyph, color: color),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: glyph * 0.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeldingChip extends StatelessWidget {
  const _MeldingChip({required this.urgency, required this.count});
  final String urgency;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = MeldingTile._urgencyColor(urgency);
    final bg = MeldingTile._urgencyBg(urgency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(MeldingTile._urgencyIcon(urgency), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$count × ${MeldingTile._urgencyLabel(urgency)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeldingAlertRow extends StatelessWidget {
  const _MeldingAlertRow({required this.item, this.active = true});
  final Map<String, dynamic> item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final urgency = item['urgency'] as String? ?? 'minder_belangrijk';
    final activeColor = MeldingTile._urgencyColor(urgency);
    final inactiveInk = LuxeColors.ink.withValues(alpha: 0.72);
    final iconKey = item['icon'] as String?;
    final label = active
        ? (item['activeLabel'] as String? ??
            item['label'] as String? ??
            'Melding')
        : (item['label'] as String? ?? 'Melding');
    final iconData =
        (iconKey != null ? kUniversalIconMap[iconKey] : null) ??
            MeldingTile._urgencyIcon(urgency);
    final btn = DeviceControlBar.buttonSizeFor(context);
    final glyph = DeviceControlBar.glyphSizeFor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: DeviceControlBar.gap),
      child: SizedBox(
        height: btn,
        width: double.infinity,
        child: active
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(DeviceControlBar.buttonRadius),
                  boxShadow: DeviceControlBar.buttonShadows(active: true),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(DeviceControlBar.buttonRadius),
                    color: MeldingTile._urgencyBg(urgency),
                    border: Border.all(
                      color: activeColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(iconData, size: glyph, color: activeColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 14,
                                color: activeColor,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        MeldingTile._urgencyLabel(urgency),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: activeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : DeviceControlButtonSurface(
                width: double.infinity,
                height: btn,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(iconData, size: glyph, color: inactiveInk),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 14,
                              color: inactiveInk,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
