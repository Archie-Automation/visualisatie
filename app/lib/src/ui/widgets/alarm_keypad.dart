import 'package:flutter/material.dart';

import '../../satel_api.dart';
import '../../theme.dart';

/// Zelfde codepaneel als het Satel-alarm: punten, toetsen, in- of uitschakelen.
class AlarmPinSection extends StatelessWidget {
  const AlarmPinSection({
    super.key,
    required this.pin,
    required this.busy,
    required this.feedback,
    required this.canConfirm,
    required this.onDigit,
    required this.onBackspace,
    required this.onConfirm,
    this.partition,
    this.arming,
  });

  final String pin;
  final bool busy;
  final String? feedback;
  final bool canConfirm;
  final SatelPartitionInfo? partition;

  /// Zet dit alleen als de knop niet uit de partitiestatus mag komen.
  final bool? arming;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final doArm = arming ??
        (partition == null ||
            partition!.isDisarmed ||
            partition!.isExitDelay);
    final label = doArm ? 'Inschakelen' : 'Uitschakelen';
    final color = doArm ? const Color(0xFFD64545) : const Color(0xFF4CAF50);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: LuxeColors.surfaceDim,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LuxeColors.line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pin.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AlarmNumPad(onDigit: onDigit, onBackspace: onBackspace),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: Material(
              color: canConfirm
                  ? color.withValues(alpha: 0.12)
                  : LuxeColors.surfaceDim,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: (busy || !canConfirm || onConfirm == null)
                    ? null
                    : onConfirm,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: canConfirm
                          ? color.withValues(alpha: 0.40)
                          : LuxeColors.line,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: color,
                          ),
                        )
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: canConfirm ? color : LuxeColors.inkFaint,
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (feedback != null) ...[
            const SizedBox(height: 10),
            Text(
              feedback!,
              style: const TextStyle(
                color: Color(0xFFD64545),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class AlarmNumPad extends StatelessWidget {
  const AlarmNumPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: row.map((key) {
              final isEmpty = key.isEmpty;
              final isBack = key == '⌫';
              return Expanded(
                child: isEmpty
                    ? const SizedBox()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _PadKey(
                          label: key,
                          isBackspace: isBack,
                          onTap: isBack ? onBackspace : () => onDigit(key),
                        ),
                      ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.isBackspace,
    required this.onTap,
  });

  final String label;
  final bool isBackspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LuxeColors.surfaceDim,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LuxeColors.line),
          ),
          alignment: Alignment.center,
          child: isBackspace
              ? Icon(Icons.backspace_outlined,
                  size: 20, color: LuxeColors.inkSoft)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: LuxeColors.ink,
                  ),
                ),
        ),
      ),
    );
  }
}
