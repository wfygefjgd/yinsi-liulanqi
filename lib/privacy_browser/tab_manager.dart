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

  List<BrowserTabModel> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  BrowserTabModel get active => _tabs[_activeIndex];
  bool get canAdd => _tabs.length < maxTabs;

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
    // Stay on current tab for background open; only switch if blank new tab from UI
    if (url == null) {
      _activeIndex = _tabs.length - 1;
    }
    notifyListeners();
    return true;
  }

  /// Open URL in a new background tab; keep current tab focused.
  bool openInBackground(String url) {
    if (url.isEmpty) return false;
    if (!canAdd) {
      // Replace last non-active tab if full
      for (var i = _tabs.length - 1; i >= 0; i--) {
        if (i != _activeIndex) {
          final t = _tabs[i];
          t.pendingUrl = url;
          t.url = url;
          t.addressText = url;
          t.title = '后台加载…';
          t.viewKey; // keep
          notifyListeners();
          return true;
        }
      }
      return false;
    }
    return addTab(url: url);
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _tabs.add(BrowserTabModel(id: _nextId()));
      _activeIndex = 0;
    } else if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
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
