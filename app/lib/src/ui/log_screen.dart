import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../log_api.dart';
import '../theme.dart';
import 'responsive.dart';
import 'widgets/luxe_backdrop.dart';

/// Time-series graph for a single log (thermostat or custom). Users can pick a
/// time range (zoom) and pan earlier/later; data is fetched + downsampled
/// server-side.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key, required this.logId, this.title, this.mode});

  final String logId;
  final String? title;

  /// For thermostat logs: 'heat' or 'cool' — colours the setpoint line.
  final String? mode;

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _RangePreset {
  final String label;
  final int ms;
  const _RangePreset(this.label, this.ms);
}

const int _hour = 3600 * 1000;
const int _day = 24 * _hour;

const List<_RangePreset> _presets = [
  _RangePreset('1u', _hour),
  _RangePreset('6u', 6 * _hour),
  _RangePreset('24u', _day),
  _RangePreset('7d', 7 * _day),
  _RangePreset('30d', 30 * _day),
  _RangePreset('90d', 90 * _day),
];

/// Distinct, on-brand series colours for generic (custom) logs.
const List<Color> _seriesColors = [
  LuxeColors.brass,
  Color(0xFF4F86C6),
  Color(0xFF5BA98C),
  Color(0xFFB06CC0),
  Color(0xFFD08A3E),
];

/// Thermostat line colours.
///   measured = warm espresso brown (continuous sensor signal)
///   setpoint = fixed brass/gold (the target, drawn as a step line)
/// The active heating/cooling state over time is shown in a separate colour
/// band at the bottom (heat = orange, cool = blue).
const Color _measuredColor = Color(0xFF2D241B);
const Color _setpointColor = LuxeColors.brass;
const Color _heatColor = Color(0xFFE07A3F);
const Color _coolColor = Color(0xFF5BA7E0);

/// Resolve the line colour for a plotted series.
Color _seriesColor(LogSeriesData s, int index) {
  switch (s.role) {
    case 'measured':
      return _measuredColor;
    case 'setpoint':
      return _setpointColor;
  }
  return _seriesColors[index % _seriesColors.length];
}

/// True for "hold until change" series (the setpoint). These are drawn as a
/// step line that keeps its value until the next recorded change, because the
/// setpoint isn't transmitted cyclically.
bool _isHoldSeries(LogSeriesData s) => s.role == 'setpoint';

class _LogScreenState extends ConsumerState<LogScreen> {
  int _rangeMs = _day;
  late int _endMs;

  @override
  void initState() {
    super.initState();
    _endMs = DateTime.now().millisecondsSinceEpoch;
  }

  LogQuery get _query => (
        id: widget.logId,
        fromMs: _endMs - _rangeMs,
        toMs: _endMs,
        maxPoints: 400,
      );

  void _setRange(int ms) {
    setState(() {
      _rangeMs = ms;
      // Keep the right edge anchored to "now" when changing zoom.
      _endMs = DateTime.now().millisecondsSinceEpoch;
    });
  }

