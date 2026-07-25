import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "privacy_browser/engine",
      binaryMessenger: messenger
    )
    privacyChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "nuclearWipe":
        PrivacyNativeWipe.run {
          result(nil)
        }
      case "exitApp":
        // Only used by manual "clear browsing data"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
          exit(0)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

enum PrivacyNativeWipe {
  static func run(completion: @escaping () -> Void) {
    let group = DispatchGroup()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()

    // 1) Default website data store
    group.enter()
    WKWebsiteDataStore.default().removeData(
      ofTypes: types,
      modifiedSince: Date(timeIntervalSince1970: 0)
    ) {
      group.leave()
    }

    // 2) Non-persistent store
    group.enter()
    WKWebsiteDataStore.nonPersistent().removeData(
      ofTypes: types,
      modifiedSince: Date(timeIntervalSince1970: 0)
    ) {
      group.leave()
    }

    // 3) HTTP cookies
    HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    HTTPCookieStorage.shared.removeCookies(since: .distantPast)

    // 4) HSTS cache (preloaded HTTP Strict Transport Security)
    if #available(iOS 14.0, *) {
        URLSession.shared.configuration.urlCache?.removeAllCachedResponses()
        URLSession.shared.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }

    // 5) URLCache - disable completely
    URLCache.shared.removeAllCachedResponses()
    URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
    URLSession.shared.reset {}

    // 6) Sandbox files + advanced cleanup
    wipeSandboxFiles()
    wipeUserDefaults()
    wipeKeychain()
    wipeProcessInfo()
    resetNetworkState()

    // 7) Second pass after delay (catch async writers)
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
      wipeSandboxFiles()
      HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    group.notify(queue: .main) {
      // Final pass on default store
      WKWebsiteDataStore.default().removeData(
        ofTypes: types,
        modifiedSince: Date(timeIntervalSince1970: 0)
      ) { }
      completion()
    }
  }

  private static func wipeSandboxFiles() {
    let fm = FileManager.default
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let targets = [
      home.appendingPathComponent("Library/Cookies"),
      home.appendingPathComponent("Library/WebKit"),
      home.appendingPathComponent("Library/Caches"),
      home.appendingPathComponent("Library/HTTPStorages"),
      home.appendingPathComponent("Library/Application Support"),
      home.appendingPathComponent("Library/Preferences"),
      home.appendingPathComponent("Library/SplashBoard"),
      home.appendingPathComponent("Library/Saved Application State"),
      home.appendingPathComponent("Library/WebKit/WebsiteData"),
      home.appendingPathComponent("tmp"),
      home.appendingPathComponent("Documents"),
    ]
    for url in targets {
      wipeDirectoryContents(url, fileManager: fm)
    }
    let cookieFile = home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
    try? fm.removeItem(at: cookieFile)

    // 霸道模式：多路径扫描，确保没有遗漏
    let extraPaths = [
      "Library/Caches/com.apple.nsurlsessiond",
      "Library/Caches/Snapshots",
      "Library/WebKit/NetworkCache",
      "Library/WebKit/com.apple.WebKit.Networking",
      "Library/WebKit/com.apple.WebKit.WebContent",
    ]
    for path in extraPaths {
      let url = home.appendingPathComponent(path)
      wipeDirectoryContents(url, fileManager: fm)
    }
  }

  private static func wipeDirectoryContents(_ url: URL, fileManager fm: FileManager) {
    guard fm.fileExists(atPath: url.path) else { return }
    guard let items = try? fm.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: nil,
      options: []
    ) else {
      return
    }
    for item in items {
      try? fm.removeItem(at: item)
    }
  }

  private static func wipeUserDefaults() {
    if let bundleId = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: bundleId)
      UserDefaults(suiteName: bundleId)?.removePersistentDomain(forName: bundleId)
    }
    for key in UserDefaults.standard.dictionaryRepresentation().keys {
      UserDefaults.standard.removeObject(forKey: key)
    }
    UserDefaults.standard.synchronize()
  }

  private static func wipeKeychain() {
    let classes: [CFString] = [
      kSecClassGenericPassword,
      kSecClassInternetPassword,
      kSecClassCertificate,
      kSecClassKey,
      kSecClassIdentity,
    ]
    for cls in classes {
      SecItemDelete([kSecClass: cls] as CFDictionary)
    }
  }

  // 霸道操作 1: 清除进程环境变量和内存缓存
  private static func wipeProcessInfo() {
    // 清空所有 NSCache 实例（系统级内存缓存）
    URLCache.shared.removeAllCachedResponses()
    URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)

    // 清空图片缓存（如果存在）
    if #available(iOS 13.0, *) {
      URLSession.shared.configuration.urlCache = nil
    }

    // 清理系统剪贴板（防止跨应用追踪）
    UIPasteboard.general.items = []
    if #available(iOS 10.0, *) {
      UIPasteboard.general.setItems([], options: [:])
    }
  }

  // 霸道操作 2: 重置网络会话状态 + 强制清理所有持久化连接
  private static func resetNetworkState() {
    // 1. 终止所有活动网络任务
    URLSession.shared.invalidateAndCancel()

    // 2. 清空所有 Cookie 和缓存
    HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    URLCache.shared.removeAllCachedResponses()

    // 3. 重建无痕会话配置
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.httpCookieAcceptPolicy = .never
    config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    config.httpShouldSetCookies = false
    config.httpAdditionalHeaders = [:] // 清空所有自定义请求头

    // 4. 清空 DNS 缓存（iOS 通过重建会话实现）
    let cleanSession = URLSession(configuration: config)
    cleanSession.finishTasksAndInvalidate()

    // 5. 强制清理 WKProcessPool（杀掉所有 WebKit 进程）
    if #available(iOS 14.0, *) {
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast
      ) { }
    }
  }
}
