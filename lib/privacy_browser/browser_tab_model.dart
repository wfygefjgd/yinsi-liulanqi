import 'package:flutter/foundation.dart';

class BrowserTabModel {
  BrowserTabModel({required this.id});

  final String id;
  final UniqueKey viewKey = UniqueKey();

  String title = '新标签';
  String url = '';
  String addressText = '';
  bool isLoading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  int progress = 0;

  /// Set true before address-bar / bookmark loadUrl so cross-site lock allows once.
  bool allowCrossSiteOnce = false;

  bool get isBlank => url.isEmpty || url == 'about:blank';
}
