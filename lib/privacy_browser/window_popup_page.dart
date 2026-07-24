import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'popup_registry.dart';

/// Overlay popup for window.open — same privacy settings as main WebView.
class WindowPopupOverlay {
  WindowPopupOverlay._();

  static OverlayEntry? _entry;
  static int? _activeId;

  static void show(
    BuildContext context, {
    required String url,
    required int windowId,
    VoidCallback? onClosed,
  }) {
    hide(notify: false);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _PopupChrome(
        initialUrl: url.isEmpty ? 'about:blank' : url,
        windowId: windowId,
        onRequestClose: () {
          hide(notify: true);
          onClosed?.call();
        },
      ),
    );
    _entry = entry;
    _activeId = windowId;

    final overlay = Overlay.of(context, rootOverlay: true);
    overlay.insert(entry);
  }

  static void hide({bool notify = true}) {
    final e = _entry;
    _entry = null;
    final id = _activeId;
    _activeId = null;
    if (id != null) {
      PopupRegistry.unregister(id);
    }
    e?.remove();
  }

  static bool get isShowing => _entry != null;
}

class _PopupChrome extends StatefulWidget {
  const _PopupChrome({
    required this.initialUrl,
    required this.windowId,
    required this.onRequestClose,
  });

  final String initialUrl;
  final int windowId;
  final VoidCallback onRequestClose;

  @override
  State<_PopupChrome> createState() => _PopupChromeState();
}

