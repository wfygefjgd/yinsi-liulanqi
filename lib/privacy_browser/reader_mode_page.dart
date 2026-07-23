import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'ad_block.dart';
import 'durable_store.dart';
import 'reader_scripts.dart';
import 'session_identity.dart';

/// Real reader: load page in worker → extract main text → clean view + stitch.
class ReaderModePage extends StatefulWidget {
  const ReaderModePage({
    super.key,
    required this.initialUrl,
    this.initialTitle = '',
  });

  final String initialUrl;
  final String initialTitle;

  @override
  State<ReaderModePage> createState() => _ReaderModePageState();
}

class _ReaderModePageState extends State<ReaderModePage> {
  final _parts = <_ChapterPart>[];
  InAppWebViewController? _worker;
  InAppWebViewController? _viewer;
  bool _loading = true;
  bool _stitching = false;
  bool _stitchEnabled = true;
  int _extractAttempts = 0;
  String _status = '加载页面…';
  String? _error;
  String? _pendingNext;
  String? _loadingUrl;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _stitchEnabled = await DurableStore.getStitchEnabled();
    if (mounted) setState(() {});
  }

  Future<void> _onWorkerCreated(InAppWebViewController c) async {
    _worker = c;
    _loadingUrl = widget.initialUrl;
    await c.loadUrl(urlRequest: URLRequest(url: WebUri(widget.initialUrl)));
  }

  Future<void> _onWorkerLoadStop(InAppWebViewController c, WebUri? url) async {
    // Wait for DOM to settle.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      await c.evaluateJavascript(source: ReaderScripts.adAndPopupBlock);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _extractFromWorker(append: _parts.isNotEmpty, attempt: 0);
  }

  Future<void> _extractFromWorker({
    required bool append,
    required int attempt,
  }) async {
    final c = _worker;
    if (c == null) return;

    dynamic raw;
    try {
      raw = await c.evaluateJavascript(source: ReaderScripts.extractArticle);
    } catch (_) {
      raw = null;
    }

    Map<String, dynamic>? data = _parseExtract(raw);

    // Retry if thin content (SPA / slow render).
    final textLen = (data?['textLen'] as num?)?.toInt() ?? 0;
    final score = (data?['score'] as num?)?.toInt() ?? 0;
    if ((data == null || textLen < 80 || score < 50) && attempt < 4) {
      if (mounted) {
        setState(() {
          _status = '提取正文中…(${attempt + 1})';
          _loading = true;
        });
      }
      await Future<void>.delayed(Duration(milliseconds: 400 + attempt * 300));
      try {
        await c.evaluateJavascript(source: ReaderScripts.adAndPopupBlock);
      } catch (_) {}
      return _extractFromWorker(append: append, attempt: attempt + 1);
    }

    if (data == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _stitching = false;
          if (!append) _error = '无法提取正文，请返回网页或换源';
        });
      }
      return;
    }

    final title = (data['title'] as String?)?.trim() ?? '';
    var html = (data['html'] as String?) ?? '';
    // HARD rule: never jump to chapter while a page-next exists.
    final nextPage = (data['nextPage'] as String?)?.trim() ?? '';
    final nextChapter = (data['nextChapter'] as String?)?.trim() ?? '';
    final kind = (data['kind'] as String?)?.trim() ?? '';
    final fallbackNext = (data['next'] as String?)?.trim() ?? '';
    final String next;
    if (nextPage.isNotEmpty) {
      next = nextPage;
    } else if (kind == 'page' && fallbackNext.isNotEmpty) {
      next = fallbackNext;
    } else if (nextChapter.isNotEmpty) {
      next = nextChapter;
    } else {
      next = fallbackNext;
    }
    final pageUrl = (data['url'] as String?) ?? _loadingUrl ?? widget.initialUrl;

    html = _sanitizeHtml(html);
    if (html.trim().isEmpty || textLen < 40) {
      // Last resort: body innerText as paragraphs
      try {
        final plain = await c.evaluateJavascript(
          source:
              r"(function(){return (document.body&&document.body.innerText)||'';})();",
        );
        final text = plain?.toString() ?? '';
        if (text.trim().length > 40) {
          html = text
              .split(RegExp(r'\n+'))
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .map(_esc)
              .map((l) => '<p>$l</p>')
              .join();
        }
      } catch (_) {}
    }

    if (html.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _stitching = false;
          if (!append) _error = '未找到正文';
        });
      }
      return;
    }

    // Don't stitch to ad / cross-site junk.
    String? nextOk = next.isNotEmpty ? next : null;
    if (nextOk != null && AdBlock.isAdUrl(nextOk)) nextOk = null;
    if (nextOk != null && !AdBlock.isSameSite(pageUrl, nextOk)) {
      // allow same-novel CDN on subdomain — rootish same only
      if (!AdBlock.isSameSite(pageUrl, nextOk)) nextOk = null;
    }

    if (!mounted) return;
    setState(() {
      if (!append) {
        _parts
          ..clear()
          ..add(_ChapterPart(title: title, html: html, url: pageUrl));
      } else {
        final dup = _parts.isNotEmpty &&
            (_parts.last.html == html || _parts.last.url == pageUrl);
        if (!dup) {
          _parts.add(_ChapterPart(title: title, html: html, url: pageUrl));
        }
      }
      _pendingNext = nextOk;
      _loading = false;
      _stitching = false;
      _extractAttempts = attempt;
      _status = _pendingNext == null
          ? '共 ${_parts.length} 段 · 已到底（无下一页/章）'
          : '共 ${_parts.length} 段 · 滚动或点 → 加载下一章';
      _error = null;
    });

    await _refreshViewer();
  }

  Map<String, dynamic>? _parseExtract(dynamic raw) {
    if (raw == null) return null;
    var s = raw is String ? raw : raw.toString();
    if (s == 'null' || s.isEmpty) return null;
    if (s.startsWith('"') && s.endsWith('"')) {
      try {
        s = jsonDecode(s) as String;
      } catch (_) {}
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  String _sanitizeHtml(String html) {
    // strip scripts/styles/iframes
    html = html.replaceAll(
      RegExp(r'<(script|style|iframe|object|embed)[^>]*>[\s\S]*?</\1>',
          caseSensitive: false),
      '',
    );
    html = html.replaceAll(
      RegExp(r'<(script|style|iframe|object|embed)[^>]*/>',
          caseSensitive: false),
      '',
    );
    html = html.replaceAll(
      RegExp(r'''\son\w+\s*=\s*['"][^'"]*['"]''', caseSensitive: false),
      '',
    );
    html = html.replaceAll(
      RegExp(r'''\s(href|src)\s*=\s*['"]javascript:[^'"]*['"]''',
          caseSensitive: false),
      '',
    );
    return html;
  }

  Future<void> _stitchNext() async {
    if (!_stitchEnabled || _stitching) return;
    final next = _pendingNext;
    if (next == null || next.isEmpty) return;
    final c = _worker;
    if (c == null) return;
    setState(() {
      _stitching = true;
      _loading = true;
      _status = '拼接下一章…';
    });
    _loadingUrl = next;
    try {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(next)));
    } catch (_) {
      if (mounted) {
        setState(() {
          _stitching = false;
          _loading = false;
          _status = '下一章加载失败';
        });
      }
    }
  }

  Future<void> _refreshViewer() async {
    final v = _viewer;
    if (v == null || _parts.isEmpty) return;
    try {
      await v.loadData(
        data: _buildDocumentHtml(),
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri(_parts.last.url),
      );
    } catch (_) {
      if (mounted) setState(() {}); // rebuild with new key
    }
  }

  String _buildDocumentHtml() {
    final body = StringBuffer();
    for (var i = 0; i < _parts.length; i++) {
      final p = _parts[i];
      if (p.title.isNotEmpty) {
        body.writeln('<h2 class="ch-title">${_esc(p.title)}</h2>');
      }
      body.writeln('<div class="ch-body">${p.html}</div>');
      if (i < _parts.length - 1) {
        body.writeln('<hr class="sep"/>');
      }
    }
    body.writeln(
      '<div id="end" style="height:120px;color:#666;text-align:center;padding:24px 0;font-size:13px;">'
      '${_pendingNext != null && _stitchEnabled ? "继续下滚加载下一章" : "— 结束 —"}'
      '</div>',
    );
    return '''
<!DOCTYPE html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; padding:18px 20px 48px; background:#E8DFC8; color:#1C1A14;
    font-size:18px; line-height:1.9; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Songti SC", "Noto Serif SC", serif;
    word-wrap: break-word; overflow-wrap: break-word; }
  h2.ch-title { font-size:20px; margin: 10px 0 18px; color:#1A1812; font-weight:700; letter-spacing:0.02em; }
  .ch-body img { max-width:100%; height:auto; border-radius:4px; }
  .ch-body a { color:#3D5A40; pointer-events: none; text-decoration:none; }
  .ch-body p { margin: 0 0 1em; text-indent: 2em; }
  hr.sep { border:none; border-top:1px solid #C9BEA2; margin:28px 0; }
  #end { color:#6B6354 !important; }
</style></head><body>${body.toString()}</body></html>
''';
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  @override
  Widget build(BuildContext context) {
    final ua = SessionIdentity.current.userAgent(desktop: false);
    final showViewer = _parts.isNotEmpty && _error == null;

    return Scaffold(
      backgroundColor: const Color(0xFFE8DFC8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD9CDB0),
        foregroundColor: const Color(0xFF1C1A14),
        title: Text(
          _parts.isNotEmpty && _parts.first.title.isNotEmpty
              ? _parts.first.title
              : (widget.initialTitle.isNotEmpty
                  ? widget.initialTitle
                  : '阅读模式'),
          style: const TextStyle(fontSize: 16, color: Color(0xFF1C1A14)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_stitchEnabled && _pendingNext != null)
            IconButton(
              tooltip: '下一页/章',
              onPressed: _stitching ? null : _stitchNext,
              icon: const Icon(Icons.skip_next_rounded, color: Color(0xFF1C1A14)),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Hidden worker: real page load + extract
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 1,
              height: 1,
              child: InAppWebView(
                initialSettings: InAppWebViewSettings(
                  incognito: true,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  cacheEnabled: false,
                  userAgent: ua,
                  transparentBackground: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  supportMultipleWindows: false,
                  useShouldOverrideUrlLoading: true,
                  useShouldInterceptRequest: true,
                ),
                onWebViewCreated: _onWorkerCreated,
                onLoadStart: (c, url) {
                  if (mounted) {
                    setState(() {
                      _status = _parts.isEmpty ? '加载页面…' : '加载下一章…';
                      _loading = true;
                    });
                  }
                },
                onLoadStop: _onWorkerLoadStop,
                shouldOverrideUrlLoading: (c, action) async {
                  final u = action.request.url?.toString() ?? '';
                  if (AdBlock.isAdUrl(u)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  // Keep worker on same site as initial novel.
                  if ((action.isForMainFrame ?? true) &&
                      !AdBlock.isSameSite(widget.initialUrl, u) &&
                      u.isNotEmpty &&
                      !u.startsWith('about:')) {
                    // allow next chapter only if we requested it
                    if (_loadingUrl != null &&
                        AdBlock.isSameSite(_loadingUrl, u)) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    if (AdBlock.isSameSite(widget.initialUrl, u)) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                shouldInterceptRequest: (c, req) async {
                  final u = req.url.toString();
                  if (AdBlock.isAdUrl(u)) {
                    return WebResourceResponse(
                      contentType: 'text/plain',
                      data: Uint8List(0),
                      statusCode: 204,
                      reasonPhrase: 'Blocked',
                    );
                  }
                  return null;
                },
                onCreateWindow: (c, a) async => false,
              ),
            ),
          ),
          if (_error != null && _parts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                          _status = '重试提取…';
                        });
                        _worker?.reload();
                      },
                      child: const Text('重试'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回网页'),
                    ),
                  ],
                ),
              ),
            )
          else if (showViewer)
            InAppWebView(
              key: ValueKey(
                  'viewer_${_parts.length}_${_parts.last.url.hashCode}'),
              initialData: InAppWebViewInitialData(
                data: _buildDocumentHtml(),
                mimeType: 'text/html',
                encoding: 'utf-8',
                baseUrl: WebUri(_parts.last.url),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: false,
                supportZoom: true,
                transparentBackground: true,
                disableHorizontalScroll: false,
                disableVerticalScroll: false,
              ),
              onWebViewCreated: (c) => _viewer = c,
              onScrollChanged: (controller, x, y) async {
                if (!_stitchEnabled || _stitching || _pendingNext == null) {
                  return;
                }
                try {
                  final h = await controller.getContentHeight() ?? 0;
                  if (h > 0 && y > h - 1000) {
                    await _stitchNext();
                  }
                } catch (_) {}
              },
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF0A84FF)),
            ),
          if (_loading || _stitching)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: const Color(0xEED9CDB0),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF5C6B4A),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _status,
                            style: const TextStyle(
                                color: Color(0xFF3D382C), fontSize: 13),
                          ),
                        ),
                        if (!_stitchEnabled)
                          const Text(
                            '拼接已关',
                            style: TextStyle(color: Color(0xFF6B6354), fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterPart {
  _ChapterPart({required this.title, required this.html, required this.url});
  final String title;
  final String html;
  final String url;
}
