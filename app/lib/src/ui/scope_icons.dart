import 'package:flutter/material.dart';

import '../theme.dart';
import 'widgets/luxe_form.dart';

enum ScopeIconKind { building, floor }

class ScopeIconChoice {
  const ScopeIconChoice.building(this.key, this.label, this.building)
      : floor = null;
  const ScopeIconChoice.floor(this.key, this.label, this.floor)
      : building = null;

  final String key;
  final String label;
  final BuildingMark? building;
  final FloorMark? floor;
}

/// Silhouet per gebouwsoort. Leeg = woning.
enum BuildingMark {
  house,
  villa,
  apartment,
  guest,
  cabin,
  pool,
  spa,
  gym,
  garage,
  barn,
  workshop,
  storage,
  office,
  garden,
  greenhouse,
  boat,
}

/// Laag ten opzichte van de begane grond. De lange streep is altijd BG.
enum FloorMark { generic, b2, b1, bg, f1, f2, f3, attic, roof }

const List<ScopeIconChoice> kBuildingScopeIcons = [
  ScopeIconChoice.building('house', 'Woning', BuildingMark.house),
  ScopeIconChoice.building('villa', 'Villa', BuildingMark.villa),
  ScopeIconChoice.building('apartment', 'Appartement', BuildingMark.apartment),
  ScopeIconChoice.building('guest', 'Gastenverblijf', BuildingMark.guest),
  ScopeIconChoice.building('cabin', 'Buitenhuis', BuildingMark.cabin),
  ScopeIconChoice.building('pool', 'Zwembadhuis', BuildingMark.pool),
  ScopeIconChoice.building('spa', 'Wellness', BuildingMark.spa),
  ScopeIconChoice.building('gym', 'Sporthal', BuildingMark.gym),
  ScopeIconChoice.building('garage', 'Garage', BuildingMark.garage),
  ScopeIconChoice.building('barn', 'Schuur', BuildingMark.barn),
  ScopeIconChoice.building('workshop', 'Werkplaats', BuildingMark.workshop),
  ScopeIconChoice.building('storage', 'Berging', BuildingMark.storage),
  ScopeIconChoice.building('office', 'Kantoor', BuildingMark.office),
  ScopeIconChoice.building('garden', 'Tuinhuis', BuildingMark.garden),
  ScopeIconChoice.building('greenhouse', 'Kas', BuildingMark.greenhouse),
  ScopeIconChoice.building('boat', 'Boothuis', BuildingMark.boat),
];

const List<ScopeIconChoice> kFloorScopeIcons = [
  ScopeIconChoice.floor('b2', 'Kelder -2', FloorMark.b2),
  ScopeIconChoice.floor('b1', 'Kelder', FloorMark.b1),
  ScopeIconChoice.floor('bg', 'Begane grond', FloorMark.bg),
  ScopeIconChoice.floor('f1', '1e verdieping', FloorMark.f1),
  ScopeIconChoice.floor('f2', '2e verdieping', FloorMark.f2),
  ScopeIconChoice.floor('f3', '3e verdieping', FloorMark.f3),
  ScopeIconChoice.floor('attic', 'Zolder', FloorMark.attic),
  ScopeIconChoice.floor('roof', 'Dak', FloorMark.roof),
];

List<ScopeIconChoice> scopeIconsFor(ScopeIconKind kind) =>
    kind == ScopeIconKind.building ? kBuildingScopeIcons : kFloorScopeIcons;

BuildingMark buildingMarkFor(String? key) {
  for (final choice in kBuildingScopeIcons) {
    if (choice.key == key && choice.building != null) return choice.building!;
  }
  return BuildingMark.house;
}

Widget scopeBuildingGlyph(
  String? key, {
  required double size,
  required Color color,
}) {
  return BuildingIcon(mark: buildingMarkFor(key), size: size, color: color);
}

