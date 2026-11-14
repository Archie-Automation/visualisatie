import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eén opgeslagen kleur van een RGBW-lamp. Dimstand hoort er niet bij:
/// die blijft de slider. [white] is het aparte KNX-witkanaal (0–255).
class RgbFavoriteColor {
  const RgbFavoriteColor.rgb({
    required this.hue,
    required this.saturation,
    this.white = 0,
  })  : tunable = false,
        warmCool = 0;

  const RgbFavoriteColor.tunable({required this.warmCool})
      : tunable = true,
        hue = 0,
        saturation = 0,
        white = 0;

  static const maxCount = 8;

  final bool tunable;
  final double hue;
  final double saturation;
  /// 0 = warm, 1 = koud. Alleen bij [tunable].
  final double warmCool;
  final int white;

  Color get swatch {
    if (tunable) {
      const warm = Color(0xFFFF9A3C);
      const mid = Color(0xFFFFEFCF);
      const cool = Color(0xFFCCE8FF);
      if (warmCool <= 0.5) {
        return Color.lerp(warm, mid, warmCool * 2) ?? mid;
      }
      return Color.lerp(mid, cool, (warmCool - 0.5) * 2) ?? mid;
    }
    final rgb = HSVColor.fromAHSV(1, _normHue(hue), saturation.clamp(0, 1), 1)
        .toColor();
    if (white <= 0) return rgb;
    return Color.lerp(rgb, Colors.white, (white / 255) * 0.65) ?? rgb;
  }

  bool sameLook(RgbFavoriteColor other) {
    if (tunable != other.tunable) return false;
    if (tunable) return (warmCool - other.warmCool).abs() < 0.025;
    if ((saturation - other.saturation).abs() > 0.04) return false;
    if ((white - other.white).abs() > 6) return false;
    return _hueDelta(hue, other.hue) <= 4;
  }

  Map<String, dynamic> toJson() => {
        'tunable': tunable,
        'hue': hue,
        'saturation': saturation,
        'warmCool': warmCool,
        'white': white,
      };

  factory RgbFavoriteColor.fromJson(Map<String, dynamic> j) {
    if (j['tunable'] == true) {
      return RgbFavoriteColor.tunable(
        warmCool: ((j['warmCool'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      );
    }
    return RgbFavoriteColor.rgb(
      hue: _normHue((j['hue'] as num?)?.toDouble() ?? 0),
      saturation: ((j['saturation'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      white: ((j['white'] as num?)?.toInt() ?? 0).clamp(0, 255),
    );
  }
}

enum RgbFavoriteSave { added, duplicate, full }

/// Voegt [next] toe aan [colors] (muteert de lijst) of weigert.
RgbFavoriteSave tryAddRgbFavorite(
  List<RgbFavoriteColor> colors,
  RgbFavoriteColor next,
) {
  if (colors.any(next.sameLook)) return RgbFavoriteSave.duplicate;
  if (colors.length >= RgbFavoriteColor.maxCount) return RgbFavoriteSave.full;
  colors.add(next);
  return RgbFavoriteSave.added;
}

double _normHue(double hue) {
  final m = hue % 360;
  return m < 0 ? m + 360 : m;
}

double _hueDelta(double a, double b) {
  final d = (_normHue(a) - _normHue(b)).abs();
  return math.min(d, 360 - d);
}

/// Lokaal op dit toestel, per lamp. Niet in de huisconfiguratie.
class RgbColorFavoriteStore {
  static String keyFor(String storageId) => 'rgb_fav_colors_v1_$storageId';

  static Future<List<RgbFavoriteColor>> load(String storageId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(keyFor(storageId));
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <RgbFavoriteColor>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(RgbFavoriteColor.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
      if (out.length > RgbFavoriteColor.maxCount) {
        return out.sublist(0, RgbFavoriteColor.maxCount);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> write(String storageId, List<RgbFavoriteColor> colors) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final key = keyFor(storageId);
      if (colors.isEmpty) {
        await sp.remove(key);
      } else {
        await sp.setString(
          key,
          jsonEncode(colors.map((c) => c.toJson()).toList()),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
