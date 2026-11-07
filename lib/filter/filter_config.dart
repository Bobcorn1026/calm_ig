/// Everything that decides what gets hidden or blocked. The same object
/// drives the Dart navigation rules and (as JSON) the injected JavaScript,
/// so both sides always agree.
class FilterConfig {
  const FilterConfig({
    this.origin = 'https://www.instagram.com',
    this.homePath = '/',
    this.followingPath = '/?variant=following',
    this.feedVariants = const ['following', 'favorites'],
    this.followingLinkText = '首頁推薦已隱藏 · 看追蹤中的貼文 →',
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

  /// The start page: Instagram's home, where the stories row lives. Its
  /// algorithmic feed is hidden by the filter script.
  final String homePath;

  /// Chronological posts from accounts you follow (linked from home).
  final String followingPath;

  /// `?variant=` values on "/" that are real feeds and stay visible.
  final List<String> feedVariants;

  /// Text of the link the script adds under the stories row on home.
  final String followingLinkText;

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
    'followingPath': followingPath,
    'feedVariants': feedVariants,
    'followingLinkText': followingLinkText,
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
