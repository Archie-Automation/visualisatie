import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../room_control_category.dart';
import '../responsive.dart';
import 'device_card_scale.dart';
import 'glass_card.dart';
import 'heater_icon.dart';
import 'solid_arrow_icon.dart';

export 'solid_arrow_icon.dart';

/// How a control button shows its label inside the 56×56 tile.
enum DeviceControlLabelMode {
  /// Icon or arrow only; full name in tooltip/accessibility.
  iconOnly,
  /// Large number (fan %, stand 1, byte level).
  numeric,
  /// Icon with caption below — legacy, avoid for new controls.
  caption,
  /// Pick iconOnly / numeric / caption from content.
  auto,
}

/// Eén knop — gebruik voor alle apparaat-tegels.
class DeviceControlItem {
  const DeviceControlItem({
    this.icon,
    this.glyph,
    this.iconRotation = 0.0,
    this.arrow,
    required this.label,
    this.sublabel,
    this.active = false,
    this.onTap,
    this.labelMode = DeviceControlLabelMode.auto,
  });

  final IconData? icon;
  /// Custom icoon — bv. vlam met streep voor openhaard uit.
  final Widget? glyph;
  final double iconRotation;
  /// Pijl met lijn + solid driehoekpunt (zonwering, haard, …).
  final DeviceArrowDirection? arrow;
  final String label;
  final String? sublabel;
  final bool active;
  final VoidCallback? onTap;
  final DeviceControlLabelMode labelMode;

  bool get hasGlyph => glyph != null || icon != null || arrow != null;

  DeviceControlLabelMode get resolvedLabelMode {
    if (labelMode != DeviceControlLabelMode.auto) return labelMode;
    if (hasGlyph) return DeviceControlLabelMode.iconOnly;
    if (deviceControlNumericLabel(label) != null) {
      return DeviceControlLabelMode.numeric;
    }
    return DeviceControlLabelMode.caption;
  }

