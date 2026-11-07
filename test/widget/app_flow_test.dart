import 'package:calm_ig/browser/browser_page.dart';
import 'package:calm_ig/main.dart';
import 'package:calm_ig/onboarding/shortcut_setup_page.dart';
import 'package:calm_ig/pass/pass_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../pass/pass_controller_test.dart'
    show FakeLauncher, FakeNotifier, FakeStore;

void main() {
  late FakeStore store;
  late FakeLauncher launcher;
  late PassController pass;
  late List<ValueChanged<String>> blockCallbacks;

  setUp(() {
    store = FakeStore();
    launcher = FakeLauncher(store);
    pass = PassController(
      store: store,
      notifier: FakeNotifier(),
      launcher: launcher,
    );
    blockCallbacks = [];
  });

  Widget app({bool setupDone = true, VoidCallback? onSetupDone}) => CalmIgApp(
    pass: pass,
    setupDone: setupDone,
    onSetupDone: () async => onSetupDone?.call(),
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
