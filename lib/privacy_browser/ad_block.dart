/// Built-in ad / tracker URL detection + bridge to online EasyList cache.
class AdBlock {
  AdBlock._();

  static const hostHints = <String>[
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'googletagmanager.com',
    'googletagservices.com',
    'google-analytics.com',
    'securepubads.g.doubleclick',
    'pagead2.googlesyndication',
    'fundingchoicesmessages.google',
    'facebook.net',
    'connect.facebook.net',
    'adservice.google',
    'partner.googleadservices',
    'adnxs.com',
    'adsrvr.org',
    'adsafeprotected.com',
    'advertising.com',
    'adcolony.com',
    'adform.net',
    'admob.com',
    'amazon-adsystem.com',
    'scorecardresearch.com',
    'quantserve.com',
    'hotjar.com',
    'clarity.ms',
    'taboola.com',
    'outbrain.com',
    'criteo.com',
    'criteo.net',
    'pubmatic.com',
    'openx.net',
    'rubiconproject.com',
    'casalemedia.com',
    'moatads.com',
    'exelator.com',
    'bidswitch.net',
    'sharethrough.com',
    'yieldmo.com',
    'media.net',
    'adsymptotic.com',
    'ads-twitter.com',
    'static.ads-twitter.com',
    'gdt.qq.com',
    'mi.gdt.qq.com',
    'wxsnsdy.tc.qq.com',
    'l.qq.com',
    'pgdt.gtimg.cn',
    'pangolin-sdk-toutiao.com',
    'pglstatp-toutiao.com',
    'bytead',
    'snssdk.com',
    'pos.baidu.com',
    'cpro.baidu.com',
    'hm.baidu.com',
    'eclick.baidu.com',
    'tanx.com',
    'cnzz.com',
    'umeng.com',
    'umengcloud.com',
    'growingio.com',
    'jiguang.cn',
    'getui.com',
    'beacon.qq.com',
    'pingjs.qq.com',
    'lianmeng.360.cn',
    'mediav.com',
    'union.uc',
    'ad.qq.com',
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'propellerpops.com',
    'adsterra.com',
    'exoclick.com',
    'juicyads.com',
    'trafficjunky.com',
    'tsyndicate.com',
    'hilltopads.com',
    'clickadu.com',
    'trafficstars.com',
    'ad-maven.com',
    'pushwoosh.com',
    'onesignal.com',
    'pushengage.com',
    'mgid.com',
    'revcontent.com',
    'zedo.com',
    'smartadserver.com',
    'teads.tv',
    'adsystem',
  ];

  static const pathHints = <String>[
    '/ads/',
    '/ad/',
    '/advert',
    '/banner',
    '/popunder',
    '/popup',
    '/pagead',
    '/adsense',
    '/prebid',
    '/gpt.js',
    '/adsbygoogle',
    '/adframe',
    '/adserver',
    '/ad.js',
    '/ads.js',
    '/pixel.',
    '/beacon',
    '/collect?',
    '/gtm.js',
    '/ga.js',
    '/tag.js',
    'doubleclick',
    'googlesyndication',
  ];

  static final _junkLanding = RegExp(
    r'(popunder|popads|clickadu|exoclick|juicyads|hilltopads|adsterra|'
    r'go\.php\?|redirect\.php|out\.php|jump\.php|clk\.|click\?|'
    r'utm_source=ads|zoneid=|ad_id=|bannerid=|'
    r'casino|bet365|1xbet|gambling|macau|vegas|博彩|赌博|澳门|威尼斯人|太阳城|'
    r'棋牌|彩票|sporttery|im体育|bbin|ag真人|开元|皇冠)',
    caseSensitive: false,
  );

  /// Online EasyList cache (set from main via FilterEngineBridge).
  static bool Function(String?)? onlineBlocker;

  static bool isAdUrl(String? raw) {
    if (raw == null || raw.isEmpty) return false;
    try {
      if (onlineBlocker?.call(raw) == true) return true;
    } catch (_) {}
    final lower = raw.toLowerCase();
    if (lower.startsWith('about:') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('javascript:')) {
      return false;
    }
    Uri? u;
    try {
      u = Uri.parse(raw);
    } catch (_) {
      return _junkLanding.hasMatch(lower);
    }
    final host = u.host.toLowerCase();
    final pathQ = '${u.path}?${u.query}'.toLowerCase();
    final full = lower;
    if (host.isEmpty) return false;

    for (final h in hostHints) {
      if (host.contains(h)) return true;
    }
    for (final p in pathHints) {
      if (pathQ.contains(p) || full.contains(p)) return true;
    }
    if (_junkLanding.hasMatch(full)) return true;
    if (RegExp(r'^(ads?|adserv|adserver|adn|adx)\.').hasMatch(host)) {
      return true;
    }
    return false;
  }

  static String rootish(String host) {
    var h = host.toLowerCase();
    for (final p in ['www.', 'm.', 'mobile.', 'wap.', 'www1.', 'www2.']) {
      if (h.startsWith(p)) {
        h = h.substring(p.length);
        break;
      }
    }
    final parts = h.split('.').where((e) => e.isNotEmpty).toList();
    if (parts.length <= 2) return h;
    final last2 = parts.sublist(parts.length - 2).join('.');
    if (parts.length >= 3 &&
        (parts[parts.length - 2] == 'co' ||
            parts[parts.length - 2] == 'com' ||
            parts[parts.length - 2] == 'net' ||
            parts[parts.length - 2] == 'org' ||
            parts[parts.length - 2] == 'ac' ||
            parts[parts.length - 2] == 'gov')) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return last2;
  }

  static bool isSameSite(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return true;
    try {
      final ha = Uri.parse(a).host;
      final hb = Uri.parse(b).host;
      if (ha.isEmpty || hb.isEmpty) return true;
      return rootish(ha) == rootish(hb);
    } catch (_) {
      return true;
    }
  }
}
