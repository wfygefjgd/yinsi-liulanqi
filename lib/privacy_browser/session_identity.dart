import 'dart:math';

/// In-memory only. Regenerated every process start = "first open" identity.
class SessionIdentity {
  SessionIdentity._({
    required this.userAgent,
    required this.language,
    required this.sessionId,
  });

  final String userAgent;
  final String language;
  final String sessionId;

  static SessionIdentity? _current;
  static SessionIdentity get current => _current ??= mint();

  static SessionIdentity mint() {
    final rng = Random.secure();
    final iosMajor = 16 + rng.nextInt(3); // 16–18
    final iosMinor = rng.nextInt(5);
    final safariMajor = iosMajor;
    final ua =
        'Mozilla/5.0 (iPhone; CPU iPhone OS ${iosMajor}_$iosMinor like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariMajor.0 '
        'Mobile/15E148 Safari/604.1';
    const langs = ['zh-CN', 'zh-TW', 'en-US', 'en-GB', 'ja-JP'];
    final id = List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
    final s = SessionIdentity._(
      userAgent: ua,
      language: langs[rng.nextInt(langs.length)],
      sessionId: id,
    );
    _current = s;
    return s;
  }

  /// Anti-fingerprint + block common trackers of "same browser again".
  /// Applied once per document load (incognito first-open style).
  String get injectScript => '''
(function() {
  try {
    Object.defineProperty(navigator, 'webdriver', { get: function() { return undefined; } });
  } catch (e) {}
  try {
    Object.defineProperty(navigator, 'language', { get: function() { return '${language.split('-').first}'; } });
    Object.defineProperty(navigator, 'languages', { get: function() { return ['$language', '${language.split('-').first}']; } });
  } catch (e) {}
  try {
    if (window.RTCPeerConnection) {
      window.RTCPeerConnection = function() { throw new Error('blocked'); };
    }
    if (window.webkitRTCPeerConnection) {
      window.webkitRTCPeerConnection = function() { throw new Error('blocked'); };
    }
  } catch (e) {}
  try {
    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
      navigator.mediaDevices.getUserMedia = function() {
        return Promise.reject(new Error('blocked'));
      };
    }
  } catch (e) {}
  try {
    if (navigator.serviceWorker) {
      navigator.serviceWorker.register = function() {
        return Promise.reject(new Error('blocked'));
      };
    }
  } catch (e) {}
  try {
    var noise = function(canvas) {
      try {
        var ctx = canvas.getContext && canvas.getContext('2d');
        if (!ctx || !ctx.getImageData) return;
        var orig = ctx.getImageData.bind(ctx);
        ctx.getImageData = function(x, y, w, h) {
          var d = orig(x, y, w, h);
          if (d && d.data && d.data.length) {
            d.data[0] = d.data[0] ^ (${sessionId.hashCode.abs() % 7});
          }
          return d;
        };
      } catch (e) {}
    };
    var desc = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'getContext');
    if (desc && desc.value) {
      var origGet = desc.value;
      HTMLCanvasElement.prototype.getContext = function() {
        var c = origGet.apply(this, arguments);
        noise(this);
        return c;
      };
    }
  } catch (e) {}
})();
''';
}