FloorMark floorMarkFor(String? key) {
  switch (key) {
    case 'b2':
    case 'k2':
      return FloorMark.b2;
    case 'b1':
    case 'basement':
    case 'kelder':
      return FloorMark.b1;
    case 'bg':
    case 'ground':
      return FloorMark.bg;
    case 'f1':
    case 'upper':
      return FloorMark.f1;
    case 'f2':
      return FloorMark.f2;
    case 'f3':
      return FloorMark.f3;
    case 'attic':
      return FloorMark.attic;
    case 'roof':
      return FloorMark.roof;
    default:
      return FloorMark.generic;
  }
}

Widget scopeFloorGlyph(
  String? key, {
  required double size,
  required Color color,
}) {
  return FloorLevelIcon(mark: floorMarkFor(key), size: size, color: color);
}

Widget scopeChoiceGlyph(ScopeIconChoice choice, {required Color color}) {
  final floor = choice.floor;
  if (floor != null) {
    return FloorLevelIcon(mark: floor, size: 20, color: color);
  }
  return BuildingIcon(
    mark: choice.building ?? BuildingMark.house,
    size: 20,
    color: color,
  );
}

/// Installateur kiest het icoon. Leeg = het standaardicoon van het soort.
class ScopeIconField extends StatelessWidget {
  const ScopeIconField({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
  });

  final ScopeIconKind kind;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = scopeIconsFor(kind);
    final known = choices.any((c) => c.key == value);
    final current = known ? value! : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('scope-icon-$kind-$current'),
      initialValue: current,
      isExpanded: true,
      decoration: luxeFilledDecoration(hint: 'Icoon'),
      items: [
        DropdownMenuItem(
          value: '',
          child: Row(
            children: [
              kind == ScopeIconKind.floor
                  ? FloorLevelIcon(
                      mark: FloorMark.generic,
                      size: 20,
                      color: LuxeColors.ink,
                    )
                  : BuildingIcon(
                      mark: BuildingMark.house,
                      size: 20,
                      color: LuxeColors.ink,
                    ),
              const SizedBox(width: 10),
              const Text('Standaard'),
            ],
          ),
        ),
        for (final choice in choices)
          DropdownMenuItem(
            value: choice.key,
            child: Row(
              children: [
                scopeChoiceGlyph(choice, color: LuxeColors.ink),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(choice.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) => onChanged(v == null || v.isEmpty ? null : v),
    );
  }
}

/// Silhouet per gebouwsoort, getekend in een vak van 24.
class BuildingIcon extends StatelessWidget {
  const BuildingIcon({
    super.key,
    required this.mark,
    required this.size,
    required this.color,
  });

  final BuildingMark mark;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BuildingPainter(mark: mark, color: color),
    );
  }
}

class _BuildingPainter extends CustomPainter {
  _BuildingPainter({required this.mark, required this.color});