  void _pan(int deltaMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _endMs = (_endMs + deltaMs).clamp(_rangeMs, now);
    });
  }

  void _jumpToNow() {
    setState(() => _endMs = DateTime.now().millisecondsSinceEpoch);
  }

  void _refresh() {
    _jumpToNow();
    ref.invalidate(logHistoryProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(logHistoryProvider(_query));
    final now = DateTime.now().millisecondsSinceEpoch;
    final atNow = _endMs >= now - 1000;

    final title = async.maybeWhen(
      data: (d) => d.name,
      orElse: () => widget.title ?? 'Log',
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: LuxeColors.ink,
        title: Text(
          title,
          style: const TextStyle(
            color: LuxeColors.ink,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: LuxeBackdrop(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              context.hPad,
              kToolbarHeight + 8,
              context.hPad,
              16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RangeBar(
                  selectedMs: _rangeMs,
                  onSelect: _setRange,
                ),
                const SizedBox(height: 12),
                _PanBar(
                  rangeMs: _rangeMs,
                  atNow: atNow,
                  onEarlier: () => _pan(-_rangeMs ~/ 2),
                  onLater: () => _pan(_rangeMs ~/ 2),
                  onNow: _jumpToNow,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child:
                          CircularProgressIndicator(color: LuxeColors.brass),
                    ),
                    error: (e, _) => Center(
                      child: Text(
                        'Kan log niet laden:\n$e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: LuxeColors.inkSoft),
                      ),
                    ),
                    data: (d) => _LogChartCard(
                      data: d,
                      rangeMs: _rangeMs,
                      mode: widget.mode,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.selectedMs, required this.onSelect});
  final int selectedMs;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in _presets) ...[
            _RangeChip(
              label: p.label,
              selected: p.ms == selectedMs,
              onTap: () => onSelect(p.ms),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? LuxeColors.brass.withValues(alpha: 0.16)
              : LuxeColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? LuxeColors.brass.withValues(alpha: 0.55)
                : LuxeColors.line,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? LuxeColors.brassDeep : LuxeColors.inkSoft,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _PanBar extends StatelessWidget {
  const _PanBar({
    required this.rangeMs,
    required this.atNow,
    required this.onEarlier,
    required this.onLater,
    required this.onNow,
  });
  final int rangeMs;
  final bool atNow;
  final VoidCallback onEarlier;
  final VoidCallback onLater;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PanButton(
          icon: Icons.chevron_left_rounded,
          label: 'Eerder',
          onTap: onEarlier,
        ),
        const Spacer(),
        GestureDetector(
          onTap: atNow ? null : onNow,
          child: Opacity(
            opacity: atNow ? 0.4 : 1,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded,
                    size: 16, color: LuxeColors.inkSoft),
                SizedBox(width: 5),
                Text(
                  'Nu',
                  style: TextStyle(
                    color: LuxeColors.inkSoft,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        _PanButton(
          icon: Icons.chevron_right_rounded,
          label: 'Later',
          trailingIcon: true,
          onTap: atNow ? null : onLater,
        ),
      ],
    );
  }
}

class _PanButton extends StatelessWidget {
  const _PanButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingIcon = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool trailingIcon;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final content = <Widget>[
      Icon(icon, size: 20, color: LuxeColors.inkSoft),
      const SizedBox(width: 2),
      Text(
        label,
        style: const TextStyle(
          color: LuxeColors.inkSoft,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
    ];
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.35 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: trailingIcon ? content.reversed.toList() : content,
          ),
        ),
      ),
    );
  }
}

class _LogChartCard extends StatelessWidget {
  const _LogChartCard({
    required this.data,
    required this.rangeMs,
    this.mode,
  });
  final LogData data;
  final int rangeMs;
  final String? mode;

  bool get _hasPoints => data.series.any((s) => s.points.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final hasBand = data.kind == 'thermostat' &&
        (mode != null ||
            data.series.any((s) => s.role == 'mode' && s.points.isNotEmpty));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 20, 18, 14),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LuxeColors.line),
      ),
      child: !_hasPoints
          ? const Center(
              child: Text(
                'Nog geen gegevens gelogd voor dit tijdsbereik.',
                textAlign: TextAlign.center,
                style: TextStyle(color: LuxeColors.inkSoft),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Chart(
                    data: data,
                    rangeMs: rangeMs,
                    mode: mode,
                    hasBand: hasBand,
                  ),
                ),
                const SizedBox(height: 12),
                _Legend(data: data, hasBand: hasBand),
              ],
            ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.data,
    required this.rangeMs,
    this.mode,
    this.hasBand = false,
  });
  final LogData data;
  final int rangeMs;
  final String? mode;
  final bool hasBand;

  @override
  Widget build(BuildContext context) {
    // Pick a clock-aligned time step (e.g. 15 min) and snap the axis to it so
    // ticks land on round times. Fewer labels on narrow screens.
    final chartWidth = MediaQuery.of(context).size.width;
    final labelCount = (chartWidth / 95).floor().clamp(3, 5);
    final xStep = _niceTimeStep(data.toMs - data.fromMs, labelCount);
    final minX = _floorToStep(data.fromMs.toDouble(), xStep);
    final maxX = _ceilToStep(data.toMs.toDouble(), xStep);
    final xInterval = xStep.toDouble();

    // Plotted lines exclude the mode series (drawn as a colour band instead).
    final plotted = data.series
        .where((s) => s.role != 'mode' && s.points.isNotEmpty)
        .toList();
    final modeSeries =
        data.series.where((s) => s.role == 'mode').toList();
    final modePts =
        modeSeries.isNotEmpty ? modeSeries.first.points : const <LogPoint>[];

    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final s in plotted) {
      for (final p in s.points) {
        if (p.value < lo) lo = p.value;
        if (p.value > hi) hi = p.value;
      }
    }
    if (lo == double.infinity) {
      lo = 0;
      hi = 1;
    }
    // Snap the temperature axis to whole/half-degree steps so ticks read 20.0,
    // 20.5, 21.0 …
    final yStep = _niceTempStep(hi - lo);
    lo = (lo / yStep).floorToDouble() * yStep;
    hi = (hi / yStep).ceilToDouble() * yStep;
    if (hi - lo < yStep * 0.5) hi = lo + yStep;
    // Reserve a lane below the data for the heat/cool colour band and pin the
    // band flush to the very bottom edge. Its lower half is clipped away so no
    // background shows beneath it.
    final dataFloor = lo;
    final bandSpan = (hi - lo) * 0.12;
    final double minY = hasBand ? lo - bandSpan : lo;
    final bandY = minY;
    final double maxY = hi;

    final bars = <LineChartBarData>[];
    // Index → series mapping for tooltips (band bars have no tooltip).
    final plottedBars = <LogSeriesData>[];
    for (final s in plotted) {
      final color = _seriesColor(s, plottedBars.length);
      final hold = _isHoldSeries(s);
      final spots = <FlSpot>[
        for (final p in s.points) FlSpot(p.ts.toDouble(), p.value),
      ];
      // Setpoint isn't sent cyclically: hold the last value flat out to the
      // right edge so the line reflects the active setting up to "now".
      if (hold && spots.isNotEmpty && spots.last.x < maxX) {
        spots.add(FlSpot(maxX, spots.last.y));
      }
      plottedBars.add(s);
      bars.add(
        LineChartBarData(
          spots: spots,
          // Hold-until-change series are stepped; continuous signals curved.
          isCurved: !hold,
          curveSmoothness: 0.18,
          isStepLineChart: hold,
          lineChartStepData: const LineChartStepData(
            stepDirection: LineChartStepData.stepDirectionForward,
          ),
          color: color,
          barWidth: 2.4,
          isStrokeCapRound: !hold,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: 0.08),
          ),
        ),
      );
    }

    // Heat/cool colour band along the bottom, segmented by time.
    final int dataBarCount = bars.length;
    if (hasBand) {
      final segments = _modeSegments(modePts, minX, maxX, mode);
      for (final seg in segments) {
        bars.add(
          LineChartBarData(
            spots: [FlSpot(seg.x1, bandY), FlSpot(seg.x2, bandY)],
            isCurved: false,
            color: seg.heat ? _heatColor : _coolColor,
            barWidth: 12,
            isStrokeCapRound: false,
            dotData: const FlDotData(show: false),
          ),
        );
      }
    }

    final yInterval = yStep;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineBarsData: bars,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yInterval <= 0 ? null : yInterval,
          verticalInterval: xInterval <= 0 ? null : xInterval,
          checkToShowHorizontalLine: (v) => v >= dataFloor - 0.0001,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: LuxeColors.line, strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: LuxeColors.lineSoft, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: yInterval <= 0 ? null : yInterval,
              getTitlesWidget: (value, meta) {
                if (value <= meta.min || value >= meta.max) {
                  return const SizedBox.shrink();
                }
                // Hide ticks that fall inside the band lane.
                if (value < dataFloor - 0.0001) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.toStringAsFixed(1),
                    style: const TextStyle(
                      color: LuxeColors.inkFaint,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: xInterval <= 0 ? null : xInterval,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _fmtAxis(value.toInt(), rangeMs),
                    style: const TextStyle(
                      color: LuxeColors.inkFaint,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final i = spot.barIndex;
                // Band segments (barIndex >= dataBarCount) carry no tooltip.
                if (i < 0 || i >= dataBarCount) return null;
                final unit = plottedBars[i].unit ?? '';
                final timeStr =
                    _fmtTooltip(spot.x.toInt(), rangeMs <= 2 * _day);
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}$unit\n',
                  TextStyle(
                    color: spot.bar.color ?? LuxeColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: timeStr,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.data, this.hasBand = false});
  final LogData data;
  final bool hasBand;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < data.series.length; i++) {
      final s = data.series[i];
      if (s.role == 'mode') continue;
      items.add(_LegendItem(color: _seriesColor(s, i), series: s));
    }
    if (hasBand) {
      items.add(const _BandLegendItem(color: _heatColor, label: 'Verwarmen'));
      items.add(const _BandLegendItem(color: _coolColor, label: 'Koelen'));
    }
    return Wrap(spacing: 18, runSpacing: 8, children: items);
  }
}

