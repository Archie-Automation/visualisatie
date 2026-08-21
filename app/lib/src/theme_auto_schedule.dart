import 'dart:convert';

import 'package:dart_suncalc/suncalc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

const _kPrefsKey = 'luxe_theme_auto_schedule_v1';

const kThemeLightOnId = '__theme_light_on__';
const kThemeLightOffId = '__theme_light_off__';

const _fallbackOn = '07:00';
const _fallbackOff = '21:00';
const _fallbackStartHour = 7;
const _fallbackEndHour = 21;

bool isThemeScheduleId(String id) =>
    id == kThemeLightOnId || id == kThemeLightOffId;

/// Non-deletable day/night window for Auto theme.
/// Shown as two rows in TIJDSCHEMA'S when Auto is selected.
class ThemeAutoSchedule {
  const ThemeAutoSchedule({
    this.lightOnName = 'Weergave · Licht',
    this.lightOffName = 'Weergave · Donker',
    this.lightOnEnabled = true,
    this.lightOffEnabled = true,
    this.lightOn = const AstroTrigger(
      event: AstroEvent.sunrise,
      days: kAllDays,
    ),
    this.lightOff = const AstroTrigger(
      event: AstroEvent.sunset,
      days: kAllDays,
    ),
  });

  final String lightOnName;
  final String lightOffName;
  final bool lightOnEnabled;
  final bool lightOffEnabled;
  final ScheduleTrigger lightOn;
  final ScheduleTrigger lightOff;

  static const defaults = ThemeAutoSchedule();

  ThemeAutoSchedule copyWith({
    String? lightOnName,
    String? lightOffName,
    bool? lightOnEnabled,
    bool? lightOffEnabled,
    ScheduleTrigger? lightOn,
    ScheduleTrigger? lightOff,
  }) =>
      ThemeAutoSchedule(
        lightOnName: lightOnName ?? this.lightOnName,
        lightOffName: lightOffName ?? this.lightOffName,
        lightOnEnabled: lightOnEnabled ?? this.lightOnEnabled,
        lightOffEnabled: lightOffEnabled ?? this.lightOffEnabled,
        lightOn: lightOn ?? this.lightOn,
        lightOff: lightOff ?? this.lightOff,
      );

  List<Schedule> asSchedules() => [
        Schedule(
          id: kThemeLightOnId,
          name: lightOnName,
          enabled: lightOnEnabled,
          trigger: lightOn,
          action: const ScheduleThemeAction(toLight: true),
        ),
        Schedule(
          id: kThemeLightOffId,
          name: lightOffName,
          enabled: lightOffEnabled,
          trigger: lightOff,
          action: const ScheduleThemeAction(toLight: false),
        ),
      ];

  /// Merge edits from editor/list (only theme ids are read).
  ThemeAutoSchedule mergeFromSchedules(Iterable<Schedule> schedules) {
    var next = this;
    for (final s in schedules) {
      if (s.id == kThemeLightOnId) {
        next = next.copyWith(
          lightOnName: s.name,
          lightOnEnabled: s.enabled,
          lightOn: s.trigger,
        );
      } else if (s.id == kThemeLightOffId) {
        next = next.copyWith(
          lightOffName: s.name,
          lightOffEnabled: s.enabled,
          lightOff: s.trigger,
        );
      }
    }
    return next;
  }

  Map<String, dynamic> toJson() => {
        'lightOnName': lightOnName,
        'lightOffName': lightOffName,
        'lightOnEnabled': lightOnEnabled,
        'lightOffEnabled': lightOffEnabled,
        'lightOn': lightOn.toJson(),
        'lightOff': lightOff.toJson(),
      };

  static ThemeAutoSchedule fromJson(Map<String, dynamic> j) {
    // Legacy edge format (kind time|astro without full trigger).
    if (j['lightOn'] is Map &&
        (j['lightOn'] as Map)['days'] == null &&
        ((j['lightOn'] as Map)['kind'] == 'time' ||
            (j['lightOn'] as Map)['kind'] == 'astro')) {
      return ThemeAutoSchedule(
        lightOn: _legacyEdgeToTrigger(j['lightOn'] as Map<String, dynamic>,
            fallbackEvent: AstroEvent.sunrise, fallbackTime: _fallbackOn),
        lightOff: _legacyEdgeToTrigger(j['lightOff'] as Map<String, dynamic>?,
            fallbackEvent: AstroEvent.sunset, fallbackTime: _fallbackOff),
      );
    }
    return ThemeAutoSchedule(
      lightOnName: (j['lightOnName'] as String?) ?? 'Weergave · Licht',
      lightOffName: (j['lightOffName'] as String?) ?? 'Weergave · Donker',
      lightOnEnabled: j['lightOnEnabled'] as bool? ?? true,
      lightOffEnabled: j['lightOffEnabled'] as bool? ?? true,
      lightOn: j['lightOn'] is Map
          ? ScheduleTrigger.fromJson(
              Map<String, dynamic>.from(j['lightOn'] as Map),
            )
          : const AstroTrigger(event: AstroEvent.sunrise, days: kAllDays),
      lightOff: j['lightOff'] is Map
          ? ScheduleTrigger.fromJson(
              Map<String, dynamic>.from(j['lightOff'] as Map),
            )
          : const AstroTrigger(event: AstroEvent.sunset, days: kAllDays),
    );
  }
}

