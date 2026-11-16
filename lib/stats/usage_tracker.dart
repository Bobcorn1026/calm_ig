import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pass/pass_controller.dart' show reminderCount, reminderInterval;
import 'daily_stats.dart';
import 'day_key.dart';

/// Pass time counts until you come back, but at most this long after the
/// pass ends (the reminder period). Putting the phone down for an hour
/// after a pass doesn't count as an hour of Instagram.
final passGrace = reminderInterval * reminderCount;

/// Coming back after at least this long (or a cold start) asks
/// "這次要做什麼？". Coming back from a pass never asks.
const askIntentAfter = Duration(minutes: 5);

/// Today's Instagram time: calm_ig on screen plus time on passes. Resets
/// only at local midnight (there is no manual reset).
///
/// Watches the app lifecycle itself (call [attach] once). State that must
/// survive iOS closing the app — when it left, an open pass — is kept in
/// shared_preferences; totals go to [StatsStore].
class UsageTracker with WidgetsBindingObserver {
  UsageTracker({
    required this.stats,
    required this._prefs,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _pausedAt = _readTime(_pausedAtKey);
    _passEnd = _readTime(_passEndKey);
  }

  final StatsStore stats;
  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const _pausedAtKey = 'tracker_paused_at_ms';
  static const _passEndKey = 'tracker_pass_end_ms';

  /// When the current on-screen stretch started; null while away.
  DateTime? _runningSince;

  /// When calm_ig last left the foreground.
  DateTime? _pausedAt;

  /// End of a pass that hasn't been accounted for yet.
  DateTime? _passEnd;

  bool _started = false;

  /// Persistence runs in order, off the lifecycle callbacks. Created on
  /// first use so it belongs to the zone that uses it.
  Future<void>? _queue;

  Future<void> get _idle => _queue ?? Future<void>.value();

  /// Set when "這次要做什麼？" should be shown; the menu clears it.
  final askIntent = ValueNotifier<bool>(false);

  bool get isRunning => _runningSince != null;

  @visibleForTesting
  DateTime? get passEnd => _passEnd;

  /// Today's total, including the stretch currently on screen.
  Duration get today {
    final now = _now();
    var total = stats.today(now).usage;
    final since = _runningSince;
    if (since != null) {
      final midnight = startOfDay(now);
      total += now.difference(since.isAfter(midnight) ? since : midnight);
    }
    return total;
  }

  DateTime? _readTime(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _writeTime(String key, DateTime? t) => t == null
      ? _prefs.remove(key)
      : _prefs.setInt(key, t.millisecondsSinceEpoch);

  Future<void> _enqueue(Future<void> Function() work) =>
      _queue = _idle.then((_) => work());

  /// A pass that ran out while calm_ig was on screen is over with no
  /// overtime: you were already back.
  void _closeExpiredPass(DateTime now) {
    final end = _passEnd;
    if (end == null || now.isBefore(end)) return;
    _passEnd = null;
    _enqueue(() => _writeTime(_passEndKey, null));
  }

  /// calm_ig left the foreground.
  Future<void> pause() {
    final since = _runningSince;
    if (since == null) return _idle;
    final now = _now();
    _closeExpiredPass(now);
    _runningSince = null;
    _pausedAt = now;
    return _enqueue(() async {
      await _writeTime(_pausedAtKey, now);
      await stats.addUsage(splitByDay(since, now));
    });
  }

  /// calm_ig is on screen again (or for the first time since launch).
  Future<void> resume() {
    if (_runningSince != null) return _idle;
    final now = _now();
    final coldStart = !_started;
    _started = true;
    final pausedAt = _pausedAt;
    final passEnd = _passEnd;
    // Back from a pass only within its counted window; later returns are
    // ordinary ones.
    final fromPass = passEnd != null && now.isBefore(passEnd.add(passGrace));

    var passTime = <String, Duration>{};
    Duration? overtime;
    if (passEnd != null) {
      // The pass started while calm_ig was on screen, so the time away
      // begins when it left.
      final from = pausedAt ?? now;
      final cap = passEnd.add(passGrace);
      final until = now.isBefore(cap) ? now : cap;
      if (until.isAfter(from)) passTime = splitByDay(from, until);
      if (!now.isBefore(passEnd)) {
        _passEnd = null; // over: account for it once
        final over = until.difference(passEnd);
        // No leave time (the app died while open): overtime is unknown.
        if (over > Duration.zero && pausedAt != null) overtime = over;
      }
      // Still running (came back early): it stays open, and leaving again
      // keeps counting until its end.
    }

    final longAway =
        coldStart ||
        pausedAt == null ||
        now.difference(pausedAt) >= askIntentAfter;
    if (longAway && !fromPass) askIntent.value = true;

    _runningSince = now;
    _pausedAt = null;
    final passClosed = passEnd != null && _passEnd == null;
    return _enqueue(() async {
      await stats.reload(); // pick up bounce counts from the App Intent
      await stats.addUsage(passTime);
      if (overtime != null) await stats.addOvertime(passEnd!, overtime);
      if (passClosed) await _writeTime(_passEndKey, null);
      await _writeTime(_pausedAtKey, null);
      if (coldStart) await stats.prune(now);
    });
  }

  /// A pass to the native app was started; it lasts until [end].
  Future<void> startPass(DateTime end) {
    _passEnd = end;
    askIntent.value = false; // coming back from it never asks

    return _enqueue(() => _writeTime(_passEndKey, end));
  }

  /// The pass was ended early from inside calm_ig (結束).
  Future<void> endPass() {
    _passEnd = null;
    return _enqueue(() => _writeTime(_passEndKey, null));
  }

  /// Saves the on-screen stretch so far (in case the app is killed while
  /// open). Called on a timer from main().
  Future<void> checkpoint() {
    final since = _runningSince;
    if (since == null) return _idle;
    final now = _now();
    _closeExpiredPass(now);
    _runningSince = now;
    return _enqueue(() => stats.addUsage(splitByDay(since, now)));
  }

  /// Re-reads records written outside Dart (bounce counts), in line with
  /// pending writes so a reload can't overwrite one in flight.
  Future<void> refresh() => _enqueue(stats.reload);

  /// Starts listening to the app lifecycle. Lifecycle changes from before
  /// this call are not replayed, so start from the current state.
  void attach() {
    final binding = WidgetsBinding.instance..addObserver(this);
    if (binding.lifecycleState == AppLifecycleState.resumed) resume();
  }

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        resume();
      // `inactive` (Control Center, a notification banner pulled down)
      // keeps the app visible, so it keeps counting.
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        pause();
    }
  }
}

/// `4:07`, or `1:02:03` after an hour.
String formatStopwatch(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h == 0) return '$m:$ss';
  return '$h:${m.toString().padLeft(2, '0')}:$ss';
}

/// `1 小時 23 分`, `45 分`, `0 分`.
String formatMinutes(Duration d) {
  final minutes = d.inMinutes < 0 ? 0 : d.inMinutes;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m 分';
  return '$h 小時 $m 分';
}
