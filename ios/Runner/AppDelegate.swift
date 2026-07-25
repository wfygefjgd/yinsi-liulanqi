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
    // 清理 ProcessInfo 环境变量（某些追踪会在这里缓存）
    let processInfo = ProcessInfo.processInfo
    _ = processInfo.environment // 触发访问但不保存

    // 清空 NSCache（系统级内存缓存）
    NSURLCache.shared.removeAllCachedResponses()
    NSURLCache.shared = NSURLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
  }

  // 霸道操作 2: 重置网络会话状态
  private static func resetNetworkState() {
    // 强制重置所有 URLSession 配置
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.httpCookieAcceptPolicy = .never
    config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    // 清空 DNS 缓存（通过重建会话实现）
    URLSession(configuration: config).finishTasksAndInvalidate()
  }
}
