/// Lets widgets outside the web view (the reload button in the top bar)
/// ask it to reload. The web view attaches its reload function while it is
/// on screen.
class ReloadHandle {
  Future<void> Function()? _action;

  void attach(Future<void> Function() action) => _action = action;

  void detach(Future<void> Function() action) {
    if (_action == action) _action = null;
  }

  Future<void> reload() async => _action?.call();
}
