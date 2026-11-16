import 'package:calm_ig/stats/daily_stats.dart';
import 'package:calm_ig/stats/usage_tracker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late SharedPreferences prefs;
  late StatsStore stats;
  late UsageTracker tracker;

  UsageTracker newTracker() =>
      UsageTracker(stats: stats, prefs: prefs, clock: () => now);

  setUp(() async {
    now = DateTime(2026, 11, 16, 20);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    stats = StatsStore(prefs);
    tracker = newTracker();
  });

  void advance(Duration d) => now = now.add(d);
  const min = Duration(minutes: 1);

  test('counts on-screen time into today', () async {
    await tracker.resume();
    advance(min * 3);
    expect(tracker.today, min * 3);
    await tracker.pause();
    expect(stats.today(now).usage, min * 3);
    expect(tracker.today, min * 3);
  });

  test(
    'time away (no pass) is not counted, and never resets the day',
    () async {
      await tracker.resume();
      advance(min * 2);
      await tracker.pause();
      advance(const Duration(hours: 3)); // long break
      await tracker.resume();
      advance(min);
      expect(tracker.today, min * 3);
    },
  );

  test('resets only at midnight, splitting a stretch across it', () async {
    now = DateTime(2026, 11, 16, 23, 50);
    await tracker.resume();
    advance(min * 20); // 00:10 next day
    expect(tracker.today, min * 10);
    await tracker.pause();
    expect(stats.day('2026-11-16').usage, min * 10);
    expect(stats.day('2026-11-17').usage, min * 10);
  });

  group('pass time (算到回來為止，最多放行結束後 5 分鐘)', () {
    Future<void> startPass(Duration length) async {
      await tracker.resume();
      advance(min); // 1 min on screen before the pass
      await tracker.startPass(now.add(length));
      await tracker.pause(); // Instagram opens
    }

    test('back early: counts until you came back, pass stays open', () async {
      await startPass(min * 5);
      advance(min * 3);
      await tracker.resume();
      expect(tracker.today, min * 4); // 1 on screen + 3 on the pass
      expect(tracker.passEnd, isNotNull);
      // Leaving again while the pass still runs keeps counting.
      await tracker.pause();
      advance(min);
      await tracker.resume();
      expect(tracker.today, min * 5);
    });

    test('back 2 minutes late: counts 7, overtime 2', () async {
      await startPass(min * 5);
      advance(min * 7);
      await tracker.resume();
      expect(tracker.today, min * 8);
      expect(stats.today(now).overtime, min * 2);
      expect(tracker.passEnd, isNull);
    });

    test('phone put down for an hour: at most pass + 5 minutes', () async {
      await startPass(min * 5);
      advance(const Duration(hours: 1));
      await tracker.resume();
      expect(tracker.today, min * (1 + 5 + 5));
      expect(stats.today(now).overtime, passGrace);
    });

    test('結束 early from the app: nothing more counted for it', () async {
      await tracker.resume();
      await tracker.startPass(now.add(min * 5));
      await tracker.endPass();
      await tracker.pause();
      advance(min * 4);
      await tracker.resume();
      expect(tracker.today, Duration.zero);
    });

    test('back early, stayed past the end: no overtime, menu later', () async {
      await startPass(min * 5);
      advance(min * 2);
      await tracker.resume(); // back early
      tracker.askIntent.value = false;
      advance(min * 10); // still in calm_ig when the pass ends
      await tracker.pause();
      expect(tracker.passEnd, isNull);
      advance(const Duration(hours: 1));
      await tracker.resume();
      expect(stats.today(now).overtime, Duration.zero);
      expect(tracker.today, min * (1 + 2 + 10));
      expect(tracker.askIntent.value, isTrue);
    });

    test('checkpoint also closes a pass that ran out on screen', () async {
      await startPass(min * 5);
      advance(min * 2);
      await tracker.resume();
      advance(min * 4);
      await tracker.checkpoint();
      expect(tracker.passEnd, isNull);
    });

    test('iOS closed the app during the pass: picked up on relaunch', () async {
      await startPass(min * 10);
      advance(min * 12);
      final relaunched = newTracker();
      await relaunched.resume();
      expect(relaunched.today, min * (1 + 12));
      expect(stats.today(now).overtime, min * 2);
    });
  });

  group('這次要做什麼？', () {
    test('asks on cold start', () async {
      await tracker.resume();
      expect(tracker.askIntent.value, isTrue);
    });

    test('a short break does not ask; 5 minutes away does', () async {
      await tracker.resume();
      tracker.askIntent.value = false;
      await tracker.pause();
      advance(min * 4);
      await tracker.resume();
      expect(tracker.askIntent.value, isFalse);
      await tracker.pause();
      advance(askIntentAfter);
      await tracker.resume();
      expect(tracker.askIntent.value, isTrue);
    });

    test('coming back from a pass never asks', () async {
      await tracker.resume();
      tracker.askIntent.value = false;
      await tracker.startPass(now.add(min * 5));
      await tracker.pause();
      advance(min * 9);
      await tracker.resume();
      expect(tracker.askIntent.value, isFalse);
    });

    test('a relaunch after the pass does not ask either', () async {
      await tracker.resume();
      await tracker.startPass(now.add(min * 5));
      await tracker.pause();
      advance(min * 6);
      final relaunched = newTracker();
      await relaunched.resume();
      expect(relaunched.askIntent.value, isFalse);
    });
  });

  test('a pass started while the menu is up clears it', () async {
    await tracker.resume();
    expect(tracker.askIntent.value, isTrue);
    await tracker.startPass(now.add(min * 5));
    expect(tracker.askIntent.value, isFalse);
  });

  test('a return long after the pass window asks again', () async {
    await tracker.resume();
    await tracker.startPass(now.add(min * 10));
    await tracker.pause();
    advance(const Duration(hours: 11));
    final relaunched = newTracker();
    await relaunched.resume();
    expect(relaunched.askIntent.value, isTrue);
  });

  test('checkpoint saves the running stretch', () async {
    await tracker.resume();
    advance(min * 2);
    await tracker.checkpoint();
    expect(stats.today(now).usage, min * 2);
    advance(min);
    expect(tracker.today, min * 3); // no double counting
  });

  test('lifecycle: hidden/paused stop it, inactive does not', () async {
    await tracker.resume();
    tracker.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(tracker.isRunning, isTrue);
    tracker.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(tracker.isRunning, isFalse);
    tracker.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(tracker.isRunning, isTrue);
  });

  testWidgets('attach starts it only when the app is in the foreground', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final background = newTracker()..attach();
    expect(background.isRunning, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(background.isRunning, isTrue);
    background.detach();
  });

  test('formatStopwatch and formatMinutes', () {
    expect(formatStopwatch(const Duration(minutes: 12, seconds: 34)), '12:34');
    expect(
      formatStopwatch(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatMinutes(const Duration(minutes: 45)), '45 分');
    expect(formatMinutes(const Duration(minutes: 83)), '1 小時 23 分');
    expect(formatMinutes(Duration.zero), '0 分');
  });
}
