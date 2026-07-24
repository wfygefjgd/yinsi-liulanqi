## 反设备指纹保护

### 新增防护

- **屏幕指纹防护**：伪装分辨率为 1920×1080 桌面尺寸
- **平台伪装**：`navigator.platform` 改为 "MacIntel"
- **触摸点隐藏**：`navigator.maxTouchPoints` 改为 0
- **硬件伪装**：CPU 核心数改为 8，内存改为 8GB
- **Canvas 指纹防护**：返回空白图像，阻止画布指纹
- **WebGL 指纹防护**：伪装为 Intel UHD Graphics 630 桌面显卡
- **弹窗同步**：弹窗 WebView 同样应用反指纹防护

### 防护效果

| 指纹项 | 之前 | 现在 |
|--------|------|------|
| 屏幕尺寸 | 390×844 (手机) | 1920×1080 (桌面) |
| 平台 | iPhone | MacIntel |
| 触摸点 | 5 | 0 |
| CPU 核心 | 实际核心数 | 8 |
| 内存 | 实际内存 | 8GB |
| Canvas 指纹 | 唯一标识 | 空白图像 |
| WebGL 指纹 | Apple GPU | Intel UHD 630 |

### 测试建议

1. 访问 https://jiurelay.com/r/JR-UQYJQT
2. 手动清除数据后冷启动
3. 检查网站是否仍识别为"手机"

---

**构建命令**:

```bash
flutter pub get
flutter build ios --release --no-codesign
```
