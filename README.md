# 隐私浏览器（yinsi-liulanqi）

极限无痕 iOS 浏览器：启动/后台/一键重置核清全部数据，最多 3 标签。

## 下载 IPA（自签名侧载）

打开 **Releases**：

https://github.com/wfygefjgd/yinsi-liulanqi/releases

下载 `Privacy-Browser-iOS.ipa`，用全能签 / Sideloadly / AltStore 等自签名安装。

- Bundle ID: `com.phub.player.phubPlayer`
- 显示名: 隐私浏览器
- 包体: 未签名（适合侧载）

## 功能

- 地址栏访问网页（默认 DuckDuckGo 搜索）
- 最多 3 个标签
- **重置**：清 Cookie / 缓存 / 沙盒 / Keychain，并冷启动
- 进后台自动核清

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```
