import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'durable_store.dart';
import 'reader_scripts.dart';
import 'session_identity.dart';

/// Clean reader: extract body, optional auto-stitch next chapters.
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
  bool _loading = true;
  bool _stitching = false;
  bool _stitchEnabled = true;
  String _status = '提取正文…';
  String? _error;
  String? _pendingNext;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _stitchEnabled = await DurableStore.getStitchEnabled();
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_stitchEnabled || _stitching || _pendingNext == null) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _stitchNext();
    }
  }

  Future<void> _onWorkerCreated(InAppWebViewController c) async {
    _worker = c;
    await c.loadUrl(urlRequest: URLRequest(url: WebUri(widget.initialUrl)));
  }

  Future<void> _extractFromWorker({bool append = false}) async {
    final c = _worker;
    if (c == null) return;
    try {
      await c.evaluateJavascript(source: ReaderScripts.popupBlock);
    } catch (_) {}
    dynamic raw;
    try {
      raw = await c.evaluateJavascript(source: ReaderScripts.extractArticle);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '提取失败';
        });
      }
      return;
    }
    if (raw == null) return;
    final s = raw is String ? raw : raw.toString();
    // flutter_inappwebview may return JSON string with quotes
    String jsonStr = s;
    if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
      try {
        jsonStr = jsonDecode(jsonStr) as String;
      } catch (_) {}
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!append) _error = '无法解析正文';
        });
      }
      return;
    }
    final title = (data['title'] as String?)?.trim() ?? '';
    final html = (data['html'] as String?) ?? '';
    final next = (data['next'] as String?)?.trim();
    final url = (data['url'] as String?) ?? widget.initialUrl;
    if (html.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!append) _error = '未找到正文，可返回原页';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      if (!append) {
        _parts
          ..clear()
          ..add(_ChapterPart(title: title, html: html, url: url));
      } else {
        // avoid exact duplicate
        if (_parts.isEmpty || _parts.last.html != html) {
          _parts.add(_ChapterPart(title: title, html: html, url: url));
        }
      }
      _pendingNext = (next != null && next.isNotEmpty && next != url) ? next : null;
      _loading = false;
      _stitching = false;
      _status = _pendingNext == null ? '已到底' : '继续滚动加载下一章';
      _error = null;
    });
  }

  Future<void> _stitchNext() async {
    if (!_stitchEnabled || _stitching) return;
    final next = _pendingNext;
    if (next == null || next.isEmpty) return;
    final c = _worker;
    if (c == null) return;
    setState(() {
      _stitching = true;
      _status = '拼接下一章…';
    });
    try {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(next)));
    } catch (_) {
      if (mounted) {
        setState(() {
          _stitching = false;
          _status = '下一章加载失败';
        });
      }
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
    return '''
<!DOCTYPE html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
<style>
  :root { color-scheme: dark; }
  body { margin:0; padding:16px 18px 80px; background:#0B0B0D; color:#E8E8ED;
    font-size:18px; line-height:1.75; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif; }
  h2.ch-title { font-size:20px; margin: 8px 0 16px; color:#fff; font-weight:600; }
  .ch-body img { max-width:100%; height:auto; }
  .ch-body a { color:#0A84FF; }
  hr.sep { border:none; border-top:1px solid #2C2C2E; margin:28px 0; }
  p { margin: 0 0 0.9em; }
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
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          _parts.isNotEmpty && _parts.first.title.isNotEmpty
              ? _parts.first.title
              : (widget.initialTitle.isNotEmpty ? widget.initialTitle : '阅读模式'),
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pendingNext != null && _stitchEnabled)
            IconButton(
              tooltip: '下一章',
              onPressed: _stitching ? null : _stitchNext,
              icon: const Icon(Icons.skip_next_rounded),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Hidden worker WebView for fetch/extract
          SizedBox(
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: InAppWebView(
                initialSettings: InAppWebViewSettings(
                  incognito: true,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  cacheEnabled: false,
                  userAgent: ua,
                  transparentBackground: true,
                ),
                onWebViewCreated: _onWorkerCreated,
                onLoadStop: (controller, url) async {
                  await Future<void>.delayed(const Duration(milliseconds: 350));
                  await _extractFromWorker(append: _parts.isNotEmpty);
                },
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
                    Text(_error!, style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回网页'),
                    ),
                  ],
                ),
              ),
            )
          else if (_parts.isNotEmpty)
            InAppWebView(
              key: ValueKey(_parts.length),
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
              ),
              onScrollChanged: (controller, x, y) async {
                // fallback stitch trigger via content height approx
                if (!_stitchEnabled || _stitching || _pendingNext == null) return;
                try {
                  final h = await controller.getContentHeight() ?? 0;
                  final sy = y;
                  if (h > 0 && sy > h - 900) {
                    _stitchNext();
                  }
                } catch (_) {}
              },
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFF0A84FF))),
          if (_loading || _stitching)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: const Color(0xEE1C1C1E),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A84FF)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _status,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
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
