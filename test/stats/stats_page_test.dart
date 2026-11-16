import 'dart:convert';

import 'package:calm_ig/settings/app_settings.dart';
import 'package:calm_ig/stats/daily_stats.dart';
import 'package:calm_ig/stats/day_key.dart';
import 'package:calm_ig/stats/stats_page.dart';
import 'package:calm_ig/stats/usage_tracker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Monday 2026-11-16, 15:30.
DateTime clock() => DateTime(2026, 11, 16, 15, 30);

String _day(int daysAgo) => dayKey(DateTime(2026, 11, 16 - daysAgo));

Map<String, Object> _record(
  int daysAgo, {
  Duration usage = Duration.zero,
  int passes = 0,
  int overQuota = 0,
  Duration overtime = Duration.zero,
  Map<String, int> intents = const {},
  int bounces = 0,
  int? quota,
}) => {
  StatsStore.statsKey(_day(daysAgo)): jsonEncode(
    DayStats(
      day: _day(daysAgo),
      usage: usage,
      passes: passes,
      overQuotaPasses: overQuota,
      overtime: overtime,
      intents: intents,
      quota: quota,
    ).toJson(),
  ),
  if (bounces > 0) StatsStore.bouncesKey(_day(daysAgo)): bounces,
};

/// Today, yesterday and four days ago (inside 7 days), plus 22 days ago
/// (only inside 30 days).
Map<String, Object> get _history => {
  AppSettings.passQuotaKey: 3,
  ..._record(
    0,
    usage: const Duration(minutes: 83),
    passes: 4,
    overQuota: 1,
    overtime: const Duration(minutes: 12),
    intents: {'發限動': 1, '回私訊': 4},
    bounces: 2,
  ),
  ..._record(1, usage: const Duration(minutes: 40), passes: 2, bounces: 5),
  ..._record(4, usage: const Duration(minutes: 20), passes: 1, bounces: 1),
  ..._record(
    22,
    usage: const Duration(minutes: 50),
    passes: 6,
    overQuota: 3,
    bounces: 2,
  ),
};

class _Harness {
  _Harness(this.settings);

  final AppSettings settings;
  int editIntentOptions = 0;
}