ScheduleTrigger _legacyEdgeToTrigger(
  Map<String, dynamic>? j, {
  required AstroEvent fallbackEvent,
  required String fallbackTime,
}) {
  if (j == null) {
    return AstroTrigger(event: fallbackEvent, days: kAllDays);
  }
  final kind = j['kind'] as String?;
  if (kind == 'time') {
    return TimeTrigger(
      time: (j['time'] as String?) ?? fallbackTime,
      days: List<bool>.from(kAllDays),
    );
  }
  return AstroTrigger(
    event: AstroEvent.fromJson((j['event'] as String?) ?? fallbackEvent.toJson()),
    offsetMin: (j['offsetMin'] as num?)?.toInt() ?? 0,
    days: List<bool>.from(kAllDays),
  );
}

class ThemeAutoScheduleController extends Notifier<ThemeAutoSchedule> {
  @override
  ThemeAutoSchedule build() {
    Future.microtask(_restore);
    return ThemeAutoSchedule.defaults;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      state = ThemeAutoSchedule.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {}
  }

  Future<void> save(ThemeAutoSchedule next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(next.toJson()));
  }
}

final themeAutoScheduleProvider =
    NotifierProvider<ThemeAutoScheduleController, ThemeAutoSchedule>(
  ThemeAutoScheduleController.new,
);

class ProjectGeo {
  const ProjectGeo({required this.lat, required this.lon});
  final double lat;
  final double lon;
}

final projectGeoProvider = Provider<ProjectGeo?>((ref) {
  final cfg = ref.watch(configProvider).maybeWhen(
        data: (c) => c,
        orElse: () => null,
      );
  final lat = cfg?.locationLat;
  final lon = cfg?.locationLon;
  if (lat == null || lon == null) return null;
  return ProjectGeo(lat: lat, lon: lon);
});

DateTime? resolveThemeTriggerTime({
  required ScheduleTrigger trigger,
  required DateTime dayLocal,
  ProjectGeo? geo,
}) {
  DateTime? t;
  if (trigger is TimeTrigger) {
    t = _atLocalClock(dayLocal, trigger.time);
  } else if (trigger is AstroTrigger) {
    t = _sunEventLocal(dayLocal, trigger.event, geo);
    if (t != null) {
      t = t.add(Duration(minutes: trigger.offsetMin));
      final lower = trigger.notBefore == null
          ? null
          : _resolveGuard(trigger.notBefore!, dayLocal, geo);
      final upper = trigger.notAfter == null
          ? null
          : _resolveGuard(trigger.notAfter!, dayLocal, geo);
      if (lower != null && t.isBefore(lower)) t = lower;
      if (upper != null && t.isAfter(upper)) return null;
    }
  }
  return t;
}

DateTime? _resolveGuard(ScheduleGuard g, DateTime dayLocal, ProjectGeo? geo) {
  if (g is TimeGuard) return _atLocalClock(dayLocal, g.time);
  if (g is AstroGuard) {
    final base = _sunEventLocal(dayLocal, g.event, geo);
    if (base == null) return null;
    return base.add(Duration(minutes: g.offsetMin));
  }
  return null;
}

DateTime? _sunEventLocal(DateTime dayLocal, AstroEvent event, ProjectGeo? geo) {
  if (geo == null) {
    final fallback =
        event == AstroEvent.sunrise ? _fallbackOn : _fallbackOff;
    return _atLocalClock(dayLocal, fallback);
  }
  final probe = DateTime(dayLocal.year, dayLocal.month, dayLocal.day, 12);
  final times = SunCalc.getTimes(probe, lat: geo.lat, lng: geo.lon);
  final raw = event == AstroEvent.sunrise ? times.sunrise : times.sunset;
  return raw?.toLocal();
}

bool _weekdayAllowed(WeekdayMask days, DateTime local) {
  // Mon=0 .. Sun=6 (DateTime.weekday is Mon=1 .. Sun=7).
  final idx = local.weekday - 1;
  if (idx < 0 || idx >= days.length) return true;
  return days[idx];
}

/// Whether Auto should use light theme for [now] under [schedule].
bool isThemeLightForSchedule({
  required ThemeAutoSchedule schedule,
  required DateTime now,
  ProjectGeo? geo,
}) {
  final day = DateTime(now.year, now.month, now.day);
  final onTrigger = schedule.lightOnEnabled ? schedule.lightOn : null;
  final offTrigger = schedule.lightOffEnabled ? schedule.lightOff : null;

  if (onTrigger != null && !_weekdayAllowed(onTrigger.days, now)) {
    // Outside configured weekdays → dark unless overnight from previous day
    // with shared mask; keep simple: dark.
    return false;
  }

  final on = onTrigger == null
      ? _atLocalClock(day, _fallbackOn)
      : resolveThemeTriggerTime(
          trigger: onTrigger, dayLocal: day, geo: geo);
  final off = offTrigger == null
      ? _atLocalClock(day, _fallbackOff)
      : resolveThemeTriggerTime(
          trigger: offTrigger, dayLocal: day, geo: geo);

  if (on == null || off == null) {
    final hour = now.hour;
    return hour >= _fallbackStartHour && hour < _fallbackEndHour;
  }

  if (!off.isBefore(on)) {
    return !now.isBefore(on) && now.isBefore(off);
  }
  return !now.isBefore(on) || now.isBefore(off);
}

DateTime? _atLocalClock(DateTime dayLocal, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return DateTime(dayLocal.year, dayLocal.month, dayLocal.day, h, m);
}
