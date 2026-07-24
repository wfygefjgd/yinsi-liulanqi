# 隐私浏览器（简洁 1.0.11）

classic 纯净行为 + 必要 window.open 弹窗；后台只清数据不杀进程。

## 下载

https://github.com/wfygefjgd/yinsi-liulanqi/releases

- **显示名**: 隐私浏览器
- **Bundle ID**: `com.tongyong.browser`
- **版本**: 1.0.11 (Build 36)
- **IPA**: `Tongyong-Browser-iOS.ipa`

## 功能

- Safari 风格界面：底部地址栏 + 工具栏
- 地址栏访问 / DuckDuckGo 搜索
- 多标签（最多 8）
- window.open 真弹窗（与主 WebView **同等无痕**）
- 内置书签 Jiurelay
- **进后台**：清 Cookie/缓存/站点数据 + 关标签（**不杀进程**，避免环境抖动）
- **手动清除**：彻底 wipe + 冷启动

## 使用说明

### 基本操作

| 操作 | 说明 |
|------|------|
| **地址栏输入** | 输入 URL 访问网站，输入关键词自动 DuckDuckGo 搜索 |
| **刷新 / 停止** | 地址栏右侧按钮，加载时显示 X（停止），加载完毕显示 ↻（刷新） |
| **前进 / 后退** | 底部工具栏左/右箭头 |
| **标签管理** | 点击底部数字按钮打开标签面板，可切换/关闭/新建标签 |
| **书签** | 点击底部书签图标打开内置书签（Jiurelay） |
| **复制链接** | 点击分享图标复制当前页 URL |
| **清除数据** | 点击红色垃圾桶，确认后清除全部数据并冷启动 |

### 隐私行为

- **启动时**：自动清除所有 Cookie、缓存、站点数据
- **切到后台**：清除所有 Web 数据，关闭所有标签，**不杀进程**（避免网站检测"环境变化过于频繁"）
- **手动清除**：杀掉进程，下次启动完全冷启动（新标识）
- 弹窗 WebView 与主页面使用完全相同的无痕设置

### 安装（侧载）

iOS 未签名 IPA 安装方式：

1. 下载 `Tongyong-Browser-iOS.ipa`
2. 使用侧载工具安装（如 AltStore、SideStore、TrollStore 等）
3. 或者使用 `ios-deploy` 命令行安装

### 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```

## 更新日志

### v1.0.11 (Build 36) — 反设备指纹

**核心变更**：注入反指纹脚本，伪装成桌面浏览器。

- **屏幕指纹防护**：伪装分辨率为 1920×1080 桌面尺寸
- **平台伪装**：`navigator.platform` 改为 "MacIntel"
- **触摸点隐藏**：`navigator.maxTouchPoints` 改为 0
- **硬件伪装**：CPU 核心数改为 8，内存改为 8GB
- **Canvas 指纹防护**：返回空白图像，阻止画布指纹
- **WebGL 指纹防护**：伪装为 Intel UHD Graphics 630 桌面显卡
- **弹窗同步**：弹窗 WebView 同样应用反指纹防护

### v1.0.10 (Build 35) — 隐私强化与 Bug 修复

**核心变更**：全面修复隐私泄露问题，增强清理能力。

- **WebView 设置修复**：关闭 `domStorageEnabled`，彻底禁用 localStorage/sessionStorage
- **WebView 设置修复**：关闭 `supportMultipleWindows`，禁止多窗口数据残留
- **User-Agent 随机化**：每次创建 WebView 时随机生成不同的 UA（7 个 iOS 版本 × 3 个 WebKit 构建 × 4 个 Mobile ID）
- **移除 AutomaticKeepAliveClientMixin**：WebView 不再保持存活，避免内存残留
- **弹窗 WebView 同步修复**：与主 WebView 应用相同的隐私设置和随机 UA
- **资源泄漏修复**：关闭标签页、弹窗、Shell 释放时正确 dispose WebView 控制器
- **清理竞态条件修复**：清理进行中新调用会排队等待，而非静默丢弃
- **剪贴板清空增强**：先检查再清空，确保 iOS 上可靠清除
- **HSTS 缓存清理**：新增 HSTS 和 URLSession cookie 存储清理
- **Keychain 清理**：新增 Keychain 全量清理（v1.0 可能未覆盖）
- **原生层清理优化**：移除冗余清理，扩展目录列表

### v1.0.9 (Build 34) — classic 回归

**核心变更**：后台只清数据不杀进程，解决"环境变化过于频繁"问题。

- **隐私引擎**：`wipeOnBackground` 不再调用 `exitApp`，进后台仅清除数据，保留进程存活
- **主 WebView**：恢复 classic 无痕设置 — `clearCache: true`、`sharedCookiesEnabled: false`、`mediaPlaybackRequiresUserGesture: true`
- **window.open polyfill** v6：仅注入一次，去掉重复 re-inject；简化 stub 实现，移除 `makeDocument()` 复杂逻辑
- **弹窗 WebView**：使用与主页完全一致的隐私设置（incognito / 无缓存 / 无第三方 Cookie）
- **弹窗空白页**：改为纯黑背景，替换之前的"请稍候"白页面
- **后台清理流程**：先关闭弹窗，清理 WebView 控制器，再执行数据擦除
- **README 更新**：补充完整使用说明

### v1.0.8 (Build 33)

- `nuclearWipe` 彻底清除：二次擦除 Web 层 + 原生全量删目录
- 进后台杀进程（v1.0.9 已改为不杀）

### v1.0.7

- window.open 弹窗：覆盖层展示，不替换主页面
- `onCreateWindow` 返回 false，避免主导航被替换

### v1.0.6

- 加固 scheme2 弹窗导航竞态 + body setters
- 弹窗 polyfill 稳定

### v1.0.5

- window.open blank + location.replace 同弹窗适配
- Jiurelay 教程验证通过

### v1.0.4

- 真正的 window.open 弹窗，用于跳转检测

### v1.0.1

- Safari 风格界面
- 底部地址栏胶囊

### v1.0.0

- 初始发布：隐私浏览器 iOS 极限无痕版
- Safari-like UI + shield app icon
- 每次启动全新标识
- 内置 Jiurelay 书签