import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'pass_controller.dart';

class PrefsPassStore implements PassStore {
  PrefsPassStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  int? readUntilMs() => _prefs.getInt(passUntilKey);

  @override
  Future<void> writeUntilMs(int? ms) async {
    if (ms == null) {
      await _prefs.remove(passUntilKey);
    } else {
      await _prefs.setInt(passUntilKey, ms);
    }
  }
}

class LocalPassNotifier implements PassNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _id = 1;

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Ask for permission only when the first pass starts.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  @override
  Future<void> scheduleEnd(DateTime at) async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true);
    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: '放行時間到了',
      body: '限動發完了嗎？點這裡回清醒IG。',
    );
  }

  @override
  Future<void> cancelEnd() => _plugin.cancel(id: _id);
}

class UrlInstagramLauncher implements InstagramLauncher {
  @override
  Future<bool> openInstagram() async {
    // Open straight into the camera (to post a story); fall back to the app.
    for (final url in ['instagram://camera', 'instagram://app']) {
      try {
        if (await launchUrl(Uri.parse(url))) return true;
      } on PlatformException {
        // Not installed or scheme rejected; try the next one.
      }
    }
    return false;
  }
}