  String get tooltipText {
    if (label.isNotEmpty) return label;
    if (sublabel != null && sublabel!.isNotEmpty) return sublabel!;
    return 'Bediening';
  }
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
    this.columnsPerRow = 4,
  });

  final List<List<DeviceControlItem>> rows;
  final int columnsPerRow;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: DeviceControlBar.rowGap),
              _SquareControlRow(
                items: rows[i],
                columnCount: columnsPerRow,
                layoutContext: context,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SquareControlRow extends StatelessWidget {
  const _SquareControlRow({
    required this.items,
    required this.columnCount,
    required this.layoutContext,
  });
  final List<DeviceControlItem> items;
  final int columnCount;
  final BuildContext layoutContext;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cols = columnCount < 1 ? items.length : columnCount;
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          for (var j = 0; j < cols; j++) ...[
            if (j > 0) SizedBox(width: DeviceControlBar.gap),
            Expanded(
              child: j < items.length
                  ? _LabeledSquareButton(
                      item: items[j],
                      expand: true,
                      layoutContext: layoutContext,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Move- + tuimelrij — zelfde volle-breedte rijen als overal.
class _MoveAndTiltBlock extends StatelessWidget {
  const _MoveAndTiltBlock({
    required this.moveItems,
    required this.tiltItems,
    this.rowGap,
  });

  final List<DeviceControlItem> moveItems;
  final List<DeviceControlItem> tiltItems;
  final double? rowGap;

  @override
  Widget build(BuildContext context) {
    final gap = rowGap ?? DeviceControlBar.sectionSpacing(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SquareControlRow(
          items: moveItems,
          columnCount: moveItems.length,
          layoutContext: context,
        ),
        if (tiltItems.isNotEmpty) ...[
          SizedBox(height: gap),
          _SquareControlRow(
            items: tiltItems,
            columnCount: tiltItems.length,
            layoutContext: context,
          ),
        ],
      ],
    );
  }
}

class _LabeledSquareButton extends StatelessWidget {
  const _LabeledSquareButton({
    required this.item,
    this.expand = false,
    required this.layoutContext,
  });
  final DeviceControlItem item;
  final bool expand;
  final BuildContext layoutContext;

  @override
  Widget build(BuildContext context) {
    final mode = item.resolvedLabelMode;
    final disabled = item.onTap == null;
    final hasIcon = item.hasGlyph;
    final numeric = deviceControlNumericLabel(item.label);
    final btnSize = DeviceControlBar.buttonSizeFor(layoutContext);
    final glyphSize = DeviceControlBar.glyphSizeFor(layoutContext);

    Widget inner;
    switch (mode) {
      case DeviceControlLabelMode.iconOnly:
        inner = _DeviceControlGlyph(
          item: item.icon != null || item.arrow != null
              ? item
              : DeviceControlItem(
                  icon: deviceControlOptionIcon(label: item.label),
                  label: item.label,
                  active: item.active,
                  onTap: item.onTap,
                ),
          active: item.active,
          disabled: disabled,
          glyphSize: glyphSize,
        );
      case DeviceControlLabelMode.numeric:
        inner = Text(
          numeric ?? item.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: DeviceControlBar.numericFontSizeFor(
              layoutContext,
              numeric ?? item.label,
            ),
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: DeviceControlIcons.color(
              active: item.active,
              disabled: disabled,
            ),
          ),
        );
      case DeviceControlLabelMode.caption:
      case DeviceControlLabelMode.auto:
        inner = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasIcon) ...[
                _DeviceControlGlyph(
                  item: item.icon != null || item.arrow != null
                      ? item
                      : DeviceControlItem(
                          icon: deviceControlOptionIcon(label: item.label),
                          label: item.label,
                        ),
                  active: item.active,
                  disabled: disabled,
                  glyphSize: glyphSize,
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
        );
    }

    final button = _SizedControlSquare(
      onTap: item.onTap,
      active: item.active,
      expand: expand,
      height: btnSize,
      child: Center(child: inner),
    );

    return Tooltip(
      message: item.tooltipText,
      child: Semantics(
        label: item.tooltipText,
        button: true,
        enabled: !disabled,
        child: button,
      ),
    );
  }
}

class _DeviceControlGlyph extends StatelessWidget {
  const _DeviceControlGlyph({
    required this.item,
    required this.active,
    required this.disabled,
    this.glyphSize = DeviceControlIcons.size,
  });

  final DeviceControlItem item;
  final bool active;
  final bool disabled;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    final color = DeviceControlIcons.color(active: active, disabled: disabled);
    if (item.icon == heaterIconData) {
      return HeaterIcon(size: glyphSize, color: color);
    }
    if (item.glyph != null) {
      return Opacity(
        opacity: disabled ? 0.35 : 1,
        child: item.glyph!,
      );
    }
    if (item.arrow != null) {
      return SolidArrowIcon(direction: item.arrow!, color: color, size: glyphSize);
    }
    return Transform.rotate(
      angle: item.iconRotation,
      child: Icon(
        item.icon,
        size: glyphSize,
        color: color,
      ),
    );
  }
}

/// Square control with explicit size (responsive).
class _SizedControlSquare extends StatefulWidget {
  const _SizedControlSquare({
    required this.onTap,
    required this.active,
    required this.expand,
    required this.height,
    required this.child,
    this.width,
  });

  final VoidCallback? onTap;
  final bool active;
  final bool expand;
  final double height;
  final double? width;
  final Widget child;

  double get _width => width ?? height;

  @override
  State<_SizedControlSquare> createState() => _SizedControlSquareState();
}

class _SizedControlSquareState extends State<_SizedControlSquare> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final w = widget.expand ? double.infinity : widget._width;
    final surface = DeviceControlButtonSurface(
      active: widget.active,
      pressed: _pressed,
      width: w,
      height: widget.height,
      child: widget.child,
    );

    return SizedBox(
      width: w,
      height: widget.height,
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

/// Sectie-label + bediening — zelfde spacing op alle apparaat-tegels.
class DeviceControlSection extends StatelessWidget {
  const DeviceControlSection({
    super.key,
    required this.title,
    required this.child,
    this.enabled = true,
  });

  final String title;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: DeviceControlBar.sectionTitleStyle(context)),
          SizedBox(height: DeviceControlBar.sectionTitleGap),
          child,
        ],
      ),
    );
  }
}

/// Gedeelde temperatuur-regelaar (klimaat + airco).
class DeviceControlSetpointRow extends StatelessWidget {
  const DeviceControlSetpointRow({
    super.key,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    this.enabled = true,
    this.decimals = 1,
  });

  final double value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool enabled;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final btn = DeviceControlBar.buttonSizeFor(context);
    final displaySize = DeviceCardScale.setpointFontSize(context);

    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SetpointStepButton(
            icon: Icons.remove,
            width: DeviceCardScale.setpointStepButtonSize(context),
            height: btn,
            onTap: enabled ? onDecrease : null,
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${value.toStringAsFixed(decimals)}°',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w200,
                      fontSize: displaySize,
                      height: 1,
                    ),
              ),
            ),
          ),
          _SetpointStepButton(
            icon: Icons.add,
            width: DeviceCardScale.setpointStepButtonSize(context),
            height: btn,
            onTap: enabled ? onIncrease : null,
          ),
        ],
      ),
    );
  }
}

