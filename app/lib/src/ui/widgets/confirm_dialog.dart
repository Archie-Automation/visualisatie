import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../theme.dart';

/// Show an "are you sure?" prompt. Returns `true` when the user confirms,
/// `false` when they cancel. If [prompt] is `null` the dialog is skipped
/// and the result is `true` (call-site keeps going).
///
/// When [prompt.pin] is set the dialog switches to PIN-entry mode.
Future<bool> maybeConfirm(BuildContext context, ConfirmPrompt? prompt) async {
  if (prompt == null) return true;
  if (prompt.pin != null) {
    return await _showPinDialog(context, prompt) ?? false;
  }
  return await _showSimpleDialog(context, prompt) ?? false;
}

/// Bevestiging voor omschakelen verwarmen ↔ koelen op thermostaten.
Future<bool?> showHvacSwitchConfirmDialog(
  BuildContext context, {
  required String target,
  required String notice,
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _LuxeDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DialogHeader(
            icon: Icons.warning_amber_rounded,
            title: 'Omschakelen naar $target',
          ),
          const SizedBox(height: 14),
          Text(
            'Weet u zeker dat u wilt omschakelen naar $target?\n\n$notice',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _CancelButton(onTap: () => Navigator.of(ctx).pop(false)),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.ink,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('OMSCHAKELEN'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ── Simple confirm ───────────────────────────────────────────────────────────

Future<bool?> _showSimpleDialog(
    BuildContext context, ConfirmPrompt prompt) async {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      final title = prompt.title ?? 'Bevestigen';
      final message =
          prompt.message ?? 'Weet u zeker dat u wilt doorgaan?';
      return _LuxeDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogHeader(icon: Icons.warning_amber_rounded, title: title),
            const SizedBox(height: 14),
            Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _CancelButton(onTap: () => Navigator.of(ctx).pop(false)),
                const SizedBox(width: 6),
                _ConfirmButton(onTap: () => Navigator.of(ctx).pop(true)),
              ],
            ),
          ],
        ),
      );
    },
  );
}

// ── PIN confirm ──────────────────────────────────────────────────────────────

Future<bool?> _showPinDialog(
    BuildContext context, ConfirmPrompt prompt) async {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    barrierDismissible: false,
    builder: (ctx) => _PinDialog(prompt: prompt),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.prompt});
  final ConfirmPrompt prompt;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_controller.text.length >= 4) return;
    setState(() {
      _wrong = false;
      _controller.text += d;
    });
    if (_controller.text.length == 4) _submit();
  }

  void _onDelete() {
    if (_controller.text.isEmpty) return;
    setState(() {
      _wrong = false;
      _controller.text =
          _controller.text.substring(0, _controller.text.length - 1);
    });
  }

  void _submit() {
    if (_controller.text == widget.prompt.pin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _wrong = true;
        _controller.text = '';
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entered = _controller.text.length;
    final title = widget.prompt.title ?? 'PIN-bevestiging';
    final message =
        widget.prompt.message ?? 'Voer de 4-cijferige PIN in om door te gaan.';

    return _LuxeDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogHeader(icon: Icons.lock_outline, title: title),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),

          // ── PIN dots ────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _wrong
                  ? const Color(0xFFFF4E4E).withValues(alpha: 0.08)
                  : LuxeColors.surfaceDim.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _wrong
                    ? const Color(0xFFFF4E4E).withValues(alpha: 0.45)
                    : LuxeColors.line,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < entered;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? (_wrong
                              ? const Color(0xFFFF4E4E)
                              : LuxeColors.brass)
                          : LuxeColors.line,
                    ),
                  ),
                );
              }),
            ),
          ),

          if (_wrong)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Onjuiste PIN, probeer opnieuw.',
                style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFFFF4E4E),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          const SizedBox(height: 20),

          // ── Numpad ──────────────────────────────────────────────────
          _PinNumpad(onDigit: _onDigit, onDelete: _onDelete),

          const SizedBox(height: 16),
          _CancelButton(onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}

// Numpad grid 1-9, *, 0, ⌫
class _PinNumpad extends StatelessWidget {
  const _PinNumpad({required this.onDigit, required this.onDelete});
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox.shrink();
        final isDelete = k == '⌫';
        return _NumpadKey(
          label: k,
          isDelete: isDelete,
          onTap: isDelete ? onDelete : () => onDigit(k),
        );
      }).toList(),
    );
  }
}

class _NumpadKey extends StatefulWidget {
  const _NumpadKey(
      {required this.label, required this.onTap, required this.isDelete});
  final String label;
  final VoidCallback onTap;
  final bool isDelete;

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _pressed
              ? LuxeColors.brass.withValues(alpha: 0.18)
              : LuxeColors.surfaceDim.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: LuxeColors.line),
        ),
        child: widget.isDelete
            ? Icon(Icons.backspace_outlined,
                size: 18, color: LuxeColors.inkSoft)
            : Text(
                widget.label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: LuxeColors.ink,
                ),
              ),
      ),
    );
  }
}

// ── Shared dialog shell ──────────────────────────────────────────────────────

/// Compact, centered luxury dialog — never stretches to full screen width.
class _LuxeDialog extends StatelessWidget {
  const _LuxeDialog({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: LuxeColors.surface,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: child,
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LuxeColors.brass.withValues(alpha: 0.14),
            border: Border.all(
              color: LuxeColors.brass.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(icon, color: LuxeColors.brass, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: LuxeColors.inkSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: const Text('Annuleren'),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: LuxeColors.ink,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.8,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: const Text('DOORGAAN'),
    );
  }
}
