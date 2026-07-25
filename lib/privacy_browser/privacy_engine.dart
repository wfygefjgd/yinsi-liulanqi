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
      // Drop any open popup overlay storage path via web layer first
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

  /// Leave app / background: fast wipe + async deep clean.
  /// Returns immediately after clearing web layer, dirs cleaned in background.
  static Future<void> wipeOnBackground() async {
    if (_wiping) return;
    _wiping = true;
    try {
      // Fast: clear web layer immediately (cookies, cache, clipboard)
      await _wipeWebLayer();
      await _wipeFlutterPrefs();
      // Fire native wipe but don't wait
      unawaited(_channel.invokeMethod<void>('nuclearWipe').catchError((_) {}));
      // Deep clean dirs in background, don't block return
      unawaited(_wipeAppDirs().then((_) => _wipeWebLayer()));
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
