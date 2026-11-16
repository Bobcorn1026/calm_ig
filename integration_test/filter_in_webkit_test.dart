// Runs the real filter script inside WKWebView on a simulator:
//   flutter test integration_test -d <simulator-id>
import 'dart:async';

import 'package:calm_ig/browser/ig_web_view.dart';
import 'package:calm_ig/filter/filter_config.dart';
import 'package:calm_ig/filter/filter_health.dart';
import 'package:calm_ig/filter/filter_script.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/fake_ig.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('filter script hides Reels and catches jumps to it', (
    tester,
  ) async {
    const config = FilterConfig();
    final script = await loadFilterScript(config);
    final loaded = Completer<InAppWebViewController>();
    final blocked = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IgWebView(
            config: config,
            filterScript: script,
            onBlocked: blocked.add,
            debugInitialHtml: fakeIgHtml,
            onPageLoaded: (c) {
              if (!loaded.isCompleted) loaded.complete(c);
            },
          ),
        ),
      ),
    );

    final controller = await _waitFor(tester, loaded.future);

    Future<Object?> js(String source) async {
      final value = controller.evaluateJavascript(source: source);
      return _waitFor(tester, value);
    }

    String display(String id) =>
        'getComputedStyle(document.getElementById("$id")).display';

    expect(await js('window.__calmIgInstalled === true'), isTrue);

    // Reels links are hidden; everything else stays.
    expect(await js(display('reels-link')), 'none');
    expect(await js(display('dm-link')), isNot('none'));
    expect(await js(display('search-link')), isNot('none'));
    expect(await js(display('single-reel-link')), isNot('none'));

    // Home: stories row stays, the feed next to it is hidden, and a link
    // to the Following feed appears right under the stories.
    await js('window.__calmIg.sweep()');
    expect(
      await js('document.documentElement.hasAttribute("data-calm-home")'),
      isTrue,
    );
    expect(await js(display('stories-row')), isNot('none'));
    expect(await js(display('feed')), 'none');
    expect(await js(display('calm-ig-following')), isNot('none'));
    expect(
      await js(
        'document.getElementById("calm-ig-following").getAttribute("href")',
      ),
      '/?variant=following',
    );
    expect(
      await js('document.getElementById("stories-row").nextElementSibling.id'),
      'calm-ig-following',
    );

    // Following feed (same path, same DOM): posts show again, minus
    // sponsored ones and everything after the end of the feed.
    await js('history.pushState({}, "", "/?variant=following")');
    await js('window.__calmIg.sweep()');
    expect(
      await js('document.documentElement.hasAttribute("data-calm-home")'),
      isFalse,
    );
    expect(await js(display('feed')), isNot('none'));
    expect(await js(display('calm-ig-following')), 'none');
    expect(await js(display('friend-post')), isNot('none'));
    expect(await js(display('friend-post-2')), isNot('none'));
    expect(await js(display('sponsored-post')), 'none');
    expect(await js(display('after-end-post')), 'none');

    // A client-side jump to Reels is reported back to Flutter.
    await js('history.pushState({}, "", "/reels/C9abc/")');
    await _waitUntil(tester, () => blocked.isNotEmpty);
    expect(blocked.first, '/reels/C9abc/');
  });

  testWidgets('filter health reaches Flutter: ok, then a broken layout', (
    tester,
  ) async {
    const config = FilterConfig();
    final script = await loadFilterScript(config);
    final loaded = Completer<InAppWebViewController>();
    final reports = <FilterHealth>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IgWebView(
            config: config,
            filterScript: script,
            onBlocked: (_) {},
            onFilterHealth: reports.add,
            debugInitialHtml: fakeIgHtml,
            onPageLoaded: (c) {
              if (!loaded.isCompleted) loaded.complete(c);
            },
          ),
        ),
      ),
    );
    final controller = await _waitFor(tester, loaded.future);
    Future<Object?> js(String source) =>
        _waitFor(tester, controller.evaluateJavascript(source: source));

    // The fake home page is laid out like the real one: all good.
    await js('window.__calmIg.sweep(); window.__calmIg.checkHealth()');
    await _waitUntil(tester, () => reports.isNotEmpty);
    expect(reports.last.ok, isTrue);

    // Instagram drops the stories row: posts lose their anchor.
    await js('document.getElementById("stories-row").remove()');
    await js('window.__calmIg.sweep(); window.__calmIg.checkHealth()');
    await _waitUntil(tester, () => !reports.last.ok);
    expect(reports.last.issues, contains('home-no-stories'));
  });

  testWidgets('a page that fails to load shows 重新載入', (tester) async {
    // .invalid never resolves, so the main frame fails with HOST_LOOKUP.
    const config = FilterConfig(
      origin: 'https://calm-ig-offline.invalid',
      allowedHosts: ['invalid'],
    );
    final script = await loadFilterScript(config);
    final failures = <WebResourceErrorType>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IgWebView(
            config: config,
            filterScript: script,
            onBlocked: (_) {},
            onLoadFailed: failures.add,
          ),
        ),
      ),
    );
    await _waitUntil(tester, () => failures.isNotEmpty);
    await tester.pump();
    expect(failures.first, WebResourceErrorType.HOST_LOOKUP);
    expect(find.text('IG 載入失敗'), findsOneWidget);
    expect(find.text('重新載入'), findsOneWidget);

    // 重新載入 really tries again (here it fails again, so the screen stays).
    // Checking that the screen briefly disappears would race the instant
    // DNS failure, so count load attempts instead.
    await tester.tap(find.text('重新載入'));
    await _waitUntil(tester, () => failures.length >= 2);
    await tester.pump();
    expect(find.text('IG 載入失敗'), findsOneWidget);
  });
}

Future<T> _waitFor<T>(WidgetTester tester, Future<T> future) async {
  T? result;
  Object? error;
  var done = false;
  future.then(
    (v) {
      result = v;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  await _waitUntil(tester, () => done);
  if (error != null) throw error!;
  return result as T;
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('timed out after $timeout');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
