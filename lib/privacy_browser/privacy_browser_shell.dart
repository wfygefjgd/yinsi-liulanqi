import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'bookmarks.dart';
import 'browser_tab_model.dart';
import 'privacy_engine.dart';
import 'privacy_web_view.dart';
import 'reader_mode_page.dart';
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
}

class PrivacyBrowserApp extends StatelessWidget {
  const PrivacyBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TabManager(maxTabs: 3),
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();
  final Map<String, InAppWebViewController> _controllers = {};
  bool _resetting = false;
  bool _backgroundWiped = false;
  bool _showTabs = false;
  bool _exiting = false;
  late final AnimationController _exitFade;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();
    _exitFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _exitOpacity = CurvedAnimation(parent: _exitFade, curve: Curves.easeInOut);
    WidgetsBinding.instance.addObserver(this);
    _addressCtrl.text = context.read<TabManager>().active.addressText;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitFade.dispose();
    _addressCtrl.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_backgroundWiped || _resetting || _exiting) return;
      _backgroundWiped = true;
      _gracefulExit();
    }
  }

  Future<void> _gracefulExit() async {
    if (_exiting) return;
    _exiting = true;
    if (mounted) {
      setState(() {
        _resetting = true;
        _showTabs = false;
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

    await Future<void>.delayed(const Duration(milliseconds: 280));
    // Bookmarks under Documents/durable are preserved by PrivacyEngine.
    await PrivacyEngine.resetAndRelaunch();
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
    await c.loadUrl(urlRequest: URLRequest(url: uri));
    _addressFocus.unfocus();
    if (mounted) setState(() => _showTabs = false);
  }

  Future<void> _openBookmark(Bookmark b) async {
    _addressCtrl.text = b.url;
    await _go(b.url);
  }

  Future<void> _addCurrentBookmark() async {
    final tab = context.read<TabManager>().active;
    final url = tab.isBlank
        ? _addressCtrl.text.trim()
        : (tab.url.isNotEmpty ? tab.url : tab.addressText.trim());
    if (url.isEmpty || url == 'about:blank') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可收藏的网址')),
      );
      return;
    }
    final title = tab.title.isNotEmpty && tab.title != '新标签' ? tab.title : '';
    await context.read<BookmarkStore>().add(Bookmark(title: title, url: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入书签（退出后仍保留）')),
    );
  }

  void _openReader() {
    final tab = context.read<TabManager>().active;
    final url = tab.isBlank ? '' : tab.url;
    if (url.isEmpty || url == 'about:blank') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先打开一个网页再进入阅读模式')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderModePage(
          initialUrl: url,
          initialTitle: tab.title,
        ),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('换新身份', style: TextStyle(color: _C.text)),
        content: const Text(
          '清除全部网站数据并冷启动。书签会保留。',
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
            child: const Text('立即换新'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_resetting || _exiting) return;
    await _gracefulExit();
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

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final bookmarks = context.watch<BookmarkStore>();
    final tab = tm.active;
    _syncAddressFromTab();
    final showHome = tab.isBlank && !tab.isLoading;
    final bottomPad = MediaQuery.of(context).padding.bottom;

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
                            key: ValueKey(t.id),
                            tab: t,
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
                          }
                        },
                      ),
                  ],
                ),
              ),
              Material(
                color: _C.bar,
                elevation: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: Color(0x33FFFFFF),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: _AddressCapsule(
                        controller: _addressCtrl,
                        focusNode: _addressFocus,
                        displayHost: _displayHost(tab),
                        isBlank: tab.isBlank,
                        isLoading: tab.isLoading,
                        onSubmit: _go,
                        onReload: () => _activeController?.reload(),
                        onStop: () => _activeController?.stopLoading(),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(2, 0, 2, 4 + bottomPad),
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
                            icon: Icons.menu_book_rounded,
                            onTap: _openReader,
                          ),
                          _BarIcon(
                            icon: Icons.bookmark_add_outlined,
                            onTap: _addCurrentBookmark,
                          ),
                          _BarIcon(
                            icon: Icons.bookmarks_outlined,
                            onTap: _showBookmarksSheet,
                          ),
                          _BarIcon(
                            icon: Icons.copy_all_outlined,
                            badge: '${tm.tabs.length}',
                            onTap: () => setState(() => _showTabs = !_showTabs),
                          ),
                          _BarIcon(
                            icon: Icons.shield_outlined,
                            color: _C.danger,
                            onTap: _confirmReset,
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
                          '安全退出中',
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
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
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
                            TextButton.icon(
                              onPressed: () async {
                                await _promptAddBookmark(ctx, store);
                                setModal(() {});
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('添加'),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '退出清痕迹，书签会保留',
                            style: TextStyle(color: _C.secondary, fontSize: 12),
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

  Future<void> _promptAddBookmark(BuildContext ctx, BookmarkStore store) async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final tab = context.read<TabManager>().active;
    if (!tab.isBlank) {
      urlCtrl.text = tab.url;
      titleCtrl.text = tab.title == '新标签' ? '' : tab.title;
    }
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('添加书签', style: TextStyle(color: _C.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: _C.text),
              decoration: const InputDecoration(
                labelText: '名称（可选）',
                labelStyle: TextStyle(color: _C.secondary),
              ),
            ),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: _C.text),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '网址',
                labelStyle: TextStyle(color: _C.secondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      var url = urlCtrl.text.trim();
      if (url.isNotEmpty &&
          !url.startsWith('http://') &&
          !url.startsWith('https://')) {
        url = 'https://$url';
      }
      if (url.isNotEmpty) {
        await store.add(Bookmark(title: titleCtrl.text.trim(), url: url));
      }
    }
    titleCtrl.dispose();
    urlCtrl.dispose();
  }
}

class _AddressCapsule extends StatelessWidget {
  const _AddressCapsule({
    required this.controller,
    required this.focusNode,
    required this.displayHost,
    required this.isBlank,
    required this.isLoading,
    required this.onSubmit,
    required this.onReload,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String displayHost;
  final bool isBlank;
  final bool isLoading;
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _C.field,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.fieldBorder, width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 12),
              Icon(
                isBlank || focused
                    ? Icons.search_rounded
                    : Icons.lock_outline_rounded,
                size: 16,
                color: _C.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 15,
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
                        ? '搜索或输入网站名称'
                        : (focused ? null : displayHost),
                    hintStyle: const TextStyle(
                      color: _C.secondary,
                      fontSize: 15,
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
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: isLoading ? onStop : onReload,
                icon: Icon(
                  isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                  size: 20,
                  color: _C.accent,
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
    this.color,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final Color? color;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c =
        enabled ? (color ?? _C.accent) : _C.secondary.withOpacity(0.35);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 24, color: c),
            if (badge != null)
              Positioned(
                right: 6,
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
                    const Spacer(flex: 2),
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _C.accent, width: 6),
                        boxShadow: [
                          BoxShadow(
                            color: _C.accent.withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _C.accent.withOpacity(0.35),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '隐私浏览器',
                      style: TextStyle(
                        color: _C.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '全新身份 · ${sessionHint.substring(0, 6)}',
                      style: const TextStyle(color: _C.secondary, fontSize: 13),
                    ),
                    const Spacer(flex: 1),
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
                          child: const Text(
                            '管理',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 16,
                        children: [
                          for (final b in bookmarks)
                            _FavoriteTile(
                              title: b.title,
                              onTap: () => onOpenBookmark(b),
                            ),
                          if (bookmarks.isEmpty)
                            const Text(
                              '点底栏书签按钮添加',
                              style: TextStyle(color: Color(0xFF48484A)),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 2),
                    const Text(
                      '底栏：阅读模式 · 加书签 · 书签 · 标签 · 换新身份',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF48484A), fontSize: 12),
                    ),
                    const SizedBox(height: 12),
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
