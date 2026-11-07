import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../filter/filter_config.dart';
import '../filter/url_rules.dart';
import 'debug_js_bridge.dart';

/// Instagram's mobile website inside a WKWebView, with the filter script
/// injected before any page script runs.
class IgWebView extends StatefulWidget {
  const IgWebView({
    super.key,
    required this.config,
    required this.filterScript,
    required this.onBlocked,
    this.debugInitialHtml,
    this.onPageLoaded,
  });

  final FilterConfig config;

  /// JavaScript built by `buildFilterScript`, injected at document start.
  final String filterScript;

  /// Called whenever a Reels / Explore page was stopped.
  final ValueChanged<String> onBlocked;

  /// Integration tests load this HTML (as if served from [FilterConfig.origin])
  /// instead of the real site.
  @visibleForTesting
  final String? debugInitialHtml;

  /// Called after each page finishes loading.
  final ValueChanged<InAppWebViewController>? onPageLoaded;

  @override
  State<IgWebView> createState() => _IgWebViewState();
}

class _IgWebViewState extends State<IgWebView> {
  InAppWebViewController? _controller;
  DebugJsBridge? _debugBridge;

  @override
  void dispose() {
    _debugBridge?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
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
      onLoadStop: (controller, _) => widget.onPageLoaded?.call(controller),
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
