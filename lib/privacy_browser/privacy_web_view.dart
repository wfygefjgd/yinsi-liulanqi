import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_tab_model.dart';
import 'reader_scripts.dart';
import 'session_identity.dart';

typedef TabChanged = void Function();

class PrivacyWebView extends StatefulWidget {
  const PrivacyWebView({
    super.key,
    required this.tab,
    required this.onChanged,
    required this.onControllerReady,
    this.popupBlock = true,
  });

  final BrowserTabModel tab;
  final TabChanged onChanged;
  final void Function(InAppWebViewController controller) onControllerReady;
  final bool popupBlock;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;

  InAppWebViewSettings get _settings {
    final id = SessionIdentity.current;
    return InAppWebViewSettings(
      incognito: true,
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: false,
      cacheEnabled: false,
      clearCache: true,
      clearSessionCache: true,
      thirdPartyCookiesEnabled: false,
      mediaPlaybackRequiresUserGesture: true,
      allowsInlineMediaPlayback: true,
      allowsBackForwardNavigationGestures: true,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      transparentBackground: false,
      allowsLinkPreview: false,
      isFraudulentWebsiteWarningEnabled: false,
      sharedCookiesEnabled: false,
      limitsNavigationsToAppBoundDomains: false,
      userAgent: id.userAgent,
      saveFormData: false,
      // Block most window.open popups at engine level.
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: false,
    );
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _inject(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(
        source: SessionIdentity.current.injectScript,
      );
    } catch (_) {}
    if (widget.popupBlock) {
      try {
        await controller.evaluateJavascript(source: ReaderScripts.popupBlock);
      } catch (_) {}
    }
  }

  Future<void> _syncNav() async {
    final c = _controller;
    if (c == null) return;
    widget.tab.canGoBack = await c.canGoBack();
    widget.tab.canGoForward = await c.canGoForward();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return InAppWebView(
      key: widget.tab.viewKey,
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: _settings,
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onControllerReady(controller);
      },
      onLoadStart: (controller, url) {
        widget.tab.isLoading = true;
        widget.tab.progress = 0;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        widget.onChanged();
      },
      onProgressChanged: (controller, progress) {
        widget.tab.progress = progress;
        widget.tab.isLoading = progress < 100;
        widget.onChanged();
      },
      onLoadStop: (controller, url) async {
        await _inject(controller);
        widget.tab.isLoading = false;
        widget.tab.progress = 100;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty) {
          widget.tab.url = s;
          if (s != 'about:blank') {
            widget.tab.addressText = s;
          }
        }
        final title = await controller.getTitle();
        if (title != null && title.trim().isNotEmpty) {
          widget.tab.title = title.trim();
        } else if (widget.tab.isBlank) {
          widget.tab.title = '新标签';
        }
        await _syncNav();
      },
      onTitleChanged: (controller, title) {
        if (title != null && title.trim().isNotEmpty) {
          widget.tab.title = title.trim();
          widget.onChanged();
        }
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        await _syncNav();
      },
      onCreateWindow: (controller, createWindowAction) async {
        // Never open popup windows — load in same tab if URL known.
        final url = createWindowAction.request.url;
        if (url != null) {
          await controller.loadUrl(urlRequest: URLRequest(url: url));
        }
        return false;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
