import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Debug builds only: run JavaScript in the web view from the Mac.
///
/// Write a script to `<app data container>/tmp/debug_eval.js`; within a
/// second it is evaluated in the page and the result (JSON, or the error) is
/// written to `debug_eval_result.txt` next to it. Used to inspect Instagram's
/// real DOM when the filter rules need updating:
///
/// ```sh
/// C=$(xcrun simctl get_app_container booted com.satori.calmIg data)
/// echo 'location.href' > "$C/tmp/debug_eval.js"; sleep 2
/// cat "$C/tmp/debug_eval_result.txt"
/// ```
class DebugJsBridge {
  DebugJsBridge(this._controller);

  final InAppWebViewController _controller;
  Timer? _timer;
  bool _busy = false;

  void start() {
    if (!kDebugMode) return;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_busy) return;
    final input = File('${Directory.systemTemp.path}/debug_eval.js');
    if (!input.existsSync()) return;
    _busy = true;
    final output = File('${Directory.systemTemp.path}/debug_eval_result.txt');
    try {
      final source = input.readAsStringSync();
      input.deleteSync();
      final result = await _controller.callAsyncJavaScript(
        functionBody: 'return JSON.stringify(await (async () => ($source))());',
      );
      output.writeAsStringSync(
        result?.error != null ? 'ERROR: ${result!.error}' : '${result?.value}',
      );
    } catch (e) {
      output.writeAsStringSync('ERROR: $e');
    } finally {
      _busy = false;
    }
  }
}
