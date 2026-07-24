import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'browser_tab_model.dart';
import 'privacy_engine.dart';
import 'privacy_web_view.dart';
import 'tab_manager.dart';
import 'window_popup_page.dart' show WindowPopupOverlay;

/// Safari-like dark palette
class _S {
  static const bg = Color(0xFF000000);
  static const bar = Color(0xF01C1C1E);
  static const field = Color(0xFF2C2C2E);
  static const fieldBorder = Color(0xFF3A3A3C);
  static const accent = Color(0xFF0A84FF);
  static const text = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF8E8E93);
  static const danger = Color(0xFFFF453A);
}

/// Hardcoded favorites (not wiped with site data).
class _Bookmark {
  const _Bookmark({required this.title, required this.url});
  final String title;
  final String url;
}

const List<_Bookmark> kBuiltInBookmarks = [
  _Bookmark(
    title: 'Jiurelay',
    url: 'https://jiurelay.com/r/JR-UQYJQT',
  ),
];

class PrivacyBrowserApp extends StatelessWidget {
  const PrivacyBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TabManager(maxTabs: 8),
      child: MaterialApp(
        title: '隐私浏览器',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _S.bg,
          colorScheme: const ColorScheme.dark(
            primary: _S.accent,
            surface: _S.bar,
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
    with WidgetsBindingObserver {
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();
  final Map<String, InAppWebViewController> _controllers = {};
  bool _resetting = false;
  bool _backgroundWiped = false;
  bool _showTabs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _addressCtrl.text = context.read<TabManager>().active.addressText;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addressCtrl.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_backgroundWiped || _resetting) return;
      _backgroundWiped = true;
      _silentBackgroundWipe();
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundWiped) {
        _backgroundWiped = false;
        _rebuildAfterWipe();
      }
    }
  }

  Future<void> _silentBackgroundWipe() async {
    // Classic: destroy WebViews + wipe site data, do NOT kill process
    // (kill-on-background caused "environment changed too often" on sites)
    WindowPopupOverlay.hide(notify: false);
    _controllers.clear();
    await PrivacyEngine.wipeOnBackground();
    if (!mounted) return;
    try {
      context.read<TabManager>().hardResetTabs();
    } catch (_) {}
    _addressCtrl.clear();
    if (mounted) setState(() => _showTabs = false);
  }

  void _rebuildAfterWipe() {
    if (!mounted) return;
    setState(() {});
    final tab = context.read<TabManager>().active;
    _addressCtrl.text = tab.addressText;
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
      uri = WebUri(
        'https://duckduckgo.com/?q=${Uri.encodeComponent(input)}',
      );
    } else {
      uri = WebUri('https://$input');
    }
    final c = _activeController;
    if (c == null) return;
    await c.loadUrl(urlRequest: URLRequest(url: uri));
    _addressFocus.unfocus();
    if (mounted) setState(() => _showTabs = false);
  }

  /// Real window.open — Overlay on top of browser (main page stays underneath).
  void _onWindowOpen(String url, int windowId, VoidCallback onClosed) {
    if (!mounted) return;
    WindowPopupOverlay.show(
      context,
      url: url.isEmpty ? 'about:blank' : url,
      windowId: windowId,
      onClosed: onClosed,
    );
  }

  Future<void> _openBookmark(_Bookmark b) async {
    _addressCtrl.text = b.url;
    await _go(b.url);
  }

  Future<void> _showBookmarks() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
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
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '书签',
                    style: TextStyle(
                      color: _S.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final b in kBuiltInBookmarks)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _S.field,
                    child: const Icon(Icons.public, color: _S.accent, size: 20),
                  ),
                  title: Text(b.title, style: const TextStyle(color: _S.text)),
                  subtitle: Text(
                    b.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _S.secondary, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openBookmark(b);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _S.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('清除浏览数据', style: TextStyle(color: _S.text)),
        content: const Text(
          '清除全部网站数据、缓存与 Cookie，并冷启动。',
          style: TextStyle(color: _S.secondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _S.danger),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runHardReset();
  }

  Future<void> _runHardReset() async {
    if (_resetting) return;
    setState(() => _resetting = true);
    _controllers.clear();
    context.read<TabManager>().hardResetTabs();
    _addressCtrl.clear();
    await PrivacyEngine.resetAndRelaunch();
    if (mounted) setState(() => _resetting = false);
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
    final tab = tm.active;
    _syncAddressFromTab();
    final showHome = tab.isBlank && !tab.isLoading;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _S.bg,
      body: Stack(
        children: [
          Column(
            children: [
              // Thin progress under status bar (Safari)
              if (tab.isLoading)
                Padding(
                  padding: EdgeInsets.only(top: topPad),
                  child: LinearProgressIndicator(
                    value: tab.progress > 0 && tab.progress < 100
                        ? tab.progress / 100
                        : null,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: _S.accent,
                  ),
                )
              else
                SizedBox(height: topPad),
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
                            onWindowOpen: _onWindowOpen,
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
                      _SafariStartPage(onOpenBookmark: _openBookmark),
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
                          _addressCtrl.text = tm.active.isBlank
                              ? ''
                              : tm.active.addressText;
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
              // Safari bottom chrome
              Material(
                color: _S.bar,
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
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 4 + bottomPad),
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
                            icon: Icons.bookmark_border_rounded,
                            onTap: _showBookmarks,
                          ),
                          _BarIcon(
                            icon: Icons.ios_share_rounded,
                            onTap: () {
                              final u = tab.isBlank ? null : tab.url;
                              if (u == null || u.isEmpty) return;
                              Clipboard.setData(ClipboardData(text: u));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('链接已复制'),
                                  duration: Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                          _BarIcon(
                            icon: Icons.copy_all_outlined,
                            badge: '${tm.tabs.length}',
                            onTap: () =>
                                setState(() => _showTabs = !_showTabs),
                          ),
                          _BarIcon(
                            icon: Icons.delete_outline_rounded,
                            color: _S.danger,
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
          if (_resetting)
            const ColoredBox(
              color: Color(0xCC000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: _S.accent),
                    SizedBox(height: 16),
                    Text('正在清除…', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Safari-style address field
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
            color: _S.field,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _S.fieldBorder, width: 0.5),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                isBlank || focused
                    ? Icons.search_rounded
                    : Icons.lock_outline_rounded,
                size: 16,
                color: _S.secondary,
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
                    color: _S.text,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: isBlank
                        ? '搜索或输入网站名称'
                        : (focused ? null : displayHost),
                    hintStyle: const TextStyle(
                      color: _S.secondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
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
                  color: _S.accent,
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
    final c = enabled
        ? (color ?? _S.accent)
        : _S.secondary.withOpacity(0.35);
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
                right: 10,
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
  const _SafariStartPage({required this.onOpenBookmark});

  final void Function(_Bookmark) onOpenBookmark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _S.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _S.accent, width: 5),
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: _S.accent,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '隐私浏览器',
                style: TextStyle(
                  color: _S.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '底部搜索 · 支持网站 window.open 弹窗',
                textAlign: TextAlign.center,
                style: TextStyle(color: _S.secondary, fontSize: 13),
              ),
              const SizedBox(height: 28),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '个人收藏',
                  style: TextStyle(
                    color: _S.secondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 20,
                  runSpacing: 16,
                  children: [
                    for (final b in kBuiltInBookmarks)
                      _FavoriteTile(
                        title: b.title,
                        onTap: () => onOpenBookmark(b),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
                color: _S.field,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '?',
                  style: const TextStyle(
                    color: _S.accent,
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
              style: const TextStyle(color: _S.text, fontSize: 11),
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
                      color: _S.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onDone,
                    child: const Text('完成', style: TextStyle(color: _S.accent)),
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
                    color: selected ? const Color(0xFF2C2C2E) : _S.field,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      onTap: () => onSelect(i),
                      title: Text(
                        t.isBlank ? '新标签页' : t.title,
                        style: const TextStyle(color: _S.text),
                      ),
                      subtitle: Text(
                        t.isBlank ? '空白页' : t.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _S.secondary,
                          fontSize: 12,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: _S.secondary),
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
                    style: const TextStyle(color: _S.secondary),
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
