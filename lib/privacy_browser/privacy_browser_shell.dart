import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'bookmarks.dart';
import 'browser_tab_model.dart';
import 'durable_store.dart';
import 'hide_store.dart';
import 'privacy_engine.dart';
import 'privacy_web_view.dart';
import 'reader_mode_page.dart';
import 'reader_scripts.dart';
import 'session_identity.dart';
import 'tab_manager.dart';

class _C {
  static const bg = Color(0xFF000000);
  static const bar = Color(0xF01C1C1E);
  static const field = Color(0xFF2C2C2E);
  static const fieldBorder = Color(0xFF3A3A3C);
  static const accent = Color(0xFF0A84FF);
  static const text = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF8E8E93);
  static const danger = Color(0xFFFF453A);
  static const star = Color(0xFFFFD60A);
}

class PrivacyBrowserApp extends StatelessWidget {
  const PrivacyBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TabManager(maxTabs: 15),
      child: MaterialApp(
        title: '隐私浏览器',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _C.bg,
          colorScheme: const ColorScheme.dark(
            primary: _C.accent,
            surface: _C.bar,
          ),
        ),
        home: const PrivacyBrowserShell(),
      ),
    );
  }
}

class PrivacyBrowserShell extends StatefulWidget {
  const PrivacyBrowserShell({super.key});

  @override
  State<PrivacyBrowserShell> createState() => _PrivacyBrowserShellState();
}

