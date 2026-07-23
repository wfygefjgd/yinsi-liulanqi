import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'browser_tab_model.dart';
import 'privacy_engine.dart';
import 'privacy_web_view.dart';
import 'tab_manager.dart';

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
    _controllers.clear();
    await PrivacyEngine.nuclearWipe(exitAfter: false);
    if (!mounted) return;
    context.read<TabManager>().hardResetTabs();
    _addressCtrl.clear();
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

  void _openInBackground(String url) {
    final tm = context.read<TabManager>();
    final ok = tm.openInBackground(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已在后台标签打开' : '标签已满，无法后台打开'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _S.field,
      ),
    );
    setState(() {});
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _S.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('清除浏览数据', style: TextStyle(color: _S.text)),
        content: const Text(
          '清除全部网站数据、缓存与 Cookie，并冷启动。书签等本地设置会一并清除。',
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
                            onOpenInBackground: _openInBackground,
                            onChanged: () {
                              if (mounted) tm.notifyTabChanged();
                            },
                            onControllerReady: (c) {
                              _controllers[t.id] = c;
                            },
                          ),
                      ],
                    ),
                    if (showHome) const _SafariStartPage(),
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
  const _SafariStartPage();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _S.bg,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _S.accent, width: 5),
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    color: _S.accent,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '隐私浏览器',
                  style: TextStyle(
                    color: _S.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '在底部地址栏搜索或输入网址\n点击链接将在后台标签打开',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _S.secondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
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
