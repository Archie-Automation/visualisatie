import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_panel_config.dart';
import 'theme.dart';

const screenCleanDuration = Duration(seconds: 20);

/// Seconden die nog lopen, of null als het scherm normaal reageert.
/// 0 blijft even staan zodat de aftelling zichtbaar eindigt.
class ScreenCleanController extends Notifier<int?> {
  Timer? _timer;

  @override
  int? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void start() {
    _timer?.cancel();
    var left = screenCleanDuration.inSeconds;
    state = left;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      left -= 1;
      if (left > 0) {
        state = left;
        return;
      }
      t.cancel();
      state = 0;
      _timer = Timer(const Duration(milliseconds: 700), () {
        _timer = null;
        state = null;
      });
    });
  }
}

final screenCleanProvider = NotifierProvider<ScreenCleanController, int?>(
  ScreenCleanController.new,
);

/// Android: volledig scherm dat aanrakingen negeert tot [screenCleanProvider] leeg is.
class ScreenCleanLayer extends ConsumerWidget {
  const ScreenCleanLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(screenCleanProvider);
    if (!wallTabletDeviceSettingsApply || seconds == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(child: ScreenCleanView(seconds: seconds)),
      ],
    );
  }
}

/// Opent het schoonmaakscherm als eigen route, boven instellingen.
void openScreenClean(BuildContext context, WidgetRef ref) {
  if (ref.read(screenCleanProvider) != null) return;
  ref.read(screenCleanProvider.notifier).start();
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const ScreenCleanPage(),
    ),
  );
}

class ScreenCleanPage extends ConsumerWidget {
  const ScreenCleanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int?>(screenCleanProvider, (prev, next) {
      if (next != null || prev == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      });
    });
    final seconds = ref.watch(screenCleanProvider) ?? 0;
    return ScreenCleanView(seconds: seconds);
  }
}

class ScreenCleanView extends StatefulWidget {
  const ScreenCleanView({super.key, required this.seconds});

  final int seconds;

  @override
  State<ScreenCleanView> createState() => _ScreenCleanViewState();
}

class _ScreenCleanViewState extends State<ScreenCleanView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bubbles;

  @override
  void initState() {
    super.initState();
    _bubbles = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _bubbles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide;
    final fontSize = (side * 0.42).clamp(180.0, 420.0);
    final accent = _cleanAccent();
    return BackButtonListener(
      onBackButtonPressed: () async => true,
      child: AbsorbPointer(
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: SizedBox.expand(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _bubbles,
                    builder: (context, _) => CustomPaint(
                      painter: _SoapBubblesPainter(
                        t: _bubbles.value,
                        color: accent,
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.seconds}',
                          style: TextStyle(
                            color: accent,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            height: 0.9,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Scherm schoonmaken',
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.72),
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Messing uit het thema. Op een zwart vlak is het lichte messing leesbaarder
/// dan het donkere messing van het lichte thema.
Color _cleanAccent() {
  final brass = LuxeColors.brass;
  if (brass.computeLuminance() < 0.4) return LuxeColors.brassGlow;
  return brass;
}

class _BubbleSpec {
  const _BubbleSpec({
    required this.x,
    required this.radius,
    required this.phase,
    required this.drift,
    required this.wobble,
  });

  final double x;
  final double radius;
  final double phase;
  final double drift;
  final double wobble;
}

const _bubbles = <_BubbleSpec>[
  _BubbleSpec(x: 0.08, radius: 18, phase: 0.02, drift: 14, wobble: 1.1),
  _BubbleSpec(x: 0.16, radius: 34, phase: 0.41, drift: 22, wobble: 0.7),
  _BubbleSpec(x: 0.27, radius: 12, phase: 0.18, drift: 10, wobble: 1.4),
  _BubbleSpec(x: 0.34, radius: 46, phase: 0.73, drift: 18, wobble: 0.6),
  _BubbleSpec(x: 0.44, radius: 22, phase: 0.55, drift: 16, wobble: 1.0),
  _BubbleSpec(x: 0.52, radius: 14, phase: 0.09, drift: 12, wobble: 1.3),
  _BubbleSpec(x: 0.61, radius: 40, phase: 0.86, drift: 24, wobble: 0.8),
  _BubbleSpec(x: 0.70, radius: 16, phase: 0.33, drift: 11, wobble: 1.2),
  _BubbleSpec(x: 0.78, radius: 28, phase: 0.62, drift: 20, wobble: 0.9),
  _BubbleSpec(x: 0.88, radius: 20, phase: 0.24, drift: 15, wobble: 1.1),
  _BubbleSpec(x: 0.93, radius: 38, phase: 0.48, drift: 18, wobble: 0.65),
  _BubbleSpec(x: 0.22, radius: 10, phase: 0.91, drift: 8, wobble: 1.6),
  _BubbleSpec(x: 0.57, radius: 26, phase: 0.15, drift: 17, wobble: 0.85),
  _BubbleSpec(x: 0.39, radius: 15, phase: 0.67, drift: 13, wobble: 1.25),
];

class _SoapBubblesPainter extends CustomPainter {
  const _SoapBubblesPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in _bubbles) {
      final progress = (t + b.phase) % 1.0;
      final fade = progress < 0.08
          ? progress / 0.08
          : (progress > 0.9 ? (1 - progress) / 0.1 : 1.0);
      final y = size.height * (1.08 - progress * 1.25);
      final x = size.width * b.x +
          math.sin((t * b.wobble + b.phase) * math.pi * 2) * b.drift;
      final center = Offset(x, y);
      final film = Color.lerp(color, const Color(0xFFFFFFFF), 0.55)!;

      canvas.drawCircle(
        center,
        b.radius,
        Paint()
          ..color = film.withValues(alpha: 0.07 * fade)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        b.radius,
        Paint()
          ..color = film.withValues(alpha: 0.55 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawArc(
        Rect.fromCircle(
          center: center.translate(-b.radius * 0.22, -b.radius * 0.28),
          radius: b.radius * 0.42,
        ),
        math.pi * 1.15,
        math.pi * 0.62,
        false,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoapBubblesPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}
