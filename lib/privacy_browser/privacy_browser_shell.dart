import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'bookmarks.dart';
import 'browser_tab_model.dart';
import 'privacy_engine.dart';
import 'privacy_web_view.dart';
import 'session_identity.dart';
import 'tab_manager.dart';

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
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4FC3F7),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0B0B0D),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final tab = context.read<TabManager>().active;
    _addressCtrl.text = tab.addressText;
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
    // Leave app → full wipe + kill process so next open is true cold start.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_backgroundWiped || _resetting) return;
      _backgroundWiped = true;
      _controllers.clear();
      PrivacyEngine.resetAndRelaunch();
    }
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
    if (mounted) setState(() {});
  }

  Future<void> _openBookmark(Bookmark b) async {
    _addressCtrl.text = b.url;
    await _go(b.url);
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text('换新身份', style: TextStyle(color: Colors.white)),
        content: const Text(
          '清除全部网站数据并强制冷启动。下次打开 = 全新第一次无痕。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('立即换新'),
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
    if (mounted) {
      setState(() => _resetting = false);
    }
  }

  void _syncAddressFromTab() {
    final tab = context.read<TabManager>().active;
    if (!_addressFocus.hasFocus) {
      _addressCtrl.value = TextEditingValue(
        text: tab.addressText,
        selection: TextSelection.collapsed(offset: tab.addressText.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;
    _syncAddressFromTab();
    final showHome = tab.isBlank && !tab.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  controller: _addressCtrl,
                  focusNode: _addressFocus,
                  tab: tab,
                  canAdd: tm.canAdd,
                  onSubmit: _go,
                  onBack: () => _activeController?.goBack(),
                  onForward: () => _activeController?.goForward(),
                  onReload: () => _activeController?.reload(),
                  onStop: () => _activeController?.stopLoading(),
                  onReset: _confirmReset,
                  onBookmarks: () => _showBookmarksSheet(),
                  onAddTab: () {
                    if (tm.addTab()) {
                      _addressCtrl.clear();
                    }
                  },
                ),
                if (tab.isLoading)
                  LinearProgressIndicator(
                    value: tab.progress > 0 && tab.progress < 100
                        ? tab.progress / 100
                        : null,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: const Color(0xFF4FC3F7),
                  ),
                _TabStrip(
                  manager: tm,
                  onSelect: (i) {
                    tm.select(i);
                    final t = tm.active;
                    _addressCtrl.text = t.addressText;
                  },
                  onClose: (i) {
                    final id = tm.tabs[i].id;
                    _controllers.remove(id);
                    tm.closeTab(i);
                    _addressCtrl.text = tm.active.addressText;
                  },
                ),
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
                                if (mounted) {
                                  tm.notifyTabChanged();
                                }
                              },
                              onControllerReady: (c) {
                                _controllers[t.id] = c;
                              },
                            ),
                        ],
                      ),
                      if (showHome)
                        _StartHome(
                          onOpenBookmark: _openBookmark,
                          sessionHint: SessionIdentity.current.sessionId,
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
                      CircularProgressIndicator(color: Color(0xFF4FC3F7)),
                      SizedBox(height: 16),
                      Text('正在换新身份…', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBookmarksSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '书签',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final b in kBookmarks)
                ListTile(
                  leading: const Icon(Icons.bookmark, color: Color(0xFF4FC3F7)),
                  title: Text(b.title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    b.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openBookmark(b);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _StartHome extends StatelessWidget {
  const _StartHome({
    required this.onOpenBookmark,
    required this.sessionHint,
  });

  final void Function(Bookmark) onOpenBookmark;
  final String sessionHint;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0B0B0D),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        children: [
          const Text(
            '隐私浏览器',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '本次会话 · 全新身份 ${sessionHint.substring(0, 6)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 28),
          const Text(
            '书签',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 10),
          for (final b in kBookmarks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: const Color(0xFF1A1A20),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onOpenBookmark(b),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark, color: Color(0xFF4FC3F7)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                b.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            '每次打开 / 退到后台 / 点重置 = 新身份（等同第一次无痕）。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.focusNode,
    required this.tab,
    required this.canAdd,
    required this.onSubmit,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onStop,
    required this.onReset,
    required this.onBookmarks,
    required this.onAddTab,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final BrowserTabModel tab;
  final bool canAdd;
  final void Function(String) onSubmit;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onBookmarks;
  final VoidCallback onAddTab;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141418),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: '后退',
              onPressed: tab.canGoBack ? onBack : null,
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            ),
            IconButton(
              tooltip: '前进',
              onPressed: tab.canGoForward ? onForward : null,
              icon: const Icon(Icons.arrow_forward_ios, size: 18),
            ),
            IconButton(
              tooltip: tab.isLoading ? '停止' : '刷新',
              onPressed: tab.isLoading ? onStop : onReload,
              icon: Icon(tab.isLoading ? Icons.close : Icons.refresh, size: 20),
            ),
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
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
                    hintText: '搜索或输入网址',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF222228),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: onSubmit,
                ),
              ),
            ),
            IconButton(
              tooltip: '书签',
              onPressed: onBookmarks,
              icon: const Icon(Icons.bookmarks_outlined, size: 20),
            ),
            IconButton(
              tooltip: '新建标签',
              onPressed: canAdd ? onAddTab : null,
              icon: const Icon(Icons.add, size: 22),
            ),
            IconButton(
              tooltip: '换新身份',
              onPressed: onReset,
              icon: const Icon(Icons.delete_forever_outlined,
                  color: Colors.redAccent, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.manager,
    required this.onSelect,
    required this.onClose,
  });

  final TabManager manager;
  final void Function(int) onSelect;
  final void Function(int) onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: manager.tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final t = manager.tabs[i];
          final selected = i == manager.activeIndex;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 140, minWidth: 72),
              padding: const EdgeInsets.only(left: 10, right: 4),
              decoration: BoxDecoration(
                color:
                    selected ? const Color(0xFF2A2A32) : const Color(0xFF1A1A20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? const Color(0xFF4FC3F7) : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.isBlank ? '新标签' : t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : Colors.white60,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => onClose(i),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14, color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
