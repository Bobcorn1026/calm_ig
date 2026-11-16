/// What the filter script reports about whether it still recognises
/// Instagram's pages (see `checkHealth` in assets/filters/instagram.js).
class FilterHealth {
  const FilterHealth({required this.ok, this.issues = const []});

  final bool ok;

  /// Issue codes from the script.
  final List<String> issues;

  static const issueText = {
    'reels-link-visible': 'Reels 的入口沒有藏住（IG 可能改了網址）',
    'home-feed-visible': '首頁的推薦貼文沒有藏住',
    'home-no-stories': '首頁找不到限動列，只好把整個首頁藏起來',
  };

  /// Parses a `{kind: 'filter', ok, issues}` message; null for anything else.
  static FilterHealth? fromMessage(Object? event) {
    if (event is! Map || event['kind'] != 'filter') return null;
    final issues = event['issues'];
    return FilterHealth(
      ok: event['ok'] == true,
      issues: issues is List ? [for (final i in issues) '$i'] : const [],
    );
  }

  /// One line per issue, for the warning dialog.
  List<String> get descriptions => [
    for (final i in issues) issueText[i] ?? '看不懂的頁面結構（$i）',
  ];
}
