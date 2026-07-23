import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'ad_block.dart';
import 'filter_engine.dart';
import 'session_identity.dart';

/// Popup browser for long-press links (user-initiated leave-site).
class LinkPopupPage extends StatefulWidget {
  const LinkPopupPage({super.key, required this.url, this.title = ''});

  final String url;
  final String title;

  static Future<void> open(
    BuildContext context,
    String url, {
    String title = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0B0D),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.92,
        child: LinkPopupPage(url: url, title: title),
      ),
    );
  }

  @override
  State<LinkPopupPage> createState() => _LinkPopupPageState();
}

class _LinkPopupPageState extends State<LinkPopupPage> {
  InAppWebViewController? _c;
  double _progress = 0;
  String _title = '';
  String _url = '';

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _title = widget.title;
  }

  @override
  Widget build(BuildContext context) {
    final ua = SessionIdentity.current.userAgent(desktop: false);
    return SafeArea(
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFF1C1C1E),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title.isNotEmpty ? _title : '弹窗打开',
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
                  onPressed: () => _c?.reload(),
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
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                userAgent: ua,
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: false,
                useShouldOverrideUrlLoading: true,
                useShouldInterceptRequest: true,
              ),
              onWebViewCreated: (c) => _c = c,
              onProgressChanged: (c, p) {
                setState(() => _progress = p / 100.0);
              },
              onTitleChanged: (c, t) {
                if (t != null && t.isNotEmpty) setState(() => _title = t);
              },
              onLoadStop: (c, u) {
                if (u != null) setState(() => _url = u.toString());
              },
              onCreateWindow: (c, a) async => false,
              shouldOverrideUrlLoading: (c, action) async {
                final u = action.request.url?.toString() ?? '';
                if (FilterEngine.shouldBlock(u) || AdBlock.isAdUrl(u)) {
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              shouldInterceptRequest: (c, req) async {
                final u = req.url.toString();
                if (FilterEngine.shouldBlock(u) || AdBlock.isAdUrl(u)) {
                  return WebResourceResponse(
                    contentType: 'text/plain',
                    data: Uint8List(0),
                    statusCode: 204,
                    reasonPhrase: 'Blocked',
                  );
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }
}
