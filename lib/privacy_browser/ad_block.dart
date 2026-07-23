/// Real ad / tracker host + path rules (EasyList-style subset, offline).
class AdBlock {
  AdBlock._();

  /// Host contains any of these → block resource / optional nav.
  static const hostHints = <String>[
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'googletagmanager.com',
    'googletagservices.com',
    'google-analytics.com',
    'securepubads.g.doubleclick.net',
    'pagead2.googlesyndication.com',
    'fundingchoicesmessages.google.com',
    'facebook.net',
    'facebook.com/tr',
    'connect.facebook.net',
    'adservice.google',
    'pagead2.googlesyndication',
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
    'analytics.twitter.com',
    'static.ads-twitter.com',
    'gdt.qq.com',
    'l.qq.com',
    'mi.gdt.qq.com',
    'wxsnsdy.tc.qq.com',
    'pangolin-sdk-toutiao.com',
    'pglstatp-toutiao.com',
    'bytead.com',
    'snssdk.com',
    'baidu.com/cpro',
    'pos.baidu.com',
    'cpro.baidu.com',
    'hm.baidu.com',
    'tanx.com',
    'alicdn.com/js/mm',
    'cnzz.com',
    'umeng.com',
    'umengcloud.com',
    'growingio.com',
    'jiguang.cn',
    'getui.com',
    'xg.qq.com',
    'beacon.qq.com',
    'pingjs.qq.com',
    'lianmeng.360.cn',
    'mediav.com',
    'ironsrc.com',
    'unityads.unity3d.com',
    'applovin.com',
    'mopub.com',
    'inmobi.com',
    'vungle.com',
    'chartboost.com',
    'supersonicads.com',
    'ads.yahoo.com',
    'adtechus.com',
    'advertising.yahoo.com',
    'zedo.com',
    'smartadserver.com',
    'lijit.com',
    'sovrn.com',
    'contextweb.com',
    '33across.com',
    'teads.tv',
    'mgid.com',
    'revcontent.com',
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
    'adnxs',
    'adsystem',
    'pagead',
    'adservice',
    'partner.googleadservices',
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
    '/track.',
    '/tracking',
    '/pixel.',
    '/beacon',
    '/collect?',
    '/analytics',
    '/gtm.js',
    '/ga.js',
    '/tag.js',
  ];

  static bool isAdUrl(String? raw) {
    if (raw == null || raw.isEmpty) return false;
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
      return false;
    }
    final host = u.host.toLowerCase();
    final path = '${u.path}?${u.query}'.toLowerCase();
    for (final h in hostHints) {
      if (host.contains(h) || lower.contains(h)) return true;
    }
    for (final p in pathHints) {
      if (path.contains(p)) return true;
    }
    return false;
  }

  /// Same registrable-ish host family (e.g. a.com / www.a.com / m.a.com).
  static String rootish(String host) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final parts = h.split('.').where((e) => e.isNotEmpty).toList();
    if (parts.length <= 2) return h;
    // co.uk / com.cn style
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
