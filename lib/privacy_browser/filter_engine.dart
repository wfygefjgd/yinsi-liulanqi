import 'dart:convert';
import 'dart:io';

import 'ad_block.dart';
import 'durable_store.dart';

/// Downloads & caches EasyList-style network filters.
/// Auto-updates every [updateInterval]; also supports manual update.
class FilterEngine {
  FilterEngine._();

  static const updateInterval = Duration(days: 3);
  static const metaFile = 'filters_meta.json';
  static const hostsFile = 'filter_hosts.txt';
  static const pathsFile = 'filter_paths.txt';

  static const sources = <String>[
    'https://easylist.to/easylist/easylist.txt',
    'https://easylist-downloads.adblockplus.org/easylistchina.txt',
    'https://easylist.to/easylist/easyprivacy.txt',
  ];

  static Set<String> _hosts = {};
  static Set<String> _paths = {};
  static bool _loaded = false;
  static bool _updating = false;
  static DateTime? lastUpdated;
  static String status = '未加载在线规则（仍用内置列表）';

  static Future<Directory> _dir() async {
    final d = await DurableStore.durableDir();
    final sub = Directory('${d.path}/filters');
    if (!await sub.exists()) await sub.create(recursive: true);
    return sub;
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) {
      _bind();
      return;
    }
    await _loadFromDisk();
    _loaded = true;
    _bind();
    if (lastUpdated == null ||
        DateTime.now().difference(lastUpdated!) > updateInterval) {
      // ignore: unawaited_futures
      update(manual: false);
    }
  }

  static void _bind() {
    AdBlock.onlineBlocker = shouldBlockOnlineOnly;
  }

  /// Only downloaded filters (no builtin — avoids recursion).
  static bool shouldBlockOnlineOnly(String? url) {
    if (url == null || url.isEmpty) return false;
    if (_hosts.isEmpty && _paths.isEmpty) return false;
    final lower = url.toLowerCase();
    Uri? u;
    try {
      u = Uri.parse(url);
    } catch (_) {
      return false;
    }
    final host = u.host.toLowerCase();
    final path = '${u.path}?${u.query}'.toLowerCase();
    for (final h in _hosts) {
      if (h.length < 4) continue;
      if (host == h || host.endsWith('.$h')) return true;
    }
    for (final p in _paths) {
      if (p.length > 2 && path.contains(p)) return true;
    }
    for (final h in _hosts) {
      if (h.length > 8 && lower.contains(h)) return true;
    }
    return false;
  }

  /// Builtin + online.
  static bool shouldBlock(String? url) {
    if (url == null || url.isEmpty) return false;
    if (AdBlock.isAdUrl(url)) return true;
    return false; // isAdUrl already includes online via onlineBlocker
  }

  static Future<void> _loadFromDisk() async {
    try {
      final dir = await _dir();
      final metaF = File('${dir.path}/$metaFile');
      final hostsF = File('${dir.path}/$hostsFile');
      final pathsF = File('${dir.path}/$pathsFile');
      if (await hostsF.exists()) {
        _hosts = (await hostsF.readAsLines())
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty && e.contains('.'))
            .toSet();
      }
      if (await pathsF.exists()) {
        _paths = (await pathsF.readAsLines())
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toSet();
      }
      if (await metaF.exists()) {
        final m =
            jsonDecode(await metaF.readAsString()) as Map<String, dynamic>;
        final ts = m['updated'] as String?;
        if (ts != null) lastUpdated = DateTime.tryParse(ts);
        status = m['status'] as String? ?? status;
      }
      if (_hosts.isNotEmpty) {
        status =
            '规则 ${_hosts.length} 域 / ${_paths.length} 路径 · ${_fmt(lastUpdated)}';
      }
    } catch (_) {}
  }

  static String _fmt(DateTime? d) {
    if (d == null) return '未知';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static void _parseList(String body, Set<String> hosts, Set<String> paths) {
    for (final raw in body.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) {
        continue;
      }
      if (line.startsWith('@@')) continue;
      if (line.contains('##') || line.contains('#@#')) continue;
      if (line.startsWith('||')) {
        line = line.substring(2);
        final dollar = line.indexOf(r'$');
        if (dollar >= 0) line = line.substring(0, dollar);
        line = line.replaceAll('^', '').replaceAll('*', '').trim().toLowerCase();
        if (line.isEmpty || line.length > 100) continue;
        if (line.contains('/')) {
          final i = line.indexOf('/');
          final host = line.substring(0, i);
          final path = line.substring(i);
          if (host.contains('.') && host.length > 3) hosts.add(host);
          if (path.length > 2 && path.length < 80) paths.add(path);
        } else if (line.contains('.') && !line.contains(' ')) {
          hosts.add(line);
        }
        continue;
      }
      if (line.startsWith('/') && line.length > 3 && line.length < 60) {
        final dollar = line.indexOf(r'$');
        if (dollar >= 0) line = line.substring(0, dollar);
        paths.add(line.toLowerCase());
      }
    }
  }

  static Future<String> update({bool manual = false}) async {
    if (_updating) return '正在更新…';
    _updating = true;
    status = '正在下载 EasyList…';
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 25);
    client.userAgent =
        'PrivacyBrowserFilter/1.7 (+https://github.com/wfygefjgd/yinsi-liulanqi)';
    final hosts = <String>{};
    final paths = <String>{};
    var ok = 0;

    try {
      for (final src in sources) {
        try {
          final uri = Uri.parse(src);
          final req = await client.getUrl(uri);
          req.headers.set(HttpHeaders.acceptHeader, 'text/plain,*/*');
          final res = await req.close().timeout(const Duration(seconds: 45));
          if (res.statusCode != 200) continue;
          final body = await res.transform(utf8.decoder).join();
          _parseList(body, hosts, paths);
          ok++;
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
      _updating = false;
    }

    if (hosts.isEmpty) {
      if (_hosts.isNotEmpty) {
        status = '更新失败，保留缓存 ${_hosts.length} 域';
      } else {
        status = '更新失败，仅用内置列表';
      }
      return status;
    }

    // Cap size for mobile memory
    final hostList = hosts.toList()..sort();
    if (hostList.length > 80000) {
      _hosts = hostList.sublist(0, 80000).toSet();
    } else {
      _hosts = hostList.toSet();
    }
    _paths = paths;
    lastUpdated = DateTime.now();
    try {
      final dir = await _dir();
      await File('${dir.path}/$hostsFile').writeAsString(_hosts.join('\n'));
      await File('${dir.path}/$pathsFile').writeAsString(_paths.join('\n'));
      status =
          'EasyList ${_hosts.length} 域 / ${_paths.length} 路径 · ${manual ? "手动" : "自动"} ${_fmt(lastUpdated)} · $ok 源';
      await File('${dir.path}/$metaFile').writeAsString(jsonEncode({
        'updated': lastUpdated!.toIso8601String(),
        'hosts': _hosts.length,
        'paths': _paths.length,
        'sources_ok': ok,
        'status': status,
      }));
    } catch (_) {
      status = '规则已解析但写入失败';
    }
    _bind();
    return status;
  }

  static int get hostCount => _hosts.length;
  static int get pathCount => _paths.length;
}
