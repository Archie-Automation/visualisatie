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
    // Zelfde messing als de systeemicoontjes in het donkere thema.
    final accent = LuxePalette.dark.brass;
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
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Scherm schoonmaken',
                          style: TextStyle(
                            color: accent,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            decoration: TextDecoration.none,
                            decorationThickness: 0,
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

/// radius en drift zijn een deel van de kortste zijde, zodat ze op een
/// wandtablet groot genoeg zijn om te zien en toch zacht blijven.
const _bubbles = <_BubbleSpec>[
  _BubbleSpec(x: 0.10, radius: 0.045, phase: 0.05, drift: 0.018, wobble: 0.8),
  _BubbleSpec(x: 0.22, radius: 0.08, phase: 0.38, drift: 0.024, wobble: 0.55),
  _BubbleSpec(x: 0.36, radius: 0.055, phase: 0.72, drift: 0.02, wobble: 0.7),
  _BubbleSpec(x: 0.50, radius: 0.034, phase: 0.16, drift: 0.016, wobble: 0.9),
  _BubbleSpec(x: 0.64, radius: 0.072, phase: 0.84, drift: 0.022, wobble: 0.6),
  _BubbleSpec(x: 0.78, radius: 0.048, phase: 0.28, drift: 0.02, wobble: 0.75),
  _BubbleSpec(x: 0.90, radius: 0.09, phase: 0.55, drift: 0.026, wobble: 0.5),
  _BubbleSpec(x: 0.30, radius: 0.028, phase: 0.93, drift: 0.014, wobble: 1.0),
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
      final radius = size.shortestSide * b.radius;
      final y = size.height * (1.08 - progress * 1.25);
      final x = size.width * b.x +
          math.sin((t * b.wobble + b.phase) * math.pi * 2) *
              size.shortestSide *
              b.drift;
      final center = Offset(x, y);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.05 * fade)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.32 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (radius * 0.045).clamp(1.2, 2.2),
      );
      canvas.drawArc(
        Rect.fromCircle(
          center: center.translate(-radius * 0.22, -radius * 0.28),
          radius: radius * 0.42,
        ),
        math.pi * 1.15,
        math.pi * 0.62,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.5 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (radius * 0.04).clamp(1.1, 2.0)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoapBubblesPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}
