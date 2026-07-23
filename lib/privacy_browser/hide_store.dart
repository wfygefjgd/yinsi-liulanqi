import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ad_block.dart';
import 'durable_store.dart';

/// Per-host CSS selectors the user manually hid (survives wipe via durable/).
class HideStore {
  HideStore._();

  static const fileName = 'user_hides.json';
  static final Map<String, List<String>> _cache = {};
  static bool _loaded = false;

  /// Undo stack for current session (selector + host).
  static final List<_HideOp> undoStack = [];

  static Future<File> _file() async {
    final dir = await DurableStore.durableDir();
    return File('${dir.path}/$fileName');
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final f = await _file();
      if (await f.exists()) {
        final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _cache
          ..clear()
          ..addAll(map.map(
            (k, v) => MapEntry(
              k,
              (v as List).map((e) => e.toString()).toList(),
            ),
          ));
      }
    } catch (_) {}
    _loaded = true;
  }

  static Future<void> _save() async {
    final f = await _file();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(_cache));
  }

  static String hostKey(String? url) {
    if (url == null || url.isEmpty) return '';
    try {
      return AdBlock.rootish(Uri.parse(url).host);
    } catch (_) {
      return '';
    }
  }

  static Future<List<String>> selectorsForUrl(String? url) async {
    await ensureLoaded();
    final k = hostKey(url);
    if (k.isEmpty) return const [];
    return List<String>.from(_cache[k] ?? const []);
  }

  static Future<void> addSelector(String? url, String selector) async {
    await ensureLoaded();
    final k = hostKey(url);
    final sel = selector.trim();
    if (k.isEmpty || sel.isEmpty) return;
    final list = _cache.putIfAbsent(k, () => <String>[]);
    if (!list.contains(sel)) {
      list.add(sel);
      // cap per host
      if (list.length > 80) list.removeRange(0, list.length - 80);
      await _save();
    }
    undoStack.add(_HideOp(host: k, selector: sel));
    if (undoStack.length > 40) undoStack.removeAt(0);
  }

  static Future<String?> undoLast() async {
    await ensureLoaded();
    if (undoStack.isEmpty) return null;
    final op = undoStack.removeLast();
    final list = _cache[op.host];
    if (list != null) {
      list.remove(op.selector);
      if (list.isEmpty) _cache.remove(op.host);
      await _save();
    }
    return op.selector;
  }

  static bool get canUndo => undoStack.isNotEmpty;

  /// JS to re-apply saved selectors on page.
  static String applyScript(List<String> selectors) {
    if (selectors.isEmpty) return '/* no hides */';
    final arr = jsonEncode(selectors);
    return '''
(function(){
  var sels = $arr;
  function apply(){
    sels.forEach(function(s){
      try {
        document.querySelectorAll(s).forEach(function(el){
          el.style.setProperty('display','none','important');
          el.setAttribute('data-pb-user-hide','1');
        });
      } catch(e){}
    });
  }
  apply();
  setInterval(apply, 1500);
})();
''';
  }
}

class _HideOp {
  _HideOp({required this.host, required this.selector});
  final String host;
  final String selector;
}
