# 隐私浏览器（yinsi-liulanqi）

极限无痕 iOS 浏览器：每次打开新身份，最多 3 标签。Safari 风格界面。

## 下载 IPA（自签名侧载）

打开 **Releases**：

https://github.com/wfygefjgd/yinsi-liulanqi/releases

下载 `Tongyong-Browser-iOS.ipa`，用全能签 / Sideloadly / AltStore 等自签名安装。

- Bundle ID: `com.tongyong.browser`（独立包名，不会覆盖旧测试包 / PHUB Player）
- 显示名: 隐私浏览器
- 版本: **1.5.1** (Build 16)
- 包体: 未签名（适合侧载）

## 功能

- **每次冷启动 = 新身份**（核清网页数据 + 随机 UA；**书签保留**）
- 进后台 / 换新身份：优雅淡出后清痕迹（书签不删）
- 手动书签：添加 / 删除 / 管理
- **阅读模式**：抽正文、挡弹窗；**拼接开关**可关
- 普通页轻量挡 `window.open` / 遮罩弹窗
- Safari 风格底栏；最多 3 标签
- **不做**下载 / 历史记录

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```

## 包体说明

iOS IPA 体积主要来自 **Flutter 引擎 + WebView 插件**，不是业务代码。