/// Legend entry for the heat/cool band (a small filled swatch, no value).
class _BandLegendItem extends StatelessWidget {
  const _BandLegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: LuxeColors.inkSoft,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.series});
  final Color color;
  final LogSeriesData series;

  @override
  Widget build(BuildContext context) {
    final last = series.points.isNotEmpty ? series.points.last.value : null;
    final unit = series.unit ?? '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          series.label,
          style: const TextStyle(
            color: LuxeColors.ink,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        if (last != null) ...[
          const SizedBox(width: 6),
          Text(
            '${last.toStringAsFixed(1)}$unit',
            style: const TextStyle(
              color: LuxeColors.inkSoft,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

/// Build heat/cool band segments from the mode series (1 = verwarmen,
/// 0 = koelen). Each segment holds its value until the next change. Falls
/// back to a single full-width segment from the [mode] hint when no history
/// has been logged yet.
List<({double x1, double x2, bool heat})> _modeSegments(
  List<LogPoint> pts,
  double minX,
  double maxX,
  String? mode,
) {
  final segs = <({double x1, double x2, bool heat})>[];
  if (pts.isNotEmpty) {
    // Fill the gap before the first logged sample by holding its value back to
    // the left edge, so the band always spans the full width and the part that
    // was already drawn stays visible after a heat/cool switch.
    final firstX = pts.first.ts.toDouble().clamp(minX, maxX);
    if (firstX > minX) {
      segs.add((x1: minX, x2: firstX, heat: pts.first.value >= 0.5));
    }
    for (var i = 0; i < pts.length; i++) {
      final x1 = pts[i].ts.toDouble().clamp(minX, maxX);
      final x2 = (i + 1 < pts.length ? pts[i + 1].ts.toDouble() : maxX)
          .clamp(minX, maxX);
      if (x2 <= x1) continue;
      segs.add((x1: x1, x2: x2, heat: pts[i].value >= 0.5));
    }
  } else if (mode != null) {
    segs.add((x1: minX, x2: maxX, heat: mode != 'cool'));
  }
  return segs;
}

/// Pick a "nice" temperature grid step (0.5°, 1°, 2°, …) so the axis reads in
/// whole and half degrees while keeping the number of ticks sensible.
double _niceTempStep(double range) {
  const steps = [0.5, 1.0, 2.0, 5.0, 10.0];
  for (final s in steps) {
    if (range / s <= 5) return s;
  }
  return 10.0;
}

/// Pick a clock-friendly time step (15 min, 30 min, 1 h, …) targeting roughly
/// [target] labels across the window.
int _niceTimeStep(int rangeMs, int target) {
  const min = 60 * 1000;
  const hour = 60 * min;
  const day = 24 * hour;
  const steps = <int>[
    15 * min, 30 * min, hour, 2 * hour, 3 * hour, 6 * hour, 12 * hour,
    day, 2 * day, 7 * day, 14 * day, 30 * day,
  ];
  for (final s in steps) {
    if (rangeMs / s <= target) return s;
  }
  return steps.last;
}

/// Floor [ms] to the previous clock-aligned multiple of [stepMs] (relative to
/// local midnight, so quarter/hour marks land on round times).
double _floorToStep(double ms, int stepMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.round());
  final dayStart =
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
  final since = d.millisecondsSinceEpoch - dayStart;
  final aligned = (since ~/ stepMs) * stepMs;
  return (dayStart + aligned).toDouble();
}

double _ceilToStep(double ms, int stepMs) {
  final f = _floorToStep(ms, stepMs);
  return f >= ms ? f : f + stepMs;
}

String _fmtAxis(int ms, int rangeMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  if (rangeMs <= 2 * _day) {
    return DateFormat('HH:mm').format(d);
  }
  return DateFormat('d/M').format(d);
}

const List<String> _nlMonths = [
  'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
  'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
];

/// Dutch tooltip timestamp without relying on intl locale data being loaded.
String _fmtTooltip(int ms, bool withTime) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final base = '${d.day} ${_nlMonths[d.month - 1]}';
  if (!withTime) return base;
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$base $hh:$mm';
}
