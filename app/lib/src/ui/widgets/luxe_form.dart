import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'glass_card.dart';

/// Compact toggle, same as tijdschema / account (not the Material yellow pill).
class LuxeOnOffSwitch extends StatelessWidget {
  const LuxeOnOffSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: LuxeColors.brass,
    );
  }
}

/// Filled soft box used by Settings and Technische configuratie.
InputDecoration luxeFilledDecoration({
  String? hint,
  String? helper,
  Widget? suffixIcon,
  int helperMaxLines = 2,
}) =>
    InputDecoration(
      hintText: hint,
      helperText: helper,
      helperMaxLines: helperMaxLines,
      suffixIcon: suffixIcon,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: LuxeColors.surface.withValues(alpha: 0.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: LuxeColors.line),
      ),
    );

class LuxeFieldLabel extends StatelessWidget {
  const LuxeFieldLabel(this.label, {super.key, this.tooltip});
  final String label;
  /// Hover (desktop) / long-press (touch) uitleg in gewone taal.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tip = tooltip?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (tip != null && tip.isNotEmpty) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: tip,
              waitDuration: const Duration(milliseconds: 250),
              child: Icon(
                Icons.help_outline,
                size: 16,
                color: LuxeColors.inkFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact brass switch on the right — same as tijdschema / account.
class LuxeSwitchRow extends StatelessWidget {
  const LuxeSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          LuxeOnOffSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class LuxeNavRow extends StatelessWidget {
  const LuxeNavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ColoredBox(
        color: selected
            ? LuxeColors.brass.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          child: Row(
            children: [
              Icon(icon, color: LuxeColors.ink, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: LuxeColors.inkSoft,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class LuxeAddRow extends StatelessWidget {
  const LuxeAddRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 20, color: LuxeColors.brassDeep),
            const SizedBox(width: 10),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class LuxeListCard extends StatelessWidget {
  const LuxeListCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 5, 22, 9),
      child: GlassCard(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 14, 12),
        radius: 18,
        child: child,
      ),
    );
  }
}

/// Section header matching Settings: icon + small-caps title + optional hint.
class LuxeSectionTitle extends StatelessWidget {
  const LuxeSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: LuxeColors.ink, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: LuxeColors.inkSoft,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Nested editor block (WTW-knop, AC-modus) — same glass as Settings rows.
class LuxeInsetCard extends StatelessWidget {
  const LuxeInsetCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 14,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        shadows: const [],
        child: child,
      ),
    );
  }
}
