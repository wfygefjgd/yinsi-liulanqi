# 隐私浏览器（简洁 1.0）

回到最初简洁版：无痕 WebView、最多 8 标签、重置核清。

## 下载

https://github.com/wfygefjgd/yinsi-liulanqi/releases

- **显示名**: 隐私浏览器  
- **Bundle ID**: `com.tongyong.browser`（独立包，不覆盖旧测试包）  
- **版本**: 1.0.7 (Build 32)  
- **IPA**: `Tongyong-Browser-iOS.ipa`

## 功能

- **Safari 风格界面**：底部地址栏胶囊 + 工具栏  
- 地址栏访问 / DuckDuckGo 搜索  
- 多标签（最多 8），标签面板  
- **window.open 方案二**：`about:blank` 真弹窗 + `location.replace`/`href` 驱动同一弹窗（适配 Jiurelay 教程验证）  
- 普通链接：当前页正常跳转  
- **内置书签** Jiurelay  
- 清除浏览数据 / 进后台核清

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```
