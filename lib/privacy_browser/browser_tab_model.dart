import 'package:flutter/foundation.dart';

class BrowserTabModel {
  BrowserTabModel({required this.id, String initialUrl = ''}) {
    if (initialUrl.isNotEmpty) {
      pendingUrl = initialUrl;
      url = initialUrl;
      addressText = initialUrl;
      title = '加载中…';
    }
  }

  final String id;
  final UniqueKey viewKey = UniqueKey();

  String title = '新标签';
  String url = '';
  String addressText = '';
  bool isLoading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  int progress = 0;

  /// Pending URL to load once WebView is ready (background open).
  String? pendingUrl;

  bool get isBlank {
    final pendingBlank = pendingUrl == null ||
        pendingUrl!.isEmpty ||
        pendingUrl == 'about:blank';
    final urlBlank = url.isEmpty || url == 'about:blank';
    return urlBlank && pendingBlank;
  }
}
