import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Classic-style wipe: clear all site data; optional cold exit only on manual reset.
class PrivacyEngine {
  PrivacyEngine._();

  static const _channel = MethodChannel('privacy_browser/engine');
  static bool _wiping = false;
  static final List<Completer<void>> _waiters = [];

  static Future<void> nuclearWipe({bool exitAfter = false}) async {
    if (_wiping) {
      final completer = Completer<void>();
      _waiters.add(completer);
      return completer.future;
    }
    _wiping = true;
    try {
      // Keep user prefs across site-data wipe (native also clears UserDefaults).
      final preserved = await _snapshotPreservedPrefs();
      await _wipeWebLayer();
      await _wipeFlutterPrefs();
      await _wipeAppDirs();
      try {
        await _channel.invokeMethod<void>('nuclearWipe');
      } on PlatformException {
      } on MissingPluginException {
      }
      // Second pass after native (async writers)
      await _wipeWebLayer();
      await _restorePreservedPrefs(preserved);
      if (exitAfter) {
        await _exitApp();
      }
    } finally {
      _wiping = false;
      for (final w in _waiters) {
        w.complete();
      }
      _waiters.clear();
    }
  }

  static Future<void> wipeOnLaunch() async {
    await nuclearWipe(exitAfter: false);
  }

  /// Manual clear only: wipe + kill process for cold identity.
  static Future<void> resetAndRelaunch() async {
    await nuclearWipe(exitAfter: true);
  }

  /// Leave app / background: fast wipe + elegant exit after brief delay.
  /// User sees smooth transition, then app kills itself (elegant violence).
  static Future<void> wipeAndExit() async {
    if (_wiping) return;
    _wiping = true;
    try {
      // Preserve user prefs in case exit is delayed / fails.
      final preserved = await _snapshotPreservedPrefs();
      await _wipeWebLayer();
      await _wipeFlutterPrefs();
      unawaited(_channel.invokeMethod<void>('nuclearWipe').catchError((_) {}));
      unawaited(_wipeAppDirs().then((_) => _wipeWebLayer()));
      await _restorePreservedPrefs(preserved);
      await Future.delayed(const Duration(milliseconds: 150));
      exit(0);
    } finally {
      _wiping = false;
    }
  }

  static Future<void> _wipeWebLayer() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
    await _clearClipboard();
  }

  static Future<void> _clearClipboard() async {
    try {
      final hasData = await Clipboard.hasStrings();
      if (hasData) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {}
  }

  static Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  /// Keys that must survive wipe (user preferences, not site data).
  static const preservePrefKeys = <String>{
    'pref_auto_wipe_on_background',
  };

  static Future<Map<String, Object?>> _snapshotPreservedPrefs() async {
    final keep = <String, Object?>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in preservePrefKeys) {
        if (prefs.containsKey(key)) {
          keep[key] = prefs.get(key);
        }
      }
    } catch (_) {}
    return keep;
  }

  static Future<void> _restorePreservedPrefs(Map<String, Object?> keep) async {
    if (keep.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in keep.entries) {
        final v = e.value;
        if (v is bool) {
          await prefs.setBool(e.key, v);
        } else if (v is int) {
          await prefs.setInt(e.key, v);
        } else if (v is double) {
          await prefs.setDouble(e.key, v);
        } else if (v is String) {
          await prefs.setString(e.key, v);
        } else if (v is List<String>) {
          await prefs.setStringList(e.key, v);
        }
      }
    } catch (_) {}
  }

  static Future<void> _wipeFlutterPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }

  static Future<void> _wipeAppDirs() async {
    final dirs = <Directory?>[];
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationCacheDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationSupportDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationDocumentsDirectory());
    } catch (_) {}

    for (final dir in dirs) {
      if (dir == null || !await dir.exists()) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  static Future<void> _exitApp() async {
    try {
      await _channel.invokeMethod<void>('exitApp');
    } catch (_) {
      exit(0);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }
}
