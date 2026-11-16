import 'package:shared_preferences/shared_preferences.dart';

import 'session_stopwatch.dart';

/// Keeps the session in shared_preferences so it survives iOS closing the
/// app in the background (common while the memory-heavy Instagram app is
/// open during a pass).
class PrefsSessionStore implements SessionStore {
  PrefsSessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const _bankedKey = 'session_banked_ms';
  static const _pausedAtKey = 'session_paused_at_ms';
  static const _breakUntilKey = 'session_break_until_ms';

  @override
  SessionSnapshot? load() {
    final banked = _prefs.getInt(_bankedKey);
    final pausedAt = _prefs.getInt(_pausedAtKey);
    if (banked == null || pausedAt == null) return null;
    final breakUntil = _prefs.getInt(_breakUntilKey);
    return SessionSnapshot(
      banked: Duration(milliseconds: banked),
      pausedAt: DateTime.fromMillisecondsSinceEpoch(pausedAt),
      breakAllowedUntil: breakUntil == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(breakUntil),
    );
  }

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    await _prefs.setInt(_bankedKey, snapshot.banked.inMilliseconds);
    await _prefs.setInt(_pausedAtKey, snapshot.pausedAt.millisecondsSinceEpoch);
    final breakUntil = snapshot.breakAllowedUntil;
    if (breakUntil == null) {
      await _prefs.remove(_breakUntilKey);
    } else {
      await _prefs.setInt(_breakUntilKey, breakUntil.millisecondsSinceEpoch);
    }
  }
}
