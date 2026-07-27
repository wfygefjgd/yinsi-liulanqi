import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_tab_model.dart';
import 'popup_registry.dart';

typedef TabChanged = void Function();

class PrivacyWebView extends StatefulWidget {
  const PrivacyWebView({
    super.key,
    required this.tabId,
    required this.tab,
    required this.onChanged,
    required this.onControllerReady,
    this.onWindowOpen,
    this.onCreateNewTab,
    this.autoWipe = true,
  });

  final String tabId;
  final BrowserTabModel tab;
  final TabChanged onChanged;
  final void Function(InAppWebViewController controller) onControllerReady;

  /// Show popup UI for window.open(url) — must NOT navigate this WebView.
  final void Function(String url, int windowId, VoidCallback onClosed)?
      onWindowOpen;

  /// Create new tab for window.open(url) — replaces popup window behavior.
  final void Function(String url)? onCreateNewTab;

  /// When false, use normal (non-incognito) mode — behaves like a regular browser.
  final bool autoWipe;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView> {
  InAppWebViewController? _controller;
  int _windowSeq = 0;
  /// Dedupe polyfill + native onCreateWindow for the same click.
  String? _lastOpenUrl;
  int _lastOpenMs = 0;

  /// 白名单域名：这些网站使用更宽松的设置
  static const _whitelistedDomains = [
    'jiurelay.com',
  ];

  bool _isWhitelisted(String? url) {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      return _whitelistedDomains.any((domain) => host.contains(domain));
    } catch (_) {
      return false;
    }
  }

  static final _rng = Random();
  static const _iosVersions = ['16_0', '16_1', '16_2', '17_0', '17_1', '17_2', '17_4'];
  static const _safariBuilds = ['605.1.15', '605.1.16', '604.1'];
  static const _mobileIds = ['15E148', '16A366', '17A849', '17F80'];

  static String _randomUA() {
    final ios = _iosVersions[_rng.nextInt(_iosVersions.length)];
    final build = _safariBuilds[_rng.nextInt(_safariBuilds.length)];
    final mobile = _mobileIds[_rng.nextInt(_mobileIds.length)];
    return 'Mozilla/5.0 (iPhone; CPU iPhone OS $ios like Mac OS X) AppleWebKit/$build (KHTML, like Gecko) Version/17.0 Mobile/$mobile Safari/604.1';
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    incognito: widget.autoWipe,
    javaScriptEnabled: true,
    domStorageEnabled: true, // 启用 localStorage，很多现代网站需要它
    databaseEnabled: !widget.autoWipe,
    cacheEnabled: true, // 允许缓存，提高加载速度
    clearCache: widget.autoWipe,
    // Must be true so window.open / target=_blank hit onCreateWindow
    // instead of navigating the *current* tab (which caused dual same-URL tabs).
    thirdPartyCookiesEnabled: !widget.autoWipe,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    allowsBackForwardNavigationGestures: true,
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: false,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    transparentBackground: false,
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
    useShouldOverrideUrlLoading: true,
    sharedCookiesEnabled: !widget.autoWipe,
    userAgent: _randomUA(),
  );

  /// Keep consistent with iPhone UA (do not spoof desktop — that is a fingerprint).
  /// 轻量级反指纹：仅伪装 webdriver，不修改 Canvas/WebGL（减少兼容性问题）
  static const _antiFingerprint = r'''
(function(){
  if (window.__pbAntiFinger) return;
  window.__pbAntiFinger = true;

  try {
    Object.defineProperty(navigator, 'webdriver', { get: () => false });
  } catch(e){}
})();
''';

