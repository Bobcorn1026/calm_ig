import 'package:flutter/material.dart';

import '../filter/filter_config.dart';
import '../filter/filter_script.dart';
import 'ig_web_view.dart';
import 'reload_handle.dart';

/// The main screen: a slim app bar on top of the filtered Instagram site.
class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    this.config = const FilterConfig(),
    this.topBar,
    this.reloadHandle,
    this.webViewBuilder,
  });

  final FilterConfig config;

  /// Shown above the web view (pass controls, settings).
  final Widget? topBar;

  /// Shared with the top bar's reload button.
  final ReloadHandle? reloadHandle;

  /// Replaces the real web view in widget tests.
  final Widget Function(BuildContext context, ValueChanged<String> onBlocked)?
  webViewBuilder;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final Future<String> _script = loadFilterScript(widget.config);

  void _onBlocked(String path) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(blockedMessage(path)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ?widget.topBar,
            Expanded(child: _buildWebView(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(BuildContext context) {
    final builder = widget.webViewBuilder;
    if (builder != null) return builder(context, _onBlocked);
    return FutureBuilder<String>(
      future: _script,
      builder: (context, snapshot) {
        final script = snapshot.data;
        if (script == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return IgWebView(
          config: widget.config,
          filterScript: script,
          onBlocked: _onBlocked,
          reloadHandle: widget.reloadHandle,
        );
      },
    );
  }
}

/// The toast text for a blocked page.
String blockedMessage(String path) {
  if (pathHasPrefix(path, '/reels')) return '已擋下 Reels';
  if (pathHasPrefix(path, '/explore')) return '探索頁已擋下，改開搜尋';
  return '已擋下';
}
