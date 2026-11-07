import 'dart:convert';
import 'dart:io';

import 'package:calm_ig/filter/filter_config.dart';
import 'package:calm_ig/filter/filter_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('config JSON is prepended to the script', () {
    const config = FilterConfig(blockedPrefixes: ['/reels', '/shorts']);
    final script = buildFilterScript('/* body */', config);
    final firstLine = script.split('\n').first;
    expect(firstLine, startsWith('window.__CALM_IG_CONFIG__ = '));
    final json = jsonDecode(
      firstLine
          .substring('window.__CALM_IG_CONFIG__ = '.length)
          .replaceAll(RegExp(r';$'), ''),
    );
    expect(json['blockedPrefixes'], ['/reels', '/shorts']);
    expect(json['homePath'], '/');
    expect(json['followingPath'], '/?variant=following');
    expect(json['feedVariants'], ['following', 'favorites']);
    expect(script, endsWith('/* body */'));
  });

  test('the asset is bundled and declared in pubspec', () {
    expect(File(filterScriptAsset).existsSync(), isTrue);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('assets/filters/'),
    );
  });

  // The JS rules must match the Dart rules; run them in Node when available.
  test('JS decide() agrees with Dart rules', () async {
    final result = await Process.run('node', [
      '--test',
      'test/js/filter_rules.test.mjs',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, skip: _hasNode() ? false : 'node not installed');
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}
