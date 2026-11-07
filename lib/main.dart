import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser/browser_page.dart';
import 'onboarding/shortcut_setup_page.dart';
import 'pass/pass_bar.dart';
import 'pass/pass_controller.dart';
import 'pass/pass_services.dart';

const setupDoneKey = 'shortcut_setup_done';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final notifier = LocalPassNotifier();
  await notifier.init();
  final pass = PassController(
    store: PrefsPassStore(prefs),
    notifier: notifier,
    launcher: UrlInstagramLauncher(),
  );
  runApp(
    CalmIgApp(
      pass: pass,
      setupDone: prefs.getBool(setupDoneKey) ?? false,
      onSetupDone: () => prefs.setBool(setupDoneKey, true),
    ),
  );
}

class CalmIgApp extends StatelessWidget {
  const CalmIgApp({
    super.key,
    required this.pass,
    required this.setupDone,
    required this.onSetupDone,
    this.webViewBuilder,
  });

  final PassController pass;

  /// Whether the Shortcuts guide was already confirmed once.
  final bool setupDone;
  final Future<void> Function() onSetupDone;

  /// Replaces the real web view in widget tests.
  final Widget Function(BuildContext, ValueChanged<String>)? webViewBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '清醒IG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: setupDone
          ? _browser()
          : Builder(
              builder: (context) => ShortcutSetupPage(
                onDone: () {
                  onSetupDone();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => _browser()),
                  );
                },
              ),
            ),
    );
  }

  Widget _browser() => Builder(
    builder: (context) => BrowserPage(
      webViewBuilder: webViewBuilder,
      topBar: PassBar(
        pass: pass,
        onHelp: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                ShortcutSetupPage(onDone: () => Navigator.of(context).pop()),
          ),
        ),
      ),
    ),
  );
}
