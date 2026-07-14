import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';
import 'glass_card.dart';
import 'solid_arrow_icon.dart';

export 'solid_arrow_icon.dart';

/// Eén knop — gebruik voor alle apparaat-tegels.
class DeviceControlItem {
  const DeviceControlItem({
    this.icon,
    this.iconRotation = 0.0,
    this.arrow,
    required this.label,
    this.sublabel,
    this.active = false,
    this.onTap,
  });

  final IconData? icon;
  final double iconRotation;
  /// Pijl met lijn + solid driehoekpunt (zonwering, haard, …).
  final DeviceArrowDirection? arrow;
  final String label;
  final String? sublabel;
  final bool active;
  final VoidCallback? onTap;

  bool get hasGlyph => icon != null || arrow != null;
}

/// Vaste maat vierkante knop — één implementatie voor Sonos, haard, zonwering, …
class DeviceControlSquare extends StatefulWidget {
  const DeviceControlSquare({
    super.key,
    required this.onTap,
    this.active = false,
    this.expand = false,
    required Widget child,
  })  : icon = null,
        iconRotation = 0,
        child = child;

  const DeviceControlSquare.icon({
    super.key,
    required this.icon,
    this.iconRotation = 0.0,
    this.onTap,
    this.active = false,
    this.expand = false,
  }) : child = null;

  final VoidCallback? onTap;
  final bool active;
  final bool expand;
  final Widget? child;
  final IconData? icon;
  final double iconRotation;

  static const size = DeviceControlBar.buttonSize;

  @override
  State<DeviceControlSquare> createState() => _DeviceControlSquareState();
}

class _DeviceControlSquareState extends State<DeviceControlSquare> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    Widget inner = widget.child ??
        Transform.rotate(
          angle: widget.iconRotation,
          child: Icon(
            widget.icon,
            size: DeviceControlIcons.size,
            color: DeviceControlIcons.color(
              active: widget.active,
              disabled: disabled,
            ),
          ),
        );

    final surface = DeviceControlButtonSurface(
      active: widget.active,
      pressed: _pressed,
      width: widget.expand ? double.infinity : DeviceControlSquare.size,
      height: DeviceControlSquare.size,
      child: Center(child: inner),
    );

    return SizedBox(
      width: widget.expand ? double.infinity : DeviceControlSquare.size,
      height: DeviceControlSquare.size,
      child: disabled
          ? surface
          : PressScale(
              onTap: widget.onTap!,
              radius: DeviceControlBar.buttonRadius,
              onPressedChanged: (pressed) =>
                  setState(() => _pressed = pressed),
              child: surface,
            ),
    );
  }
}

/// Warm ivory button chrome — glass rim + top highlight, no blur.
class DeviceControlButtonSurface extends StatelessWidget {
  const DeviceControlButtonSurface({
    super.key,
    required this.child,
    this.active = false,
    this.pressed = false,
    this.locked = false,
    this.radius = DeviceControlBar.buttonRadius,
    this.width,
    this.height,
    this.constraints,
    this.padding,
  });

  final Widget child;
  final bool active;
  final bool pressed;
  final bool locked;
  final double radius;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: DeviceControlBar.buttonShadows(active: active),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          height: height,
          constraints: constraints ?? const BoxConstraints(),
          padding: padding,
          decoration: DeviceControlBar.buttonDecoration(
            active: active,
            pressed: pressed,
            locked: locked,
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: radius + 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(radius),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Losse witte knoppen met tussenruimte (zonwering, haard, universal, WTW, AC, …).
class DeviceControlPanel extends StatelessWidget {
  const DeviceControlPanel({
    super.key,
    required this.rows,
    this.compactRows = const {},
  });

  final List<List<DeviceControlItem>> rows;
  final Set<int> compactRows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = DeviceControlBar.useFullWidthRows(
          context,
          constraints.maxWidth,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: DeviceControlBar.gap),
              if (compactRows.contains(i))
                _CompactControlRow(items: rows[i], fullWidth: fullWidth)
              else
                _SquareControlRow(items: rows[i], fullWidth: fullWidth),
            ],
          ],
        );
      },
    );
  }
}

class _SquareControlRow extends StatelessWidget {
  const _SquareControlRow({required this.items, this.fullWidth = false});
  final List<DeviceControlItem> items;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (fullWidth) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            for (var j = 0; j < items.length; j++) ...[
              if (j > 0) const SizedBox(width: DeviceControlBar.gap),
              Expanded(
                child: _LabeledSquareButton(item: items[j], expand: true),
              ),
            ],
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var j = 0; j < items.length; j++) ...[
          if (j > 0) const SizedBox(width: DeviceControlBar.gap),
          _LabeledSquareButton(item: items[j]),
        ],
      ],
    );
  }
}

