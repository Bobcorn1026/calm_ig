import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'day_key.dart';

/// Everything recorded about one day.
class DayStats {
  const DayStats({
    required this.day,
    this.usage = Duration.zero,
    this.passes = 0,
    this.overQuotaPasses = 0,
    this.overtime = Duration.zero,
    this.bounces = 0,
    this.intents = const {},
  });

  /// `2026-11-16` (see [dayKey]).
  final String day;

  /// Time on Instagram: calm_ig on screen plus time spent on passes.
  final Duration usage;

  /// Passes to the native app started that day (including over-quota ones).
  final int passes;

  /// Passes started after the daily quota was used up.
  final int overQuotaPasses;

  /// How long passes ran over before coming back (capped per pass).
  final Duration overtime;

  /// Times the native app was opened and sent back to calm_ig. Written by
  /// the iOS App Intent, not by Dart.
  final int bounces;

  /// "這次要做什麼？" answers: option label → times chosen.
  final Map<String, int> intents;

  DayStats copyWith({
    Duration? usage,
    int? passes,
    int? overQuotaPasses,
    Duration? overtime,
    Map<String, int>? intents,
  }) => DayStats(
    day: day,
    usage: usage ?? this.usage,
    passes: passes ?? this.passes,
    overQuotaPasses: overQuotaPasses ?? this.overQuotaPasses,
    overtime: overtime ?? this.overtime,
    bounces: bounces,
    intents: intents ?? this.intents,
  );

  Map<String, Object> toJson() => {
    'usageMs': usage.inMilliseconds,
    'passes': passes,
    'overQuota': overQuotaPasses,
    'overtimeMs': overtime.inMilliseconds,
    'intents': intents,
  };

  factory DayStats.fromJson(
    String day,
    Map<String, dynamic> json, {
    int bounces = 0,
  }) => DayStats(
    day: day,
    usage: Duration(milliseconds: (json['usageMs'] as num?)?.toInt() ?? 0),
    passes: (json['passes'] as num?)?.toInt() ?? 0,
    overQuotaPasses: (json['overQuota'] as num?)?.toInt() ?? 0,
    overtime: Duration(
      milliseconds: (json['overtimeMs'] as num?)?.toInt() ?? 0,
    ),
    bounces: bounces,
    intents: {
      for (final e in ((json['intents'] as Map?) ?? const {}).entries)
        if (e.value is num) '${e.key}': (e.value as num).toInt(),
    },
  );
}

/// Daily records in shared_preferences: `stats_<day>` (JSON, written here)
/// and `bounces_<day>` (int, written by the iOS App Intent).
class StatsStore {
  StatsStore(this._prefs);

  final SharedPreferences _prefs;

  /// How many days of history to keep.
  static const keepDays = 120;

  static String statsKey(String day) => 'stats_$day';
  static String bouncesKey(String day) => 'bounces_$day';

  /// Re-reads values written outside Dart (the App Intent's bounce counts).
  Future<void> reload() => _prefs.reload();

  DayStats day(String day) {
    final raw = _prefs.getString(statsKey(day));
    final bounces = _prefs.getInt(bouncesKey(day)) ?? 0;
    if (raw == null) return DayStats(day: day, bounces: bounces);
    try {
      return DayStats.fromJson(
        day,
        jsonDecode(raw) as Map<String, dynamic>,
        bounces: bounces,
      );
    } on Object {
      // Unreadable record (corrupt JSON or wrong types): treat as empty.
      return DayStats(day: day, bounces: bounces);
    }
  }

  DayStats today(DateTime now) => day(dayKey(now));

  /// The [count] days ending today, oldest first (missing days are empty).
  List<DayStats> recent(DateTime now, int count) => [
    for (final d in lastDays(now, count)) day(dayKey(d)),
  ];

  Future<void> _update(String key, DayStats Function(DayStats) change) =>
      _prefs.setString(statsKey(key), jsonEncode(change(day(key)).toJson()));

  /// Adds time per day, as produced by [splitByDay].
  Future<void> addUsage(Map<String, Duration> parts) async {
    for (final e in parts.entries) {
      if (e.value <= Duration.zero) continue;
      await _update(e.key, (s) => s.copyWith(usage: s.usage + e.value));
    }
  }

  Future<void> recordPass(DateTime at, {required bool overQuota}) => _update(
    dayKey(at),
    (s) => s.copyWith(
      passes: s.passes + 1,
      overQuotaPasses: s.overQuotaPasses + (overQuota ? 1 : 0),
    ),
  );

  /// Overtime counts on the day the pass ended.
  Future<void> addOvertime(DateTime passEnd, Duration overtime) => _update(
    dayKey(passEnd),
    (s) => s.copyWith(overtime: s.overtime + overtime),
  );

  Future<void> recordIntent(DateTime at, String label) => _update(
    dayKey(at),
    (s) =>
        s.copyWith(intents: {...s.intents, label: (s.intents[label] ?? 0) + 1}),
  );

  /// Drops records older than [keepDays].
  Future<void> prune(DateTime now) async {
    final keep = {for (final d in lastDays(now, keepDays)) dayKey(d)};
    for (final key in _prefs.getKeys().toList()) {
      final match = RegExp(r'^(stats|bounces)_(\d{4}-\d{2}-\d{2})$')
          .firstMatch(key);
      if (match != null && !keep.contains(match.group(2))) {
        await _prefs.remove(key);
      }
    }
  }
}
