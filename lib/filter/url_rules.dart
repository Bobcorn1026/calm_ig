import 'filter_config.dart';

enum UrlAction {
  /// Load it.
  allow,

  /// Drop it silently (e.g. `instagram://` "open in app" attempts).
  cancel,

  /// Drop it, tell the user, and go to [UrlDecision.target].
  block,

  /// Quietly load [UrlDecision.target] instead.
  redirect,

  /// Open it in the system browser.
  external,
}

class UrlDecision {
  const UrlDecision(this.action, this.uri, [this.target]);

  final UrlAction action;
  final Uri uri;
  final Uri? target;

  @override
  String toString() => 'UrlDecision($action, $uri -> $target)';
}

const _innocuousSchemes = {'about', 'data', 'blob', 'javascript'};

/// Decides what to do with a navigation inside the web view.
///
/// Only top-level navigations are filtered by path; sub-frames (login
/// helpers, embedded players) are left alone unless they try to leave the web.
UrlDecision decideUrl(Uri uri, FilterConfig config, {bool isMainFrame = true}) {
  final scheme = uri.scheme.toLowerCase();
  if (_innocuousSchemes.contains(scheme)) {
    return UrlDecision(UrlAction.allow, uri);
  }
  if (scheme != 'http' && scheme != 'https') {
    return UrlDecision(UrlAction.cancel, uri);
  }
  if (!isMainFrame) return UrlDecision(UrlAction.allow, uri);

  final host = uri.host.toLowerCase();
  if (!_isAllowedHost(host, config.allowedHosts)) {
    return UrlDecision(UrlAction.external, uri);
  }
  if (!_isInstagramPageHost(host)) return UrlDecision(UrlAction.allow, uri);

  final path = uri.path.isEmpty ? '/' : uri.path;
  final origin = Uri.parse(config.origin);

  for (final prefix in config.blockedPrefixes) {
    if (pathHasPrefix(path, prefix)) {
      return UrlDecision(UrlAction.block, uri, Uri.parse(config.homeUrl));
    }
  }
  if (!pathHasPrefix(path, config.searchPath)) {
    for (final prefix in config.searchRedirectPrefixes) {
      if (pathHasPrefix(path, prefix)) {
        return UrlDecision(
          UrlAction.block,
          uri,
          origin.replace(path: config.searchPath),
        );
      }
    }
  }
  if (path == '/' && uri.queryParameters['variant'] != 'following') {
    return UrlDecision(UrlAction.redirect, uri, Uri.parse(config.homeUrl));
  }
  return UrlDecision(UrlAction.allow, uri);
}

bool _isAllowedHost(String host, List<String> allowed) =>
    allowed.any((h) => host == h || host.endsWith('.$h'));

/// Hosts that serve Instagram's pages (not its CDN or login helpers).
bool _isInstagramPageHost(String host) =>
    host == 'instagram.com' ||
    host == 'www.instagram.com' ||
    host == 'm.instagram.com';