/// Omhoog/stop/omlaag: gelijke tussenruimte over een vaste breedte.
class _JalousieMoveRow extends StatelessWidget {
  const _JalousieMoveRow({
    required this.items,
    required this.width,
    this.fullWidth = false,
  });

  final List<DeviceControlItem> items;
  final double width;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final n = items.length;

    if (fullWidth) {
      return SizedBox(
        width: width,
        child: Row(
          children: [
            for (var j = 0; j < n; j++) ...[
              if (j > 0) const SizedBox(width: DeviceControlBar.gap),
              Expanded(
                child: _LabeledSquareButton(item: items[j], expand: true),
              ),
            ],
          ],
        ),
      );
    }

    final buttons = n * DeviceControlBar.buttonSize;
    final slotCount = n - 1;
    final slotWidth = slotCount > 0
        ? math.max(0.0, (width - buttons) / slotCount)
        : 0.0;

    return SizedBox(
      width: width,
      child: Row(
        children: [
          for (var j = 0; j < n; j++) ...[
            if (j > 0) SizedBox(width: slotWidth),
            _LabeledSquareButton(item: items[j]),
          ],
        ],
      ),
    );
  }
}

/// Move- + tuimelrij; breedte vast berekend (geen meting → geen verspringen).
class _MoveAndTiltBlock extends StatelessWidget {
  const _MoveAndTiltBlock({
    required this.moveItems,
    required this.tiltItems,
  });

  final List<DeviceControlItem> moveItems;
  final List<DeviceControlItem> tiltItems;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = DeviceControlBar.useFullWidthRows(
          context,
          constraints.maxWidth,
        );
        final width = fullWidth
            ? constraints.maxWidth
            : DeviceControlBar.compactRowWidth(context, tiltItems);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _JalousieMoveRow(
              items: moveItems,
              width: width,
              fullWidth: fullWidth,
            ),
            const SizedBox(height: DeviceControlBar.gap),
            _CompactControlRow(items: tiltItems, fullWidth: fullWidth),
          ],
        );
      },
    );
  }
}

class _CompactControlRow extends StatelessWidget {
  const _CompactControlRow({super.key, required this.items, this.fullWidth = false});
  final List<DeviceControlItem> items;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    if (fullWidth) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            for (var j = 0; j < items.length; j++) ...[
              if (j > 0) const SizedBox(width: DeviceControlBar.gap),
              Expanded(
                child: _CompactLabeledButton(item: items[j], expand: true),
              ),
            ],
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var j = 0; j < items.length; j++) ...[
          if (j > 0) const SizedBox(width: DeviceControlBar.gap),
          _CompactLabeledButton(item: items[j]),
        ],
      ],
    );
  }
}

class _LabeledSquareButton extends StatelessWidget {
  const _LabeledSquareButton({required this.item, this.expand = false});
  final DeviceControlItem item;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final hasIcon = item.hasGlyph;
    final disabled = item.onTap == null;

    return DeviceControlSquare(
      onTap: item.onTap,
      active: item.active,
      expand: expand,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasIcon) ...[
              _DeviceControlGlyph(
                item: item,
                active: item.active,
                disabled: disabled,
              ),
              if (item.label.isNotEmpty) const SizedBox(height: 3),
            ],
            if (item.label.isNotEmpty)
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: hasIcon
                      ? DeviceControlBar.labeledFontSize
                      : DeviceControlBar.labelOnlyFontSize,
                  height: 1.05,
                  fontWeight:
                      item.active ? FontWeight.w600 : FontWeight.w400,
                  color: DeviceControlIcons.color(
                    active: item.active,
                    disabled: disabled,
                  ),
                  letterSpacing: hasIcon ? 0.3 : 0.15,
                ),
              ),
            if (item.sublabel != null)
              Text(
                item.sublabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  color: DeviceControlIcons.color(
                    active: item.active,
                    disabled: disabled,
                  ).withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactLabeledButton extends StatefulWidget {
  const _CompactLabeledButton({required this.item, this.expand = false});

  final DeviceControlItem item;
  final bool expand;

  @override
  State<_CompactLabeledButton> createState() => _CompactLabeledButtonState();
}

class _CompactLabeledButtonState extends State<_CompactLabeledButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final disabled = item.onTap == null;
    final hasIcon = item.hasGlyph;

    var surface = DeviceControlButtonSurface(
      active: item.active,
      pressed: _pressed,
      height: DeviceControlBar.buttonSize,
      width: widget.expand ? double.infinity : null,
      constraints: widget.expand
          ? const BoxConstraints(minHeight: DeviceControlBar.buttonSize)
          : const BoxConstraints(
              minWidth: DeviceControlBar.tiltButtonMinWidth,
            ),
      padding: const EdgeInsets.symmetric(
        horizontal: DeviceControlBar.tiltButtonHPadding,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasIcon) ...[
            _DeviceControlGlyph(
              item: item,
              active: item.active,
              disabled: disabled,
            ),
            if (item.label.isNotEmpty) const SizedBox(width: 6),
          ],
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: DeviceControlBar.labelOnlyFontSize,
              fontWeight: item.active ? FontWeight.w600 : FontWeight.w400,
              color: DeviceControlIcons.color(
                active: item.active,
                disabled: disabled,
              ),
            ),
          ),
        ],
      ),
    );

    if (disabled) return surface;

    return PressScale(
      onTap: item.onTap!,
      radius: DeviceControlBar.buttonRadius,
      onPressedChanged: (pressed) => setState(() => _pressed = pressed),
      child: surface,
    );
  }
}

