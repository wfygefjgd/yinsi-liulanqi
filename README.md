# 隐私浏览器（简洁 1.0）

回到最初简洁版：无痕 WebView、最多 8 标签、重置核清。

## 下载

https://github.com/wfygefjgd/yinsi-liulanqi/releases

- **显示名**: 隐私浏览器  
- **Bundle ID**: `com.tongyong.browser`（独立包，不覆盖旧测试包）  
- **版本**: 1.0.0 (Build 25)  
- **IPA**: `Tongyong-Browser-iOS.ipa`

## 功能

- 地址栏访问 / DuckDuckGo 搜索  
- 多标签（最多 8）  
- **点击页面链接 → 在后台新标签打开**（当前页不跳走）  
- 重置 / 进后台：核清网站数据  
- 无广告脚本、无阅读器、无 EasyList（纯简版）

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```
