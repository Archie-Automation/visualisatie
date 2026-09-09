import 'package:flutter_riverpod/flutter_riverpod.dart';

class WtwLogicActive {
  const WtwLogicActive({
    required this.deviceId,
    required this.logicId,
    required this.label,
    required this.standId,
    required this.end,
    this.untilMs,
  });

  final String deviceId;
  final String logicId;
  final String label;
  final String standId;
  final String end;
  final int? untilMs;

  factory WtwLogicActive.fromJson(Map<String, dynamic> j) {
    final until = j['untilMs'];
    return WtwLogicActive(
      deviceId: j['deviceId'] as String? ?? '',
      logicId: j['logicId'] as String? ?? '',
      label: (j['label'] as String? ?? '').trim(),
      standId: j['standId'] as String? ?? '',
      end: j['end'] as String? ?? 'duration',
      untilMs: until is num ? until.toInt() : null,
    );
  }

  DateTime? get until {
    final ms = untilMs;
    if (ms == null) return null;
    if (ms <= DateTime.now().millisecondsSinceEpoch) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Duration? remaining([DateTime? now]) {
    final u = until;
    if (u == null) return null;
    final left = u.difference(now ?? DateTime.now());
    if (left <= Duration.zero) return null;
    return left;
  }

  String standLabel() => switch (standId) {
        'stand1' => 'stand 1',
        'stand2' => 'stand 2',
        'stand3' => 'stand 3',
        'away' => 'afwezig',
        'boost' => 'boost',
        _ => standId,
      };

  String statusText([DateTime? now]) {
    final parts = <String>['Actief'];
    if (label.isNotEmpty) parts.add(label);
    parts.add(standLabel());
    final left = remaining(now);
    if (left != null) parts.add(_formatLeft(left));
    return parts.join(' · ');
  }

  static String _formatLeft(Duration d) {
    final total = d.inMinutes;
    if (total >= 60) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      if (m == 0) return '$h u';
      return '$h u ${m.toString().padLeft(2, '0')} min';
    }
    if (total < 1) {
      final s = d.inSeconds.clamp(1, 59);
      return '$s s';
    }
    return '$total min';
  }
}

class WtwLogicStore extends Notifier<List<WtwLogicActive>> {
  @override
  List<WtwLogicActive> build() => const [];

  void snapshot(List<Map<String, dynamic>> raw) {
    state = [for (final e in raw) WtwLogicActive.fromJson(e)];
  }
}

extension WtwLogicActiveList on List<WtwLogicActive> {
  List<WtwLogicActive> forDevice(String id) =>
      [for (final r in this) if (r.deviceId == id) r];
}

final wtwLogicProvider =
    NotifierProvider<WtwLogicStore, List<WtwLogicActive>>(WtwLogicStore.new);
