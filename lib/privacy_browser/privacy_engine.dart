import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Extreme privacy wipe — match original thorough clean + process death.
class PrivacyEngine {
  PrivacyEngine._();

  static const _channel = MethodChannel('privacy_browser/engine');
  static bool _wiping = false;

  static Future<void> nuclearWipe({bool exitAfter = false}) async {
    if (_wiping) return;
    _wiping = true;
    try {
      await _wipeWebLayer();
      await _wipeFlutterPrefs();
      await _wipeAppDirs();
      try {
        // Wait for native WebKit / keychain / sandbox wipe to finish
        await _channel.invokeMethod<void>('nuclearWipe');
      } on PlatformException {
      } on MissingPluginException {
      }
      // Second pass web layer after native (some data reappears)
      await _wipeWebLayer();
      if (exitAfter) {
        await _exitApp();
      }
    } finally {
      _wiping = false;
    }
  }

  static Future<void> wipeOnLaunch() async {
    await nuclearWipe(exitAfter: false);
  }

  /// Full reset: wipe + kill process (next open is cold identity).
  static Future<void> resetAndRelaunch() async {
    await nuclearWipe(exitAfter: true);
  }

  /// Background leave: same thorough wipe + kill (like oldest build).
  static Future<void> wipeOnBackground() async {
    await nuclearWipe(exitAfter: true);
  }

  static Future<void> _wipeWebLayer() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
    try {
      // Session cookies / storage extras if API available
      await CookieManager.instance().deleteCookies(url: WebUri('https://jiurelay.com'));
      await CookieManager.instance().deleteCookies(url: WebUri('https://www.jiurelay.com'));
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
          // Only keep hard-coded bookmarks folder name if present
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path.split(Platform.pathSeparator).last;
          if (name == 'durable') continue;
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
    // Fallback if native ignores
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }
}