class _DeviceControlGlyph extends StatelessWidget {
  const _DeviceControlGlyph({
    required this.item,
    required this.active,
    required this.disabled,
  });

  final DeviceControlItem item;
  final bool active;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final color = DeviceControlIcons.color(active: active, disabled: disabled);
    if (item.arrow != null) {
      return SolidArrowIcon(direction: item.arrow!, color: color);
    }
    return Transform.rotate(
      angle: item.iconRotation,
      child: Icon(
        item.icon,
        size: DeviceControlIcons.size,
        color: color,
      ),
    );
  }
}

/// @deprecated Use [DeviceControlSquare.icon].
class DeviceControlIconButton extends StatelessWidget {
  const DeviceControlIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.iconRotation = 0.0,
    this.active = false,
    this.expand = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double iconRotation;
  final bool active;
  final bool expand;

  @override
  Widget build(BuildContext context) => DeviceControlSquare.icon(
        icon: icon,
        onTap: onTap,
        iconRotation: iconRotation,
        active: active,
        expand: expand,
      );
}

/// Uniforme padding en tussenruimte voor apparaat-tegels in kamers.
abstract final class DeviceTileLayout {
  static EdgeInsets padding(BuildContext context) => EdgeInsets.fromLTRB(
        context.cardHPad,
        context.cardVPad,
        context.cardHPad,
        context.cardVPad,
      );

  /// Ruimte tussen 56×56 header-icoon en titelkolom.
  static const double iconGap = 14.0;

  /// Verticale ruimte tussen apparaatnaam en statusregel.
  static const double titleStatusGap = 2.0;

  /// Iconen linksboven uitlijnen op alle apparaat-tegels.
  static const CrossAxisAlignment iconRowAlignment = CrossAxisAlignment.start;

  /// Vaste 56×56 schijf links — onderkanten lopen gelijk op alle tegels.
  static Widget statusIconSlot({required Widget child}) => SizedBox(
        width: DeviceControlBar.tileIconSize,
        height: DeviceControlBar.tileIconSize,
        child: child,
      );

  /// Standaard header: icoon · tekst · optionele actie rechts.
  static Widget headerRow({
    required Widget leading,
    required Widget content,
    Widget? trailing,
  }) =>
      Row(
        crossAxisAlignment: iconRowAlignment,
        children: [
          statusIconSlot(child: leading),
          const SizedBox(width: iconGap),
          Expanded(child: content),
          if (trailing != null) trailing,
        ],
      );

  /// Switch rechts, verticaal binnen de icon-hoogte (zelfde onderlijn).
  static Widget trailingSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      statusIconSlot(
        child: Align(
          alignment: Alignment.centerRight,
          child: adaptiveOnOffSwitch(value: value, onChanged: onChanged),
        ),
      );

  static Switch adaptiveOnOffSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Switch.adaptive(
        value: value,
        activeThumbColor: LuxeColors.brass,
        activeTrackColor: LuxeColors.brass.withValues(alpha: 0.35),
        onChanged: onChanged,
      );
}

class DeviceControlBar {
  DeviceControlBar._();

  /// Zelfde maat als Sonos-artwork / speaker-placeholder in [MediaTile].
  static const double buttonSize = 56.0;
  static const double tileIconSize = buttonSize;
  static const double tileIconRadius = 14.0;
  static const double tileGlyphSize = 22.0;
  static const double buttonRadius = tileIconRadius;
  static const double gap = 6.0;

