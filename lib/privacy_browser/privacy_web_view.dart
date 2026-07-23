import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'ad_block.dart';
import 'browser_tab_model.dart';
import 'hide_store.dart';
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
    this.adBlock = true,
    this.crossSiteBlock = false,
    this.desktopMode = false,
    this.onUserHide,
  });

  final BrowserTabModel tab;
  final TabChanged onChanged;
  final void Function(InAppWebViewController controller) onControllerReady;
  final bool popupBlock;
  final bool adBlock;
  final bool crossSiteBlock;
  final bool desktopMode;
  final void Function(String selector, String pageUrl)? onUserHide;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  String? _siteRoot;

  InAppWebViewSettings get _settings {
    final id = SessionIdentity.current;
    return InAppWebViewSettings(
      incognito: true,
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: false,
      cacheEnabled: false,
      clearCache: false,
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
      userAgent: id.userAgent(desktop: widget.desktopMode),
      preferredContentMode: widget.desktopMode
          ? UserPreferredContentMode.DESKTOP
          : UserPreferredContentMode.MOBILE,
      saveFormData: false,
      // Allow normal navigation; block only true popups via onCreateWindow.
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: false,
      useShouldOverrideUrlLoading: true,
      useShouldInterceptRequest: true,
    );
  }

  UnmodifiableListView<UserScript> get _userScripts {
    final list = <UserScript>[];
    if (widget.adBlock || widget.popupBlock) {
      list.add(UserScript(
        source: ReaderScripts.adAndPopupBlock,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ));
    }
    return UnmodifiableListView(list);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant PrivacyWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.desktopMode != widget.desktopMode) {
      _applyDesktop();
    }
  }

  Future<void> _applyDesktop() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setSettings(settings: _settings);
      await c.reload();
    } catch (_) {}
  }

  void _lockSiteFrom(String? url) {
    if (url == null || url.isEmpty || url.startsWith('about:')) return;
    try {
      final h = Uri.parse(url).host;
      if (h.isEmpty) return;
      _siteRoot = AdBlock.rootish(h);
    } catch (_) {}
  }

  bool _isCrossSite(String url) {
    if (_siteRoot == null) return false;
    try {
      final h = Uri.parse(url).host;
      if (h.isEmpty) return false;
      return AdBlock.rootish(h) != _siteRoot;
    } catch (_) {
      return false;
    }
  }

  Future<void> _inject(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(
        source: SessionIdentity.current.injectScript,
      );
    } catch (_) {}
    if (widget.popupBlock || widget.adBlock) {
      try {
        await controller.evaluateJavascript(
          source: ReaderScripts.adAndPopupBlock,
        );
      } catch (_) {}
    }
    // Re-apply user manual hides for this host
    try {
      final url = widget.tab.url;
      final sels = await HideStore.selectorsForUrl(url);
      if (sels.isNotEmpty) {
        await controller.evaluateJavascript(
          source: HideStore.applyScript(sels),
        );
      }
    } catch (_) {}
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
      initialUserScripts: _userScripts,
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'hideElement',
          callback: (args) {
            final sel = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
            final pageUrl = args.length > 1
                ? args[1]?.toString() ?? widget.tab.url
                : widget.tab.url;
            if (sel.isNotEmpty) {
              HideStore.addSelector(pageUrl, sel);
              widget.onUserHide?.call(sel, pageUrl);
            }
            return null;
          },
        );
        widget.onControllerReady(controller);
      },
      onLoadStart: (controller, url) {
        widget.tab.isLoading = true;
        widget.tab.progress = 0;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          if (_siteRoot == null || widget.tab.allowCrossSiteOnce) {
            _lockSiteFrom(s);
            widget.tab.allowCrossSiteOnce = false;
          }
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
        Future<void>.delayed(const Duration(milliseconds: 500), () async {
          try {
            await _inject(controller);
          } catch (_) {}
        });
        Future<void>.delayed(const Duration(milliseconds: 1500), () async {
          try {
            await _inject(controller);
          } catch (_) {}
        });
        widget.tab.isLoading = false;
        widget.tab.progress = 100;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty) {
          if (_siteRoot == null) _lockSiteFrom(s);
          widget.tab.url = s;
          if (s != 'about:blank') widget.tab.addressText = s;
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
        // Popup windows blocked; user can long-press for system open if needed.
        final u = createWindowAction.request.url;
        if (u != null && !AdBlock.isAdUrl(u.toString())) {
          // Soft: open same tab instead of new window
          await controller.loadUrl(urlRequest: URLRequest(url: u));
        }
        return false;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString();
        if (url == null || url.isEmpty) {
          return NavigationActionPolicy.ALLOW;
        }
        if (url.startsWith('about:') ||
            url.startsWith('data:') ||
            url.startsWith('blob:') ||
            url.startsWith('javascript:')) {
          return NavigationActionPolicy.ALLOW;
        }

        // Always block hard-ad navigations (main or sub).
        if (widget.adBlock && AdBlock.isAdUrl(url)) {
          return NavigationActionPolicy.CANCEL;
        }

        final isMain = navigationAction.isForMainFrame ?? true;
        if (!isMain) return NavigationActionPolicy.ALLOW;

        // Address bar / bookmark
        if (widget.tab.allowCrossSiteOnce) {
          _siteRoot = null;
          _lockSiteFrom(url);
          widget.tab.allowCrossSiteOnce = false;
          return NavigationActionPolicy.ALLOW;
        }

        if (_siteRoot == null || widget.tab.isBlank) {
          _lockSiteFrom(url);
          return NavigationActionPolicy.ALLOW;
        }

        // Default: ALLOW almost all main-frame navigations (normal browsing).
        // Optional cross-site mode: only cancel silent auto redirects to other roots.
        if (widget.crossSiteBlock && _isCrossSite(url)) {
          final gesture = navigationAction.hasGesture;
          // iOS often reports null for hasGesture — treat null as allow.
          if (gesture == false) {
            return NavigationActionPolicy.CANCEL;
          }
          _lockSiteFrom(url);
        } else if (!_isCrossSite(url)) {
          // same site ok
        } else {
          _lockSiteFrom(url);
        }

        return NavigationActionPolicy.ALLOW;
      },
      shouldInterceptRequest: (controller, request) async {
        if (!widget.adBlock) return null;
        final url = request.url.toString();
        if (AdBlock.isAdUrl(url)) {
          return WebResourceResponse(
            contentType: 'text/plain',
            data: Uint8List(0),
            statusCode: 204,
            reasonPhrase: 'Blocked',
          );
        }
        return null;
      },
    );
  }
}
