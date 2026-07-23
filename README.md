# 隐私浏览器（yinsi-liulanqi）

极限无痕 iOS 浏览器：每次打开新身份，最多 3 标签。Safari 风格界面。

## 下载 IPA（自签名侧载）

打开 **Releases**：

https://github.com/wfygefjgd/yinsi-liulanqi/releases

下载 `Tongyong-Browser-iOS.ipa`，用全能签 / Sideloadly / AltStore 等自签名安装。

- Bundle ID: `com.tongyong.browser`（独立包名，不会覆盖旧测试包 / PHUB Player）
- 显示名: 隐私浏览器
- 版本: **1.6.2** (Build 20)
- 包体: 未签名（适合侧载）

## 功能

- **默认普通浏览**：切后台不清数据
- **换新身份**（右下角，仅手动）：核清网页数据，**书签保留**
- ★ 一键收藏（最多 50）；标签最多 15
- **阅读模式**（左下角）：章内分页再下一章；竹纸底黑字
- **去广告点选**（书签旁）：点击页面元素隐藏
- 广告/弹窗/跨站拦截（≡ 菜单开关）
- **不做**下载

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```

## 包体说明

iOS IPA 体积主要来自 **Flutter 引擎 + WebView 插件**，不是业务代码。