class _PopupChromeState extends State<_PopupChrome> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String _title = '新窗口';
  String _url = '';
  bool _closed = false;

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

  /// Identical privacy profile to main PrivacyWebView.
  InAppWebViewSettings get _privacySettings => InAppWebViewSettings(
    incognito: true,
    javaScriptEnabled: true,
    domStorageEnabled: false,
    databaseEnabled: false,
    cacheEnabled: false,
    clearCache: true,
    thirdPartyCookiesEnabled: false,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: false,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    transparentBackground: false,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    useShouldOverrideUrlLoading: true,
    sharedCookiesEnabled: false,
    userAgent: _randomUA(),
  );

  static const _antiFingerprint = r'''
(function(){
  if (window.__pbAntiFinger) return;
  window.__pbAntiFinger = true;

  try {
    Object.defineProperty(screen, 'width', { get: () => 1920 });
    Object.defineProperty(screen, 'height', { get: () => 1080 });
    Object.defineProperty(screen, 'availWidth', { get: () => 1920 });
    Object.defineProperty(screen, 'availHeight', { get: () => 1040 });
    Object.defineProperty(window, 'innerWidth', { get: () => 1920 });
    Object.defineProperty(window, 'innerHeight', { get: () => 1040 });
    Object.defineProperty(window, 'outerWidth', { get: () => 1920 });
    Object.defineProperty(window, 'outerHeight', { get: () => 1040 });
    Object.defineProperty(window, 'devicePixelRatio', { get: () => 1 });
  } catch(e){}

  try {
    Object.defineProperty(navigator, 'platform', { get: () => 'MacIntel' });
  } catch(e){}

  try {
    Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 0 });
  } catch(e){}

  try {
    Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => 8 });
  } catch(e){}

  try {
    Object.defineProperty(navigator, 'deviceMemory', { get: () => 8 });
  } catch(e){}

  try {
    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function() {
      const blank = document.createElement('canvas');
      blank.width = this.width;
      blank.height = this.height;
      return origToDataURL.call(blank);
    };

    const origToBlob = HTMLCanvasElement.prototype.toBlob;
    HTMLCanvasElement.prototype.toBlob = function() {
      const blank = document.createElement('canvas');
      blank.width = this.width;
      blank.height = this.height;
      return origToBlob.call(blank);
    };
  } catch(e){}

  try {
    const origGetParameter = WebGLRenderingContext.prototype.getParameter;
    WebGLRenderingContext.prototype.getParameter = function(param) {
      if (param === 37445) return 'Google Inc.';
      if (param === 37446) return 'ANGLE (Intel, Intel(R) UHD Graphics 630 Direct3D11 vs_5_0 ps_5_0)';
      return origGetParameter.call(this, param);
    };
  } catch(e){}
})();
''';

  static const _blankHtml = '''
<!DOCTYPE html><html><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title></title>
<style>
  body{margin:0;background:#000;}
</style>
<script>
${_antiFingerprint}
</script>
</head><body></body></html>
''';

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
    PopupRegistry.registerNavigator(widget.windowId, _navigateTo);
    PopupRegistry.registerCloser(widget.windowId, _closeFromPage);
  }

  void _navigateTo(String url) {
    if (_closed) return;
    final c = _controller;
    setState(() {
      _url = url;
      _title = '加载中…';
    });
    if (c == null) return;
    if (url.isEmpty || url == 'about:blank') {
      c.loadData(
        data: _blankHtml,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      );
      return;
    }
    c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _closeFromPage() {
    if (_closed) return;
    _finishClose();
  }

  void _finishClose() {
    if (_closed) return;
    _closed = true;
    PopupRegistry.unregister(widget.windowId);
    widget.onRequestClose();
  }

  @override
  void dispose() {
    if (!_closed) {
      _closed = true;
      PopupRegistry.unregister(widget.windowId);
    }
    try {
      _controller?.dispose();
    } catch (_) {}
    super.dispose();
  }

  static const _windowOpenPolyfill = r'''
(function(){
  if (window.__pbWinOpenV6) return;
  window.__pbWinOpenV6 = true;
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
          source: _antiFingerprint,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: _windowOpenPolyfill,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
  ]);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Material(
      color: Colors.black.withOpacity(0.45),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: top + 8,
            bottom: 0,
            child: Material(
              color: const Color(0xFF000000),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              clipBehavior: Clip.antiAlias,
              elevation: 16,
              child: Column(
                children: [
                  Container(
                    height: 48,
                    color: const Color(0xFF1C1C1E),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '关闭弹窗',
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _finishClose,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _url.isEmpty || _url == 'about:blank'
                                    ? 'about:blank'
                                    : _url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              color: Color(0xFF0A84FF)),
                          onPressed: () => _controller?.reload(),
                        ),
                      ],
                    ),
                  ),
                  if (_progress > 0 && _progress < 1)
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 2,
                      color: const Color(0xFF0A84FF),
                      backgroundColor: Colors.transparent,
                    ),
                  Expanded(
                    child: InAppWebView(
                      initialData: (widget.initialUrl.isEmpty ||
                              widget.initialUrl == 'about:blank')
                          ? InAppWebViewInitialData(
                              data: _blankHtml,
                              mimeType: 'text/html',
                              encoding: 'utf-8',
                              baseUrl: WebUri('about:blank'),
                            )
                          : null,
                      initialUrlRequest: (widget.initialUrl.isEmpty ||
                              widget.initialUrl == 'about:blank')
                          ? null
                          : URLRequest(url: WebUri(widget.initialUrl)),
                      initialSettings: _privacySettings,
                      initialUserScripts: _userScripts,
                      onWebViewCreated: (c) {
                        _controller = c;
                      },
                      onProgressChanged: (c, p) {
                        setState(() => _progress = p / 100.0);
                      },
                      onTitleChanged: (c, t) {
                        if (t != null && t.trim().isNotEmpty) {
                          setState(() => _title = t.trim());
                        }
                      },
                      onLoadStop: (c, u) {
                        if (u != null) {
                          final s = u.toString();
                          if (!s.startsWith('data:')) {
                            setState(() => _url = s);
                          }
                        }
                      },
                      onCreateWindow: (c, a) async {
                        final u = a.request.url;
                        if (u != null) {
                          await c.loadUrl(urlRequest: URLRequest(url: u));
                        }
                        return false;
                      },
                      shouldOverrideUrlLoading: (c, a) async {
                        return NavigationActionPolicy.ALLOW;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
