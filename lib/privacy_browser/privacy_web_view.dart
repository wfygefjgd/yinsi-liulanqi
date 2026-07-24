import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_tab_model.dart';

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

  /// Real `window.open`: show popup UI; when user closes, invoke [onClosed].
  final void Function(String url, int windowId, VoidCallback onClosed)?
      onWindowOpen;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  int _windowSeq = 0;

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

  /// Polyfill so page gets a Window-like object with closed/close.
  static const _windowOpenPolyfill = r'''
(function(){
  if (window.__pbWinOpenV2) return;
  window.__pbWinOpenV2 = true;
  window.__pbPopups = window.__pbPopups || {};

  window.__pbMarkPopupClosed = function(id) {
    try {
      var s = window.__pbPopups[id];
      if (s) s.closed = true;
      try { window.focus(); } catch(e){}
      try {
        window.dispatchEvent(new Event('focus'));
        if (typeof document.hidden !== 'undefined') {
          try {
            Object.defineProperty(document, 'hidden', { configurable: true, get: function(){ return false; } });
          } catch(e2){}
        }
        document.dispatchEvent(new Event('visibilitychange'));
      } catch(e){}
    } catch(e){}
  };

  function makeStub(id, url) {
    var stub = {
      closed: false,
      name: '',
      opener: window,
      location: {
        href: url || 'about:blank',
        replace: function(u){ this.href = u; },
        assign: function(u){ this.href = u; }
      },
      document: { readyState: 'complete', title: '' },
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
      url = (url == null || url === '') ? 'about:blank' : String(url);
      if (url.indexOf('javascript:') === 0) return null;
      try {
        if (url !== 'about:blank' && url.indexOf('http') !== 0) {
          url = new URL(url, location.href).href;
        }
      } catch(e){}

      var id = (Date.now() % 100000000) + Math.floor(Math.random() * 999);
      var stub = makeStub(id, url);

      try {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('windowOpen', url, id, name || '');
        }
      } catch(e){}
      return stub;
    } catch(e) {
      return null;
    }
  };
})();
''';

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
          handlerName: 'windowClose',
          callback: (args) {
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
        // Early inject so first click can open
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
        if (s.isNotEmpty) {
          widget.tab.url = s;
          if (s != 'about:blank') {
            widget.tab.addressText = s;
          }
        }
        final title = await controller.getTitle();
        if (title != null && title.trim().isNotEmpty) {
          widget.tab.title = title.trim();
        } else if (widget.tab.isBlank) {
          widget.tab.title = '新标签';
        }
        await _injectPolyfill(controller);
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _injectPolyfill(controller);
        });
        Future<void>.delayed(const Duration(milliseconds: 1000), () {
          _injectPolyfill(controller);
        });
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
        var url = createWindowAction.request.url?.toString() ?? '';
        if (url.isEmpty) url = 'about:blank';
        final id = ++_windowSeq;
        _openPopup(url, id);
        return false;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        // Normal navigation in current tab (like Safari).
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
