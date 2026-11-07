// Checks that the real notification plugin queues the pass reminders on iOS:
//   flutter test integration_test/reminders_test.dart -d <simulator-id>
import 'package:calm_ig/pass/pass_controller.dart';
import 'package:calm_ig/pass/pass_services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pass queues 5 reminders and cancelAll clears them', (_) async {
    final notifier = LocalPassNotifier();
    await notifier.init();
    final plugin = FlutterLocalNotificationsPlugin();
    // A fresh install has no permission; tap "Allow" on the simulator.
    expect(await notifier.requestPermission(), isTrue);
    await notifier.cancelAll();

    final end = DateTime.now().add(const Duration(hours: 1));
    await notifier.schedule(remindersFor(end));

    final pending = await plugin.pendingNotificationRequests();
    expect(pending.map((p) => p.id).toSet(), {1, 2, 3, 4, 5});
    expect(pending.firstWhere((p) => p.id == 1).title, '放行時間到了');
    expect(pending.firstWhere((p) => p.id == 5).body, contains('超過 4 分鐘'));

    await notifier.cancelAll();
    expect(await plugin.pendingNotificationRequests(), isEmpty);
  });
}
