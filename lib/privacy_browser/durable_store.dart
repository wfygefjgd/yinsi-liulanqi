import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bookmarks.dart';

/// Survives nuclear wipe. Only URL bookmarks + app switches (not web data).
class DurableStore {
  DurableStore._();

  static const durableDirName = 'durable';
  static const bookmarksFileName = 'bookmarks.json';
  static const settingsFileName = 'settings.json';

  static Future<Directory> durableDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$durableDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _bookmarksFile() async {
    final dir = await durableDir();
    return File('${dir.path}/$bookmarksFileName');
  }

  static Future<File> _settingsFile() async {
    final dir = await durableDir();
    return File('${dir.path}/$settingsFileName');
  }

  static Future<List<Bookmark>> loadBookmarks() async {
    try {
      final f = await _bookmarksFile();
      if (!await f.exists()) {
        final seed = List<Bookmark>.from(kDefaultBookmarks);
        await saveBookmarks(seed);
        return seed;
      }
      final raw = await f.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Bookmark.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((b) => b.url.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return List<Bookmark>.from(kDefaultBookmarks);
    }
  }

  static Future<void> saveBookmarks(List<Bookmark> items) async {
    final f = await _bookmarksFile();
    final data = items.map((b) => b.toJson()).toList();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    try {
      final f = await _settingsFile();
      if (!await f.exists()) {
        return {'stitchEnabled': true, 'popupBlockEnabled': true};
      }
      final raw = await f.readAsString();
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {'stitchEnabled': true, 'popupBlockEnabled': true};
    }
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final f = await _settingsFile();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(settings));
  }

  static Future<bool> getStitchEnabled() async {
    final s = await loadSettings();
    return s['stitchEnabled'] != false;
  }

  static Future<void> setStitchEnabled(bool v) async {
    final s = await loadSettings();
    s['stitchEnabled'] = v;
    await saveSettings(s);
  }

  static Future<bool> getPopupBlockEnabled() async {
    final s = await loadSettings();
    return s['popupBlockEnabled'] != false;
  }

  static Future<void> setPopupBlockEnabled(bool v) async {
    final s = await loadSettings();
    s['popupBlockEnabled'] = v;
    await saveSettings(s);
  }
}
