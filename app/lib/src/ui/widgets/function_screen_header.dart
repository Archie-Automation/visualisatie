import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';
import 'back_pill.dart';

/// Pinned-style header for function/category screens — matches [RoomScreen] layout.
class FunctionScreenHeader extends StatelessWidget {
  const FunctionScreenHeader({
    super.key,
    required this.onBack,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final VoidCallback onBack;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    final backSize = isPhone ? 44.0 : 48.0;
    final titleFont = isPhone ? 18.0 : 20.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: LuxeColors.surface.withValues(alpha: 0.82),
          border: Border(
            bottom: BorderSide(
              color: LuxeColors.line.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
        ),
        height: context.roomStickyHeaderH,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(isPhone ? 8 : 12, 0, isPhone ? 8 : 12, 10),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: BackPill(onTap: onBack),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: backSize + 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        Text(
                          subtitle!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isPhone ? 10 : 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.9,
                            color: LuxeColors.inkSoft,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleFont,
                          fontWeight: FontWeight.w700,
                          color: LuxeColors.ink,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: trailing!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
