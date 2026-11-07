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
  Future<bool> requestPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true);
    return granted ?? false;
  }

  @override
  Future<void> schedule(List<PassReminder> reminders) async {
    for (final (i, r) in reminders.indexed) {
      await _plugin.zonedSchedule(
        id: i + 1,
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentSound: true,
            // One thread, so the reminders stack instead of piling up.
            threadIdentifier: 'pass-reminders',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    }
  }

  // calm_ig only ever schedules pass reminders, so clearing everything is
  // safe; it also removes delivered ones from Notification Center.
  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// Opens iOS Settings on calm_ig's page (to turn notifications back on).
Future<void> openAppSettings() async {
  await launchUrl(Uri.parse('app-settings:'));
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
