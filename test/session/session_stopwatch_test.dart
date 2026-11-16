import 'package:calm_ig/browser/reload_handle.dart';
import 'package:calm_ig/session/prefs_session_store.dart';
import 'package:calm_ig/session/session_clock.dart';
import 'package:calm_ig/session/session_stopwatch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStore implements SessionStore {
  SessionSnapshot? saved;
  int saves = 0;

  @override
  SessionSnapshot? load() => saved;

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    saves++;
    saved = snapshot;
  }
}

void main() {
  late DateTime now;
  late SessionStopwatch sw;

  setUp(() {
    now = DateTime(2026, 11, 16, 20);
    sw = SessionStopwatch(clock: () => now);
  });

  void advance(Duration d) => now = now.add(d);

  test('starts at zero and counts while running', () {
    expect(sw.elapsed, Duration.zero);
    expect(sw.isRunning, isTrue);
    advance(const Duration(minutes: 2, seconds: 5));
    expect(sw.elapsed, const Duration(minutes: 2, seconds: 5));
  });

  test('a short break pauses and then continues', () {
    advance(const Duration(minutes: 3));
    sw.pause();
    advance(const Duration(minutes: 4)); // away < 5 min
    expect(sw.elapsed, const Duration(minutes: 3));
    sw.resume();
    advance(const Duration(seconds: 30));
    expect(sw.elapsed, const Duration(minutes: 3, seconds: 30));
  });

  test('being away for 5 minutes starts a new session', () {
    advance(const Duration(minutes: 3));
    sw.pause();
    advance(sessionResetAfter);
    sw.resume();
    expect(sw.elapsed, Duration.zero);
    advance(const Duration(seconds: 10));
    expect(sw.elapsed, const Duration(seconds: 10));
  });

  test('pause and resume are safe to repeat', () {
    advance(const Duration(minutes: 1));
    sw.pause();
    sw.pause();
    advance(const Duration(minutes: 1));
    sw.resume();
    sw.resume();
    advance(const Duration(minutes: 1));
    expect(sw.elapsed, const Duration(minutes: 2));
  });

  test('lifecycle: hidden/paused stop it, inactive does not', () {
    sw.didChangeAppLifecycleState(AppLifecycleState.inactive);
    advance(const Duration(minutes: 1));
    expect(sw.isRunning, isTrue);
    sw.didChangeAppLifecycleState(AppLifecycleState.hidden);
    sw.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(sw.isRunning, isFalse);
    advance(const Duration(minutes: 1));
    sw.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(sw.isRunning, isTrue);
    expect(sw.elapsed, const Duration(minutes: 1));
  });

  test('startRunning: false waits for resume', () {
    final idle = SessionStopwatch(clock: () => now, startRunning: false);
    advance(const Duration(minutes: 10));
    expect(idle.isRunning, isFalse);
    expect(idle.elapsed, Duration.zero);
    idle.resume();
    advance(const Duration(seconds: 3));
    expect(idle.elapsed, const Duration(seconds: 3));
  });

  testWidgets('attach starts it only when the app is in the foreground', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final background = SessionStopwatch(clock: () => now, startRunning: false)
      ..attach();
    expect(background.isRunning, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(background.isRunning, isTrue);
    background.detach();

    final foreground = SessionStopwatch(clock: () => now, startRunning: false)
      ..attach();
    expect(foreground.isRunning, isTrue);
    foreground.detach();
  });

  group('coming back from a pass (延續計時)', () {
    test('back within 5 minutes after the pass ends: continues', () {
      advance(const Duration(minutes: 3));
      sw.allowBreakUntil(now.add(const Duration(minutes: 10)));
      sw.pause(); // native Instagram opens
      advance(const Duration(minutes: 14)); // 10 min pass + 4 min late
      sw.resume();
      expect(sw.elapsed, const Duration(minutes: 3));
    });

    test('back 5+ minutes after the pass ends: new session', () {
      advance(const Duration(minutes: 3));
      sw.allowBreakUntil(now.add(const Duration(minutes: 5)));
      sw.pause();
      advance(const Duration(minutes: 10)); // 5 min pass + 5 min late
      sw.resume();
      expect(sw.elapsed, Duration.zero);
    });

    test('the allowance is used once', () {
      advance(const Duration(minutes: 1));
      sw.allowBreakUntil(now.add(const Duration(minutes: 5)));
      sw.pause();
      advance(const Duration(minutes: 6));
      sw.resume();
      expect(sw.breakAllowedUntil, isNull);
      advance(const Duration(minutes: 1));
      sw.pause();
      advance(const Duration(minutes: 5)); // ordinary break, no pass
      sw.resume();
      expect(sw.elapsed, Duration.zero);
    });
  });

  group('saved session (iOS closed the app in the background)', () {
    test('pause saves; a new stopwatch picks the session up', () {
      final store = MemoryStore();
      final first = SessionStopwatch(clock: () => now, store: store);
      advance(const Duration(minutes: 7));
      first.allowBreakUntil(now.add(const Duration(minutes: 10)));
      first.pause();
      expect(store.saved!.banked, const Duration(minutes: 7));
      expect(store.saved!.breakAllowedUntil, isNotNull);

      // App killed during the pass; relaunched 12 minutes later.
      advance(const Duration(minutes: 12));
      final second = SessionStopwatch(
        clock: () => now,
        startRunning: false,
        store: store,
      );
      expect(second.isRunning, isFalse);
      second.resume();
      expect(second.elapsed, const Duration(minutes: 7));
    });

    test('an old saved session starts over', () {
      final store = MemoryStore()
        ..saved = SessionSnapshot(
          banked: const Duration(minutes: 40),
          pausedAt: now.subtract(const Duration(hours: 8)),
        );
      final sw2 = SessionStopwatch(
        clock: () => now,
        startRunning: false,
        store: store,
      );
      sw2.resume();
      expect(sw2.elapsed, Duration.zero);
    });

    test('PrefsSessionStore round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PrefsSessionStore(prefs);
      expect(store.load(), isNull);
      await store.save(
        SessionSnapshot(
          banked: const Duration(seconds: 95),
          pausedAt: now,
          breakAllowedUntil: now.add(const Duration(minutes: 5)),
        ),
      );
      final loaded = store.load()!;
      expect(loaded.banked, const Duration(seconds: 95));
      expect(loaded.pausedAt, now);
      expect(loaded.breakAllowedUntil, now.add(const Duration(minutes: 5)));
      await store.save(SessionSnapshot(banked: Duration.zero, pausedAt: now));
      expect(store.load()!.breakAllowedUntil, isNull);
    });
  });

  test('formatStopwatch', () {
    expect(formatStopwatch(Duration.zero), '0:00');
    expect(formatStopwatch(const Duration(seconds: 7)), '0:07');
    expect(formatStopwatch(const Duration(minutes: 12, seconds: 34)), '12:34');
    expect(
      formatStopwatch(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatStopwatch(const Duration(seconds: -1)), '0:00');
  });

  testWidgets('SessionClock redraws every second', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SessionClock(stopwatch: sw)),
      ),
    );
    expect(find.text('0:00'), findsOneWidget);
    advance(const Duration(seconds: 65));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:05'), findsOneWidget);
  });

  test('ReloadHandle reaches the attached web view only', () async {
    final handle = ReloadHandle();
    await handle.reload(); // nothing attached: no-op
    var calls = 0;
    Future<void> action() async => calls++;
    handle.attach(action);
    await handle.reload();
    expect(calls, 1);
    handle.detach(action);
    await handle.reload();
    expect(calls, 1);
  });
}
