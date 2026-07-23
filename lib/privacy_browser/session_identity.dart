import 'dart:math';

/// In-memory only. Regenerated every process start.
class SessionIdentity {
  SessionIdentity._({
    required this.mobileUserAgent,
    required this.language,
    required this.sessionId,
  });

  final String mobileUserAgent;
  final String language;
  final String sessionId;

  static const desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';

  static SessionIdentity? _current;
  static SessionIdentity get current => _current ??= mint();

  String userAgent({required bool desktop}) =>
      desktop ? desktopUserAgent : mobileUserAgent;

  static SessionIdentity mint() {
    final rng = Random.secure();
    final iosMajor = 16 + rng.nextInt(3);
    final iosMinor = rng.nextInt(5);
    final safariMajor = iosMajor;
    final ua =
        'Mozilla/5.0 (iPhone; CPU iPhone OS ${iosMajor}_$iosMinor like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariMajor.0 '
        'Mobile/15E148 Safari/604.1';
    const langs = ['zh-CN', 'zh-TW', 'en-US', 'en-GB', 'ja-JP'];
    final id =
        List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
    final s = SessionIdentity._(
      mobileUserAgent: ua,
      language: langs[rng.nextInt(langs.length)],
      sessionId: id,
    );
    _current = s;
    return s;
  }

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
})();
''';
}
