import 'package:calm_ig/intent/intent_option.dart';
import 'package:calm_ig/intent/intent_prompt.dart';
import 'package:calm_ig/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;
  late ValueNotifier<bool> visible;
  late List<IntentOption> chosen;
  late List<bool> visibleWhenChosen;
  late int edits;
  late int pageTaps;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    visible = ValueNotifier(false);
    chosen = [];
    visibleWhenChosen = [];
    edits = 0;
    pageTaps = 0;
  });

  Widget host({Duration browseDelay = const Duration(seconds: 5)}) =>
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // Stands in for the web view.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => pageTaps++,
                ),
              ),
              Positioned.fill(
                child: IntentPrompt(
                  visible: visible,
                  settings: settings,
                  browseDelay: browseDelay,
                  onChoose: (option) async {
                    chosen.add(option);
                    visibleWhenChosen.add(visible.value);
                  },
                  onEditOptions: () => edits++,
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('draws nothing while not visible', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('這次要做什麼？'), findsNothing);
    await tester.tap(find.byType(Scaffold));
    expect(pageTaps, 1);
  });

  testWidgets('shows the saved options in order and blocks the page', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    visible.value = true;
    await tester.pumpAndSettle();

    expect(find.text('這次要做什麼？'), findsOneWidget);
    expect(find.text('想清楚再打開 IG'), findsOneWidget);
    final labels = [for (final o in defaultIntentOptions) o.label];
    final ys = [for (final l in labels) tester.getCenter(find.text(l)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    for (final label in labels) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    // The dimmed area around the card swallows taps.
    await tester.tapAt(const Offset(4, 4));
    expect(pageTaps, 0);
  });

  testWidgets('follows changes to the options while shown', (tester) async {
    visible.value = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await settings.setIntentOptions([
      const IntentOption(
        id: 'custom-1',
        label: '看小明',
        action: IntentAction.open,
        path: '/ming/',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('看小明'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('回私訊'), findsNothing);
  });

  testWidgets('an open option hides the menu before carrying it out', (
    tester,
  ) async {
    visible.value = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('回私訊'));
    await tester.pumpAndSettle();

    expect(chosen, [defaultIntentOptions.first]);
    expect(visibleWhenChosen, [false]);
    expect(visible.value, isFalse);
    expect(find.text('這次要做什麼？'), findsNothing);
  });

  testWidgets('the pass option hides the menu first too', (tester) async {
    visible.value = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('發限動'));
    await tester.pumpAndSettle();

    expect(chosen.single.action, IntentAction.pass);
    expect(visibleWhenChosen, [false]);
  });

  testWidgets('隨便看看 counts down, then shows the page', (tester) async {
    visible.value = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('隨便看看'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(chosen.single.action, IntentAction.browse);
    expect(visibleWhenChosen, [true]);
    expect(find.text('先深呼吸一下'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('這次要做什麼？'), findsNothing);
    expect(find.text('回私訊'), findsNothing);

    await tester.pump(const Duration(milliseconds: 700)); // 1 s in
    expect(find.text('4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // 4 s in
    expect(find.text('1'), findsOneWidget);
    expect(visible.value, isTrue);
    await tester.tapAt(const Offset(4, 4));
    expect(pageTaps, 0);

    await tester.pump(const Duration(seconds: 1)); // 5 s in
    expect(visible.value, isFalse);
    await tester.pump();
    expect(find.text('先深呼吸一下'), findsNothing);
    expect(chosen, hasLength(1));
  });

  testWidgets('the pause follows browseDelay', (tester) async {
    visible.value = true;
    await tester.pumpWidget(host(browseDelay: const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('隨便看看'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(visible.value, isFalse);
  });

  testWidgets('hiding it from outside stops the countdown', (tester) async {
    visible.value = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('隨便看看'));
    await tester.pump();

    visible.value = false;
    await tester.pump();
    expect(find.text('先深呼吸一下'), findsNothing);

    // Shown again later: the menu, not the old countdown.
    visible.value = true;
    await tester.pump(const Duration(seconds: 6));
    expect(visible.value, isTrue);
    expect(find.text('這次要做什麼？'), findsOneWidget);
  });

  testWidgets('with no options it hides itself', (tester) async {
    await settings.setIntentOptions([]);
    await tester.pumpWidget(host());

    visible.value = true;
    await tester.pump();
    await tester.pump();

    expect(visible.value, isFalse);
    expect(find.text('這次要做什麼？'), findsNothing);
    expect(chosen, isEmpty);
  });

  testWidgets('with no options it hides itself on first build too', (
    tester,
  ) async {
    await settings.setIntentOptions([]);
    visible.value = true; // cold start: already asking when built
    await tester.pumpWidget(host());
    await tester.pump();

    expect(visible.value, isFalse);
  });

  testWidgets('編輯選項 opens the editor', (tester) async {
    visible.value = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('編輯選項'));

    expect(edits, 1);
    expect(visible.value, isTrue);
  });

  testWidgets('fits a phone screen, even with many long options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await settings.setIntentOptions([
      for (var i = 0; i < 10; i++)
        IntentOption(
          id: 'custom-$i',
          label: '看看第$i個朋友的限動好嗎',
          action: IntentAction.open,
          path: '/friend$i/',
        ),
    ]);
    visible.value = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 56), // the top bar
              Expanded(
                child: IntentPrompt(
                  visible: visible,
                  settings: settings,
                  onChoose: (_) async {},
                  onEditOptions: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('編輯選項'), findsOneWidget);

    // The breather screen fits too.
    await tester.scrollUntilVisible(find.text('看看第9個朋友的限動好嗎'), 100);
    await settings.setIntentOptions(defaultIntentOptions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('隨便看看'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('先深呼吸一下'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(visible.value, isFalse);
  });
}
