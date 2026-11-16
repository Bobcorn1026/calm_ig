import 'package:calm_ig/intent/intent_option.dart';
import 'package:calm_ig/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  test('defaults', () {
    expect(settings.passQuota, AppSettings.defaultPassQuota);
    expect(settings.intentOptions, defaultIntentOptions);
  });

  test('quota is clamped and notifies', () async {
    var calls = 0;
    settings.addListener(() => calls++);
    await settings.setPassQuota(99);
    expect(settings.passQuota, AppSettings.maxPassQuota);
    await settings.setPassQuota(-2);
    expect(settings.passQuota, 0);
    expect(calls, 2);
  });

  test('intent options round-trip, including an empty list', () async {
    const custom = [
      IntentOption(
        id: 'custom-1',
        label: '看阿久',
        action: IntentAction.open,
        path: '/jz._.1026/',
      ),
      IntentOption(id: 'post', label: '發限動', action: IntentAction.pass),
    ];
    await settings.setIntentOptions(custom);
    expect(settings.intentOptions, custom);
    await settings.setIntentOptions(const []);
    expect(settings.intentOptions, isEmpty);
  });
}
