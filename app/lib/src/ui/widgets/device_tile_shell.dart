import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';
import 'device_card_scale.dart';
import 'glass_card.dart';

/// GlassCard-shell voor alle apparaat-kaarten.
class DeviceTileShell extends StatelessWidget {
  const DeviceTileShell({
    super.key,
    required this.child,
    this.glow = false,
  });

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: DeviceCardScale.cardPadding(context),
      radius: 26,
      shadows: glow ? LuxeShadows.brassGlow : LuxeShadows.soft,
      child: child,
    );
  }
}

/// Lijst-wrapper — beperkt kaartbreedte op tablet/desktop.
class DeviceCardListItem extends StatelessWidget {
  const DeviceCardListItem({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxW = DeviceCardScale.listCardMaxWidth(context);
    if (maxW.isInfinite) return child;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}

/// Visueel zwaartepunt: groot setpoint, percentage, album preview, …
class DeviceCardHero extends StatelessWidget {
  const DeviceCardHero({
    super.key,
    required this.child,
    this.center = true,
  });

  final Widget child;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: DeviceCardScale.sectionSpacing(context) * 0.5,
        bottom: DeviceCardScale.sectionSpacing(context),
      ),
      child: center
          ? Center(child: child)
          : Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}

/// Bedieningszone — max-breedte op desktop.
class DeviceCardBody extends StatelessWidget {
  const DeviceCardBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxW = DeviceCardScale.controlMaxWidth(context);
    final content = maxW == null
        ? child
        : Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: child,
            ),
          );
    return SizedBox(width: double.infinity, child: content);
  }
}

/// Accent icon well (scene/system chips) — scherpe ondoorzichtige ring.
class LuxeAccentIconWell extends StatelessWidget {
  const LuxeAccentIconWell({
    super.key,
    required this.size,
    required this.radius,
    required this.accent,
    required this.child,
    this.rim = 1.25,
  });

  final double size;
  final double radius;
  final Color accent;
  final Widget child;
  final double rim;

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      accent.withValues(alpha: 0.22),
      LuxeColors.surface,
    );
    return LuxeRimBox(
      width: size,
      height: size,
      radius: radius,
      rimWidth: rim,
      rimColor: accent,
      fillColor: fill,
      child: Center(child: child),
    );
  }
}

/// Responsive 56×56 status-icoon linksboven.
///
/// Gouden/actieve rand via ondoorzichtige “ring” (outer fill + inner pad),
/// niet via semi-transparante [Border.all] — die wordt brokkelig op Impeller.
class DeviceTileIconBadge extends StatelessWidget {
  const DeviceTileIconBadge({
    super.key,
    this.icon,
    this.glyph,
    this.active = false,
    this.onTap,
  }) : assert(icon != null || glyph != null);

  final IconData? icon;
  final Widget? glyph;
  final bool active;
  final VoidCallback? onTap;

  static const double _rim = 1.5;

  @override
  Widget build(BuildContext context) {
    final size = DeviceCardScale.iconBadgeSize(context);
    final outerR = DeviceCardScale.iconRadius(context);
    final rimColor = active ? LuxeColors.brass : LuxeColors.line;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = active
        ? Color.alphaBlend(
            LuxeColors.brass.withValues(alpha: 0.14),
            LuxeColors.surface,
          )
        : Color.alphaBlend(
            LuxeColors.surfaceDim.withValues(alpha: isDark ? 0.7 : 0.45),
            LuxeColors.surface,
          );

    final badge = LuxeRimBox(
      width: size,
      height: size,
      radius: outerR,
      rimWidth: _rim,
      rimColor: rimColor,
      fillColor: fillColor,
      child: Center(
        child: glyph ??
            Icon(
              icon,
              color: active ? LuxeColors.brass : LuxeColors.ink,
              size: DeviceCardScale.glyphSize(context),
            ),
      ),
    );
    if (onTap == null) return badge;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(outerR),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(outerR),
        child: badge,
      ),
    );
  }
}

/// Grote hero-waarde (temperatuur, percentage, stand).
class DeviceCardHeroValue extends StatelessWidget {
  const DeviceCardHeroValue({
    super.key,
    required this.value,
    this.unit,
    this.subtitle,
  });

  final String value;
  final String? unit;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final size = DeviceCardScale.heroValueFontSize(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: size,
                    height: 1,
                  ),
            ),
            if (unit != null)
              Padding(
                padding: EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  unit!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: LuxeColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
          ],
        ),
        if (subtitle != null) ...[
          SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuxeColors.inkSoft,
                ),
          ),
        ],
      ],
    );
  }
}

/// Compacte statusrijen (WTW, meldingen).
class DeviceStatusList extends StatelessWidget {
  const DeviceStatusList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }
}

/// Slider binnen proportionele breedte op desktop.
class DeviceCardSliderWrap extends StatelessWidget {
  const DeviceCardSliderWrap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxW = DeviceCardScale.sliderMaxWidth(context);
    if (maxW.isInfinite) return child;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}

/// Desktop split: hero links, bediening rechts.
class DeviceCardSplitRow extends StatelessWidget {
  const DeviceCardSplitRow({
    super.key,
    required this.primary,
    required this.secondary,
  });

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    if (context.isPhone || context.isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          SizedBox(height: DeviceCardScale.sectionSpacing(context)),
          secondary,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: primary),
        SizedBox(width: DeviceCardScale.sectionSpacing(context)),
        Expanded(flex: 3, child: secondary),
      ],
    );
  }
}
