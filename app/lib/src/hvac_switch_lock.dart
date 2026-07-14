import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Vergrendelduur na omschakelen verwarm/koel (formaat `u:mm`, bijv. `4:00`).
class HvacSwitchLockDuration {
  const HvacSwitchLockDuration({required this.hours, required this.minutes});

  final int hours;
  final int minutes;

  bool get hasLock => hours > 0 || minutes > 0;

  Duration get duration => Duration(hours: hours, minutes: minutes);

  /// Lees uit `climate.hvacSwitchLockDuration` in house.json.
  static HvacSwitchLockDuration fromClimateConfig(Map<String, dynamic>? climate) {
    final raw = climate?['hvacSwitchLockDuration'];
    if (raw is! String || raw.trim().isEmpty) {
      return const HvacSwitchLockDuration(hours: 0, minutes: 0);
    }
    return parse(raw);
  }

  static HvacSwitchLockDuration parse(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 2) {
      return const HvacSwitchLockDuration(hours: 0, minutes: 0);
    }
    final h = int.tryParse(parts[0].trim()) ?? 0;
    final m = int.tryParse(parts[1].trim()) ?? 0;
    return HvacSwitchLockDuration(
      hours: h.clamp(0, 99),
      minutes: m.clamp(0, 59),
    );
  }

  String toConfigValue() =>
      '${hours.toString()}:${minutes.toString().padLeft(2, '0')}';

  /// Tekst voor de bevestigingsdialoog ("4 uur", "2 uur en 30 minuten", …).
  String formatForDialog() {
    if (!hasLock) return '';
    if (hours > 0 && minutes > 0) {
      return '$hours uur en $minutes minuten';
    }
    if (hours > 0) {
      return hours == 1 ? '1 uur' : '$hours uur';
    }
    return minutes == 1 ? '1 minuut' : '$minutes minuten';
  }
}

/// Server-gesynchroniseerde HVAC-vergrendeling per apparaat (epoch ms).
class HvacLockStore extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void snapshot(List<Map<String, dynamic>> locks) {
    state = {
      for (final e in locks)
        e['deviceId'] as String: (e['untilMs'] as num).toInt(),
    };
  }

  void applyLock(String deviceId, int untilMs) {
    state = {...state, deviceId: untilMs};
  }

  void pruneExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = Map<String, int>.from(state)
      ..removeWhere((_, untilMs) => untilMs <= now);
    if (next.length != state.length) state = next;
  }

  DateTime? lockUntil(String deviceId) {
    final ms = state[deviceId];
    if (ms == null || ms <= DateTime.now().millisecondsSinceEpoch) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Minuten voor weergave: deels minute telt als volle minuut (2:59 → 3 min).
  static int _displayMinutes(int totalSeconds) =>
      (totalSeconds + 59) ~/ 60;

  static String formatRemaining(Duration remaining) {
    if (remaining.isNegative) return '';
    // Naar boven op hele seconden — geen vroeg aftellen door truncatie.
    final total = (remaining.inMicroseconds + 999999) ~/ 1000000;
    if (total <= 0) return '';

    final h = total ~/ 3600;
    final secInHour = total % 3600;

    if (h > 0) {
      final m = secInHour ~/ 60;
      if (m > 0) return 'nog $h u $m min';
      return h == 1 ? 'nog 1 uur' : 'nog $h uur';
    }

    // > 60 s: volle minuten naar boven (180 s → 3 min, 179 s → 3 min, 120 s → 2 min).
    // ≤ 60 s: per seconde (geen "1 minuut" die ~60 s blijft staan).
    if (total > 60) {
      return 'nog ${_displayMinutes(total)} min';
    }
    return total == 1 ? 'nog 1 sec' : 'nog $total sec';
  }
}

final hvacLockProvider =
    NotifierProvider<HvacLockStore, Map<String, int>>(HvacLockStore.new);
