import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/widgets/confirm_dialog.dart';
import '../ui/widgets/luxe_form.dart';
import 'installer_api.dart';
import 'installer_form_sections.dart';

const _processorLabels = {
  3: 'Druk (Press)',
  4: 'Loslaten (Release)',
  5: 'Lang vast (LongHold)',
  6: 'Dubbel (MultiTap)',
};

const _appLabels = {
  3: 'Korte druk',
  4: 'Loslaten',
  5: 'Vasthouden',
  6: 'Dubbele druk',
};

/// Live overzicht van wat een QSX-knop stuurt en wat de server ermee doet.
class LutronButtonMonitorCard extends StatefulWidget {
  const LutronButtonMonitorCard({
    super.key,
    required this.buttons,
    required this.getToken,
  });

  final List<LutronButtonInfo> buttons;
  final Future<String?> Function() getToken;

  @override
  State<LutronButtonMonitorCard> createState() =>
      _LutronButtonMonitorCardState();
}

class _LutronButtonMonitorCardState extends State<LutronButtonMonitorCard> {
  static const _pollEvery = Duration(milliseconds: 400);
  static const _autoOff = Duration(minutes: 15);
  static const _keep = 150;
  /// Hoger dan elk volgnummer: het eerste verzoek levert alleen de stand.
  static const _latestOnly = 2147483647;

  bool _on = false;
  int? _button;
  int _seq = _latestOnly;
  final List<LutronMonitorEvent> _events = [];
  Timer? _poll;
  Timer? _offTimer;
  bool _fetching = false;
  String? _error;

  @override
  void dispose() {
    _poll?.cancel();
    _offTimer?.cancel();
    super.dispose();
  }

  void _setOn(bool on) {
    _poll?.cancel();
    _offTimer?.cancel();
    setState(() {
      _on = on;
      _error = null;
    });
    if (!on) return;
    _seq = _latestOnly;
    _fetch();
    _poll = Timer.periodic(_pollEvery, (_) => _fetch());
    _offTimer = Timer(_autoOff, () {
      if (mounted) _setOn(false);
    });
  }

  Future<void> _fetch() async {
    if (_fetching || !mounted) return;
    _fetching = true;
    try {
      final token = await widget.getToken();
      if (!mounted || token == null || !_on) return;
      final result = await fetchInstallerLutronMonitor(token, since: _seq);
      if (!mounted || !_on) return;
      setState(() {
        final first = _seq == _latestOnly;
        _seq = result.seq;
        _error = null;
        if (first) return;
        _events.insertAll(0, result.events.reversed);
        if (_events.length > _keep) _events.removeRange(_keep, _events.length);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      _fetching = false;
    }
  }

  String _buttonLabel(int id) {
    for (final b in widget.buttons) {
      if (b.id == id) return lutronButtonChoiceLabel(b);
    }
    return '/button/$id';
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [
      for (final e in _events)
        if (_button == null || e.button == _button) e,
    ];
    final known = {for (final b in widget.buttons) b.id};
    final filter = _button != null && known.contains(_button) ? _button : null;

    return LuxeListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeSectionTitle(
            icon: Icons.monitor_heart_outlined,
            title: 'Knopmonitor',
            trailing: LuxeInfoIconButton(
              title: 'Knopmonitor',
              body: 'Kies een knop, zet de monitor aan en druk op de keypad.\n\n'
                  'Processor = wat de QSX stuurt. Komt hier niets binnen, dan '
                  'heeft de knop in Lutron Designer geen actie.\n\n'
                  'Server = hoe de app het leest: korte druk, loslaten, '
                  'vasthouden (na 0,6 s) of dubbele druk (binnen 0,45 s), met '
                  'de KNX-koppelingen die afgingen.\n\n'
                  'Bij een snelle tik stuurt de QSX vaak alleen Loslaten. De '
                  'server maakt daar zelf een korte druk van, of een dubbele '
                  'druk bij twee snelle tikken.\n\n'
                  'Heeft de knop een koppeling op dubbele druk, dan komt de '
                  'korte druk pas na 0,45 s. Zo gaat bij een dubbele druk niet '
                  'eerst ook de korte druk af.\n\n'
                  'De tijd achter een regel is het verschil met de vorige '
                  'regel van dezelfde knop. Na 15 minuten stopt de monitor.',
            ),
          ),
          const LuxeFieldLabel('Knop'),
          DropdownButtonFormField<int?>(
            key: ValueKey('monitor-$filter-${widget.buttons.length}'),
            initialValue: filter,
            isExpanded: true,
            decoration: luxeFilledDecoration(),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Alle knoppen'),
              ),
              for (final b in widget.buttons)
                DropdownMenuItem<int?>(
                  value: b.id,
                  child: Text(
                    lutronButtonChoiceLabel(b),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _button = v),
          ),
          const SizedBox(height: 8),
          LuxeSwitchRow(
            title: 'Monitor aan',
            subtitle: _on ? 'Druk nu op de knop.' : null,
            value: _on,
            onChanged: _setOn,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade700,
                ),
              ),
            ),
          if (_on || shown.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    shown.isEmpty
                        ? 'Nog niets ontvangen'
                        : '${shown.length} meldingen',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (_events.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_events.clear),
                    child: const Text('Wissen'),
                  ),
              ],
            ),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
              _MonitorRow(
                event: shown[i],
                previous: () {
                  for (var j = i + 1; j < shown.length; j++) {
                    if (shown[j].button == shown[i].button) return shown[j];
                  }
                  return null;
                }(),
                buttonLabel: _button == null ? _buttonLabel(shown[i].button) : null,
                time: _time(shown[i].at),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MonitorRow extends StatelessWidget {
  const _MonitorRow({
    required this.event,
    required this.previous,
    required this.buttonLabel,
    required this.time,
  });

  final LutronMonitorEvent event;
  final LutronMonitorEvent? previous;
  final String? buttonLabel;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final processor = event.fromProcessor;
    final what = (processor ? _processorLabels : _appLabels)[event.action] ??
        'Actie ${event.action}';
    final prev = previous;
    final delta = prev == null ? null : event.at.difference(prev.at).inMilliseconds;
    final detail = processor
        ? null
        : event.fired.isEmpty
            ? 'Geen koppeling'
            : event.fired.join('\n');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              time,
              style: small?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              processor ? 'Processor' : 'Server',
              style: small?.copyWith(
                color: processor ? LuxeColors.inkSoft : LuxeColors.brassOnCanvas,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  what,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: processor ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                if (buttonLabel != null)
                  Text(buttonLabel!, style: small),
                if (detail != null)
                  Text(
                    detail,
                    style: small?.copyWith(color: LuxeColors.inkSoft),
                  ),
                if (event.error != null)
                  Text(
                    event.error!,
                    style: small?.copyWith(color: Colors.red.shade700),
                  ),
              ],
            ),
          ),
          if (delta != null)
            Text(
              '+$delta ms',
              style: small?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
