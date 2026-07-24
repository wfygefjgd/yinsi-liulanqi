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
        // Kill process so next launch is cold (no leftover WebKit process state)
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
  /// Keep only Application Documents/durable (built-in bookmark list if any).
  private static let durableFolderName = "durable"

  static func run(completion: @escaping () -> Void) {
    let group = DispatchGroup()

    // 1) Default website data store (cookies, localStorage, indexedDB, service workers…)
    group.enter()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    WKWebsiteDataStore.default().removeData(
      ofTypes: types,
      modifiedSince: Date(timeIntervalSince1970: 0)
    ) {
      group.leave()
    }

    // 2) Non-persistent store if ever used
    group.enter()
    let nonPersist = WKWebsiteDataStore.nonPersistent()
    nonPersist.removeData(
      ofTypes: types,
      modifiedSince: Date(timeIntervalSince1970: 0)
    ) {
      group.leave()
    }

    // 3) Process pool cannot be fully reset, but clear shared cookie/cache layers
    HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    URLCache.shared.removeAllCachedResponses()
    URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
    URLSession.shared.reset {}

    wipeSandboxFiles()
    wipeUserDefaults()
    wipeKeychain()
    // Second filesystem pass after short delay (WebKit async writers)
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) {
      wipeSandboxFiles()
    }

    group.notify(queue: .main) {
      // Extra default store pass
      WKWebsiteDataStore.default().removeData(
        ofTypes: types,
        modifiedSince: Date(timeIntervalSince1970: 0)
      ) {
        completion()
      }
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
      home.appendingPathComponent("tmp"),
      URL(fileURLWithPath: NSTemporaryDirectory()),
      home.appendingPathComponent("Documents"),
    ]
    for url in targets {
      wipeDirectoryContents(url, fileManager: fm, preserveName: durableFolderName)
    }
    // Known cookie file
    let cookieFile = home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
    try? fm.removeItem(at: cookieFile)
  }

  private static func wipeDirectoryContents(
    _ url: URL,
    fileManager fm: FileManager,
    preserveName: String?
  ) {
    guard fm.fileExists(atPath: url.path) else { return }
    guard let items = try? fm.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: nil,
      options: []
    ) else {
      return
    }
    for item in items {
      if let preserveName, item.lastPathComponent == preserveName {
        continue
      }
      // Preserve nested durable under Documents or app_flutter
      if let preserveName, item.hasDirectoryPath {
        let nested = item.appendingPathComponent(preserveName)
        if fm.fileExists(atPath: nested.path) {
          // wipe siblings only
          if let kids = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
            for kid in kids where kid.lastPathComponent != preserveName {
              try? fm.removeItem(at: kid)
            }
          }
          continue
        }
      }
      try? fm.removeItem(at: item)
    }
  }

  private static func wipeUserDefaults() {
    if let bundleId = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: bundleId)
      // Suite if any
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
}
