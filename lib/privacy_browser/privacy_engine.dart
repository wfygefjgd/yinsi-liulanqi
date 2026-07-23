import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'durable_store.dart';
import 'session_identity.dart';

/// Extreme privacy wipe: web data + sandbox, **keeps durable bookmarks/settings**.
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
      await _wipeAppDirsPreserveDurable();
      try {
        await _channel.invokeMethod<void>('nuclearWipe');
      } on PlatformException {
      } on MissingPluginException {
      }
      SessionIdentity.mint();
      if (exitAfter) {
        await _exitApp();
      }
    } finally {
      _wiping = false;
    }
  }

  static Future<void> wipeOnLaunch() async {
    SessionIdentity.mint();
    await nuclearWipe(exitAfter: false);
    SessionIdentity.mint();
  }

  static Future<void> resetAndRelaunch() async {
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
      final store = WebStorageManager.instance();
      await store.deleteAllData();
    } catch (_) {}
  }

  static Future<void> _wipeFlutterPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }

  static Future<void> _wipeAppDirsPreserveDurable() async {
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
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path.split(Platform.pathSeparator).last;
          if (name == DurableStore.durableDirName) continue;
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
  }
}
