/// Bridges page `window.open` stubs to browser tabs (not floating overlays).
class PopupRegistry {
  PopupRegistry._();

  static final Map<int, void Function(String url)> _navigators = {};
  static final Map<int, void Function()> _closers = {};
  /// URL queued before the target tab finished registering.
  static final Map<int, String> _pendingUrls = {};
  /// windowId → tabId for tab-based popups.
  static final Map<int, String> _windowToTab = {};

  static void bindWindowToTab(int windowId, String tabId) {
    _windowToTab[windowId] = tabId;
  }

  static String? tabIdForWindow(int windowId) => _windowToTab[windowId];

  static void registerNavigator(int id, void Function(String url) nav) {
    _navigators[id] = nav;
    final pending = _pendingUrls.remove(id);
    if (pending != null && pending.isNotEmpty) {
      Future<void>.microtask(() => nav(pending));
    }
  }

  static void registerCloser(int id, void Function() close) {
    _closers[id] = close;
  }

  static void unregister(int id) {
    _navigators.remove(id);
    _closers.remove(id);
    _pendingUrls.remove(id);
    _windowToTab.remove(id);
  }

  static void navigate(int id, String url) {
    if (url.isEmpty) return;
    final n = _navigators[id];
    if (n != null) {
      n(url);
    } else {
      _pendingUrls[id] = url;
    }
  }

  static void closeFromPage(int id) {
    // Remove first so a second close cannot double-dispose the tab.
    final c = _closers.remove(id);
    _navigators.remove(id);
    _pendingUrls.remove(id);
    // Keep _windowToTab until closer finishes closeTab (closer calls unregister).
    if (c != null) c();
  }

  static void clearAll() {
    _navigators.clear();
    _closers.clear();
    _pendingUrls.clear();
    _windowToTab.clear();
  }

  /// User closed the tab from the tab strip — only detach registry (tab already closing).
  /// Does NOT invoke closers (those dispose + closeTab again).
  static List<int> detachWindowsForTab(String tabId) {
    final ids = <int>[];
    for (final e in _windowToTab.entries) {
      if (e.value == tabId) ids.add(e.key);
    }
    for (final id in ids) {
      _navigators.remove(id);
      _closers.remove(id);
      _pendingUrls.remove(id);
      _windowToTab.remove(id);
    }
    return ids;
  }
}
