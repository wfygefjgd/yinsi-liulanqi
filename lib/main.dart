import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'privacy_browser/bookmarks.dart';
import 'privacy_browser/filter_engine.dart';
import 'privacy_browser/privacy_browser_shell.dart';
import 'privacy_browser/session_identity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(false);
  }

  // Normal browser: do NOT wipe on every launch.
  SessionIdentity.mint();

  // Load cached EasyList; auto-update every 3 days in background.
  await FilterEngine.ensureLoaded();

  final bookmarks = BookmarkStore();
  await bookmarks.load();

  runApp(
    ChangeNotifierProvider.value(
      value: bookmarks,
      child: const PrivacyBrowserApp(),
    ),
  );
}