class _SetpointStepButton extends StatelessWidget {
  const _SetpointStepButton({
    required this.icon,
    required this.width,
    required this.height,
    this.onTap,
  });

  final IconData icon;
  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _SizedControlSquare(
      onTap: onTap,
      active: false,
      expand: false,
      width: width,
      height: height,
      child: Center(
        child: Icon(
          icon,
          size: DeviceControlBar.glyphSizeFor(context),
          color: DeviceControlIcons.color(disabled: onTap == null),
        ),
      ),
    );
  }
}

/// Uniforme padding en tussenruimte voor apparaat-tegels in kamers.
abstract final class DeviceTileLayout {
  static EdgeInsets padding(BuildContext context) =>
      DeviceCardScale.cardPadding(context);

  /// Ruimte tussen 56×56 header-icoon en titelkolom.
  static const double iconGap = 14.0;

  /// Verticale ruimte tussen apparaatnaam en statusregel.
  static const double titleStatusGap = 2.0;

  /// Iconen linksboven uitlijnen op alle apparaat-tegels.
  static const CrossAxisAlignment iconRowAlignment = CrossAxisAlignment.start;

  /// Responsive icoon-slot links — onderkanten lopen gelijk op alle tegels.
  static Widget statusIconSlot(
    BuildContext context, {
    required Widget child,
  }) =>
      SizedBox(
        width: DeviceCardScale.iconBadgeSize(context),
        height: DeviceCardScale.iconBadgeSize(context),
        child: child,
      );

  /// Standaard header: icoon · tekst · optionele actie rechts.
  static Widget headerRow({
    required BuildContext context,
    required Widget leading,
    required Widget content,
    Widget? trailing,
  }) =>
      Row(
        crossAxisAlignment: iconRowAlignment,
        children: [
          statusIconSlot(context, child: leading),
          const SizedBox(width: iconGap),
          Expanded(child: content),
          if (trailing != null) trailing,
        ],
      );

  /// Switch rechts, verticaal binnen de icon-hoogte (zelfde onderlijn).
  static Widget trailingSwitch({
    required BuildContext context,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      statusIconSlot(
        context,
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
  static const double gap = 8.0;
  static const double rowGap = 8.0;
  static const double sectionGap = 18.0;
  static const double sectionTitleGap = 10.0;

  /// Knopmaat — overal 56×56, gelijk aan audio.
  static double buttonSizeFor(BuildContext context) => buttonSize;

  static double glyphSizeFor(BuildContext context) =>
      DeviceCardScale.glyphSize(context);

  static double numericFontSizeFor(BuildContext context, String text) =>
      DeviceCardScale.numericFontSize(context, text);

  static double sectionSpacing(BuildContext context) =>
      DeviceCardScale.sectionSpacing(context);

  static TextStyle sectionTitleStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            color: LuxeColors.inkSoft,
          );

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

  /// 2 → 2 cols, 3 → 3, 4 → 4, 5 → 5 op telefoon — begrensd per form factor.
  static int autoPerRow(BuildContext context, int itemCount) {
    final cap = DeviceCardScale.maxGridColumns(context);
    final cols = switch (itemCount) {
      <= 1 => 1,
      2 => 2,
      3 => 3,
      4 => 4,
      5 => 5,
      6 => 3,
      _ => 4,
    };
    return cols > cap ? cap : cols;
  }

  static Widget build(
    BuildContext context, {
    required List<List<DeviceControlItem>> rows,
    int columnsPerRow = 4,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: DeviceControlPanel(
        rows: rows,
        columnsPerRow: columnsPerRow,
      ),
    );
  }

  static Widget singleRow(
    BuildContext context,
    List<DeviceControlItem> items,
  ) =>
      build(context, rows: [items]);

  static Widget tiltRow(
    BuildContext context,
    List<DeviceControlItem> items,
  ) =>
      build(context, rows: [items]);

  static Widget moveAndTiltBlock({
    required List<DeviceControlItem> moveItems,
    required List<DeviceControlItem> tiltItems,
    double? rowGap,
  }) =>
      SizedBox(
        width: double.infinity,
        child: _MoveAndTiltBlock(
          moveItems: moveItems,
          tiltItems: tiltItems,
          rowGap: rowGap,
        ),
      );

  static Widget gridAuto(
    BuildContext context,
    List<DeviceControlItem> items,
  ) {
    final perRow = autoPerRow(context, items.length);
    return grid(context, items, perRow: perRow);
  }

  static Widget grid(
    BuildContext context,
    List<DeviceControlItem> items, {
    int perRow = 4,
  }) =>
      build(
        context,
        rows: chunk(items, perRow: perRow),
        columnsPerRow: perRow,
      );
}
