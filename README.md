# 隐私浏览器（yinsi-liulanqi）

极限无痕 iOS 浏览器：启动/后台/一键重置核清全部数据，最多 3 标签。

## 下载 IPA（自签名侧载）

打开 **Releases**：

https://github.com/wfygefjgd/yinsi-liulanqi/releases

下载 `Yinsi-Liulanqi-iOS.ipa`，用全能签 / Sideloadly / AltStore 等自签名安装。

- Bundle ID: `com.yinsi.liulanqi`（与 PHUB Player 不同，可共存）
- 显示名: 隐私浏览器
- 版本: 1.1.0 (3)
- 包体: 未签名（适合侧载）

## 功能

- **每次冷启动 = 新身份**（核清 + 随机 UA/语言 + 无痕 WebView）
- 进后台 / 点「换新身份」= 杀进程冷启动
- 地址栏访问网页（默认 DuckDuckGo 搜索）
- 书签：Jiurelay
- 最多 3 个标签

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```

## 包体说明

iOS IPA 体积主要来自 **Flutter 引擎 + WebView 插件**，不是业务代码。
已去掉未使用的播放器依赖（`video_player` 等）和遗留 Dart 源码，以减小体积。