Future<_Harness> _pumpPage(
  WidgetTester tester,
  Map<String, Object> values, {
  Brightness brightness = Brightness.light,
  Map<String, Object>? writtenByIos,
}) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final stats = StatsStore(prefs);
  final settings = AppSettings(prefs);
  final tracker = UsageTracker(stats: stats, prefs: prefs, clock: clock);
  // Values the App Intent writes behind Dart's back, seen after reload().
  if (writtenByIos != null) {
    SharedPreferences.setMockInitialValues({...values, ...writtenByIos});
  }
  final harness = _Harness(settings);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: brightness),
      home: StatsPage(
        stats: stats,
        tracker: tracker,
        settings: settings,
        onEditIntentOptions: () => harness.editIntentOptions++,
        clock: clock,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

List<BarChart> _charts(WidgetTester tester) =>
    tester.widgetList<BarChart>(find.byType(BarChart)).toList();

String _tooltip(BarChart chart, int group) {
  final data = chart.data;
  final g = data.barGroups[group];
  final item = data.barTouchData.touchTooltipData.getTooltipItem(
    g,
    group,
    g.barRods.first,
    0,
  )!;
  return item.text + (item.children ?? []).map((s) => s.text).join();
}

String? _lineLabel(BarChart chart) {
  final lines = chart.data.extraLinesData.horizontalLines;
  if (lines.isEmpty) return null;
  return lines.single.label.labelResolver(lines.single);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('summarises today', (tester) async {
    await _pumpPage(tester, _history);

    expect(find.text('今日紀錄'), findsOneWidget);
    expect(find.text('今天 11/16 週一'), findsOneWidget);
    expect(find.text('1:23:00'), findsOneWidget);
    expect(find.text('已放行 4 / 額度 3 次（超額 1 次）'), findsOneWidget);
    expect(find.text('12 分'), findsOneWidget);
    expect(find.text('2 次'), findsOneWidget);
    expect(find.text('打開原生 IG 被帶回來的次數'), findsOneWidget);
    expect(find.text('這次要做什麼？'), findsOneWidget);
    expect(find.text('回私訊 ×4'), findsOneWidget);
    expect(find.text('發限動 ×1'), findsOneWidget);
    // Most chosen first.
    expect(
      tester.getTopLeft(find.text('回私訊 ×4')).dx,
      lessThan(tester.getTopLeft(find.text('發限動 ×1')).dx),
    );
  });

  testWidgets('reloads to pick up bounces written by iOS', (tester) async {
    await _pumpPage(
      tester,
      _history,
      writtenByIos: {StatsStore.bouncesKey(_day(0)): 7},
    );

    expect(find.text('7 次'), findsOneWidget);
  });

  testWidgets('coming back to the app picks up new bounces right away', (
    tester,
  ) async {
    await _pumpPage(tester, _history);
    expect(find.text('2 次'), findsOneWidget);
    // While the app is in the background, the App Intent counts a bounce.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    SharedPreferences.setMockInitialValues({
      ..._history,
      StatsStore.bouncesKey(_day(0)): 3,
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // The quota stepper also says "3 次"; the bounce row is the other one.
    expect(find.text('2 次'), findsNothing);
    expect(find.text('3 次'), findsNWidgets(2));
  });

  testWidgets('charts the last 7 days, or 30 after switching', (tester) async {
    await _pumpPage(tester, _history);

    var charts = _charts(tester);
    expect(charts, hasLength(3));
    expect([for (final c in charts) c.data.barGroups.length], [7, 7, 7]);
    expect(find.text('近 7 天共 2 小時 23 分'), findsOneWidget);
    expect(find.text('近 7 天放行 7 次，其中超額 1 次'), findsOneWidget);
    expect(find.text('近 7 天共擋回 8 次'), findsOneWidget);

    final usage = charts[0];
    expect(usage.data.barGroups.last.barRods.single.toY, 83);
    // Averaged from the first day with records (4 days ago): 143 / 5.
    expect(_lineLabel(usage), '平均 28 分');
    expect(_tooltip(usage, 6), '11/16 週一 · 1 小時 23 分');
    expect(_tooltip(usage, 5), '11/15 週日 · 40 分');

    final passes = charts[1];
    expect(_lineLabel(passes), '目前額度 3 次');
    final today = passes.data.barGroups.last.barRods.single;
    expect(today.toY, 4);
    expect(today.rodStackItems, hasLength(2));
    expect(
      today.rodStackItems.first.color,
      isNot(today.rodStackItems.last.color),
    );
    expect(_tooltip(passes, 6), '11/16 週一 · 放行 4 次（超額 1 次）\n超時 12 分');
    expect(_tooltip(passes, 5), '11/15 週日 · 放行 2 次（沒有超額）\n沒有超時');

    expect(_tooltip(charts[2], 6), '11/16 週一 · 擋回 2 次');

    await _tap(tester, find.text('30 天'));

    charts = _charts(tester);
    expect([for (final c in charts) c.data.barGroups.length], [30, 30, 30]);
    expect(find.text('近 30 天共 3 小時 13 分'), findsOneWidget);
    expect(find.text('近 30 天放行 13 次，其中超額 4 次'), findsOneWidget);
    expect(find.text('近 30 天共擋回 10 次'), findsOneWidget);
    // 193 minutes over the 23 days since the first record.
    expect(_lineLabel(charts[0]), '平均 8 分');
    expect(_tooltip(charts[1], 7), '10/25 週日 · 放行 6 次（超額 3 次）\n沒有超時');

    await _tap(tester, find.text('7 天'));
    expect(_charts(tester).first.data.barGroups, hasLength(7));
  });

  testWidgets('tapping a bar opens its tooltip, tapping again closes it', (
    tester,
  ) async {
    await _pumpPage(tester, _history);
    final chart = find.byType(BarChart).first;
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();

    final rect = tester.getRect(chart);
    const yAxis = 40.0;
    final slot = (rect.width - yAxis) / 7;
    final todayBar = Offset(rect.left + yAxis + slot * 6.5, rect.top + 100);
    List<int> shown(int group) =>
        _charts(tester).first.data.barGroups[group].showingTooltipIndicators;

    await tester.tapAt(todayBar);
    await tester.pumpAndSettle();
    expect(shown(6), [0]);

    await tester.tapAt(todayBar);
    await tester.pumpAndSettle();
    expect(shown(6), isEmpty);
  });

  testWidgets('daily pass quota steps up and down', (tester) async {
    final harness = await _pumpPage(tester, _history);
    final value = find.byKey(const ValueKey('quota-value'));
    expect(tester.widget<Text>(value).data, '3 次');

    await _tap(tester, find.byTooltip('增加額度'));
    expect(harness.settings.passQuota, 4);
    expect(tester.widget<Text>(value).data, '4 次');
    expect(find.text('已放行 4 / 額度 4 次（超額 1 次）'), findsOneWidget);
    expect(_lineLabel(_charts(tester)[1]), '目前額度 4 次');

    await _tap(tester, find.byTooltip('減少額度'));
    await _tap(tester, find.byTooltip('減少額度'));
    expect(harness.settings.passQuota, 2);
    expect(tester.widget<Text>(value).data, '2 次');
  });

  testWidgets('a raise after the first pass waits until tomorrow', (
    tester,
  ) async {
    await _pumpPage(tester, {
      AppSettings.passQuotaKey: 3,
      ..._record(0, passes: 3, quota: 3),
    });
    expect(find.text('已放行 3 / 額度 3 次'), findsOneWidget);
    expect(find.textContaining('今天仍是'), findsNothing);

    await _tap(tester, find.byTooltip('增加額度'));
    await _tap(tester, find.byTooltip('增加額度'));
    // The setting says 5, but today still has 3.
    expect(find.text('已放行 3 / 額度 3 次'), findsOneWidget);
    expect(find.textContaining('今天仍是 3 次，明天起 5 次'), findsOneWidget);
    expect(_lineLabel(_charts(tester)[1]), '目前額度 5 次');

    // Lowering applies at once and the note goes away.
    for (var i = 0; i < 3; i++) {
      await _tap(tester, find.byTooltip('減少額度'));
    }
    expect(find.text('已放行 3 / 額度 2 次'), findsOneWidget);
    expect(find.textContaining('今天仍是'), findsNothing);
  });

  testWidgets('quota stops at 0 and at the maximum', (tester) async {
    final harness = await _pumpPage(tester, {AppSettings.passQuotaKey: 0});
    IconButton button(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );
    expect(button('減少額度').onPressed, isNull);

    await harness.settings.setPassQuota(AppSettings.maxPassQuota);
    await tester.pumpAndSettle();
    expect(button('增加額度').onPressed, isNull);
    expect(button('減少額度').onPressed, isNotNull);
  });

  testWidgets('opens the option editor', (tester) async {
    final harness = await _pumpPage(tester, _history);
    expect(find.text('「這次要做什麼？」的選項'), findsOneWidget);

    await _tap(tester, find.text('開場選項'));
    expect(harness.editIntentOptions, 1);
  });

  testWidgets('with no records the charts keep their axes and say so', (
    tester,
  ) async {
    await _pumpPage(tester, {});

    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('已放行 0 / 額度 3 次'), findsOneWidget);
    expect(find.text('沒有超時'), findsOneWidget);
    expect(find.text('0 次'), findsOneWidget);
    expect(find.text('這次要做什麼？'), findsNothing);
    expect(find.text('還沒有紀錄'), findsNWidgets(3));
    final charts = _charts(tester);
    expect(charts, hasLength(3));
    for (final chart in charts) {
      expect(chart.data.maxY, greaterThan(0));
      expect(chart.data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
      expect(chart.data.titlesData.bottomTitles.sideTitles.showTitles, isTrue);
    }
    expect(_lineLabel(charts[0]), isNull); // no average yet
    expect(_lineLabel(charts[1]), '目前額度 3 次');
  });

  group('fits a 375×812 phone', () {
    final busy = {
      ..._history,
      AppSettings.passQuotaKey: 10,
      ..._record(
        0,
        usage: const Duration(hours: 5, minutes: 47),
        passes: 12,
        overQuota: 2,
        overtime: const Duration(hours: 2, minutes: 5),
        intents: {
          '回私訊': 14,
          '發限動': 3,
          '看朋友的限動': 9,
          '隨便看看': 22,
          '找一則以前的貼文': 1,
          '看活動資訊': 2,
        },
        bounces: 123,
      ),
    };

    for (final brightness in Brightness.values) {
      testWidgets('in 7 and 30 day mode, ${brightness.name}', (tester) async {
        _usePhone(tester);
        await _pumpPage(tester, busy, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('已放行 12 / 額度 10 次（超額 2 次）'), findsOneWidget);

        await _tap(tester, find.text('30 天'));
        expect(tester.takeException(), isNull);
        expect(_charts(tester).first.data.barGroups, hasLength(30));

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('when empty', (tester) async {
      _usePhone(tester);
      await _pumpPage(tester, {});
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('30 天'));
      expect(tester.takeException(), isNull);
    });
  });
}
