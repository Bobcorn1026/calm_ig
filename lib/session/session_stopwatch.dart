import 'package:flutter/widgets.dart';

/// Leaving calm_ig for at least this long starts a new session (the
/// stopwatch goes back to 0:00). Shorter breaks — replying in another app,
/// locking the phone for a moment — just pause it.
const sessionResetAfter = Duration(minutes: 5);

/// Counts how long calm_ig has been on screen in this session.
///
/// Runs only while the app is in the foreground. It watches the app
/// lifecycle itself (call [attach] once), so it keeps counting correctly no
/// matter which widgets are on screen.
class SessionStopwatch with WidgetsBindingObserver {
  /// [startRunning] is for tests; the app starts paused and lets [attach]
  /// start it only if the app is really in the foreground.
  SessionStopwatch({
    DateTime Function()? clock,
    this.resetAfter = sessionResetAfter,
    bool startRunning = true,
  }) : _now = clock ?? DateTime.now {
    if (startRunning) _runningSince = _now();
  }

  final DateTime Function() _now;
  final Duration resetAfter;

  /// Time counted before the current running stretch.
  Duration _banked = Duration.zero;

  /// When the current running stretch started; null while paused.
  DateTime? _runningSince;

  /// When the stopwatch was paused; null while running.
  DateTime? _pausedAt;

  bool get isRunning => _runningSince != null;

  Duration get elapsed {
    final since = _runningSince;
    return since == null ? _banked : _banked + _now().difference(since);
  }

  void pause() {
    final since = _runningSince;
    if (since == null) return;
    final now = _now();
    _banked += now.difference(since);
    _runningSince = null;
    _pausedAt = now;
  }

  void resume() {
    if (_runningSince != null) return;
    final now = _now();
    final pausedAt = _pausedAt;
    if (pausedAt != null && now.difference(pausedAt) >= resetAfter) {
      _banked = Duration.zero;
    }
    _runningSince = now;
    _pausedAt = null;
  }

  /// Starts listening to the app lifecycle. Lifecycle changes that happened
  /// before this call are not replayed, so start from the current state.
  void attach() {
    final binding = WidgetsBinding.instance..addObserver(this);
    if (binding.lifecycleState == AppLifecycleState.resumed) {
      resume();
    }
  }

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        resume();
      // `inactive` (Control Center, a notification banner pulled down) keeps
      // the app visible, so it keeps counting.
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
