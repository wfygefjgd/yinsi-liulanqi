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
    this.onOpenInBackground,
  });

  final BrowserTabModel tab;
  final TabChanged onChanged;
  final void Function(InAppWebViewController controller) onControllerReady;

  /// When user taps a link, open it in a background tab instead of navigating.
  final void Function(String url)? onOpenInBackground;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;

  static final InAppWebViewSettings _settings = InAppWebViewSettings(
    incognito: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: false,
    cacheEnabled: false,
    thirdPartyCookiesEnabled: false,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    allowsBackForwardNavigationGestures: true,
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: false,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    transparentBackground: false,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    useShouldOverrideUrlLoading: true,
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );

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
          handlerName: 'openBackground',
          callback: (args) {
            final u = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
            if (u.startsWith('http://') || u.startsWith('https://')) {
              widget.onOpenInBackground?.call(u);
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
        // Click link → background tab (JS, works even when hasGesture is null)
        if (widget.onOpenInBackground != null) {
          try {
            await controller.evaluateJavascript(source: r'''
(function(){
  if (window.__pbBgClick) return;
  window.__pbBgClick = true;
  document.addEventListener('click', function(ev){
    try {
      if (ev.defaultPrevented) return;
      if (ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
      var a = ev.target && ev.target.closest && ev.target.closest('a,area');
      if (!a) return;
      var href = a.href || '';
      if (!href || href.indexOf('javascript:')===0 || href==='#') return;
      if (href.indexOf('http')!==0) {
        try { href = new URL(href, location.href).href; } catch(e){ return; }
      }
      // same-page hash only: allow
      if (href.split('#')[0] === location.href.split('#')[0]) return;
      ev.preventDefault();
      ev.stopPropagation();
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('openBackground', href);
      }
    } catch(e){}
  }, true);
})();
''');
          } catch (_) {}
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
        final u = createWindowAction.request.url?.toString();
        if (u != null &&
            u.isNotEmpty &&
            (u.startsWith('http://') || u.startsWith('https://'))) {
          widget.onOpenInBackground?.call(u);
        }
        return false;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        // Address bar / pending load / redirects: allow in current tab.
        // Link clicks are handled primarily by JS openBackground.
        final url = navigationAction.request.url?.toString() ?? '';
        if (url.isEmpty ||
            url.startsWith('about:') ||
            url.startsWith('data:') ||
            url.startsWith('blob:') ||
            url.startsWith('javascript:')) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
