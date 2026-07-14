/// Full-screen PIN overlay that fires automatically when the Satel partition
/// enters "Entry_Delay" (inlooptijd). The user must enter their code to disarm
/// before the delay runs out. The overlay dismisses itself as soon as the
/// state returns to "Disarmed".
///
/// Usage (wrap the navigator child in app.dart):
///   builder: (context, child) => SatelEntryDelayLayer(child: child!),
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../satel_api.dart';
import '../../theme.dart';
import '_satel_beep_stub.dart'
    if (dart.library.html) '_satel_beep_web.dart';

class SatelEntryDelayLayer extends ConsumerStatefulWidget {
  const SatelEntryDelayLayer({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SatelEntryDelayLayer> createState() =>
      _SatelEntryDelayLayerState();
}

class _SatelEntryDelayLayerState extends ConsumerState<SatelEntryDelayLayer>
    with TickerProviderStateMixin {
  bool _overlayVisible = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  Timer? _beepTimer;
  SatelPartitionState? _lastState;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _beepTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  void _syncState(SatelStatus status) {
    final worst = status.worstState;
    if (worst == _lastState) return;
    _lastState = worst;

    // Overlay ─────────────────────────────────────────────────────────────
    final shouldShow = worst == SatelPartitionState.entryDelay;
    if (shouldShow && !_overlayVisible) {
      setState(() => _overlayVisible = true);
      _animCtrl.forward();
      HapticFeedback.heavyImpact();
    } else if (!shouldShow && _overlayVisible) {
      _animCtrl.reverse().then((_) {
        if (mounted) setState(() => _overlayVisible = false);
      });
    }

    // Beep ────────────────────────────────────────────────────────────────
    _beepTimer?.cancel();
    _beepTimer = null;

    switch (worst) {
      case SatelPartitionState.entryDelay:
        // Satel entry-delay pattern: urgent "bi-bi" double-beep every second.
        beepDouble(frequency: 1100, durationSec: 0.08);
        _beepTimer = Timer.periodic(
          const Duration(milliseconds: 1000),
          (_) => beepDouble(frequency: 1100, durationSec: 0.08),
        );
      case SatelPartitionState.exitDelay:
        // Satel exit-delay pattern: single short beep once per second.
        beepOnce(frequency: 900, durationSec: 0.10);
        _beepTimer = Timer.periodic(
          const Duration(milliseconds: 1000),
          (_) => beepOnce(frequency: 900, durationSec: 0.10),
        );
      default:
        break; // no beep when armed / disarmed
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SatelStatus>(satelStatusProvider, (_, next) {
      _syncState(next);
    });

    final status = ref.watch(satelStatusProvider);

    return Stack(
      children: [
        widget.child,
        if (_overlayVisible)
          FadeTransition(
            opacity: _fadeAnim,
            child: _EntryDelayOverlay(
              status: status,
              // The overlay itself cannot be popped — it auto-dismisses on disarm.
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay contents
// ---------------------------------------------------------------------------

class _EntryDelayOverlay extends ConsumerStatefulWidget {
  const _EntryDelayOverlay({required this.status});
  final SatelStatus status;

  @override
  ConsumerState<_EntryDelayOverlay> createState() =>
      _EntryDelayOverlayState();
}

class _EntryDelayOverlayState extends ConsumerState<_EntryDelayOverlay>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  String? _error;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _disarm() async {
    setState(() { _busy = true; _error = null; });
    final token  = ref.read(authProvider).token;
    final status = ref.read(satelStatusProvider);
    final target = status.partitions
        .where((p) => p.isEntryDelay)
        .map((p) => p.number)
        .firstOrNull ?? 1;
    final result = await satelDisarm(target, token: token);
    if (!mounted) return;
    setState(() { _busy = false; });
    if (!result.ok) {
      setState(() => _error = result.error ?? 'Uitschakelen mislukt.');
      HapticFeedback.heavyImpact();
    }
    // On success the status provider flips to Disarmed and the layer
    // auto-dismisses this overlay.
  }

  @override
  Widget build(BuildContext context) {
    final status   = ref.watch(satelStatusProvider);
    final violated = status.allZones.where((z) => z.violated).toList();

    return Material(
      color: Colors.transparent,
      child: Container(
        color: const Color(0xE8181820),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Pulsing warning icon ─────────────────────────────
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      const Color(0xFFD64545).withValues(alpha: 0.15),
                      const Color(0xFFD64545).withValues(alpha: 0.30),
                      _pulse.value,
                    ),
                    border: Border.all(
                      color: Color.lerp(
                        const Color(0xFFD64545).withValues(alpha: 0.40),
                        const Color(0xFFD64545).withValues(alpha: 0.80),
                        _pulse.value,
                      )!,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFD64545),
                    size: 40,
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'INLOOPTIJD',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.0,
                  color: Color(0xFFD64545),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Druk op Uitschakelen om het\nalarm te stoppen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),

              // Violated zones hint
              if (violated.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: violated.take(4).map((z) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD64545).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFD64545).withValues(alpha: 0.30),
                            width: 0.5),
                      ),
                      child: Text(
                        z.name,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFD64545),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 40),

              // ── Single disarm button ─────────────────────────────
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.20),
                      foregroundColor: const Color(0xFF4CAF50),
                      side: const BorderSide(
                        color: Color(0xFF4CAF50),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      elevation: 0,
                    ),
                    onPressed: _busy ? null : _disarm,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF4CAF50),
                            ),
                          )
                        : const Icon(Icons.lock_open_outlined, size: 22),
                    label: const Text(
                      'Uitschakelen',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFD64545),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

