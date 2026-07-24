# 隐私浏览器（简洁 1.0）

回到最初简洁版：无痕 WebView、最多 8 标签、重置核清。

## 下载

https://github.com/wfygefjgd/yinsi-liulanqi/releases

- **显示名**: 隐私浏览器  
- **Bundle ID**: `com.tongyong.browser`（独立包，不覆盖旧测试包）  
- **版本**: 1.0.4 (Build 29)  
- **IPA**: `Tongyong-Browser-iOS.ipa`

## 功能

- **Safari 风格界面**：底部地址栏胶囊 + 工具栏  
- 地址栏访问 / DuckDuckGo 搜索  
- 多标签（最多 8），标签面板  
- **真实 `window.open` 弹窗**（返回带 closed/close 的窗口对象，便于站点 15 秒跳转检测）  
- 普通链接：当前页正常跳转（像 Safari）  
- **内置书签** Jiurelay  
- 清除浏览数据 / 进后台核清  
- 简洁无痕版

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```
