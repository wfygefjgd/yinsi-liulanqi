/// Bridges page `window.open` stubs to live popup WebViews.
class PopupRegistry {
  PopupRegistry._();

  static final Map<int, void Function(String url)> _navigators = {};
  static final Map<int, VoidCallback> _closers = {};

  static void registerNavigator(int id, void Function(String url) nav) {
    _navigators[id] = nav;
  }

  static void registerCloser(int id, VoidCallback close) {
    _closers[id] = close;
  }

  static void unregister(int id) {
    _navigators.remove(id);
    _closers.remove(id);
  }

  static void navigate(int id, String url) {
    final n = _navigators[id];
    if (n != null) {
      n(url);
    }
  }

  /// Page called stub.close() — close our UI if still open.
  static void closeFromPage(int id) {
    final c = _closers[id];
    if (c != null) c();
  }
}

typedef VoidCallback = void Function();
