/// Everything that decides what gets hidden or blocked. The same object
/// drives the Dart navigation rules and (as JSON) the injected JavaScript,
/// so both sides always agree.
class FilterConfig {
  const FilterConfig({
    this.origin = 'https://www.instagram.com',
    this.homePath = '/?variant=following',
    this.blockedPrefixes = const ['/reels'],
    this.searchPath = '/explore/search/',
    this.searchRedirectPrefixes = const ['/explore'],
    this.allowedHosts = const [
      'instagram.com',
      'cdninstagram.com',
      'facebook.com',
      'fbcdn.net',
      'fb.com',
      'meta.com',
    ],
    this.hiddenPostLabels = const [
      'Suggested for you',
      'Suggested posts',
      'Sponsored',
      '為你推薦',
      '推薦貼文',
      '建議的貼文',
      '贊助',
      '贊助內容',
    ],
    this.feedEndLabels = const [
      "You're all caught up",
      '你已看完所有新內容',
      '你已經看完所有內容',
    ],
  });

  /// Instagram's web origin, without a trailing slash.
  final String origin;

  /// Where "home" goes: the chronological Following feed.
  final String homePath;

  /// Paths (and everything below them) that are never shown.
  final List<String> blockedPrefixes;

  /// Search stays usable even though Explore is blocked.
  final String searchPath;

  /// Paths that are sent to [searchPath] instead (Explore grid).
  final List<String> searchRedirectPrefixes;

  /// Hosts (and their subdomains) that may load inside the web view.
  final List<String> allowedHosts;

  /// A feed post containing one of these labels is hidden.
  final List<String> hiddenPostLabels;

  /// Every post after one of these markers (end of the Following feed,
  /// where Instagram starts suggesting posts) is hidden.
  final List<String> feedEndLabels;

  String get homeUrl => '$origin$homePath';

  Map<String, Object> toJson() => {
    'homePath': homePath,
    'blockedPrefixes': blockedPrefixes,
    'searchPath': searchPath,
    'searchRedirectPrefixes': searchRedirectPrefixes,
    'hiddenPostLabels': hiddenPostLabels,
    'feedEndLabels': feedEndLabels,
  };
}

/// True when [path] is [prefix] itself or lies below it
/// (`/reels`, `/reels/`, `/reels/abc/` all match `/reels`; `/reelsy` does not).
bool pathHasPrefix(String path, String prefix) {
  final p = prefix.endsWith('/')
      ? prefix.substring(0, prefix.length - 1)
      : prefix;
  return path == p || path.startsWith('$p/');
}
