import 'package:calm_ig/browser/load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPageLoadFailure', () {
    test('network failures of the page itself count', () {
      for (final type in [
        WebResourceErrorType.NOT_CONNECTED_TO_INTERNET,
        WebResourceErrorType.TIMEOUT,
        WebResourceErrorType.HOST_LOOKUP,
        WebResourceErrorType.NETWORK_CONNECTION_LOST,
      ]) {
        expect(isPageLoadFailure(type, isMainFrame: true), isTrue);
      }
    });

    test('our own cancelled navigations do not count', () {
      // Fired when calm_ig blocks a Reels link or an instagram:// link.
      expect(
        isPageLoadFailure(WebResourceErrorType.CANCELLED, isMainFrame: true),
        isFalse,
      );
      expect(
        isPageLoadFailure(WebResourceErrorType.UNKNOWN, isMainFrame: true),
        isFalse,
      );
    });

    test('a failing sub-frame or resource does not cover the page', () {
      expect(
        isPageLoadFailure(
          WebResourceErrorType.NOT_CONNECTED_TO_INTERNET,
          isMainFrame: false,
        ),
        isFalse,
      );
    });
  });

  test('loadFailureMessage', () {
    expect(
      loadFailureMessage(WebResourceErrorType.NOT_CONNECTED_TO_INTERNET),
      contains('沒有網路'),
    );
    expect(loadFailureMessage(WebResourceErrorType.TIMEOUT), contains('太慢'));
    expect(
      loadFailureMessage(WebResourceErrorType.HOST_LOOKUP),
      contains('連不上'),
    );
  });

  testWidgets('LoadFailureView shows the reason and retries', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoadFailureView(message: '沒有網路連線', onRetry: () => retries++),
      ),
    );
    expect(find.text('IG 載入失敗'), findsOneWidget);
    expect(find.text('沒有網路連線'), findsOneWidget);
    await tester.tap(find.text('重新載入'));
    expect(retries, 1);
  });
}
