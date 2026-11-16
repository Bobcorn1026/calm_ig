import 'package:flutter/widgets.dart';

/// Leaving calm_ig for at least this long starts a new session (the
/// stopwatch goes back to 0:00). Shorter breaks — replying in another app,
/// locking the phone for a moment — just pause it.
const sessionResetAfter = Duration(minutes: 5);

/// What survives iOS closing the app while it is in the background.
class SessionSnapshot {
  const SessionSnapshot({
    required this.banked,
    required this.pausedAt,
    this.breakAllowedUntil,
  });

  final Duration banked;
  final DateTime pausedAt;
  final DateTime? breakAllowedUntil;
}

abstract interface class SessionStore {
  SessionSnapshot? load();
  Future<void> save(SessionSnapshot snapshot);
}

/// Counts how long calm_ig has been on screen in this session.
///
/// Runs only while the app is in the foreground. It watches the app
/// lifecycle itself (call [attach] once), so it keeps counting correctly no
/// matter which widgets are on screen.
class SessionStopwatch with WidgetsBindingObserver {
  /// [startRunning] is for tests; the app starts paused and lets [attach]
  /// start it only if the app is really in the foreground.
  ///
  /// With a [store], the session is saved whenever the app leaves the
  /// foreground and picked up again on the next launch, so iOS closing the
  /// app in the background doesn't reset the stopwatch.
  SessionStopwatch({
    DateTime Function()? clock,
    this.resetAfter = sessionResetAfter,
    bool startRunning = true,
    SessionStore? store,
  }) : _now = clock ?? DateTime.now,
       _store = store {
    final saved = store?.load();
    if (saved != null) {
      _banked = saved.banked;
      _pausedAt = saved.pausedAt;
      _breakAllowedUntil = saved.breakAllowedUntil;
    } else if (startRunning) {
      _runningSince = _now();
    }
  }

  final DateTime Function() _now;
  final Duration resetAfter;
  final SessionStore? _store;

  /// Time counted before the current running stretch.
  Duration _banked = Duration.zero;

  /// When the current running stretch started; null while paused.
  DateTime? _runningSince;

  /// When the stopwatch was paused; null while running.
  DateTime? _pausedAt;

  /// A planned break (a pass to the native Instagram app) lasts until here;
  /// the 5-minute reset is counted from this time instead of the pause.
  DateTime? _breakAllowedUntil;

  bool get isRunning => _runningSince != null;

  @visibleForTesting
  DateTime? get breakAllowedUntil => _breakAllowedUntil;

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
    _save();
  }

  void resume() {
    if (_runningSince != null) return;
    final now = _now();
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      final breakUntil = _breakAllowedUntil;
      final breakStart = breakUntil != null && breakUntil.isAfter(pausedAt)
          ? breakUntil
          : pausedAt;
      if (now.difference(breakStart) >= resetAfter) _banked = Duration.zero;
    }
    _runningSince = now;
    _pausedAt = null;
    _breakAllowedUntil = null;
  }

  /// Leaving until [until] doesn't end the session: coming back within
  /// [resetAfter] after it continues the stopwatch. Used for passes.
  void allowBreakUntil(DateTime until) {
    _breakAllowedUntil = until;
    _save();
  }

  void _save() {
    final pausedAt = _pausedAt;
    final store = _store;
    if (store == null) return;
    // While running there is nothing to resume from yet; the next pause
    // saves. A planned break started from the foreground is saved by that
    // pause too, but saving here keeps it if the app dies first.
    store.save(
      SessionSnapshot(
        banked: elapsed,
        pausedAt: pausedAt ?? _now(),
        breakAllowedUntil: _breakAllowedUntil,
      ),
    );
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
