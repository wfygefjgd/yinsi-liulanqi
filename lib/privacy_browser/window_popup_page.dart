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

  /// Identical privacy profile to main PrivacyWebView.
  static final InAppWebViewSettings _privacySettings = InAppWebViewSettings(
    incognito: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
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
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );

  static const _blankHtml = '''
<!DOCTYPE html><html><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title></title>
<style>
  body{margin:0;background:#000;}
</style></head><body></body></html>
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
    super.dispose();
  }

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
