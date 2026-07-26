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

  /// Identical privacy profile to main PrivacyWebView (autoWipe=true).
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
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: false,
    useShouldOverrideUrlLoading: true,
    sharedCookiesEnabled: false,
    userAgent: _randomUA(),
  );

  /// Keep in sync with PrivacyWebView._antiFingerprint.
  static const _antiFingerprint = r'''
(function(){
  if (window.__pbAntiFinger) return;
  window.__pbAntiFinger = true;

  try {
    Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => 4 });
  } catch(e){}

  try {
    Object.defineProperty(navigator, 'deviceMemory', { get: () => 4 });
  } catch(e){}

  try {
    Object.defineProperty(navigator, 'webdriver', { get: () => false });
  } catch(e){}

  try {
    const noise = function(canvas) {
      try {
        var ctx = canvas.getContext('2d');
        if (!ctx) return;
        var w = canvas.width || 0, h = canvas.height || 0;
        if (w < 1 || h < 1) return;
        var x = Math.min(w - 1, 1) | 0, y = Math.min(h - 1, 1) | 0;
        var d = ctx.getImageData(x, y, 1, 1);
        d.data[0] = (d.data[0] + 1) % 256;
        ctx.putImageData(d, x, y);
      } catch(e){}
    };
    var origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function() {
      noise(this);
      return origToDataURL.apply(this, arguments);
    };
    var origToBlob = HTMLCanvasElement.prototype.toBlob;
    HTMLCanvasElement.prototype.toBlob = function() {
      noise(this);
      return origToBlob.apply(this, arguments);
    };
    var origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
    CanvasRenderingContext2D.prototype.getImageData = function() {
      var data = origGetImageData.apply(this, arguments);
      try {
        if (data && data.data && data.data.length) {
          data.data[0] = (data.data[0] + 1) % 256;
        }
      } catch(e){}
      return data;
    };
  } catch(e){}

  function patchWebGL(proto) {
    if (!proto || !proto.getParameter) return;
    var orig = proto.getParameter;
    proto.getParameter = function(param) {
      if (param === 37445) return 'Apple Inc.';
      if (param === 37446) return 'Apple GPU';
      return orig.call(this, param);
    };
  }
  try { patchWebGL(WebGLRenderingContext && WebGLRenderingContext.prototype); } catch(e){}
  try { patchWebGL(typeof WebGL2RenderingContext !== 'undefined' && WebGL2RenderingContext.prototype); } catch(e){}
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
                        c.addJavaScriptHandler(
                          handlerName: 'windowNavigate',
                          callback: (args) {
                            final id = args.isNotEmpty
                                ? int.tryParse(args[0]?.toString() ?? '') ?? 0
                                : 0;
                            final url = args.length > 1
                                ? args[1]?.toString() ?? ''
                                : '';
                            if (id != 0 && url.isNotEmpty) {
                              PopupRegistry.navigate(id, url);
                            }
                            return null;
                          },
                        );
                        c.addJavaScriptHandler(
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
                        c.addJavaScriptHandler(
                          handlerName: 'windowOpen',
                          callback: (args) {
                            final url =
                                args.isNotEmpty ? args[0]?.toString() ?? '' : '';
                            if (url.isNotEmpty &&
                                url != 'about:blank' &&
                                !url.startsWith('javascript:')) {
                              _navigateTo(url);
                            }
                            return widget.windowId;
                          },
                        );
                      },
                      onProgressChanged: (c, p) {
                        if (!mounted || _closed) return;
                        setState(() => _progress = p / 100.0);
                      },
                      onTitleChanged: (c, t) {
                        if (!mounted || _closed) return;
                        if (t != null && t.trim().isNotEmpty) {
                          setState(() => _title = t.trim());
                        }
                      },
                      onLoadStop: (c, u) {
                        if (!mounted || _closed) return;
                        if (u != null) {
                          final s = u.toString();
                          if (!s.startsWith('data:')) {
                            setState(() => _url = s);
                          }
                        }
                      },
                      onCreateWindow: (c, a) async {
                        // Block nested window.open in popups to prevent jumping
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