  final BuildingMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (mark) {
      case BuildingMark.house:
        _roof(canvas, stroke, 4, 12, 12, 4, 20, 12);
        _walls(canvas, stroke, 6, 11.2, 18, 20);
        _door(canvas, stroke, 10.2, 15, 13.8, 20);
      case BuildingMark.villa:
        _roof(canvas, stroke, 2, 13, 12, 6.5, 22, 13);
        _walls(canvas, stroke, 3.5, 12.2, 20.5, 21);
        _rect(canvas, stroke, 6, 15, 9.2, 18.2);
        _rect(canvas, stroke, 14.8, 15, 18, 18.2);
      case BuildingMark.apartment:
        _rect(canvas, stroke, 7, 3, 17, 21);
        _hline(canvas, stroke, 7, 17, 9);
        _hline(canvas, stroke, 7, 17, 15);
      case BuildingMark.guest:
        _poly(canvas, stroke, const [
          Offset(2.4, 21),
          Offset(2.4, 11),
          Offset(1.2, 11),
          Offset(7.2, 4.2),
          Offset(13.2, 11),
          Offset(13.2, 16.2),
          Offset(17.4, 13.4),
          Offset(21.8, 16.2),
          Offset(21.8, 21),
        ]);
        _door(canvas, stroke, 5, 15.2, 8.4, 21);
      case BuildingMark.cabin:
        _poly(canvas, stroke, const [
          Offset(3.5, 21),
          Offset(12, 3.5),
          Offset(20.5, 21),
        ], close: true);
        _door(canvas, stroke, 10, 15, 14, 21);
      case BuildingMark.pool:
        _roof(canvas, stroke, 3, 10, 8, 5, 13, 10);
        _walls(canvas, stroke, 4.2, 9.2, 11.8, 14.5);
        _round(canvas, stroke, 3, 16, 21, 21.5, 2.4);
        _hline(canvas, stroke, 6.5, 16.5, 18.6);
      case BuildingMark.spa:
        _roof(canvas, stroke, 6, 10.5, 12, 5, 18, 10.5);
        canvas.drawCircle(const Offset(12, 16.4), 4.4, stroke);
      case BuildingMark.gym:
        final hall = Path()
          ..moveTo(3, 21)
          ..lineTo(3, 13)
          ..quadraticBezierTo(12, 3.5, 21, 13)
          ..lineTo(21, 21);
        canvas.drawPath(hall, stroke);
      case BuildingMark.garage:
        _rect(canvas, stroke, 2.5, 8, 21.5, 21);
        _door(canvas, stroke, 6.5, 11.5, 17.5, 21);
      case BuildingMark.barn:
        _poly(canvas, stroke, const [
          Offset(3, 14),
          Offset(7, 8.5),
          Offset(12, 5.5),
          Offset(17, 8.5),
          Offset(21, 14),
        ]);
        _walls(canvas, stroke, 4, 13.2, 20, 21);
        _door(canvas, stroke, 9.5, 14, 14.5, 21);
      case BuildingMark.workshop:
        _poly(canvas, stroke, const [
          Offset(2.5, 13),
          Offset(21.5, 7),
          Offset(21.5, 21),
          Offset(2.5, 21),
        ], close: true);
        _door(canvas, stroke, 8, 15, 16, 21);
      case BuildingMark.storage:
        _rect(canvas, stroke, 5, 6, 19, 21);
        _door(canvas, stroke, 10, 13.5, 14, 21);
      case BuildingMark.office:
        _rect(canvas, stroke, 3, 5.5, 21, 21);
        _hline(canvas, stroke, 3, 21, 13);
        _door(canvas, stroke, 10, 16, 14, 21);
      case BuildingMark.garden:
        canvas.drawCircle(const Offset(16.8, 8.2), 3.6, stroke);
        _vline(canvas, stroke, 16.8, 11.6, 21);
        _roof(canvas, stroke, 2, 14, 6.5, 9, 11, 14);
        _walls(canvas, stroke, 3.2, 13.2, 9.8, 21);
      case BuildingMark.greenhouse:
        _poly(canvas, stroke, const [
          Offset(3.5, 21),
          Offset(3.5, 12),
          Offset(12, 4.5),
          Offset(20.5, 12),
          Offset(20.5, 21),
        ], close: true);
        _vline(canvas, stroke, 12, 7.2, 21);
        _hline(canvas, stroke, 3.5, 20.5, 12);
        _hline(canvas, stroke, 5.2, 18.8, 16.5);
      case BuildingMark.boat:
        _roof(canvas, stroke, 6, 11, 12, 5, 18, 11);
        _walls(canvas, stroke, 7.2, 10.2, 16.8, 14);
        final hull = Path()
          ..moveTo(3, 16)
          ..quadraticBezierTo(12, 23.5, 21, 16);
        canvas.drawPath(hull, stroke);
    }
    canvas.restore();
  }

  void _roof(
    Canvas canvas,
    Paint paint,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _poly(canvas, paint, [Offset(x1, y1), Offset(x2, y2), Offset(x3, y3)]);
  }

  void _walls(
    Canvas canvas,
    Paint paint,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    _poly(canvas, paint, [
      Offset(left, bottom),
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
    ]);
  }

  void _rect(
    Canvas canvas,
    Paint paint,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
  }

  void _round(
    Canvas canvas,
    Paint paint,
    double left,
    double top,
    double right,
    double bottom,
    double radius,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right, bottom),
        Radius.circular(radius),
      ),
      paint,
    );
  }

  void _door(
    Canvas canvas,
    Paint paint,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    _poly(canvas, paint, [
      Offset(left, bottom),
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
    ]);
  }

  void _hline(Canvas canvas, Paint paint, double x1, double x2, double y) {
    canvas.drawLine(Offset(x1, y), Offset(x2, y), paint);
  }

  void _vline(Canvas canvas, Paint paint, double x, double y1, double y2) {
    canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
  }

  void _poly(
    Canvas canvas,
    Paint paint,
    List<Offset> points, {
    bool close = false,
  }) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (close) path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BuildingPainter oldDelegate) =>
      oldDelegate.mark != mark || oldDelegate.color != color;
}

