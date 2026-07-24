import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Full-screen popup used to implement browser `window.open`.
class WindowPopupPage extends StatefulWidget {
  const WindowPopupPage({
    super.key,
    required this.url,
    this.windowId = 0,
    this.onClosed,
  });

  final String url;
  final int windowId;
  final VoidCallback? onClosed;

  /// Show as modal route; returns when user closes.
  static Future<void> open(
    BuildContext context, {
    required String url,
    int windowId = 0,
    VoidCallback? onClosed,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WindowPopupPage(
          url: url,
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
    _url = widget.url;
  }

  void _notifyClosed() {
    if (_closedNotified) return;
    _closedNotified = true;
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
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  // Nested popups: open in same popup webview
                  javaScriptCanOpenWindowsAutomatically: true,
                  supportMultipleWindows: false,
                  useShouldOverrideUrlLoading: true,
                  userAgent:
                      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
                ),
                onWebViewCreated: (c) => _controller = c,
                onProgressChanged: (c, p) {
                  setState(() => _progress = p / 100.0);
                },
                onTitleChanged: (c, t) {
                  if (t != null && t.trim().isNotEmpty) {
                    setState(() => _title = t.trim());
                  }
                },
                onLoadStop: (c, u) {
                  if (u != null) setState(() => _url = u.toString());
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
