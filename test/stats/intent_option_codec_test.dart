import 'package:calm_ig/intent/intent_option.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bad saved data falls back or skips safely', () {
    expect(decodeIntentOptions(null), defaultIntentOptions);
    expect(decodeIntentOptions('{oops'), defaultIntentOptions);
    expect(decodeIntentOptions('{"a":1}'), defaultIntentOptions);
    // Unknown actions are dropped; unsafe paths become home.
    final decoded = decodeIntentOptions(
      '[{"id":"a","label":"A","action":"teleport"},'
      '{"id":"b","label":"B","action":"open","path":"//evil.com/"}]',
    );
    expect(decoded, hasLength(1));
    expect(decoded.single.path, '/');
  });

  test('profilePath accepts Instagram usernames only', () {
    expect(profilePath('jz._.1026'), '/jz._.1026/');
    expect(profilePath('@someone'), '/someone/');
    expect(profilePath('  spaced  '), '/spaced/');
    expect(profilePath('has space'), isNull);
    expect(profilePath('../etc'), isNull);
    expect(profilePath(''), isNull);
  });

  test('isValidIgPath', () {
    expect(isValidIgPath('/direct/inbox/'), isTrue);
    expect(isValidIgPath('//evil.com/'), isFalse);
    expect(isValidIgPath('https://evil.com/'), isFalse);
    expect(isValidIgPath('/a/../b'), isFalse);
  });
}
