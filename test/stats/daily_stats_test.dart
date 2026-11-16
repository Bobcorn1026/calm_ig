import 'dart:convert';

import 'package:calm_ig/stats/daily_stats.dart';
import 'package:calm_ig/stats/day_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 11, 16, 20);
  late SharedPreferences prefs;
  late StatsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = StatsStore(prefs);
  });

  test('an unknown day is empty', () {
    final day = store.today(now);
    expect(day.day, '2026-11-16');
    expect(day.usage, Duration.zero);
    expect(day.passes, 0);
    expect(day.bounces, 0);
    expect(day.intents, isEmpty);
  });

  test('usage adds up per day', () async {
    await store.addUsage({
      '2026-11-15': const Duration(minutes: 10),
      '2026-11-16': const Duration(minutes: 5),
    });
    await store.addUsage({'2026-11-16': const Duration(minutes: 7)});
    expect(store.day('2026-11-15').usage, const Duration(minutes: 10));
    expect(store.day('2026-11-16').usage, const Duration(minutes: 12));
  });

  test('passes, over-quota passes, overtime and intents', () async {
    await store.recordPass(now, overQuota: false, quota: 3);
    await store.recordPass(now, overQuota: true, quota: 3);
    await store.addOvertime(now, const Duration(minutes: 3));
    await store.recordIntent(now, '回私訊');
    await store.recordIntent(now, '回私訊');
    await store.recordIntent(now, '隨便看看');
    final day = store.today(now);
    expect(day.passes, 2);
    expect(day.overQuotaPasses, 1);
    expect(day.overtime, const Duration(minutes: 3));
    expect(day.intents, {'回私訊': 2, '隨便看看': 1});
  });

  test('bounces come from the key the iOS App Intent writes', () async {
    await prefs.setInt('bounces_2026-11-16', 7);
    expect(store.today(now).bounces, 7);
    // Writing other stats doesn't touch it.
    await store.recordPass(now, overQuota: false, quota: 3);
    expect(store.today(now).bounces, 7);
    expect(prefs.getInt('bounces_2026-11-16'), 7);
  });

  test('recent fills missing days and ends today', () async {
    await store.addUsage({'2026-11-14': const Duration(minutes: 9)});
    final days = store.recent(now, 3);
    expect(days.map((d) => d.day), ['2026-11-14', '2026-11-15', '2026-11-16']);
    expect(days.first.usage, const Duration(minutes: 9));
    expect(days[1].usage, Duration.zero);
  });

  test('a corrupt record reads as empty instead of crashing', () async {
    await prefs.setString('stats_2026-11-16', '{not json');
    expect(store.today(now).usage, Duration.zero);
  });

  test('prune keeps ${StatsStore.keepDays} days', () async {
    final old = DateTime(now.year, now.month, now.day - StatsStore.keepDays);
    await prefs.setString(
      StatsStore.statsKey(dayKey(old)),
      jsonEncode({'usageMs': 1}),
    );
    await prefs.setInt(StatsStore.bouncesKey(dayKey(old)), 1);
    await store.addUsage({'2026-11-16': const Duration(minutes: 1)});
    await store.prune(now);
    expect(prefs.getString(StatsStore.statsKey(dayKey(old))), isNull);
    expect(prefs.getInt(StatsStore.bouncesKey(dayKey(old))), isNull);
    expect(store.today(now).usage, const Duration(minutes: 1));
  });
}