  /// Tuimel-knoppen: iets breder dan vierkant, zelfde hoogte.
  static const double tiltButtonMinWidth = 80.0;
  static const double tiltButtonHPadding = 16.0;

  static const double labeledFontSize = 10.0;
  static const double labelOnlyFontSize = 11.0;

  /// Volle-breedte knoppenrijen op telefoon of smalle tegels.
  static bool useFullWidthRows(BuildContext context, double maxWidth) =>
      context.isPhone || maxWidth < 600;

  /// Breedte van één tuimelknop (zelfde formule als [_CompactLabeledButton]).
  static double compactLabeledButtonWidth(
    BuildContext context,
    DeviceControlItem item,
  ) {
    final hasIcon = item.hasGlyph;
    var inner = 0.0;
    if (hasIcon) inner += DeviceControlIcons.size;
    if (hasIcon && item.label.isNotEmpty) inner += 6;
    if (item.label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: item.label,
          style: const TextStyle(
            fontSize: labelOnlyFontSize,
            fontWeight: FontWeight.w400,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      inner += tp.width;
    }
    return math.max(tiltButtonMinWidth, tiltButtonHPadding * 2 + inner);
  }

  /// Totale breedte van een tuimelrij (vaste gap tussen knoppen).
  static double compactRowWidth(
    BuildContext context,
    List<DeviceControlItem> items,
  ) {
    if (items.isEmpty) return 0;
    var w = 0.0;
    for (var i = 0; i < items.length; i++) {
      if (i > 0) w += gap;
      w += compactLabeledButtonWidth(context, items[i]);
    }
    return w;
  }

  static BoxDecoration buttonDecoration({
    bool active = false,
    bool pressed = false,
    bool locked = false,
  }) =>
      BoxDecoration(
        color: active
            ? LuxeColors.brass.withValues(alpha: 0.12)
            : pressed
                ? LuxeColors.surfaceDim
                : LuxeColors.surface,
        borderRadius: BorderRadius.circular(buttonRadius),
        border: Border.all(
          color: active
              ? LuxeColors.brass.withValues(alpha: 0.35)
              : locked
                  ? LuxeColors.inkSoft.withValues(alpha: 0.35)
                  : LuxeColors.glassRim,
        ),
      );

  static List<BoxShadow> buttonShadows({bool active = false}) =>
      active ? LuxeShadows.brassGlow : LuxeShadows.controlButton;

  static List<List<DeviceControlItem>> chunk(
    List<DeviceControlItem> items, {
    int perRow = 4,
  }) {
    if (items.isEmpty) return const [];
    final out = <List<DeviceControlItem>>[];
    for (var i = 0; i < items.length; i += perRow) {
      final end = math.min(i + perRow, items.length);
      out.add(items.sublist(i, end));
    }
    return out;
  }

  static Widget build(
    BuildContext context, {
    required List<List<DeviceControlItem>> rows,
    Set<int> compactRows = const {},
    bool alignLeftOnDesktop = false,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final panel = DeviceControlPanel(
      rows: rows,
      compactRows: compactRows,
    );
    if (alignLeftOnDesktop && !context.isPhone) {
      return Align(alignment: Alignment.centerLeft, child: panel);
    }
    return SizedBox(width: double.infinity, child: panel);
  }

  static Widget singleRow(
    BuildContext context,
    List<DeviceControlItem> items, {
    bool alignLeftOnDesktop = false,
  }) =>
      build(
        context,
        rows: [items],
        alignLeftOnDesktop: alignLeftOnDesktop,
      );

  static Widget tiltRow(
    BuildContext context,
    List<DeviceControlItem> items, {
    bool alignLeftOnDesktop = false,
  }) =>
      build(
        context,
        rows: [items],
        compactRows: const {0},
        alignLeftOnDesktop: alignLeftOnDesktop,
      );

  static Widget moveAndTiltBlock({
    required List<DeviceControlItem> moveItems,
    required List<DeviceControlItem> tiltItems,
  }) =>
      SizedBox(
        width: double.infinity,
        child: _MoveAndTiltBlock(
          moveItems: moveItems,
          tiltItems: tiltItems,
        ),
      );

  static Widget grid(
    BuildContext context,
    List<DeviceControlItem> items, {
    int perRow = 4,
    bool alignLeftOnDesktop = false,
  }) =>
      build(
        context,
        rows: chunk(items, perRow: perRow),
        alignLeftOnDesktop: alignLeftOnDesktop,
      );
}
