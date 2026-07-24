/// Bridges page `window.open` stubs to live popup WebViews.
class PopupRegistry {
  PopupRegistry._();

  static final Map<int, void Function(String url)> _navigators = {};
  static final Map<int, void Function()> _closers = {};
  /// URL queued before popup UI finished registering.
  static final Map<int, String> _pendingUrls = {};

  static void registerNavigator(int id, void Function(String url) nav) {
    _navigators[id] = nav;
    final pending = _pendingUrls.remove(id);
    if (pending != null && pending.isNotEmpty) {
      nav(pending);
    }
  }

  static void registerCloser(int id, void Function() close) {
    _closers[id] = close;
  }

  static void unregister(int id) {
    _navigators.remove(id);
    _closers.remove(id);
    _pendingUrls.remove(id);
  }

  static void navigate(int id, String url) {
    if (url.isEmpty) return;
    final n = _navigators[id];
    if (n != null) {
      n(url);
    } else {
      // Popup route not mounted yet — remember and apply on register.
      _pendingUrls[id] = url;
    }
  }

  static void closeFromPage(int id) {
    final c = _closers[id];
    if (c != null) c();
  }
}
