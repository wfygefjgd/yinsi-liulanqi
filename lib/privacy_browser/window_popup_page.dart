import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'popup_registry.dart';

/// Full-screen popup for `window.open` — same instance navigated via location.replace.
class WindowPopupPage extends StatefulWidget {
  const WindowPopupPage({
    super.key,
    required this.initialUrl,
    required this.windowId,
    this.onClosed,
  });

  final String initialUrl;
  final int windowId;
  final VoidCallback? onClosed;

  static Future<void> open(
    BuildContext context, {
    required String url,
    required int windowId,
    VoidCallback? onClosed,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WindowPopupPage(
          initialUrl: url,
          windowId: windowId,
          onClosed: onClosed,
        ),
      ),
    );
  }

  @override
  State<WindowPopupPage> createState() => _WindowPopupPageState();
}

class _WindowPopupPageState extends State<WindowPopupPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String _title = '弹窗';
  String _url = '';
  bool _closedNotified = false;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
    PopupRegistry.registerNavigator(widget.windowId, _navigateTo);
    PopupRegistry.registerCloser(widget.windowId, _closeFromPage);
  }

  void _navigateTo(String url) {
    final c = _controller;
    if (c == null) {
      _url = url;
      return;
    }
    if (url.isEmpty) return;
    setState(() {
      _url = url;
      _title = '加载中…';
    });
    c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _closeFromPage() {
    if (!mounted) return;
    _notifyClosed();
    Navigator.of(context).maybePop();
  }

  void _notifyClosed() {
    if (_closedNotified) return;
    _closedNotified = true;
    PopupRegistry.unregister(widget.windowId);
    widget.onClosed?.call();
  }

  @override
  void dispose() {
    _notifyClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: const Color(0xFF1C1C1E),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        _notifyClosed();
                        Navigator.of(context).pop();
                      },
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
                            _url,
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
                      icon: const Icon(Icons.refresh, color: Color(0xFF0A84FF)),
                      onPressed: () => _controller?.reload(),
                    ),
                  ],
                ),
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
                initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  supportMultipleWindows: false,
                  useShouldOverrideUrlLoading: true,
                  userAgent:
                      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
                ),
                onWebViewCreated: (c) {
                  _controller = c;
                  // If navigate arrived before controller ready
                  if (_url.isNotEmpty &&
                      _url != widget.initialUrl &&
                      _url != 'about:blank') {
                    c.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
                  }
                },
                onProgressChanged: (c, p) {
                  setState(() => _progress = p / 100.0);
                },
                onTitleChanged: (c, t) {
                  if (t != null && t.trim().isNotEmpty) {
                    setState(() => _title = t.trim());
                  }
                },
                onLoadStop: (c, u) async {
                  if (u != null) setState(() => _url = u.toString());
                  // about:blank placeholder text for sites that only set opener-side document
                  if (u != null && u.toString().startsWith('about:blank')) {
                    try {
                      await c.evaluateJavascript(source: r'''
document.title = document.title || '正在打开…';
if (document.body && !document.body.dataset.pb) {
  document.body.dataset.pb = '1';
  document.body.style.cssText = 'font-family:-apple-system,sans-serif;padding:24px;color:#333;';
  document.body.textContent = '请稍候，正在确认并打开页面…';
}
''');
                    } catch (_) {}
                  }
                },
                onCreateWindow: (c, action) async {
                  final u = action.request.url;
                  if (u != null) {
                    await c.loadUrl(urlRequest: URLRequest(url: u));
                  }
                  return false;
                },
                shouldOverrideUrlLoading: (c, action) async {
                  return NavigationActionPolicy.ALLOW;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