  /// window.open + target=_blank → Flutter tab only (never navigate opener).
  static const _windowOpenPolyfill = r'''
(function(){
  if (window.__pbWinOpenV7) return;
  window.__pbWinOpenV7 = true;
  window.__pbPopups = window.__pbPopups || {};

  function absUrl(u) {
    try {
      if (!u || u === 'about:blank') return 'about:blank';
      if (String(u).indexOf('javascript:') === 0) return null;
      if (String(u).indexOf('http') === 0 || String(u).indexOf('about:') === 0) return String(u);
      return new URL(String(u), location.href).href;
    } catch(e) { return String(u); }
  }

  function navigatePopup(id, u) {
    var url = absUrl(u);
    if (!url) return;
    try {
      var s = window.__pbPopups[id];
      if (s && s.location) s.location._href = url;
    } catch(e){}
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('windowNavigate', id, url);
      }
    } catch(e){}
  }

  window.__pbMarkPopupClosed = function(id) {
    try {
      var s = window.__pbPopups[id];
      if (s) s.closed = true;
    } catch(e){}
  };

  function makeLocation(id, initial) {
    var loc = { _href: initial || 'about:blank' };
    Object.defineProperty(loc, 'href', {
      configurable: true,
      enumerable: true,
      get: function(){ return this._href; },
      set: function(u){ navigatePopup(id, u); }
    });
    loc.replace = function(u){ navigatePopup(id, u); };
    loc.assign = function(u){ navigatePopup(id, u); };
    loc.toString = function(){ return this._href; };
    return loc;
  }

  function makeStub(id, url) {
    var stub = {
      closed: false,
      name: '',
      opener: null,
      location: makeLocation(id, url || 'about:blank'),
      document: {
        readyState: 'complete',
        body: { style: {}, textContent: '', innerHTML: '' },
        documentElement: { style: {} },
        getElementById: function(){ return null; },
        querySelector: function(){ return null; },
        querySelectorAll: function(){ return []; },
        createElement: function(){
          return { style: {}, appendChild: function(){}, setAttribute: function(){}, textContent: '', innerHTML: '' };
        },
        write: function(){},
        open: function(){},
        close: function(){},
        title: ''
      },
      focus: function(){},
      blur: function(){},
      postMessage: function(){},
      close: function(){
        this.closed = true;
        try {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('windowClose', id);
          }
        } catch(e){}
      }
    };
    window.__pbPopups[id] = stub;
    return stub;
  }

  window.open = function(url, name, specs) {
    try {
      // Same-window targets: do not open a tab, let normal navigation handle.
      var n = name != null ? String(name) : '';
      if (n === '_self' || n === '_parent' || n === '_top') {
        var su = absUrl(url);
        if (su && su !== 'about:blank') {
          try { location.href = su; } catch(e){}
        }
        return window;
      }
      var u = (url == null || url === '') ? 'about:blank' : String(url);
      if (u.indexOf('javascript:') === 0) return null;
      u = absUrl(u);
      if (!u) return null;
      var id = (Date.now() % 100000000) + Math.floor(Math.random() * 999);
      var stub = makeStub(id, u);
      try {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('windowOpen', u, id, n || '');
        }
      } catch(e){}
      return stub;
    } catch(e) {
      return null;
    }
  };

  // target=_blank links must not navigate the opener tab.
  document.addEventListener('click', function(e) {
    try {
      var t = e.target;
      if (!t || !t.closest) return;
      var a = t.closest('a');
      if (!a) return;
      var tgt = (a.getAttribute('target') || '').toLowerCase();
      if (tgt !== '_blank' && tgt !== '_new') return;
      var href = a.href;
      if (!href || href.indexOf('javascript:') === 0) return;
      e.preventDefault();
      e.stopPropagation();
      if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
      window.open(href, '_blank');
    } catch(err){}
  }, true);

  document.addEventListener('submit', function(e) {
    try {
      var f = e.target;
      if (!f || !f.getAttribute) return;
      var tgt = (f.getAttribute('target') || '').toLowerCase();
      if (tgt !== '_blank' && tgt !== '_new') return;
      e.preventDefault();
      e.stopPropagation();
      var action = f.action || location.href;
      var method = (f.method || 'get').toLowerCase();
      if (method === 'get') {
        var fd = new FormData(f);
        var q = new URLSearchParams(fd).toString();
        var url = action + (action.indexOf('?') >= 0 ? '&' : '?') + q;
        window.open(url, '_blank');
      } else {
        window.open(action, '_blank');
      }
    } catch(err){}
  }, true);
})();
''';

