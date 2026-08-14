import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../log_api.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'responsive.dart';
import 'widgets/back_pill.dart';
import 'widgets/function_screen_header.dart';
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
List<Color> _seriesColors = [
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
final Color _setpointColor = LuxeColors.brass;
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
    _endMs = _floorTo15Min(DateTime.now().millisecondsSinceEpoch);
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
      // Keep the right edge anchored to "now" (floored to 15 min) when zooming.
      _endMs = _floorTo15Min(DateTime.now().millisecondsSinceEpoch);
    });
  }

  void _pan(int deltaMs) {
    final nowFloor = _floorTo15Min(DateTime.now().millisecondsSinceEpoch);
    setState(() {
      _endMs = _floorTo15Min((_endMs + deltaMs).clamp(_rangeMs, nowFloor));
    });
  }

  void _jumpToNow() {
    setState(
      () => _endMs = _floorTo15Min(DateTime.now().millisecondsSinceEpoch),
    );
  }

  void _refresh() {
    _jumpToNow();
    ref.invalidate(logHistoryProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(logHistoryProvider(_query));
    final nowFloor = _floorTo15Min(DateTime.now().millisecondsSinceEpoch);
    final atNow = _endMs >= nowFloor;

    final title = async.maybeWhen(
      data: (d) => d.name,
      orElse: () => widget.title ?? 'Log',
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FunctionScreenHeader(
              onBack: () => appBack(context),
              title: title,
              trailing: HeaderIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Vernieuwen',
                onTap: _refresh,
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.hPad,
                    8,
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
                      SizedBox(height: 12),
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
                          loading: () => Center(
                            child: CircularProgressIndicator(
                                color: LuxeColors.brass),
                          ),
                          error: (e, _) => Center(
                            child: Text(
                              'Kan log niet laden:\n$e',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: LuxeColors.inkSoft),
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
          ],
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
        duration: Duration(milliseconds: 160),
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
        Spacer(),
        GestureDetector(
          onTap: atNow ? null : onNow,
          child: Opacity(
            opacity: atNow ? 0.4 : 1,
            child: Row(
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
      SizedBox(width: 2),
      Text(
        label,
        style: TextStyle(
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
      padding: EdgeInsets.fromLTRB(14, 20, 18, 14),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LuxeColors.line),
      ),
      child: !_hasPoints
          ? Center(
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

/// Width reserved for the left (temperature) axis labels. Shared by the
/// layout calculation and the axis config so the two can't drift apart.
const double _leftAxisWidth = 42.0;

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
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints),
    );
  }

  Widget _build(BuildContext context, BoxConstraints constraints) {
    // Window is always snapped to 15-minute clock marks (e.g. 14:58 → 14:45).
    // Right edge = floored "to"; left edge = exactly [rangeMs] earlier so the
    // 24h view reads "now" on the right and "24h ago" on the left.
    final maxX = _floorTo15Min(data.toMs).toDouble();
    final minX = maxX - rangeMs;

    // 24h: always 4 labels (left, 2 middle, right). Other ranges: as many as
    // fit without colliding, still equally spaced across the window.
    final plotWidth = (constraints.maxWidth - _leftAxisWidth)
        .clamp(0.0, double.infinity);
    final labelCount =
        rangeMs == _day ? 4 : (plotWidth / 110).floor().clamp(3, 5);
    final xStep = rangeMs / (labelCount - 1);
    final xInterval = xStep;

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
        // Align interval ticks to our local-clock minX. Without this, fl_chart
        // steps from Unix epoch (UTC), which drifts vs local midnight and
        // packs neighbouring labels like 12:00 + 14:00 on top of each other.
        baselineX: minX,
        clipData: FlClipData.all(),
        lineBarsData: bars,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yInterval <= 0 ? null : yInterval,
          verticalInterval: xInterval <= 0 ? null : xInterval,
          checkToShowHorizontalLine: (v) => v >= dataFloor - 0.0001,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: LuxeColors.line, strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              FlLine(color: LuxeColors.lineSoft, strokeWidth: 1),
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
              reservedSize: _leftAxisWidth,
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
                  padding: EdgeInsets.only(right: 6),
                  child: Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
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
              // Endpoints are part of the equal-spaced grid (left = now-range,
              // right = now floored to 15 min); keep them visible.
              minIncluded: true,
              maxIncluded: true,
              getTitlesWidget: (value, meta) {
                // Only accept ticks on our equal-spaced grid from minX.
                if (!_isAxisTick(value, minX, xStep)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    _fmtAxis(value.toInt(), rangeMs),
                    style: TextStyle(
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
        SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
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
        SizedBox(width: 7),
        Text(
          series.label,
          style: TextStyle(
            color: LuxeColors.ink,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        if (last != null) ...[
          SizedBox(width: 6),
          Text(
            '${last.toStringAsFixed(1)}$unit',
            style: TextStyle(
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

const int _quarterHourMs = 15 * 60 * 1000;

/// Floor [ms] to the previous 15-minute mark on the local clock
/// (e.g. 14:58 → 14:45). Used for every zoom window's right edge.
int _floorTo15Min(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final dayStart = DateTime(d.year, d.month, d.day);
  final since = d.difference(dayStart).inMilliseconds;
  final aligned = (since ~/ _quarterHourMs) * _quarterHourMs;
  return dayStart.millisecondsSinceEpoch + aligned;
}

/// True when [value] lands on the equal-spaced grid starting at [minX].
bool _isAxisTick(double value, double minX, double stepMs) {
  if (stepMs <= 0) return false;
  final n = ((value - minX) / stepMs).round();
  final aligned = minX + n * stepMs;
  return (value - aligned).abs() < 1.0;
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
