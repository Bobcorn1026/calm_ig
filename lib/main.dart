import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser/browser_page.dart';
import 'browser/web_view_handle.dart';
import 'filter/filter_health.dart';
import 'intent/intent_option.dart';
import 'intent/intent_options_page.dart';
import 'intent/intent_prompt.dart';
import 'onboarding/shortcut_setup_page.dart';
import 'pass/pass_bar.dart';
import 'pass/pass_controller.dart';
import 'pass/pass_flow.dart';
import 'pass/pass_services.dart';
import 'settings/app_settings.dart';
import 'stats/daily_stats.dart';
import 'stats/stats_page.dart';
import 'stats/usage_tracker.dart';

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
  final stats = StatsStore(prefs);
  final tracker = UsageTracker(stats: stats, prefs: prefs)..attach();
  // Save the on-screen time now and then, in case the app dies while open.
  Timer.periodic(const Duration(seconds: 30), (_) => tracker.checkpoint());
  runApp(
    CalmIgApp(
      pass: pass,
      stats: stats,
      tracker: tracker,
      settings: AppSettings(prefs),
      setupDone: prefs.getBool(setupDoneKey) ?? false,
      onSetupDone: () => prefs.setBool(setupDoneKey, true),
    ),
  );
}

class CalmIgApp extends StatelessWidget {
  CalmIgApp({
    super.key,
    required this.pass,
    required this.stats,
    required this.tracker,
    required this.settings,
    required this.setupDone,
    required this.onSetupDone,
    WebViewHandle? handle,
    this.onOpenSettings = openAppSettings,
    this.webViewBuilder,
  }) : handle = handle ?? WebViewHandle();

  final PassController pass;
  final StatsStore stats;
  final UsageTracker tracker;
  final AppSettings settings;

  /// Whether the Shortcuts guide was already confirmed once.
  final bool setupDone;
  final Future<void> Function() onSetupDone;

  /// Connects the top bar and the "這次要做什麼？" menu to the web view.
  final WebViewHandle handle;

  /// Opens iOS Settings (to turn notifications on); replaced in tests.
  final Future<void> Function() onOpenSettings;

  /// Replaces the real web view in widget tests.
  final Widget Function(BuildContext, ValueChanged<String>)? webViewBuilder;

  /// Latest report from the filter script (null until the first one).
  final filterHealth = ValueNotifier<FilterHealth?>(null);

  late final flow = PassFlow(
    pass: pass,
    stats: stats,
    settings: settings,
    tracker: tracker,
    onOpenSettings: onOpenSettings,
  );

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

  void _openIntentOptions(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => IntentOptionsPage(settings: settings),
    ),
  );

  Future<void> _choose(BuildContext context, IntentOption option) async {
    if (option.action == IntentAction.pass) {
      // Only counts once a pass really started; backing out brings the menu
      // back instead of leaving the page unguarded.
      final started = await flow.run(context);
      if (started) {
        await stats.recordIntent(DateTime.now(), option.label);
      } else {
        tracker.askIntent.value = true;
      }
      return;
    }
    await stats.recordIntent(DateTime.now(), option.label);
    if (!context.mounted) return;
    switch (option.action) {
      case IntentAction.open:
        await handle.open(option.path);
      case IntentAction.pass:
        break; // handled above
      case IntentAction.browse:
        break; // the prompt itself makes you wait a moment
    }
  }

  Widget _browser() => Builder(
    builder: (context) => BrowserPage(
      webViewBuilder: webViewBuilder,
      handle: handle,
      onFilterHealth: (health) => filterHealth.value = health,
      topBar: PassBar(
        flow: flow,
        filterHealth: filterHealth,
        onReload: handle.reload,
        onOpenStats: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => StatsPage(
              stats: stats,
              tracker: tracker,
              settings: settings,
              onEditIntentOptions: () => _openIntentOptions(context),
            ),
          ),
        ),
        onHelp: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                ShortcutSetupPage(onDone: () => Navigator.of(context).pop()),
          ),
        ),
      ),
      overlay: IntentPrompt(
        visible: tracker.askIntent,
        settings: settings,
        onChoose: (option) => _choose(context, option),
        onEditOptions: () => _openIntentOptions(context),
      ),
    ),
  );
}
