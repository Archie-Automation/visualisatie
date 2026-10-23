import 'package:flutter/material.dart';

/// Stilstaand demobeeld. Geen stream, wel een herkenbare cameraweergave.
class DemoCameraView extends StatelessWidget {
  const DemoCameraView({
    super.key,
    required this.label,
    required this.seed,
    this.expand = false,
    this.aspectRatio = 16 / 9,
    this.doorStation = false,
  });

  final String label;
  final String seed;
  final bool expand;
  final double aspectRatio;

  /// Deuropname van een intercom, in plaats van het getekende camerabeeld.
  final bool doorStation;

  @override
  Widget build(BuildContext context) {
    final view = DecoratedBox(
      decoration: BoxDecoration(gradient: _gradient(seed)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (doorStation)
            Image.asset(
              'assets/images/demo_intercom.jpg',
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          else
            CustomPaint(painter: _DemoScenePainter(seed.hashCode)),
          Positioned(
            left: 12,
            bottom: 12,
            right: 12,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
          ),
          const Positioned(
            top: 10,
            right: 10,
            child: _DemoChip(),
          ),
        ],
      ),
    );
    if (expand) return view;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(aspectRatio: aspectRatio, child: view),
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Text(
        'DEMO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

LinearGradient _gradient(String seed) {
  final n = seed.hashCode.abs();
  final hues = <List<Color>>[
    [const Color(0xFF1C2838), const Color(0xFF3D5A4C)],
    [const Color(0xFF243044), const Color(0xFF6A5340)],
    [const Color(0xFF1A2430), const Color(0xFF3E4E68)],
    [const Color(0xFF2A241C), const Color(0xFF4E5A3A)],
  ];
  final pair = hues[n % hues.length];
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: pair,
  );
}

class _DemoScenePainter extends CustomPainter {
  _DemoScenePainter(this.salt);
  final int salt;

  @override
  void paint(Canvas canvas, Size size) {
    final ground = Paint()..color = const Color(0xFF1E2A22).withValues(alpha: 0.55);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38),
      ground,
    );

    final wall = Paint()..color = const Color(0xFFD7CBB8).withValues(alpha: 0.9);
    final house = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.28,
        size.width * 0.42,
        size.height * 0.4,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(house, wall);

    final roof = Path()
      ..moveTo(size.width * 0.14, size.height * 0.30)
      ..lineTo(size.width * 0.39, size.height * 0.14)
      ..lineTo(size.width * 0.64, size.height * 0.30)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFF6E4B3A));

    final door = Paint()..color = const Color(0xFF3E2A22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.33,
          size.height * 0.46,
          size.width * 0.1,
          size.height * 0.22,
        ),
        const Radius.circular(2),
      ),
      door,
    );

    final glass = Paint()..color = const Color(0xFF8FB4C9).withValues(alpha: 0.85);
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.22,
        size.height * 0.36,
        size.width * 0.08,
        size.height * 0.1,
      ),
      glass,
    );
    if (salt.isEven) {
      canvas.drawRect(
        Rect.fromLTWH(
          size.width * 0.48,
          size.height * 0.36,
          size.width * 0.08,
          size.height * 0.1,
        ),
        glass,
      );
    }

    final tree = Paint()..color = const Color(0xFF2F4A38);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.48),
      size.height * 0.12,
      tree,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.76, size.height * 0.52, size.width * 0.035, size.height * 0.16),
      Paint()..color = const Color(0xFF5A4030),
    );
  }

  @override
  bool shouldRepaint(covariant _DemoScenePainter oldDelegate) =>
      oldDelegate.salt != salt;
}
