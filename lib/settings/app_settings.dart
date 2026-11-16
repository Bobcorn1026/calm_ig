import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../intent/intent_option.dart';

/// User settings, in shared_preferences. Notifies on change so open screens
/// redraw.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const passQuotaKey = 'pass_daily_quota';
  static const intentOptionsKey = 'intent_options';

  static const defaultPassQuota = 3;
  static const maxPassQuota = 10;

  /// Passes per day before the "type a sentence" friction kicks in.
  int get passQuota =>
      (_prefs.getInt(passQuotaKey) ?? defaultPassQuota).clamp(0, maxPassQuota);

  Future<void> setPassQuota(int value) async {
    await _prefs.setInt(passQuotaKey, value.clamp(0, maxPassQuota));
    notifyListeners();
  }

  /// The "這次要做什麼？" menu, in order. Empty means the menu is skipped.
  List<IntentOption> get intentOptions =>
      decodeIntentOptions(_prefs.getString(intentOptionsKey));

  Future<void> setIntentOptions(List<IntentOption> options) async {
    await _prefs.setString(intentOptionsKey, encodeIntentOptions(options));
    notifyListeners();
  }
}
