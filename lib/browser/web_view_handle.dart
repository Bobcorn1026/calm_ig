/// Lets widgets outside the web view (top bar, "這次要做什麼？" menu) reload
/// it or send it to a page. The web view attaches itself while on screen.
class WebViewHandle {
  Future<void> Function()? _reload;
  Future<void> Function(String path)? _open;

  void attach({
    required Future<void> Function() reload,
    required Future<void> Function(String path) open,
  }) {
    _reload = reload;
    _open = open;
  }

  void detach(Future<void> Function() reload) {
    if (_reload != reload) return;
    _reload = null;
    _open = null;
  }

  Future<void> reload() async => _reload?.call();

  /// Loads an instagram.com [path] such as `/direct/inbox/`.
  Future<void> open(String path) async => _open?.call(path);
}
