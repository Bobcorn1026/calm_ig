import 'package:calm_ig/browser/browser_page.dart';
import 'package:calm_ig/browser/web_view_handle.dart';
import 'package:calm_ig/filter/filter_health.dart';
import 'package:calm_ig/main.dart';
import 'package:calm_ig/onboarding/shortcut_setup_page.dart';
import 'package:calm_ig/pass/pass_controller.dart';
import 'package:calm_ig/pass/pass_flow.dart';
import 'package:calm_ig/settings/app_settings.dart';
import 'package:calm_ig/stats/daily_stats.dart';
import 'package:calm_ig/stats/stats_page.dart';
import 'package:calm_ig/stats/usage_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pass/pass_controller_test.dart'
    show FakeLauncher, FakeNotifier, FakeStore;

void main() {
  late FakeStore store;
  late FakeLauncher launcher;
  late FakeNotifier notifier;
  late PassController pass;
  late SharedPreferences prefs;
  late StatsStore stats;
  late AppSettings settings;
  late UsageTracker tracker;
  late List<ValueChanged<String>> blockCallbacks;
  var settingsOpened = false;

  setUp(() async {
    store = FakeStore();
    launcher = FakeLauncher(store);
    pass = PassController(
      store: store,
      notifier: notifier = FakeNotifier(),
      launcher: launcher,
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    stats = StatsStore(prefs);
    settings = AppSettings(prefs);
    tracker = UsageTracker(stats: stats, prefs: prefs);
    blockCallbacks = [];
    settingsOpened = false;
  });

  CalmIgApp app({
    bool setupDone = true,
    VoidCallback? onSetupDone,
    UsageTracker? withTracker,
    WebViewHandle? handle,
  }) => CalmIgApp(
    pass: pass,
    stats: stats,
    tracker: withTracker ?? tracker,
    settings: settings,
    setupDone: setupDone,
    onSetupDone: () async => onSetupDone?.call(),
    handle: handle,
    onOpenSettings: () async => settingsOpened = true,
    webViewBuilder: (context, onBlocked) {
      blockCallbacks.add(onBlocked);
      return const Center(child: Text('fake web view'));
    },
  );

  DayStats today() => stats.today(DateTime.now());

  Future<void> openPassSheet(WidgetTester tester) async {
    await tester.tap(find.text('發限動'));
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows the Shortcuts guide, then the browser', (
    tester,
  ) async {
    var marked = false;
    await tester.pumpWidget(
      app(setupDone: false, onSetupDone: () => marked = true),
    );
    expect(find.byType(ShortcutSetupPage), findsOneWidget);
    for (final step in setupSteps) {
      await tester.scrollUntilVisible(find.text(step.title), 100);
      expect(find.text(step.title), findsOneWidget);
    }

    await tester.scrollUntilVisible(find.text('我設定好了'), 100);
    expect(find.text('打開捷徑 app'), findsOneWidget);
    expect(find.text(legacySetupNote), findsOneWidget);
    await tester.tap(find.text('我設定好了'));
    await tester.pumpAndSettle();
    expect(marked, isTrue);
    expect(find.text('fake web view'), findsOneWidget);
    expect(find.text('發限動'), findsOneWidget);
  });

  testWidgets('pass flow: shows today and quota, records the pass', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openPassSheet(tester);
    expect(find.text('今天已放行 0 次 · 額度 3 次'), findsOneWidget);

    await tester.tap(find.text('5 分鐘'));
    await tester.pumpAndSettle();
    expect(launcher.storeValueWhenOpened, isNotNull);
    expect(find.textContaining('原生 IG 放行中'), findsOneWidget);
    expect(today().passes, 1);
    expect(today().overQuotaPasses, 0);
    expect(tracker.passEnd, pass.until);

    await tester.tap(find.text('結束'));
    await tester.pumpAndSettle();
    expect(find.text('發限動'), findsOneWidget);
    expect(store.value, isNull);
    expect(tracker.passEnd, isNull);
  });

  testWidgets('over quota: type the sentence to go anyway', (tester) async {
    for (var i = 0; i < 3; i++) {
      await stats.recordPass(DateTime.now(), overQuota: false, quota: 3);
    }
    await tester.pumpWidget(app());
    await openPassSheet(tester);
    expect(find.textContaining('額度已用完'), findsOneWidget);
    await tester.tap(find.text('5 分鐘'));
    await tester.pumpAndSettle();
    expect(find.text('今天的放行額度用完了（3/3）'), findsOneWidget);

    FilledButton goButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '放行'));
    expect(goButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '我需要');
    await tester.pump();
    expect(goButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), overQuotaPhrase);
    await tester.pump();
    expect(goButton().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, '放行'));
    await tester.pumpAndSettle();
    expect(launcher.storeValueWhenOpened, isNotNull);
    expect(today().passes, 4);
    expect(today().overQuotaPasses, 1);
  });

  testWidgets('over quota: 算了 opens nothing', (tester) async {
    await settings.setPassQuota(0);
    await tester.pumpWidget(app());
    await openPassSheet(tester);
    await tester.tap(find.text('10 分鐘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('算了'));
    await tester.pumpAndSettle();
    expect(launcher.storeValueWhenOpened, isNull);
    expect(today().passes, 0);
  });

  testWidgets('notifications off: warn before opening Instagram', (
    tester,
  ) async {
    notifier.allowed = false;
    await tester.pumpWidget(app());
    await openPassSheet(tester);
    await tester.tap(find.text('5 分鐘'));
    await tester.pumpAndSettle();
    expect(find.text('通知被關掉了'), findsOneWidget);
    expect(launcher.storeValueWhenOpened, isNull);

    await tester.tap(find.text('照樣放行'));
    await tester.pumpAndSettle();
    expect(launcher.storeValueWhenOpened, isNotNull);
    expect(find.textContaining('原生 IG 放行中'), findsOneWidget);
  });

  testWidgets('notifications off: 去設定 does not open Instagram', (tester) async {
    notifier.allowed = false;
    await tester.pumpWidget(app());
    await openPassSheet(tester);
    await tester.tap(find.text('10 分鐘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去設定'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
    expect(launcher.storeValueWhenOpened, isNull);
    expect(today().passes, 0);
  });

  testWidgets('no Instagram installed: message, nothing recorded', (
    tester,
  ) async {
    launcher.installed = false;
    await tester.pumpWidget(app());
    await openPassSheet(tester);
    await tester.tap(find.text('10 分鐘'));
    await tester.pumpAndSettle();
    expect(find.text('找不到 Instagram app'), findsOneWidget);
    expect(today().passes, 0);
    expect(tracker.passEnd, isNull);
  });

  testWidgets('help button opens the guide and 我設定好了 returns', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('捷徑設定教學'));
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutSetupPage), findsOneWidget);
    await tester.scrollUntilVisible(find.text('我設定好了'), 100);
    await tester.tap(find.text('我設定好了'));
    await tester.pumpAndSettle();
    expect(find.text('fake web view'), findsOneWidget);
  });

  testWidgets('top bar shows today\'s time next to the name; tap opens 紀錄', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 16, 20);
    final clocked = UsageTracker(stats: stats, prefs: prefs, clock: () => now);
    await clocked.resume();
    clocked.askIntent.value = false;
    await tester.pumpWidget(app(withTracker: clocked));
    expect(find.text('清醒IG'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    now = now.add(const Duration(minutes: 3, seconds: 9));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3:09'), findsOneWidget);
    final name = tester.getCenter(find.text('清醒IG'));
    final clock = tester.getCenter(find.text('3:09'));
    expect(clock.dx, greaterThan(name.dx));
    expect((clock.dy - name.dy).abs(), lessThan(4));

    await tester.tap(find.text('3:09'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);
  });

  testWidgets('filter warning appears only while the filter reports issues', (
    tester,
  ) async {
    final widget = app();
    await tester.pumpWidget(widget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    widget.filterHealth.value = const FilterHealth(
      ok: false,
      issues: ['home-feed-visible'],
    );
    await tester.pump();
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.warning_amber_rounded));
    await tester.pumpAndSettle();
    expect(find.text('過濾可能失效'), findsOneWidget);
    expect(find.textContaining('首頁的推薦貼文沒有藏住'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    widget.filterHealth.value = const FilterHealth(ok: true);
    await tester.pump();
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('reload button reaches the web view', (tester) async {
    final handle = WebViewHandle();
    var reloads = 0;
    handle.attach(reload: () async => reloads++, open: (_) async {});
    await tester.pumpWidget(app(handle: handle));
    await tester.tap(find.byTooltip('重新載入'));
    expect(reloads, 1);
  });

  testWidgets('blocked pages show a toast', (tester) async {
    await tester.pumpWidget(app());
    blockCallbacks.last('/reels/C9abc/');
    await tester.pump();
    expect(find.text('已擋下 Reels'), findsOneWidget);
  });

  test('blockedMessage', () {
    expect(blockedMessage('/reels/'), '已擋下 Reels');
    expect(blockedMessage('/explore/'), '探索頁已擋下，改開搜尋');
    expect(blockedMessage('/other/'), '已擋下');
  });

  test('FilterHealth parses script messages', () {
    expect(FilterHealth.fromMessage({'kind': 'blocked'}), isNull);
    expect(FilterHealth.fromMessage('nope'), isNull);
    final h = FilterHealth.fromMessage({
      'kind': 'filter',
      'ok': false,
      'issues': ['reels-link-visible', 'mystery'],
    })!;
    expect(h.ok, isFalse);
    expect(h.descriptions.first, contains('Reels'));
    expect(h.descriptions.last, contains('mystery'));
  });

  test('WebViewHandle open/reload reach only the attached view', () async {
    final handle = WebViewHandle();
    await handle.reload();
    await handle.open('/x/');
    final opened = <String>[];
    Future<void> reload() async {}
    handle.attach(reload: reload, open: (p) async => opened.add(p));
    await handle.open('/direct/inbox/');
    expect(opened, ['/direct/inbox/']);
    handle.detach(reload);
    await handle.open('/y/');
    expect(opened, ['/direct/inbox/']);
  });
}
