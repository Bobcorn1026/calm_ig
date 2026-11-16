import 'package:flutter/foundation.dart';

/// Key of the pass end time (ms since epoch). shared_preferences stores it in
/// `UserDefaults.standard` as `flutter.pass_until_ms`, which is where the
/// iOS App Intent (ios/Runner/InstagramPassIntent.swift) reads it.
const passUntilKey = 'pass_until_ms';

/// How long a pass can be.
const passLengths = [Duration(minutes: 5), Duration(minutes: 10)];

/// iOS can't pull you out of Instagram when a pass ends, so calm_ig keeps
/// reminding you: one notification at the end, then one every
/// [reminderInterval], [reminderCount] in total, until you come back.
const reminderCount = 5;
const reminderInterval = Duration(minutes: 1);

class PassReminder {
  const PassReminder({
    required this.at,
    required this.title,
    required this.body,
  });

  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => 'PassReminder($at, $title, $body)';
}

/// The reminders for a pass that ends at [end].
List<PassReminder> remindersFor(DateTime end) => [
  for (var i = 0; i < reminderCount; i++)
    PassReminder(
      at: end.add(reminderInterval * i),
      title: i == 0 ? '放行時間到了' : '還在 IG 嗎？',
      body: i == 0
          ? '限動發完了嗎？點這裡回清醒IG。'
          : '已經超過 ${(reminderInterval * i).inMinutes} 分鐘了，點這裡回清醒IG。',
    ),
];

abstract interface class PassStore {
  int? readUntilMs();
  Future<void> writeUntilMs(int? ms);
}

abstract interface class PassNotifier {
  /// Asks for notification permission if needed; true when allowed.
  Future<bool> requestPermission();
  Future<void> schedule(List<PassReminder> reminders);
  Future<void> cancelAll();
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

  /// A pass whose time ran out but that was never ended (its reminders may
  /// still be scheduled).
  bool get isExpired => _store.readUntilMs() != null && !isActive;

  Duration get remaining => until?.difference(_now()) ?? Duration.zero;

  /// Whether reminders can be shown (asks the first time).
  Future<bool> canRemind() => _notifier.requestPermission();

  /// Starts a pass and opens Instagram. Returns false (and cancels the pass)
  /// if Instagram could not be opened.
  Future<bool> start(Duration length) async {
    final end = _now().add(length);
    // Save first: the automation asks "is a pass active?" the moment
    // Instagram opens.
    await _store.writeUntilMs(end.millisecondsSinceEpoch);
    await _notifier.cancelAll();
    await _notifier.schedule(remindersFor(end));
    notifyListeners();
    if (await _launcher.openInstagram()) return true;
    await this.end();
    return false;
  }

  Future<void> end() async {
    await _store.writeUntilMs(null);
    await _notifier.cancelAll();
    notifyListeners();
  }

  /// Call when calm_ig comes back to the foreground. If the pass is over,
  /// you are back: stop the remaining reminders. A pass that is still
  /// running is left alone (you may go back to Instagram).
  Future<void> onResumed() async {
    if (isExpired) {
      await end();
    } else {
      notifyListeners();
    }
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
