import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_auto_schedule.dart';

const _kThemeMode = 'luxe_theme_mode';

/// Android wall-panel APK (not iPhone/web). Auto theme uses schedule, not OS.
bool get isWallTabletThemeTarget =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Legacy fixed-hour fallback when schedule/astro cannot be resolved.
const autoLightStartHour = 7;
const autoLightEndHour = 21;

/// Maps a stored preference to the [ThemeMode] MaterialApp should use.
ThemeMode resolveEffectiveThemeMode(
  ThemeMode preferred, {
  DateTime? now,
  ThemeAutoSchedule? schedule,
  ProjectGeo? geo,
}) {
  if (preferred != ThemeMode.system) return preferred;
  // Phone / web: follow OS appearance.
  if (!isWallTabletThemeTarget) return ThemeMode.system;
  final sched = schedule ?? ThemeAutoSchedule.defaults;
  final light = isThemeLightForSchedule(
    schedule: sched,
    now: now ?? DateTime.now(),
    geo: geo,
  );
  return light ? ThemeMode.light : ThemeMode.dark;
}

/// Persisted appearance preference: light / dark / system (= Automatisch).
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    Future.microtask(_restore);
    // Soft default: dark is easier on the eyes for always-on tablets.
    return ThemeMode.dark;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeMode);
    if (raw == 'light') {
      state = ThemeMode.light;
    } else if (raw == 'dark') {
      state = ThemeMode.dark;
    } else if (raw == 'system' || raw == 'auto') {
      state = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_kThemeMode, raw);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Ticks once per minute on wall tablet when Automático is selected,
/// so day→night flips without restart.
final themeAutoTickProvider = StreamProvider<int>((ref) {
  final pref = ref.watch(themeModeProvider);
  if (pref != ThemeMode.system || !isWallTabletThemeTarget) {
    return Stream.value(0);
  }
  return Stream.periodic(const Duration(minutes: 1), (i) => i + 1);
});

/// Preference resolved for [MaterialApp.themeMode].
final effectiveThemeModeProvider = Provider<ThemeMode>((ref) {
  ref.watch(themeAutoTickProvider);
  return resolveEffectiveThemeMode(
    ref.watch(themeModeProvider),
    schedule: ref.watch(themeAutoScheduleProvider),
    geo: ref.watch(projectGeoProvider),
  );
});
