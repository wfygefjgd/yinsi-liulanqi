import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'privacy_browser/privacy_browser_shell.dart';
import 'privacy_browser/privacy_engine.dart';
import 'privacy_browser/session_identity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(false);
  }

  // Cold start: wipe leftovers, then mint brand-new session identity.
  await PrivacyEngine.wipeOnLaunch();
  SessionIdentity.mint();
  runApp(const PrivacyBrowserApp());
}
