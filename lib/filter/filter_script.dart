import 'dart:convert';

import 'package:flutter/services.dart';

import 'filter_config.dart';

const filterScriptAsset = 'assets/filters/instagram.js';

/// Prepends the config (as JSON) to the filter script source.
String buildFilterScript(String source, FilterConfig config) =>
    'window.__CALM_IG_CONFIG__ = ${jsonEncode(config.toJson())};\n$source';

Future<String> loadFilterScript(
  FilterConfig config, {
  AssetBundle? bundle,
}) async {
  final source = await (bundle ?? rootBundle).loadString(filterScriptAsset);
  return buildFilterScript(source, config);
}
