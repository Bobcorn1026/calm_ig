import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../filter/filter_config.dart';
import '../filter/url_rules.dart';
import 'debug_js_bridge.dart';
import 'load_failure.dart';
import 'reload_handle.dart';

/// Instagram's mobile website inside a WKWebView, with the filter script
/// injected before any page script runs.
class IgWebView extends StatefulWidget {
  const IgWebView({
    super.key,
    required this.config,
    required this.filterScript,
    required this.onBlocked,
    this.reloadHandle,
    this.debugInitialHtml,
    this.onPageLoaded,
    this.onLoadFailed,
  });

  final FilterConfig config;

  /// JavaScript built by `buildFilterScript`, injected at document start.
  final String filterScript;

  /// Called whenever a Reels / Explore page was stopped.
  final ValueChanged<String> onBlocked;

  /// Lets the top bar's reload button reload this page.
  final ReloadHandle? reloadHandle;

  /// Integration tests load this HTML (as if served from [FilterConfig.origin])
  /// instead of the real site.
  @visibleForTesting
  final String? debugInitialHtml;

  /// Called after each page finishes loading.
  final ValueChanged<InAppWebViewController>? onPageLoaded;

  /// Called each time the page fails to load and the retry screen shows.
  final ValueChanged<WebResourceErrorType>? onLoadFailed;

  @override
  State<IgWebView> createState() => _IgWebViewState();
}

class _IgWebViewState extends State<IgWebView> {
  InAppWebViewController? _controller;
  DebugJsBridge? _debugBridge;

  /// Pull down at the top of the page to reload (also works on a blank or
  /// half-loaded page, thanks to `alwaysBounceVertical`).
  late final _pullToRefresh = PullToRefreshController(
    settings: PullToRefreshSettings(color: Colors.grey),
    onRefresh: _onPullToRefresh,
  );

  /// Stops the pull-to-refresh spinner if no load event ever ends it.
  Timer? _refreshTimeout;

  /// Whether any page has finished loading. Before that, WKWebView's
  /// `reload()` does nothing (there is no page to reload).
  bool _hasLoaded = false;

  /// Set when the page failed to load; shows [LoadFailureView].
  String? _failure;

  /// The page that failed, so "重新載入" retries it instead of a blank page.
  WebUri? _failedUrl;

  @override
  void initState() {
    super.initState();
    widget.reloadHandle?.attach(_reload);
  }

  @override
  void dispose() {
    widget.reloadHandle?.detach(_reload);
    _refreshTimeout?.cancel();
    _debugBridge?.stop();
    super.dispose();
  }

  Future<void> _onPullToRefresh() async {
    _refreshTimeout?.cancel();
    _refreshTimeout = Timer(
      const Duration(seconds: 15),
      _pullToRefresh.endRefreshing,
    );
    await _reload();
  }

  void _endRefreshing() {
    _refreshTimeout?.cancel();
    _pullToRefresh.endRefreshing();
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final target = reloadTarget(
      failedUrl: _failedUrl?.uriValue,
      hasLoaded: _hasLoaded,
      homeUrl: Uri.parse(widget.config.homeUrl),
    );
    setState(() {
      _failure = null;
      _failedUrl = null;
    });
    if (target != null) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(target)));
    } else {
      await controller.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return Stack(
      children: [
        _buildWebView(),
        if (failure != null)
          Positioned.fill(
            child: LoadFailureView(message: failure, onRetry: _reload),
          ),
      ],
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      pullToRefreshController: _pullToRefresh,
      initialUrlRequest: widget.debugInitialHtml == null
          ? URLRequest(url: WebUri(widget.config.homeUrl))
          : null,
      initialData: widget.debugInitialHtml == null
          ? null
          : InAppWebViewInitialData(
              data: widget.debugInitialHtml!,
              baseUrl: WebUri(widget.config.homeUrl),
            ),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: widget.filterScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      initialSettings: InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        allowsBackForwardNavigationGestures: true,
        allowsInlineMediaPlayback: true,
        // Without a Safari token Instagram treats WKWebView as an unknown
        // browser and keeps pushing the native app.
        applicationNameForUserAgent: 'Version/18.0 Mobile/15E148 Safari/604.1',
        isInspectable: kDebugMode,
        // Lets pull-to-refresh work even when the page is blank or short.
        alwaysBounceVertical: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        // Only in debug builds and only for the real site (not tests).
        if (kDebugMode && widget.debugInitialHtml == null) {
          _debugBridge = DebugJsBridge(controller)..start();
        }
        controller.addJavaScriptHandler(
          handlerName: 'calmIg',
          callback: (args) {
            final event = args.isNotEmpty ? args.first : null;
            if (event is Map && event['kind'] == 'blocked') {
              widget.onBlocked('${event['path'] ?? ''}');
            }
            return null;
          },
        );
      },
      onLoadStop: (controller, _) {
        _hasLoaded = true;
        _endRefreshing();
        widget.onPageLoaded?.call(controller);
      },
      onReceivedError: (controller, request, error) {
        _endRefreshing();
        if (!isPageLoadFailure(
          error.type,
          isMainFrame: request.isForMainFrame ?? false,
        )) {
          return;
        }
        setState(() {
          _failure = loadFailureMessage(error.type);
          _failedUrl = request.url;
        });
        widget.onLoadFailed?.call(error.type);
      },
      // iOS kills the page's process under memory pressure (e.g. while you
      // are in the native Instagram app); the web view is then blank.
      onWebContentProcessDidTerminate: (_) => _reload(),
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url;
        if (url == null) return NavigationActionPolicy.ALLOW;
        final decision = decideUrl(
          url.uriValue,
          widget.config,
          isMainFrame: action.isForMainFrame,
        );
        return _apply(decision);
      },
      onCreateWindow: (controller, action) async {
        // target="_blank" links: keep Instagram here, send the rest out.
        final url = action.request.url;
        if (url != null) {
          final decision = decideUrl(url.uriValue, widget.config);
          if (decision.action == UrlAction.allow) {
            await controller.loadUrl(urlRequest: URLRequest(url: url));
          } else {
            await _apply(decision);
          }
        }
        return false;
      },
    );
  }

  Future<NavigationActionPolicy> _apply(UrlDecision decision) async {
    switch (decision.action) {
      case UrlAction.allow:
        return NavigationActionPolicy.ALLOW;
      case UrlAction.cancel:
        return NavigationActionPolicy.CANCEL;
      case UrlAction.block:
        widget.onBlocked(decision.uri.path);
        await _load(decision.target!);
        return NavigationActionPolicy.CANCEL;
      case UrlAction.external:
        await launchUrl(decision.uri, mode: LaunchMode.externalApplication);
        return NavigationActionPolicy.CANCEL;
    }
  }

  Future<void> _load(Uri target) async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(target)));
  }
}
