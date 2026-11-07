import 'package:calm_ig/filter/filter_config.dart';
import 'package:calm_ig/filter/url_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = FilterConfig();

  UrlDecision decide(String url, {bool mainFrame = true}) =>
      decideUrl(Uri.parse(url), config, isMainFrame: mainFrame);

  group('blocked pages', () {
    for (final url in [
      'https://www.instagram.com/reels/',
      'https://www.instagram.com/reels',
      'https://www.instagram.com/reels/C9abc123/',
      'https://instagram.com/reels/',
      'https://m.instagram.com/reels/xyz/',
    ]) {
      test('$url → block to home', () {
        final d = decide(url);
        expect(d.action, UrlAction.block);
        expect(d.target.toString(), config.homeUrl);
      });
    }

    test('Explore grid is sent to search', () {
      for (final url in [
        'https://www.instagram.com/explore/',
        'https://www.instagram.com/explore/tags/cats/',
      ]) {
        final d = decide(url);
        expect(d.action, UrlAction.block, reason: url);
        expect(
          d.target.toString(),
          'https://www.instagram.com/explore/search/',
          reason: url,
        );
      }
    });
  });

  group('allowed pages', () {
    for (final url in [
      'https://www.instagram.com/direct/inbox/',
      'https://www.instagram.com/direct/t/1234567890/',
      'https://www.instagram.com/stories/some.friend/3456/',
      'https://www.instagram.com/some.friend/',
      'https://www.instagram.com/p/Cxyz123/',
      'https://www.instagram.com/some.friend/p/Cxyz123/',
      // A single reel a friend posted or sent in a DM (singular "reel").
      'https://www.instagram.com/reel/Cxyz123/',
      'https://www.instagram.com/some.friend/reel/Cxyz123/',
      'https://www.instagram.com/explore/search/',
      'https://www.instagram.com/accounts/login/',
      // Not a prefix match.
      'https://www.instagram.com/reelsfan/',
    ]) {
      test(url, () => expect(decide(url).action, UrlAction.allow));
    }
  });

  group('home', () {
    test('home and its feed variants all load (the script hides the feed)', () {
      for (final url in [
        'https://www.instagram.com/',
        'https://www.instagram.com',
        'https://www.instagram.com/?variant=following',
        'https://www.instagram.com/?variant=favorites',
      ]) {
        expect(decide(url).action, UrlAction.allow, reason: url);
      }
    });

    test('blocked pages fall back to home', () {
      expect(config.homeUrl, 'https://www.instagram.com/');
    });
  });

  group('other hosts and schemes', () {
    test('Instagram helpers and CDN stay inside', () {
      for (final url in [
        'https://scontent.cdninstagram.com/v/t51/abc.jpg',
        'https://accountscenter.instagram.com/',
        'https://l.instagram.com/?u=https%3A%2F%2Fexample.com',
        'https://www.facebook.com/login/',
        'https://auth.meta.com/',
      ]) {
        expect(decide(url).action, UrlAction.allow, reason: url);
      }
    });

    test('outside links open in the system browser', () {
      expect(decide('https://example.com/').action, UrlAction.external);
      expect(
        decide('https://notinstagram.com/reels/').action,
        UrlAction.external,
      );
    });

    test('app-open attempts are dropped silently', () {
      expect(decide('instagram://reels').action, UrlAction.cancel);
      expect(decide('itms-apps://apps.apple.com/x').action, UrlAction.cancel);
    });

    test('about:blank and data URLs load', () {
      expect(decide('about:blank').action, UrlAction.allow);
      expect(decide('data:text/html,hi').action, UrlAction.allow);
    });

    test('sub-frames are not path-filtered', () {
      expect(
        decide('https://www.instagram.com/reels/', mainFrame: false).action,
        UrlAction.allow,
      );
    });
  });

  test('pathHasPrefix', () {
    expect(pathHasPrefix('/reels', '/reels'), isTrue);
    expect(pathHasPrefix('/reels/', '/reels'), isTrue);
    expect(pathHasPrefix('/reels/a/', '/reels/'), isTrue);
    expect(pathHasPrefix('/reelsy', '/reels'), isFalse);
    expect(pathHasPrefix('/reel/abc/', '/reels'), isFalse);
  });
}
