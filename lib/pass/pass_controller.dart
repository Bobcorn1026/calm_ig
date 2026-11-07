import 'package:flutter/foundation.dart';

/// Key of the pass end time (ms since epoch). shared_preferences stores it in
/// `UserDefaults.standard` as `flutter.pass_until_ms`, which is where the
/// iOS App Intent (ios/Runner/InstagramPassIntent.swift) reads it.
const passUntilKey = 'pass_until_ms';

/// How long a pass can be.
const passLengths = [Duration(minutes: 5), Duration(minutes: 10)];

abstract interface class PassStore {
  int? readUntilMs();
  Future<void> writeUntilMs(int? ms);
}

abstract interface class PassNotifier {
  Future<void> scheduleEnd(DateTime at);
  Future<void> cancelEnd();
}

abstract interface class InstagramLauncher {
  /// Opens the native Instagram app; false when it is not installed.
  Future<bool> openInstagram();
}

/// A "pass" lets the native Instagram app open for a few minutes (to post a
/// story) without the Shortcuts automation bouncing back to calm_ig.
class PassController extends ChangeNotifier {
  PassController({
    required this._store,
    required this._notifier,
    required this._launcher,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final PassStore _store;
  final PassNotifier _notifier;
  final InstagramLauncher _launcher;
  final DateTime Function() _now;

  /// When the current pass ends, or null if there is none.
  DateTime? get until {
    final ms = _store.readUntilMs();
    if (ms == null) return null;
    final end = DateTime.fromMillisecondsSinceEpoch(ms);
    return end.isAfter(_now()) ? end : null;
  }

  bool get isActive => until != null;

  Duration get remaining => until?.difference(_now()) ?? Duration.zero;

  /// Starts a pass and opens Instagram. Returns false (and cancels the pass)
  /// if Instagram could not be opened.
  Future<bool> start(Duration length) async {
    final end = _now().add(length);
    // Save first: the automation asks "is a pass active?" the moment
    // Instagram opens.
    await _store.writeUntilMs(end.millisecondsSinceEpoch);
    await _notifier.scheduleEnd(end);
    notifyListeners();
    if (await _launcher.openInstagram()) return true;
    await this.end();
    return false;
  }

  Future<void> end() async {
    await _store.writeUntilMs(null);
    await _notifier.cancelEnd();
    notifyListeners();
  }

  /// Lets listeners redraw the countdown (called by a UI timer).
  void tick() => notifyListeners();
}

/// `4:07` style countdown text.
String formatRemaining(Duration d) {
  final seconds = d.inSeconds.clamp(0, 359999);
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