  UnmodifiableListView<UserScript> get _userScripts => UnmodifiableListView([
        UserScript(
          source: _antiFingerprint,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: _windowOpenPolyfill,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]);

  Future<void> _syncNav() async {
    final c = _controller;
    if (c == null || !mounted) return;
    try {
      widget.tab.canGoBack = await c.canGoBack();
      widget.tab.canGoForward = await c.canGoForward();
      if (mounted) widget.onChanged();
    } catch (_) {}
  }

  Future<void> _loadPending() async {
    final c = _controller;
    final pending = widget.tab.pendingUrl;
    if (c == null || pending == null || pending.isEmpty) return;
    widget.tab.pendingUrl = null;
    if (pending == 'about:blank') return;
    try {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(pending)));
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  bool _isDuplicateOpen(String url) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastOpenUrl == url && (now - _lastOpenMs) < 800) {
      return true;
    }
    _lastOpenUrl = url;
    _lastOpenMs = now;
    return false;
  }

  void _openPopup(String url, int id) {
    if (url.isEmpty) url = 'about:blank';
    if (_isDuplicateOpen(url)) return;
    // Prefer onWindowOpen (tab + PopupRegistry for navigate/close).
    final cb = widget.onWindowOpen;
    if (cb != null) {
      cb(url, id, () {
        final c = _controller;
        if (c == null) return;
        c.evaluateJavascript(
          source:
              'try{window.__pbMarkPopupClosed&&window.__pbMarkPopupClosed($id);}catch(e){}',
        );
      });
      return;
    }
    final createTab = widget.onCreateNewTab;
    if (createTab != null && url != 'about:blank') {
      createTab(url);
    }
  }

  @override
  void didUpdateWidget(covariant PrivacyWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab.pendingUrl != null &&
        widget.tab.pendingUrl!.isNotEmpty &&
        widget.tab.pendingUrl != oldWidget.tab.pendingUrl) {
      _loadPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      key: widget.tab.viewKey,
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: _settings,
      initialUserScripts: _userScripts,
      onWebViewCreated: (controller) {
        _controller = controller;

        controller.addJavaScriptHandler(
          handlerName: 'windowOpen',
          callback: (args) {
            final url = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
            final id = args.length > 1
                ? int.tryParse(args[1]?.toString() ?? '') ?? (++_windowSeq)
                : (++_windowSeq);
            if (url.isNotEmpty) {
              _openPopup(url, id);
            }
            return id;
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'windowNavigate',
          callback: (args) {
            final id = args.isNotEmpty
                ? int.tryParse(args[0]?.toString() ?? '') ?? 0
                : 0;
            final url = args.length > 1 ? args[1]?.toString() ?? '' : '';
            if (id != 0 && url.isNotEmpty) {
              PopupRegistry.navigate(id, url);
            }
            return null;
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'windowClose',
          callback: (args) {
            final id = args.isNotEmpty
                ? int.tryParse(args[0]?.toString() ?? '') ?? 0
                : 0;
            if (id != 0) {
              PopupRegistry.closeFromPage(id);
            }
            return null;
          },
        );

        widget.onControllerReady(controller);
        Future<void>.microtask(_loadPending);
      },
      onLoadStart: (controller, url) {
        widget.tab.isLoading = true;
        widget.tab.progress = 0;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        widget.onChanged();
      },
      onProgressChanged: (controller, progress) {
        widget.tab.progress = progress;
        widget.tab.isLoading = progress < 100;
        widget.onChanged();
      },
      onLoadStop: (controller, url) async {
        if (!mounted) return;
        widget.tab.isLoading = false;
        widget.tab.progress = 100;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        try {
          final title = await controller.getTitle();
          if (!mounted) return;
          if (title != null && title.trim().isNotEmpty) {
            widget.tab.title = title.trim();
          } else if (widget.tab.isBlank) {
            widget.tab.title = '新标签';
          }
        } catch (_) {}
        await _syncNav();

        // 添加错误检测和日志
        try {
          final hasError = await controller.evaluateJavascript(source: '''
            (function() {
              var errors = window.__pbErrors || [];
              return errors.length > 0 ? JSON.stringify(errors) : null;
            })();
          ''');
          if (hasError != null) {
            debugPrint('页面加载错误: $hasError');
          }
        } catch (_) {}
      },
      onTitleChanged: (controller, title) {
        if (title != null && title.trim().isNotEmpty) {
          widget.tab.title = title.trim();
          widget.onChanged();
        }
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        await _syncNav();
      },
      onCreateWindow: (controller, createWindowAction) async {
        // New window requested: open as tab, NEVER load in this WebView.
        var url = createWindowAction.request.url?.toString() ?? '';
        if (url.isEmpty) url = 'about:blank';
        final id = ++_windowSeq;
        _openPopup(url, id);
        // false = do not create WKWebView popup; opener must stay put.
        return false;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final u = navigationAction.request.url;
        if (u == null) return NavigationActionPolicy.CANCEL;
        final scheme = u.scheme.toLowerCase();
        if (scheme != 'http' &&
            scheme != 'https' &&
            scheme != 'about' &&
            scheme != 'data' &&
            scheme != 'blob') {
          return NavigationActionPolicy.CANCEL;
        }
        // iOS/macOS only: targetFrame is null for new-window navigations.
        // On Android targetFrame is always null — must not cancel main loads.
        final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS;
        if (isApple && navigationAction.targetFrame == null) {
          final s = u.toString();
          if (s.isNotEmpty && s != 'about:blank') {
            _openPopup(s, ++_windowSeq);
            return NavigationActionPolicy.CANCEL;
          }
        }
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
