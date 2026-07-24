import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_tab_model.dart';
import 'popup_registry.dart';

typedef TabChanged = void Function();

class PrivacyWebView extends StatefulWidget {
  const PrivacyWebView({
    super.key,
    required this.tab,
    required this.onChanged,
    required this.onControllerReady,
    this.onWindowOpen,
  });

  final BrowserTabModel tab;
  final TabChanged onChanged;
  final void Function(InAppWebViewController controller) onControllerReady;

  /// Show popup UI for window.open(url) — must NOT navigate this WebView.
  final void Function(String url, int windowId, VoidCallback onClosed)?
      onWindowOpen;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  int _windowSeq = 0;

  /// Main tab: multi-window so window.open is delivered to onCreateWindow,
  /// but we cancel loading into this view and open overlay instead.
  static final InAppWebViewSettings _settings = InAppWebViewSettings(
    incognito: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: false,
    cacheEnabled: false,
    thirdPartyCookiesEnabled: false,
    mediaPlaybackRequiresUserGesture: false,
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
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );

  /// Scheme 2 polyfill: blank + location.replace → same popup only.
  static const _windowOpenPolyfill = r'''
(function(){
  if (window.__pbWinOpenV5) return;
  window.__pbWinOpenV5 = true;
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
      try { window.focus(); } catch(e){}
      try {
        window.dispatchEvent(new Event('focus'));
        document.dispatchEvent(new Event('visibilitychange'));
      } catch(e){}
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

  function makeDocument() {
    var _tc = '', _ih = '', _title = '';
    var body = { style: {} };
    Object.defineProperty(body, 'textContent', {
      configurable: true,
      get: function(){ return _tc; },
      set: function(v){ _tc = String(v == null ? '' : v); }
    });
    Object.defineProperty(body, 'innerHTML', {
      configurable: true,
      get: function(){ return _ih; },
      set: function(v){ _ih = String(v == null ? '' : v); }
    });
    var doc = {
      readyState: 'complete',
      body: body,
      documentElement: { style: {} },
      getElementById: function(){ return null; },
      querySelector: function(){ return null; },
      querySelectorAll: function(){ return []; },
      createElement: function(){
        return { style: {}, appendChild: function(){}, setAttribute: function(){}, textContent: '', innerHTML: '' };
      },
      write: function(){},
      open: function(){},
      close: function(){}
    };
    Object.defineProperty(doc, 'title', {
      configurable: true,
      get: function(){ return _title; },
      set: function(v){ _title = String(v || ''); }
    });
    return doc;
  }

  function makeStub(id, url) {
    var stub = {
      closed: false,
      name: '',
      opener: null,
      location: makeLocation(id, url || 'about:blank'),
      document: makeDocument(),
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
      var u = (url == null || url === '') ? 'about:blank' : String(url);
      if (u.indexOf('javascript:') === 0) return null;
      u = absUrl(u);
      if (!u) return null;

      var id = (Date.now() % 100000000) + Math.floor(Math.random() * 999);
      var stub = makeStub(id, u);

      try {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('windowOpen', u, id, name || '');
        }
      } catch(e){}
      return stub;
    } catch(e) {
      return null;
    }
  };
})();
''';

  UnmodifiableListView<UserScript> get _userScripts => UnmodifiableListView([
        UserScript(
          source: _windowOpenPolyfill,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: _windowOpenPolyfill,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        ),
      ]);

  @override
  bool get wantKeepAlive => true;

  Future<void> _syncNav() async {
    final c = _controller;
    if (c == null) return;
    widget.tab.canGoBack = await c.canGoBack();
    widget.tab.canGoForward = await c.canGoForward();
    widget.onChanged();
  }

  Future<void> _loadPending() async {
    final c = _controller;
    final pending = widget.tab.pendingUrl;
    if (c == null || pending == null || pending.isEmpty) return;
    widget.tab.pendingUrl = null;
    try {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(pending)));
    } catch (_) {}
  }

  Future<void> _injectPolyfill(InAppWebViewController c) async {
    try {
      await c.evaluateJavascript(source: _windowOpenPolyfill);
    } catch (_) {}
  }

  void _openPopup(String url, int id) {
    final cb = widget.onWindowOpen;
    if (cb == null) return;
    if (url.isEmpty) url = 'about:blank';
    // Never load popup URL into this (main) WebView.
    cb(url, id, () {
      final c = _controller;
      if (c == null) return;
      c.evaluateJavascript(
        source:
            'try{window.__pbMarkPopupClosed&&window.__pbMarkPopupClosed($id);}catch(e){}',
      );
    });
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
    super.build(context);
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
        // Ignore accidental about:blank navigations that would wipe the page
        // (can happen if multi-window mishandles open). Do not clear address.
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        _injectPolyfill(controller);
        widget.onChanged();
      },
      onProgressChanged: (controller, progress) {
        widget.tab.progress = progress;
        widget.tab.isLoading = progress < 100;
        widget.onChanged();
      },
      onLoadStop: (controller, url) async {
        widget.tab.isLoading = false;
        widget.tab.progress = 100;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        // If main view was wrongly navigated to about:blank while we had a page, try goBack
        if ((s.isEmpty || s == 'about:blank') &&
            widget.tab.addressText.isNotEmpty &&
            widget.tab.addressText != 'about:blank') {
          try {
            if (await controller.canGoBack()) {
              await controller.goBack();
            }
          } catch (_) {}
        }
        final title = await controller.getTitle();
        if (title != null && title.trim().isNotEmpty) {
          widget.tab.title = title.trim();
        } else if (widget.tab.isBlank) {
          widget.tab.title = '新标签';
        }
        await _injectPolyfill(controller);
        for (final ms in [200, 800, 2000]) {
          Future<void>.delayed(Duration(milliseconds: ms), () {
            _injectPolyfill(controller);
          });
        }
        await _syncNav();
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
        // CRITICAL: do not load this request in the current WebView.
        // Open overlay popup only.
        var url = createWindowAction.request.url?.toString() ?? '';
        if (url.isEmpty) url = 'about:blank';
        final id = ++_windowSeq;
        _openPopup(url, id);
        // false = cancel default (do NOT load into this WebView / do not require windowId child)
        return false;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        // Always allow normal in-page navigation.
        // Popup targets should not appear here if polyfill works.
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
