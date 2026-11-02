import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../energy_state.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'responsive.dart';
import 'widgets/function_screen_header.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';

class EnergyScreen extends ConsumerWidget {
  const EnergyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final snap = ref.watch(energyStateProvider);
    final enabled = cfg.maybeWhen(
      data: (c) => c.energyEnabled,
      orElse: () => snap.enabled,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: Column(
          children: [
            FunctionScreenHeader(
              onBack: () => appBack(context),
              title: 'Energie',
              subtitle: 'Live',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  context.hPad,
                  8,
                  context.hPad,
                  28,
                ),
                children: [
                  if (!enabled)
                    const _Note(
                      'Energie staat uit. De installateur zet dit aan onder '
                      'Technische configuratie → Energie.',
                    )
                  else ...[
                    if (snap.stale)
                      _Note(
                        snap.hasAnyValue
                            ? 'Geen KNX-verbinding. Dit zijn de laatste waarden.'
                            : 'Geen KNX-verbinding.',
                      ),
                    if (!snap.stale && !snap.hasAnyValue)
                      const _Note(
                        'Wachten op de KNX-bus. Een ontbrekend telegram blijft '
                        'leeg en wordt niet als 0 W getoond.',
                      ),
                    if (snap.gridPowerW != null ||
                        snap.solarPowerW != null ||
                        snap.batteryPowerW != null ||
                        snap.batterySoc != null ||
                        snap.housePowerW != null)
                      _PowerBlock(snap: snap),
                    if (snap.importEnergyKwh != null ||
                        snap.exportEnergyKwh != null ||
                        snap.solarEnergyKwh != null ||
                        snap.gasM3 != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        'STANDEN',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.9,
                          fontWeight: FontWeight.w600,
                          color: LuxeColors.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tellerstand, nog niet het verbruik van vandaag.',
                        style: TextStyle(
                          fontSize: 13,
                          color: LuxeColors.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MeterWrap(snap: snap),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerBlock extends StatelessWidget {
  const _PowerBlock({required this.snap});
  final EnergySnapshot snap;

  @override
  Widget build(BuildContext context) {
    final waitingForRest =
        snap.housePowerW == null &&
        (snap.gridPowerW != null ||
            snap.solarPowerW != null ||
            snap.batteryPowerW != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricWrap(
          children: [
            if (snap.gridPowerW != null)
              _Metric(
                icon: Icons.electrical_services_outlined,
                label: 'Net',
                value: formatPower(snap.gridPowerW!),
                caption: _gridCaption(snap.gridPowerW!),
              ),
            _Metric(
              icon: Icons.home_outlined,
              label: 'Woning',
              value: snap.housePowerW == null
                  ? '—'
                  : formatPower(snap.housePowerW!),
              caption: snap.housePowerW == null ? 'wacht op meting' : 'verbruik',
            ),
            if (snap.solarPowerW != null)
              _Metric(
                icon: Icons.solar_power_outlined,
                label: 'PV',
                value: formatPower(snap.solarPowerW!),
                caption: 'productie',
              ),
            if (snap.batteryPowerW != null || snap.batterySoc != null)
              _Metric(
                icon: Icons.battery_charging_full_outlined,
                label: 'Accu',
                value: snap.batteryPowerW == null
                    ? (snap.batterySoc == null ? '—' : formatSoc(snap.batterySoc!))
                    : formatPower(snap.batteryPowerW!),
                caption: _batteryCaption(snap),
              ),
          ],
        ),
        if (waitingForRest) ...[
          const SizedBox(height: 8),
          Text(
            'Woningverbruik wacht tot elk gekoppeld vermogen binnen is.',
            style: TextStyle(fontSize: 13, color: LuxeColors.inkFaint),
          ),
        ],
      ],
    );
  }
}

String _gridCaption(double watts) {
  if (watts.abs() < 30) return 'in balans';
  return watts < 0 ? 'teruglevering' : 'afname';
}

String _batteryCaption(EnergySnapshot snap) {
  final parts = <String>[];
  final power = snap.batteryPowerW;
  if (power != null) {
    if (power.abs() < 30) {
      parts.add('stil');
    } else {
      parts.add(power < 0 ? 'laden' : 'ontladen');
    }
  }
  if (snap.batterySoc != null) parts.add(formatSoc(snap.batterySoc!));
  return parts.isEmpty ? 'accu' : parts.join(' · ');
}

class _MeterWrap extends StatelessWidget {
  const _MeterWrap({required this.snap});
  final EnergySnapshot snap;

  @override
  Widget build(BuildContext context) {
    return _MetricWrap(
      children: [
        if (snap.importEnergyKwh != null)
          _Metric(
            icon: Icons.south_west_outlined,
            label: 'Afname',
            value: formatKwh(snap.importEnergyKwh!),
            caption: 'stand',
          ),
        if (snap.exportEnergyKwh != null)
          _Metric(
            icon: Icons.north_east_outlined,
            label: 'Teruglevering',
            value: formatKwh(snap.exportEnergyKwh!),
            caption: 'stand',
          ),
        if (snap.solarEnergyKwh != null)
          _Metric(
            icon: Icons.solar_power_outlined,
            label: 'PV',
            value: formatKwh(snap.solarEnergyKwh!),
            caption: 'stand',
          ),
        if (snap.gasM3 != null)
          _Metric(
            icon: Icons.local_fire_department_outlined,
            label: 'Gas',
            value: formatGas(snap.gasM3!),
            caption: 'stand',
          ),
      ],
    );
  }
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = !context.isPhone;
    if (!wide) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final w = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: LuxeColors.brass, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w600,
                    color: LuxeColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: LuxeColors.ink,
                    height: 1.15,
                  ),
                ),
                Text(
                  caption,
                  style: TextStyle(fontSize: 13, color: LuxeColors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, height: 1.35, color: LuxeColors.inkSoft),
      ),
    );
  }
}