class _PrivacyBrowserShellState extends State<PrivacyBrowserShell>
    with SingleTickerProviderStateMixin {
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();
  final Map<String, InAppWebViewController> _controllers = {};
  bool _resetting = false;
  bool _showTabs = false;
  bool _exiting = false;
  bool _pickMode = false;
  bool _stitchEnabled = true;
  bool _popupBlock = true;
  bool _adBlock = true;
  bool _crossSiteBlock = true;
  bool _desktopMode = false;
  late final AnimationController _exitFade;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();
    // Fast, light fade for manual「换新身份」only.
    _exitFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _exitOpacity = CurvedAnimation(parent: _exitFade, curve: Curves.easeOut);
    _addressCtrl.text = context.read<TabManager>().active.addressText;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final stitch = await DurableStore.getStitchEnabled();
    final popup = await DurableStore.getPopupBlockEnabled();
    final ad = await DurableStore.getAdBlockEnabled();
    final cross = await DurableStore.getCrossSiteBlockEnabled();
    final desk = await DurableStore.getDesktopMode();
    if (!mounted) return;
    setState(() {
      _stitchEnabled = stitch;
      _popupBlock = popup;
      _adBlock = ad;
      _crossSiteBlock = cross;
      _desktopMode = desk;
    });
  }

  @override
  void dispose() {
    _exitFade.dispose();
    _addressCtrl.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  /// Manual only — does not run on background. Fast exit.
  Future<void> _newIdentity() async {
    if (_exiting || _resetting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('换新身份', style: TextStyle(color: _C.text)),
        content: const Text(
          '清除全部网站数据并冷启动。书签会保留。\n平时可当普通浏览器使用，需要时再点这里。',
          style: TextStyle(color: _C.secondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _C.danger),
            child: const Text('换新身份'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _gracefulExit();
  }

  Future<void> _gracefulExit() async {
    if (_exiting) return;
    _exiting = true;
    if (mounted) {
      setState(() {
        _resetting = true;
        _showTabs = false;
        _pickMode = false;
      });
    }
    try {
      await _exitFade.forward();
    } catch (_) {}

    for (final c in _controllers.values) {
      try {
        await c.stopLoading();
      } catch (_) {}
      try {
        await c.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
      } catch (_) {}
    }
    _controllers.clear();
    if (mounted) {
      try {
        context.read<TabManager>().hardResetTabs();
      } catch (_) {}
      _addressCtrl.clear();
    }

    // Keep exit snappy.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await PrivacyEngine.resetAndRelaunch();
  }

  Future<void> _togglePicker() async {
    final c = _activeController;
    if (c == null) {
      _toast('请先打开网页');
      return;
    }
    try {
      final r = await c.evaluateJavascript(source: ReaderScripts.elementPicker);
      final on = r?.toString().contains('on') == true;
      setState(() => _pickMode = on);
      _toast(on
          ? '点选去广告：点要藏的块（会记住本站）；长按本按钮可撤销'
          : '已退出点选');
    } catch (_) {
      _toast('当前页无法启动点选');
    }
  }

  Future<void> _undoHide() async {
    final sel = await HideStore.undoLast();
    if (sel == null) {
      _toast('没有可撤销的隐藏');
      return;
    }
    final c = _activeController;
    if (c != null) {
      try {
        // Show again elements matching last selector (best-effort)
        await c.evaluateJavascript(
          source: '''
(function(){
  try {
    document.querySelectorAll(${jsonEncode(sel)}).forEach(function(el){
      el.style.removeProperty('display');
      el.removeAttribute('data-pb-user-hide');
    });
  } catch(e){}
})();
''',
        );
      } catch (_) {}
    }
    if (mounted) setState(() {});
    _toast('已撤销一处隐藏（本站规则已更新）');
  }

  void _onUserHide(String selector, String pageUrl) {
    if (!mounted) return;
    setState(() {});
    _toast('已隐藏并记住本站（长按去广告键可撤销）');
  }

  InAppWebViewController? get _activeController {
    final id = context.read<TabManager>().active.id;
    return _controllers[id];
  }

  Future<void> _go(String raw) async {
    var input = raw.trim();
    if (input.isEmpty) return;
    late WebUri uri;
    if (input.startsWith('http://') || input.startsWith('https://')) {
      uri = WebUri(input);
    } else if (input.contains(' ') || !input.contains('.')) {
      uri = WebUri('https://duckduckgo.com/?q=${Uri.encodeComponent(input)}');
    } else {
      uri = WebUri('https://$input');
    }
    final c = _activeController;
    if (c == null) return;
    // User-initiated: allow leaving current site once (address bar / search).
    context.read<TabManager>().active.allowCrossSiteOnce = true;
    await c.loadUrl(urlRequest: URLRequest(url: uri));
    _addressFocus.unfocus();
    if (mounted) setState(() => _showTabs = false);
  }

  Future<void> _openBookmark(Bookmark b) async {
    _addressCtrl.text = b.url;
    await _go(b.url);
  }

  String? _currentPageUrl() {
    final tab = context.read<TabManager>().active;
    if (!tab.isBlank && tab.url.isNotEmpty && tab.url != 'about:blank') {
      return tab.url;
    }
    final t = _addressCtrl.text.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return null;
  }

  Future<void> _starBookmark() async {
    // Never focus address bar.
    _addressFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    final url = _currentPageUrl();
    if (url == null) {
      _toast('请先打开一个网页再收藏');
      return;
    }
    final tab = context.read<TabManager>().active;
    final store = context.read<BookmarkStore>();
    final title = tab.title.isNotEmpty && tab.title != '新标签' ? tab.title : '';

    if (store.containsUrl(url)) {
      await store.removeUrl(url);
      _toast('已取消收藏');
      if (mounted) setState(() {});
      return;
    }

    final r = await store.add(Bookmark(title: title, url: url));
    switch (r) {
      case BookmarkAddResult.added:
        _toast('已加入书签');
      case BookmarkAddResult.updated:
        _toast('书签已更新');
      case BookmarkAddResult.full:
        _toast('书签已满（最多 ${BookmarkStore.maxItems} 个），请先删除');
      case BookmarkAddResult.invalid:
        _toast('无法收藏此页');
    }
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _openReader() {
    final url = _currentPageUrl();
    if (url == null) {
      _toast('请先打开一个网页再进入阅读模式');
      return;
    }
    final tab = context.read<TabManager>().active;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderModePage(
          initialUrl: url,
          initialTitle: tab.title,
        ),
      ),
    );
  }

  Future<void> _shareCurrent() async {
    final url = _currentPageUrl();
    if (url == null) {
      _toast('没有可分享的链接');
      return;
    }
    final tab = context.read<TabManager>().active;
    final title = tab.title.isNotEmpty && tab.title != '新标签' ? tab.title : url;
    await Share.share('$title\n$url', subject: title);
  }

  Future<void> _copyLink() async {
    final url = _currentPageUrl();
    if (url == null) {
      _toast('没有可复制的链接');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _toast('链接已复制');
  }

  Future<void> _setStitch(bool v) async {
    setState(() => _stitchEnabled = v);
    await DurableStore.setStitchEnabled(v);
  }

  Future<void> _setPopup(bool v) async {
    setState(() => _popupBlock = v);
    await DurableStore.setPopupBlockEnabled(v);
  }

  Future<void> _setAdBlock(bool v) async {
    setState(() => _adBlock = v);
    await DurableStore.setAdBlockEnabled(v);
  }

  Future<void> _setCrossSite(bool v) async {
    setState(() => _crossSiteBlock = v);
    await DurableStore.setCrossSiteBlockEnabled(v);
  }

  Future<void> _setDesktop(bool v) async {
    setState(() => _desktopMode = v);
    await DurableStore.setDesktopMode(v);
  }

  void _syncAddressFromTab() {
    final tab = context.read<TabManager>().active;
    if (!_addressFocus.hasFocus) {
      final t = tab.isBlank ? '' : tab.addressText;
      if (_addressCtrl.text != t) {
        _addressCtrl.value = TextEditingValue(
          text: t,
          selection: TextSelection.collapsed(offset: t.length),
        );
      }
    }
  }

  String _displayHost(BrowserTabModel tab) {
    if (tab.isBlank) return '';
    try {
      final u = Uri.parse(tab.url);
      return u.host.isEmpty ? tab.addressText : u.host;
    } catch (_) {
      return tab.addressText;
    }
  }

  bool _isBookmarked() {
    final url = _currentPageUrl();
    if (url == null) return false;
    return context.read<BookmarkStore>().containsUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final bookmarks = context.watch<BookmarkStore>();
    final tab = tm.active;
    _syncAddressFromTab();
    final showHome = tab.isBlank && !tab.isLoading;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final starred = _isBookmarked();

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: [
          Column(
            children: [
              if (tab.isLoading)
                SafeArea(
                  bottom: false,
                  child: LinearProgressIndicator(
                    value: tab.progress > 0 && tab.progress < 100
                        ? tab.progress / 100
                        : null,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: _C.accent,
                  ),
                )
              else
                SizedBox(height: MediaQuery.of(context).padding.top),
              Expanded(
                child: Stack(
                  children: [
                    IndexedStack(
                      index: tm.activeIndex,
                      children: [
                        for (final t in tm.tabs)
                          PrivacyWebView(
                            key: ValueKey('${t.id}_d$_desktopMode'),
                            tab: t,
                            desktopMode: _desktopMode,
                            popupBlock: _popupBlock,
                            adBlock: _adBlock,
                            crossSiteBlock: _crossSiteBlock,
                            onUserHide: _onUserHide,
                            onChanged: () {
                              if (mounted) tm.notifyTabChanged();
                            },
                            onControllerReady: (c) {
                              _controllers[t.id] = c;
                            },
                          ),
                      ],
                    ),
                    if (showHome)
                      _SafariStartPage(
                        bookmarks: bookmarks.items,
                        onOpenBookmark: _openBookmark,
                        sessionHint: SessionIdentity.current.sessionId,
                        onManageBookmarks: _showBookmarksSheet,
                      ),
                    // Floating reader button — bottom-left
                    if (!showHome)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: SafeArea(
                          top: false,
                          child: Material(
                            color: _C.field,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(22),
                            child: InkWell(
                              onTap: _openReader,
                              borderRadius: BorderRadius.circular(22),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.menu_book_rounded,
                                        color: _C.accent, size: 20),
                                    SizedBox(width: 6),
                                    Text(
                                      '阅读',
                                      style: TextStyle(
                                        color: _C.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_showTabs)
                      _TabsOverlay(
                        manager: tm,
                        onSelect: (i) {
                          tm.select(i);
                          _addressCtrl.text = tm.active.isBlank
                              ? ''
                              : tm.active.addressText;
                          setState(() => _showTabs = false);
                        },
                        onClose: (i) {
                          final id = tm.tabs[i].id;
                          _controllers.remove(id);
                          tm.closeTab(i);
                          _addressCtrl.text =
                              tm.active.isBlank ? '' : tm.active.addressText;
                          setState(() {});
                        },
                        onDone: () => setState(() => _showTabs = false),
                        onAdd: () {
                          if (tm.addTab()) {
                            _addressCtrl.clear();
                            setState(() => _showTabs = false);
                          } else {
                            _toast('标签已满（最多 ${tm.maxTabs} 个）');
                          }
                        },
                      ),
                  ],
                ),
              ),
              Material(
                color: _C.bar,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: Color(0x33FFFFFF),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                      child: _AddressBar(
                        controller: _addressCtrl,
                        focusNode: _addressFocus,
                        displayHost: _displayHost(tab),
                        isBlank: tab.isBlank,
                        isLoading: tab.isLoading,
                        starred: starred,
                        onStar: _starBookmark,
                        onMenu: _showPageMenu,
                        onSubmit: _go,
                        onReload: () => _activeController?.reload(),
                        onStop: () => _activeController?.stopLoading(),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 4 + bottomPad),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _BarIcon(
                            icon: Icons.chevron_left_rounded,
                            enabled: tab.canGoBack,
                            onTap: () => _activeController?.goBack(),
                          ),
                          _BarIcon(
                            icon: Icons.chevron_right_rounded,
                            enabled: tab.canGoForward,
                            onTap: () => _activeController?.goForward(),
                          ),
                          _BarIcon(
                            icon: Icons.bookmarks_outlined,
                            onTap: _showBookmarksSheet,
                          ),
                          GestureDetector(
                            onLongPress: _undoHide,
                            child: _BarIcon(
                              icon: _pickMode
                                  ? Icons.highlight_alt
                                  : Icons.auto_fix_high_outlined,
                              onTap: _togglePicker,
                              color: _pickMode ? _C.danger : null,
                            ),
                          ),
                          _BarIcon(
                            icon: Icons.copy_all_outlined,
                            badge: '${tm.tabs.length}',
                            onTap: () =>
                                setState(() => _showTabs = !_showTabs),
                          ),
                          _BarIcon(
                            icon: Icons.shield_outlined,
                            color: _C.danger,
                            onTap: _newIdentity,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          FadeTransition(
            opacity: _exitOpacity,
            child: IgnorePointer(
              ignoring: !_resetting && !_exiting,
              child: ColoredBox(
                color: _C.bg,
                child: Center(
                  child: Opacity(
                    opacity: _resetting || _exiting ? 1 : 0,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _C.accent,
                          ),
                        ),
                        SizedBox(height: 18),
                        Text(
                          '换新身份…',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPageMenu() async {
    _addressFocus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '页面菜单',
                        style: TextStyle(
                          color: _C.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('拼接', style: TextStyle(color: _C.text)),
                    subtitle: const Text(
                      '全局：阅读模式自动拼下一章',
                      style: TextStyle(color: _C.secondary, fontSize: 12),
                    ),
                    value: _stitchEnabled,
                    activeColor: _C.accent,
                    onChanged: (v) async {
                      await _setStitch(v);
                      setModal(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('广告拦截', style: TextStyle(color: _C.text)),
                    subtitle: const Text(
                      '拦截广告域名/脚本/资源（真拦截）',
                      style: TextStyle(color: _C.secondary, fontSize: 12),
                    ),
                    value: _adBlock,
                    activeColor: _C.accent,
                    onChanged: (v) async {
                      await _setAdBlock(v);
                      setModal(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('跨站拦截', style: TextStyle(color: _C.text)),
                    subtitle: const Text(
                      '默认开：本站内可跳；禁止跳到其它网站（地址栏/书签仍可）',
                      style: TextStyle(color: _C.secondary, fontSize: 12),
                    ),
                    value: _crossSiteBlock,
                    activeColor: _C.accent,
                    onChanged: (v) async {
                      await _setCrossSite(v);
                      setModal(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('弹窗清理', style: TextStyle(color: _C.text)),
                    subtitle: const Text(
                      '屏蔽 window.open 与遮罩弹层',
                      style: TextStyle(color: _C.secondary, fontSize: 12),
                    ),
                    value: _popupBlock,
                    activeColor: _C.accent,
                    onChanged: (v) async {
                      await _setPopup(v);
                      setModal(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('桌面模式', style: TextStyle(color: _C.text)),
                    subtitle: const Text(
                      '请求桌面版网页',
                      style: TextStyle(color: _C.secondary, fontSize: 12),
                    ),
                    value: _desktopMode,
                    activeColor: _C.accent,
                    onChanged: (v) async {
                      await _setDesktop(v);
                      setModal(() {});
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  ListTile(
                    leading: const Icon(Icons.ios_share, color: _C.accent),
                    title: const Text('分享…', style: TextStyle(color: _C.text)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _shareCurrent();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.link, color: _C.accent),
                    title: const Text('复制链接', style: TextStyle(color: _C.text)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _copyLink();
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.bookmarks_outlined, color: _C.accent),
                    title: const Text('书签', style: TextStyle(color: _C.text)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showBookmarksSheet();
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.copy_all_outlined, color: _C.accent),
                    title: const Text('标签页', style: TextStyle(color: _C.text)),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _showTabs = true);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showBookmarksSheet() async {
    final store = context.read<BookmarkStore>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              final items = store.items;
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.55,
                minChildSize: 0.35,
                maxChildSize: 0.9,
                builder: (_, scrollCtrl) {
                  return Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Row(
                          children: [
                            const Text(
                              '书签',
                              style: TextStyle(
                                color: _C.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${items.length}/${BookmarkStore.maxItems}',
                              style: const TextStyle(color: _C.secondary),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '地址栏 ★ 一键收藏 · 退出后仍保留',
                            style:
                                TextStyle(color: _C.secondary, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: items.isEmpty
                            ? const Center(
                                child: Text(
                                  '暂无书签',
                                  style: TextStyle(color: _C.secondary),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollCtrl,
                                itemCount: items.length,
                                itemBuilder: (_, i) {
                                  final b = items[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _C.field,
                                      child: const Icon(
                                        Icons.public,
                                        color: _C.accent,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      b.title,
                                      style: const TextStyle(color: _C.text),
                                    ),
                                    subtitle: Text(
                                      b.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _C.secondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: _C.secondary,
                                      ),
                                      onPressed: () async {
                                        await store.removeAt(i);
                                        setModal(() {});
                                      },
                                    ),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _openBookmark(b);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// ★ | ≡ | narrow field | reload — star/menu never focus the text field.
class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.controller,
    required this.focusNode,
    required this.displayHost,
    required this.isBlank,
    required this.isLoading,
    required this.starred,
    required this.onStar,
    required this.onMenu,
    required this.onSubmit,
    required this.onReload,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String displayHost;
  final bool isBlank;
  final bool isLoading;
  final bool starred;
  final VoidCallback onStar;
  final VoidCallback onMenu;
  final void Function(String) onSubmit;
  final VoidCallback onReload;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return Container(
          height: 44,
          decoration: BoxDecoration(
            color: _C.field,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.fieldBorder, width: 0.5),
          ),
          child: Row(
            children: [
              // ★ bookmark — separate hit target, no focus
              SizedBox(
                width: 40,
                height: 44,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  splashRadius: 20,
                  onPressed: onStar,
                  icon: Icon(
                    starred ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 22,
                    color: starred ? _C.star : _C.secondary,
                  ),
                ),
              ),
              // ≡ menu
              SizedBox(
                width: 36,
                height: 44,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  splashRadius: 20,
                  onPressed: onMenu,
                  icon: const Icon(
                    Icons.menu_rounded,
                    size: 22,
                    color: _C.secondary,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _C.text,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[\u0000]')),
                  ],
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: isBlank
                        ? '搜索或输入网站'
                        : (focused ? null : displayHost),
                    hintStyle: const TextStyle(
                      color: _C.secondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.25,
                    ),
                  ),
                  onSubmitted: onSubmit,
                  onTap: () {
                    controller.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: controller.text.length,
                    );
                  },
                ),
              ),
              SizedBox(
                width: 40,
                height: 44,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  splashRadius: 20,
                  onPressed: isLoading ? onStop : onReload,
                  icon: Icon(
                    isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                    size: 20,
                    color: _C.accent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.badge,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final String? badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = enabled
        ? (color ?? _C.accent)
        : _C.secondary.withOpacity(0.35);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 26, color: c),
            if (badge != null)
              Positioned(
                right: 8,
                bottom: 6,
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SafariStartPage extends StatelessWidget {
  const _SafariStartPage({
    required this.bookmarks,
    required this.onOpenBookmark,
    required this.sessionHint,
    required this.onManageBookmarks,
  });

  final List<Bookmark> bookmarks;
  final void Function(Bookmark) onOpenBookmark;
  final String sessionHint;
  final VoidCallback onManageBookmarks;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _C.bg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _C.accent, width: 5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '隐私浏览器',
                      style: TextStyle(
                        color: _C.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '会话 ${sessionHint.substring(0, 6)} · 需要时点右下角换新身份',
                      style: const TextStyle(color: _C.secondary, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text(
                          '个人收藏',
                          style: TextStyle(
                            color: _C.secondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: onManageBookmarks,
                          child: const Text('管理', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 16,
                        children: [
                          for (final b in bookmarks.take(20))
                            _FavoriteTile(
                              title: b.title,
                              onTap: () => onOpenBookmark(b),
                            ),
                          if (bookmarks.isEmpty)
                            const Text(
                              '地址栏左侧 ★ 可收藏当前页',
                              style: TextStyle(color: Color(0xFF48484A)),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '★ 收藏 · ≡ 菜单 · 左下阅读 · 书签旁去广告 · 右下换新身份',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF48484A), fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _C.field,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '?',
                  style: const TextStyle(
                    color: _C.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _C.text, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabsOverlay extends StatelessWidget {
  const _TabsOverlay({
    required this.manager,
    required this.onSelect,
    required this.onClose,
    required this.onDone,
    required this.onAdd,
  });

  final TabManager manager;
  final void Function(int) onSelect;
  final void Function(int) onClose;
  final VoidCallback onDone;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF0000000),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const Text(
                    '标签页',
                    style: TextStyle(
                      color: _C.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onDone,
                    child: const Text('完成', style: TextStyle(color: _C.accent)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: manager.tabs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final t = manager.tabs[i];
                  final selected = i == manager.activeIndex;
                  return Material(
                    color: selected ? const Color(0xFF2C2C2E) : _C.field,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      onTap: () => onSelect(i),
                      title: Text(
                        t.isBlank ? '新标签页' : t.title,
                        style: const TextStyle(color: _C.text),
                      ),
                      subtitle: Text(
                        t.isBlank ? '空白页' : t.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: _C.secondary, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: _C.secondary),
                        onPressed: () => onClose(i),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: manager.canAdd ? onAdd : null,
                    icon: const Icon(Icons.add),
                    label: const Text('新建标签页'),
                  ),
                  const Spacer(),
                  Text(
                    '${manager.tabs.length}/${manager.maxTabs}',
                    style: const TextStyle(color: _C.secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
