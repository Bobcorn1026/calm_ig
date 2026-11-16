import 'package:calm_ig/intent/intent_option.dart';
import 'package:calm_ig/intent/intent_options_page.dart';
import 'package:calm_ig/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  List<String> ids() => [for (final o in settings.intentOptions) o.id];

  /// The page on a 375×812 phone.
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: IntentOptionsPage(settings: settings)),
    );
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  test('describes what each option does', () {
    expect(describeIntentOption(defaultIntentOptions[0]), '打開私訊');
    expect(describeIntentOption(defaultIntentOptions[1]), '打開限動（首頁）');
    expect(describeIntentOption(defaultIntentOptions[2]), '開始發限動（放行原生 IG）');
    expect(describeIntentOption(defaultIntentOptions[3]), '等 5 秒再看');
    const profile = IntentOption(
      id: 'x',
      label: 'x',
      action: IntentAction.open,
      path: '/ming.lee/',
    );
    expect(describeIntentOption(profile), '打開 @ming.lee 的個人頁');
  });

  testWidgets('lists the default options with what they do', (tester) async {
    await pumpPage(tester);

    expect(find.text('開場選項'), findsOneWidget);
    expect(find.textContaining('離開超過 5 分鐘再回來'), findsOneWidget);
    for (final option in defaultIntentOptions) {
      expect(find.text(option.label), findsOneWidget);
    }
    expect(find.text('打開私訊'), findsOneWidget);
    expect(find.text('打開限動（首頁）'), findsOneWidget);
    expect(find.text('開始發限動（放行原生 IG）'), findsOneWidget);
    expect(find.text('等 5 秒再看'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds an option that opens a profile', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('打開頁面'), findsOneWidget);

    await tester.enterText(field('名稱'), '  看小明  ');
    await tapVisible(tester, find.text('某個帳號的個人頁'));
    await tester.enterText(field('帳號'), 'ming lee!');
    await tapVisible(tester, find.text('儲存'));

    expect(find.text('帳號只能有英文字母、數字、. 和 _'), findsOneWidget);
    expect(settings.intentOptions, defaultIntentOptions);
    expect(tester.takeException(), isNull);

    await tester.enterText(field('帳號'), '@ming.lee');
    await tapVisible(tester, find.text('儲存'));

    final added = settings.intentOptions.last;
    expect(settings.intentOptions, hasLength(5));
    expect(added.id, startsWith('custom-'));
    expect(added.label, '看小明');
    expect(added.action, IntentAction.open);
    expect(added.path, '/ming.lee/');
    expect(find.text('看小明'), findsOneWidget);
    expect(find.text('打開 @ming.lee 的個人頁'), findsOneWidget);
  });

  testWidgets('a name is required and must be new', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('儲存'));
    expect(find.text('請輸入名稱'), findsOneWidget);

    await tester.enterText(field('名稱'), '回私訊');
    await tapVisible(tester, find.text('儲存'));
    expect(find.text('已經有叫「回私訊」的選項了'), findsOneWidget);

    await tester.enterText(field('名稱'), '一二三四五六七八九十一二三四');
    expect(find.text('一二三四五六七八九十一二'), findsOneWidget); // capped at 12
    await tapVisible(tester, find.text('發限動').last);
    await tapVisible(tester, find.text('儲存'));

    expect(settings.intentOptions.last.label, '一二三四五六七八九十一二');
    expect(settings.intentOptions.last.action, IntentAction.pass);
  });

  testWidgets('cancel leaves the options alone', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(field('名稱'), '不要了');

    await tapVisible(tester, find.text('取消'));

    expect(find.text('儲存'), findsNothing);
    expect(settings.intentOptions, defaultIntentOptions);
  });

  testWidgets('renames an option, keeping its id and page', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('回私訊'));
    await tester.pumpAndSettle();
    expect(find.text('編輯選項'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '私訊')).selected,
      isTrue,
    );

    await tester.enterText(field('名稱'), '回訊息');
    await tapVisible(tester, find.text('儲存'));

    expect(
      settings.intentOptions.first,
      defaultIntentOptions.first.copyWith(label: '回訊息'),
    );
    expect(ids(), ['dm', 'stories', 'post', 'browse']);
    expect(find.text('回訊息'), findsOneWidget);
    expect(find.text('回私訊'), findsNothing);
  });

  testWidgets('changes what an option does', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('隨便看看'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('打開頁面'));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, '搜尋'));
    await tapVisible(tester, find.text('儲存'));

    final changed = settings.intentOptions.last;
    expect(changed.id, 'browse');
    expect(changed.action, IntentAction.open);
    expect(changed.path, '/explore/search/');
    expect(find.text('打開搜尋'), findsOneWidget);
  });

  testWidgets('editing a profile option shows its account', (tester) async {
    await settings.setIntentOptions([
      const IntentOption(
        id: 'custom-1',
        label: '看小明',
        action: IntentAction.open,
        path: '/ming.lee/',
      ),
    ]);
    await pumpPage(tester);

    await tester.tap(find.text('看小明'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '某個帳號的個人頁'))
          .selected,
      isTrue,
    );
    expect(find.widgetWithText(TextFormField, 'ming.lee'), findsOneWidget);
  });

  testWidgets('deletes an option, and 復原 puts it back', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('刪除「看限動」'));
    await tester.pumpAndSettle();

    expect(ids(), ['dm', 'post', 'browse']);
    expect(find.text('看限動'), findsNothing);
    expect(find.text('已刪除「看限動」'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await tester.pumpAndSettle();

    expect(settings.intentOptions, defaultIntentOptions);
    expect(find.text('看限動'), findsOneWidget);
  });

  testWidgets('shows a note when every option is gone', (tester) async {
    await settings.setIntentOptions([]);
    await pumpPage(tester);

    expect(find.text('沒有選項時，打開清醒IG 就不會問。'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });

  testWidgets('恢復預設 brings back the defaults after confirming', (tester) async {
    await settings.setIntentOptions([
      const IntentOption(
        id: 'custom-1',
        label: '看小明',
        action: IntentAction.browse,
      ),
    ]);
    await pumpPage(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢復預設'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(ids(), ['custom-1']);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢復預設'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢復'));
    await tester.pumpAndSettle();

    expect(settings.intentOptions, defaultIntentOptions);
    expect(find.text('看小明'), findsNothing);
    expect(find.text('回私訊'), findsOneWidget);
  });

  testWidgets('dragging a handle saves the new order', (tester) async {
    await pumpPage(tester);

    final handle = find.byIcon(Icons.drag_handle).first;
    final rowHeight = tester.getSize(find.byType(ListTile).first).height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 1.3 / 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(ids(), ['stories', 'dm', 'post', 'browse']);
    final dmY = tester.getCenter(find.text('回私訊')).dy;
    final storiesY = tester.getCenter(find.text('看限動')).dy;
    expect(storiesY, lessThan(dmY));
  });

  testWidgets('the editor fits a phone screen', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('某個帳號的個人頁'));
    await tapVisible(tester, find.text('儲存')); // shows both errors

    expect(tester.takeException(), isNull);
    expect(find.text('請輸入名稱'), findsOneWidget);
    expect(find.text('請輸入帳號'), findsOneWidget);

    await tapVisible(tester, find.text('發限動').last);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.text('隨便看看').last);
    expect(tester.takeException(), isNull);
  });
}
