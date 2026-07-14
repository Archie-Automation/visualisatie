import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../camera_api.dart';
import '../intercom/intercom_sip_providers.dart';
import '../theme.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/intercom_player.dart';
import 'widgets/luxe_backdrop.dart';

class IntercomScreen extends ConsumerStatefulWidget {
  const IntercomScreen({super.key, required this.intercomId});
  final String intercomId;

  @override
  ConsumerState<IntercomScreen> createState() => _IntercomScreenState();
}

class _IntercomScreenState extends ConsumerState<IntercomScreen> {
  bool _talking = false;
  bool _releasing = false;
  String? _releaseFeedback;
  bool _sipUaStarted = false;
  bool _sipDiscoveryScheduled = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    // Answering an active ring dismisses the incoming-call overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ring = ref.read(intercomRingProvider);
      if (ring != null && ring.intercomId == widget.intercomId) {
        ref.read(intercomRingProvider.notifier).clear();
      }
    });
  }

  void _ensureSipUaFromConfig() {
    if (_sipUaStarted) return;
    final cfg = ref.read(configProvider).value;
    if (cfg == null) return;
    final device = cfg.deviceById(widget.intercomId);
    if (device == null) return;
    final ic = device.raw['intercom'];
    if (ic is! Map) return;
    final kind = ic['kind'] as String?;
    if (kind != 'sip') return;
    _sipUaStarted = true;
    ref.read(intercomSipControllerProvider).startFromHouseIntercom(
          intercomId: widget.intercomId,
          houseIntercom: Map<String, dynamic>.from(ic),
        );
  }

  Future<void> _release(IntercomInfo i) async {
    if (_releasing) return;

    // Surface an "are you sure?" prompt if the config requests one.
    final cfg = ref.read(configProvider).value;
    final device = cfg?.deviceById(i.id);
    final prompt = device?.confirm?.actions['release'];
    final ok = await maybeConfirm(context, prompt);
    if (!ok) return;

    setState(() {
      _releasing = true;
      _releaseFeedback = null;
    });
    try {
      final auth = ref.read(authProvider);
      await releaseIntercomDoor(intercomId: i.id, token: auth.token);
      if (!mounted) return;
      setState(() => _releaseFeedback = 'Deur geopend');
    } catch (e) {
      if (!mounted) return;
      setState(() => _releaseFeedback = 'Fout: $e');
    } finally {
      if (mounted) {
        setState(() => _releasing = false);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _releaseFeedback = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(intercomInfoProvider(widget.intercomId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: info.maybeWhen(
          data: (i) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('INTERCOM',
                  style: TextStyle(
                    color: LuxeColors.brass,
                    fontSize: 10,
                    letterSpacing: 2.6,
                    fontWeight: FontWeight.w600,
                  )),
              Text(i.name,
                  style: const TextStyle(
                    color: LuxeColors.ink,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                    fontSize: 18,
                  )),
            ],
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Sluiten',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: LuxeBackdrop(
        child: info.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: LuxeColors.brass),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Kan intercom niet laden:\n$e',
                  style: TextStyle(color: LuxeColors.inkSoft),
                  textAlign: TextAlign.center),
            ),
          ),
          data: (i) {
            if (!_sipDiscoveryScheduled) {
              _sipDiscoveryScheduled = true;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _ensureSipUaFromConfig());
            }
            return SafeArea(
              child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Hero(
                      tag: 'intercom-${i.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: LuxeShadows.darkLift,
                          ),
                          child: IntercomPlayer(
                            intercomId: i.id,
                            aspectRatio: i.aspectRatio,
                            talking: _talking,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_releaseFeedback != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: LuxeColors.brass.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(_releaseFeedback!,
                          style: const TextStyle(
                            color: LuxeColors.brassGlow,
                            letterSpacing: 2,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 24),
                        decoration: BoxDecoration(
                          color: LuxeColors.surface.withValues(alpha: 0.80),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(
                            color: LuxeColors.line,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ActionButton(
                              icon: Icons.call_end,
                              label: 'OPHANGEN',
                              color: LuxeColors.danger,
                              onTap: () => context.canPop()
                                  ? context.pop()
                                  : context.go('/'),
                            ),
                            _TalkButton(
                              active: _talking,
                              onChanged: (v) =>
                                  setState(() => _talking = v),
                            ),
                            if (i.canRelease)
                              _ActionButton(
                                icon: Icons.lock_open_outlined,
                                label: 'DEUR OPEN',
                                color: LuxeColors.brass,
                                loading: _releasing,
                                onTap: () => _release(i),
                              )
                            else
                              const SizedBox(width: 72),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            );
          },
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: loading ? null : onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(
                  color: color.withValues(alpha: 0.55), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: loading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: LuxeColors.ink),
                    ),
                  )
                : Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 12),
        Text(label,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 10,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

class _TalkButton extends StatelessWidget {
  const _TalkButton({required this.active, required this.onChanged});
  final bool active;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onLongPressStart: (_) => onChanged(true),
          onLongPressEnd: (_) => onChanged(false),
          onTap: () => onChanged(!active),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active
                  ? const LinearGradient(
                      colors: [LuxeColors.brassGlow, LuxeColors.brass],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: active ? null : LuxeColors.surfaceDim,
              border: Border.all(
                color: active
                    ? LuxeColors.brass
                    : LuxeColors.inkFaint,
                width: 1.6,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: LuxeColors.brass.withValues(alpha: 0.5),
                        blurRadius: 40,
                        spreadRadius: 4,
                      )
                    ]
                  : null,
            ),
            child: Icon(
              active ? Icons.mic : Icons.mic_none,
              color: active ? Colors.white : LuxeColors.ink,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          active ? 'SPREKEN…' : 'HOUD INGEDRUKT',
          style: TextStyle(
            color: LuxeColors.inkSoft,
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
