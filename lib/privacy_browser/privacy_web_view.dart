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
    /// true = page may only navigate within same site root; other hosts blocked.
    this.crossSiteBlock = true,
    this.desktopMode = false,
    this.onUserHide,
    this.onLongPressLink,
  });

  final BrowserTabModel tab;
  final TabChanged onChanged;
  final void Function(InAppWebViewController controller) onControllerReady;
  final bool popupBlock;
  final bool adBlock;
  final bool crossSiteBlock;
  final bool desktopMode;
  final void Function(String selector, String pageUrl)? onUserHide;
  final void Function(String url, String title)? onLongPressLink;
  /// Long-press link → open in in-app popup sheet.
  final void Function(String url, String title)? onLongPressLink;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  /// Locked site root (e.g. example.com) after first intentional load.
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
      list.add(UserScript(
        source: ReaderScripts.adAndPopupBlock,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
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
      // Never lock onto a known ad host as the "home" site.
      if (AdBlock.isAdUrl(url)) return;
      _siteRoot = AdBlock.rootish(h);
    } catch (_) {}
  }

  /// true = different site root than locked page (ad landers, random domains).
  bool _isOtherSite(String url) {
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
    // Long-press any link / button with href → popup browser
    try {
      await controller.evaluateJavascript(source: ReaderScripts.longPressOpen);
    } catch (_) {}
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
        controller.addJavaScriptHandler(
          handlerName: 'openLinkPopup',
          callback: (args) {
            final url = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
            final title = args.length > 1 ? args[1]?.toString() ?? '' : '';
            if (url.isNotEmpty &&
                (url.startsWith('http://') || url.startsWith('https://'))) {
              widget.onLongPressLink?.call(url, title);
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
        for (final ms in [400, 1000, 2500]) {
          Future<void>.delayed(Duration(milliseconds: ms), () async {
            try {
              await _inject(controller);
            } catch (_) {}
          });
        }
        widget.tab.isLoading = false;
        widget.tab.progress = 100;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty) {
          if (_siteRoot == null && !AdBlock.isAdUrl(s)) _lockSiteFrom(s);
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
        // Never open popup windows (ad garbage).
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

        // 1) Ad / tracker URLs — always block (main + iframe).
        if (widget.adBlock && AdBlock.isAdUrl(url)) {
          return NavigationActionPolicy.CANCEL;
        }

        final isMain = navigationAction.isForMainFrame ?? true;

        // 2) Address bar / bookmark — user may go anywhere once.
        if (isMain && widget.tab.allowCrossSiteOnce) {
          _siteRoot = null;
          _lockSiteFrom(url);
          widget.tab.allowCrossSiteOnce = false;
          return NavigationActionPolicy.ALLOW;
        }

        // 3) First page in empty tab — lock site, allow.
        if (isMain && (_siteRoot == null || widget.tab.isBlank)) {
          _lockSiteFrom(url);
          return NavigationActionPolicy.ALLOW;
        }

        // 4) Same site (www / m / path) — always allow continuous browsing.
        if (!_isOtherSite(url)) {
          return NavigationActionPolicy.ALLOW;
        }

        // 5) Other site from page content — HARD BLOCK when feature on.
        //    This is the product: 自己站能跳，别的站（含广告站）不能跳。
        if (widget.crossSiteBlock) {
          return NavigationActionPolicy.CANCEL;
        }

        // Feature off: allow leave and re-lock.
        if (isMain) _lockSiteFrom(url);
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
