import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser/browser_page.dart';
import 'browser/reload_handle.dart';
import 'onboarding/shortcut_setup_page.dart';
import 'pass/pass_bar.dart';
import 'pass/pass_controller.dart';
import 'pass/pass_services.dart';
import 'session/session_stopwatch.dart';

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
  // Opened by tapping a reminder after the app was closed: clean up.
  await pass.onResumed();
  final stopwatch = SessionStopwatch(startRunning: false)..attach();
  runApp(
    CalmIgApp(
      pass: pass,
      stopwatch: stopwatch,
      setupDone: prefs.getBool(setupDoneKey) ?? false,
      onSetupDone: () => prefs.setBool(setupDoneKey, true),
    ),
  );
}

class CalmIgApp extends StatelessWidget {
  CalmIgApp({
    super.key,
    required this.pass,
    required this.setupDone,
    required this.onSetupDone,
    this.stopwatch,
    ReloadHandle? reloadHandle,
    this.webViewBuilder,
  }) : reloadHandle = reloadHandle ?? ReloadHandle();

  final PassController pass;

  /// Session time shown next to the app name.
  final SessionStopwatch? stopwatch;

  /// Connects the top bar's reload button to the web view.
  final ReloadHandle reloadHandle;

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
      reloadHandle: reloadHandle,
      topBar: PassBar(
        pass: pass,
        stopwatch: stopwatch,
        onReload: reloadHandle.reload,
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