/// Streepjes per laag. De lange streep zit op dezelfde hoogte: dat is BG.
class FloorLevelIcon extends StatelessWidget {
  const FloorLevelIcon({
    super.key,
    required this.mark,
    required this.size,
    required this.color,
  });

  final FloorMark mark;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FloorLevelPainter(mark: mark, color: color),
    );
  }
}

class _Stripe {
  const _Stripe(this.step, this.long, this.emphasis);
  final int step;
  final bool long;
  final int emphasis;
}

class _FloorLevelPainter extends CustomPainter {
  _FloorLevelPainter({required this.mark, required this.color});

  final FloorMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final barH = (s * 0.075).clamp(1.4, 1.8);
    final gap = (s * 0.07).clamp(1.2, 1.6);
    final step = barH + gap;
    final cx = size.width / 2;
    final mid = (size.height - barH) / 2;
    final longW = s * 0.88;
    final shortW = s * 0.52;

    final stripes = _stripes(mark);
    for (final stripe in stripes) {
      final top = mid + stripe.step * step;
      final w = stripe.long ? longW : shortW;
      final alpha = stripe.emphasis == 2
          ? 1.0
          : stripe.emphasis == 1
              ? 0.55
              : 0.32;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w / 2, top, w, barH),
        Radius.circular(barH / 2),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: alpha),
      );
    }

    if (mark == FloorMark.attic || mark == FloorMark.roof) {
      final anchor = mark == FloorMark.attic ? mid - step : mid;
      final base = anchor - gap * 0.45;
      final peak = base - shortW * 0.46;
      final roof = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s * 0.07).clamp(1.15, 1.55)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(
        Path()
          ..moveTo(cx - shortW / 2, base)
          ..lineTo(cx, peak)
          ..lineTo(cx + shortW / 2, base),
        roof,
      );
    }
  }

  List<_Stripe> _stripes(FloorMark mark) {
    switch (mark) {
      case FloorMark.generic:
        return const [
          _Stripe(-1, false, 0),
          _Stripe(0, false, 2),
          _Stripe(1, false, 0),
        ];
      case FloorMark.b2:
        return const [
          _Stripe(0, true, 1),
          _Stripe(1, false, 0),
          _Stripe(2, false, 2),
        ];
      case FloorMark.b1:
        return const [
          _Stripe(0, true, 1),
          _Stripe(1, false, 2),
        ];
      case FloorMark.bg:
        return const [_Stripe(0, true, 2)];
      case FloorMark.f1:
        return const [
          _Stripe(-1, false, 2),
          _Stripe(0, true, 1),
        ];
      case FloorMark.f2:
        return const [
          _Stripe(-2, false, 2),
          _Stripe(-1, false, 0),
          _Stripe(0, true, 1),
        ];
      case FloorMark.f3:
        return const [
          _Stripe(-3, false, 2),
          _Stripe(-2, false, 0),
          _Stripe(-1, false, 0),
          _Stripe(0, true, 1),
        ];
      case FloorMark.attic:
        return const [
          _Stripe(-1, false, 2),
          _Stripe(0, true, 1),
        ];
      case FloorMark.roof:
        return const [_Stripe(0, true, 1)];
    }
  }

  @override
  bool shouldRepaint(covariant _FloorLevelPainter oldDelegate) =>
      oldDelegate.mark != mark || oldDelegate.color != color;
}
