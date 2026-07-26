import 'package:flutter/foundation.dart';

import 'browser_tab_model.dart';

class TabManager extends ChangeNotifier {
  TabManager({this.maxTabs = 8}) {
    _tabs.add(BrowserTabModel(id: _nextId()));
  }

  final int maxTabs;
  final List<BrowserTabModel> _tabs = [];
  int _activeIndex = 0;
  int _seq = 0;
  bool _coldStartPending = false;

  List<BrowserTabModel> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  BrowserTabModel get active => _tabs[_activeIndex];
  bool get canAdd => _tabs.length < maxTabs;
  bool get coldStartPending => _coldStartPending;

  void markColdStartPending() {
    _coldStartPending = true;
    notifyListeners();
  }

  void clearColdStartPending() {
    if (!_coldStartPending) return;
    _coldStartPending = false;
    notifyListeners();
  }

  String _nextId() {
    _seq += 1;
    return 'tab_$_seq';
  }

  void select(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  bool addTab({String? url}) {
    if (!canAdd) return false;
    final t = BrowserTabModel(id: _nextId());
    if (url != null && url.isNotEmpty) {
      t.pendingUrl = url;
      t.addressText = url;
      t.url = url;
      t.title = '加载中…';
    }
    _tabs.add(t);
    // New tab becomes active (old page stays as another tab in the strip).
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return true;
  }

  /// Open URL in a new tab and switch to it (old page remains open in background).
  /// Returns the new/reused tab id, or null if nothing opened.
  ///
  /// When at [maxTabs], replaces a non-active tab with a fresh model (new viewKey)
  /// so history/cookies of the recycled slot do not bleed into the new page.
  /// Never navigates away from the current tab when other slots exist.
  String? openInNewTabForeground(String url) {
    if (url.isEmpty) return null;
    if (!canAdd) {
      for (var i = _tabs.length - 1; i >= 0; i--) {
        if (i != _activeIndex) {
          final fresh = BrowserTabModel(id: _nextId());
          fresh.pendingUrl = url;
          fresh.url = url;
          fresh.addressText = url;
          fresh.title = '加载中…';
          _tabs[i] = fresh;
          _activeIndex = i;
          notifyListeners();
          return fresh.id;
        }
      }
      // maxTabs == 1 only: must use the single tab
      final t = active;
      t.pendingUrl = url;
      t.url = url;
      t.addressText = url;
      t.title = '加载中…';
      notifyListeners();
      return t.id;
    }
    if (!addTab(url: url)) return null;
    return active.id;
  }

  int? indexOfTabId(String tabId) {
    for (var i = 0; i < _tabs.length; i++) {
      if (_tabs[i].id == tabId) return i;
    }
    return null;
  }

  BrowserTabModel? tabById(String tabId) {
    for (final t in _tabs) {
      if (t.id == tabId) return t;
    }
    return null;
  }

  /// Load [url] into an existing tab without switching away from current if inactive.
  bool loadUrlInTab(String tabId, String url) {
    final t = tabById(tabId);
    if (t == null || url.isEmpty) return false;
    t.pendingUrl = url;
    t.url = url;
    t.addressText = url;
    t.title = '加载中…';
    notifyListeners();
    return true;
  }

  bool closeTabById(String tabId) {
    final i = indexOfTabId(tabId);
    if (i == null) return false;
    closeTab(i);
    return true;
  }

  /// @use [openInNewTabForeground] instead
  @Deprecated('Use openInNewTabForeground instead')
  bool openInBackground(String url) => openInNewTabForeground(url) != null;

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final closingActive = index == _activeIndex;
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _tabs.add(BrowserTabModel(id: _nextId()));
      _activeIndex = 0;
    } else if (closingActive) {
      // Prefer previous tab (Safari-like), else clamp.
      _activeIndex = index > 0 ? index - 1 : 0;
      if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      }
    } else if (_activeIndex > index) {
      _activeIndex -= 1;
    }
    notifyListeners();
  }

  void hardResetTabs() {
    _tabs
      ..clear()
      ..add(BrowserTabModel(id: _nextId()));
    _activeIndex = 0;
    notifyListeners();
  }

  void notifyTabChanged() => notifyListeners();
}
