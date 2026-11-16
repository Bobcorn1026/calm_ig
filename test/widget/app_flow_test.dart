import 'package:calm_ig/browser/browser_page.dart';
import 'package:calm_ig/browser/reload_handle.dart';
import 'package:calm_ig/main.dart';
import 'package:calm_ig/onboarding/shortcut_setup_page.dart';
import 'package:calm_ig/pass/pass_bar.dart';
import 'package:calm_ig/pass/pass_controller.dart';
import 'package:calm_ig/session/session_stopwatch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../pass/pass_controller_test.dart'
    show FakeLauncher, FakeNotifier, FakeStore;

void main() {
  late FakeStore store;
  late FakeLauncher launcher;
  late FakeNotifier notifier;
  late PassController pass;
  late List<ValueChanged<String>> blockCallbacks;

  setUp(() {
    store = FakeStore();
    launcher = FakeLauncher(store);
    pass = PassController(
      store: store,
      notifier: notifier = FakeNotifier(),
      launcher: launcher,
    );
    blockCallbacks = [];
  });

  Widget app({
    bool setupDone = true,
    VoidCallback? onSetupDone,
    SessionStopwatch? stopwatch,
    ReloadHandle? reloadHandle,
  }) => CalmIgApp(
    pass: pass,
    setupDone: setupDone,
    onSetupDone: () async => onSetupDone?.call(),
    stopwatch: stopwatch,
    reloadHandle: reloadHandle,
    webViewBuilder: (context, onBlocked) {
      blockCallbacks.add(onBlocked);
      return const Center(child: Text('fake web view'));
    },
  );

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

  testWidgets('pass flow: choose 5 minutes, count down, end early', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('發限動'));
    await tester.pumpAndSettle();
    expect(find.text('5 分鐘'), findsOneWidget);
    expect(find.text('10 分鐘'), findsOneWidget);

    await tester.tap(find.text('5 分鐘'));
    await tester.pumpAndSettle();
    expect(launcher.storeValueWhenOpened, isNotNull);
    expect(find.textContaining('原生 IG 放行中'), findsOneWidget);

    await tester.tap(find.text('結束'));
    await tester.pump();
    expect(find.text('發限動'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('notifications off: warn before opening Instagram', (
    tester,
  ) async {
    notifier.allowed = false;
    await tester.pumpWidget(app());
    await tester.tap(find.text('發限動'));
    await tester.pumpAndSettle();
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
    var settingsOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PassBar(
            pass: pass,
            onHelp: () {},
            onOpenSettings: () async => settingsOpened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('發限動'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 分鐘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去設定'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
    expect(launcher.storeValueWhenOpened, isNull);
    expect(find.text('發限動'), findsOneWidget);
  });

  testWidgets('no Instagram installed shows a message', (tester) async {
    launcher.installed = false;
    await tester.pumpWidget(app());
    await tester.tap(find.text('發限動'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 分鐘'));
    await tester.pumpAndSettle();
    expect(find.text('找不到 Instagram app'), findsOneWidget);
    expect(find.text('發限動'), findsOneWidget);
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

  testWidgets('top bar shows the session stopwatch next to the name', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 16, 20);
    final stopwatch = SessionStopwatch(clock: () => now);
    await tester.pumpWidget(app(stopwatch: stopwatch));
    expect(find.text('清醒IG'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    now = now.add(const Duration(minutes: 3, seconds: 9));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3:09'), findsOneWidget);
    // Right of the name, on the same row.
    final name = tester.getCenter(find.text('清醒IG'));
    final clock = tester.getCenter(find.text('3:09'));
    expect(clock.dx, greaterThan(name.dx));
    expect((clock.dy - name.dy).abs(), lessThan(4));
  });

  testWidgets('starting a pass lets the stopwatch continue afterwards', (
    tester,
  ) async {
    final stopwatch = SessionStopwatch();
    await tester.pumpWidget(app(stopwatch: stopwatch));
    await tester.tap(find.text('發限動'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 分鐘'));
    await tester.pumpAndSettle();
    expect(stopwatch.breakAllowedUntil, pass.until);
    await tester.tap(find.text('結束'));
    await tester.pump();
  });

  testWidgets('reload button reaches the web view', (tester) async {
    final handle = ReloadHandle();
    var reloads = 0;
    handle.attach(() async => reloads++);
    await tester.pumpWidget(app(reloadHandle: handle));
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
}
