CoinFlow Liquid Glass 真玻璃主题 · 实现文档
=========================================

本文档描述 CoinFlow App 的第三主题 **Liquid Glass**（iOS 26 真·液态玻璃）的设计 token、组件清单、使用示例与已知约束。本主题与既有的 Dark Notion / Dark Liquid 并列存在，用户可在「设置 → 主题与颜色」中自由切换。

---

## 1. 设计原则

1. 严格遵循 Apple iOS 26 Liquid Glass 设计语言，使用 SwiftUI 原生 API：
   - `.glassEffect(.regular, in: …)`
   - `.glassEffect(.regular.tint(_:).interactive(), in: …)`
   - `Button(...).buttonStyle(.glass)` / `.glassProminent`
2. **跟随系统**亮暗模式（不强制深色），与 macOS / iPadOS 玻璃一致。
3. 与既有主题**完全解耦**：不替换 LGATheme 任何字段，桥接器内做 switch 分发。
4. 切换零代码改动：所有现有调用方使用 `cardSurface(...)` / `appTabPillBackground()` / `glassChipIfLGA(...)` / `themedBackground(...)` 即可获得三主题切换能力。

---

## 2. 设计 Token

文件 `CoinFlow/Theme/LiquidGlassRealTheme.swift`

| Token | 值 | 用途 |
|-------|----|----|
| `LiquidGlassTheme.radiusSM` | 10 | 小元素圆角（chip） |
| `LiquidGlassTheme.radiusMD` | 12 | 列表行圆角 |
| `LiquidGlassTheme.radiusLG` | 14 | 卡片圆角 |
| `LiquidGlassTheme.radiusXL` | 18 | 大卡片 / 浮岛 |
| `LiquidGlassTheme.space2..7` | 4..24 | 标准间距阶梯（与 LGATheme 对齐） |
| `LiquidGlassTheme.containerSpacing` | 20 | `GlassEffectContainer` 元素合并阈值 |
| `LiquidGlassTheme.accent` | `.accentColor` | 强调色（系统蓝） |

文字色（自适应明暗）：

| Token | 浅色模式 | 深色模式 |
|-------|--------|--------|
| `Color.liquidGlassTextPrimary` | #1C1C1F | #FFFFFF |
| `Color.liquidGlassTextSecondary` | #636366 | #8E8E93 |
| `Color.liquidGlassTextTertiary` | #8E8E93 | #6B6B6F |

---

## 3. 主题枚举与持久化

文件 `CoinFlow/Theme/LiquidGlassATheme.swift`

```swift
enum AppTheme: String, CaseIterable {
    case notion        // 现有 Notion 浅色实色
    case darkLiquid    // v4 深炭灰实色（旧 "Dark Liquid"）
    case liquidGlass   // 新增·真玻璃，跟随系统
}
```

**持久化键**：`UserDefaults.standard["theme.app.kind"]`（String）

**迁移策略**：旧版本若启用过 `theme.lga.enabled = true`，初始化时自动迁移为 `.darkLiquid`，无感升级。

**API**：

```swift
LGAThemeStore.shared.kind                  // 当前主题
LGAThemeStore.shared.setKind(.liquidGlass) // 切换主题（带动画）
LGAThemeStore.shared.isEnabled             // 旧 API 兼容：等价 kind == .darkLiquid
LGAThemeRuntime.kind                       // 静态查询（非响应式）
LGAThemeRuntime.isLiquidGlass              // 静态判断
```

---

## 4. 组件清单

| 修饰器 | 调用方式 | Liquid Glass 行为 |
|--------|--------|-----|
| `.cardSurface(cornerRadius:)` | 既有调用 | `glassEffect(.regular, in: .rect(...))` |
| `.appTabPillBackground()` | 既有调用 | `glassEffect(.regular.interactive(), in: .capsule)` |
| `.glassChipIfLGA(radius:tint:)` | 既有调用 | `glassEffect(.regular.tint(_:).interactive(), in: .rect)` |
| `.themedBackground(kind:)` | 既有调用 | `LiquidGlassBackground(kind:)`（渐变 + 环境光） |
| `Color.appCanvas` | 既有引用 | `Color.clear`（让背景层透出） |
| `Color.appSheetCanvas` | 既有引用 | 浅灰渐变（玻璃需要色彩内容才能折射） |

**全屏背景** `LiquidGlassBackground`：

- 浅色：`#F2F2F7 → #E5E5EA` 上下渐变
- 深色：`#1C1C1E → #2C2C2E` 上下渐变
- 顶部 Radial Gradient（accent 12% 透明度，PlusLighter 混合）模拟"屏内光源"，让玻璃元素背后有色彩可折射

---

## 5. 用户切换入口

文件 `CoinFlow/Features/Settings/AppearanceSettingsView.swift`

**「设置 → 主题与颜色」** 现有 3 张主题卡片（VStack 单列布局）：

| 卡片 | 标题 | 副标题 | 图标 | 切换动作 |
|---|---|---|---|---|
| 1 | Dark Notion | 实色扁平·遵循 Notion 设计语言 | `square.grid.2x2` | `setKind(.notion)` |
| 2 | Dark Liquid | 深炭灰实色·低干扰阅读 | `moon.fill` | `setKind(.darkLiquid)` |
| 3 | Liquid Glass | iOS 26 真·液态玻璃·跟随系统亮暗 | `sparkles` | `setKind(.liquidGlass)` |

设置首页的"主题与颜色"行右侧也会显示当前主题名 + 金额配色名（如 `Liquid Glass · 系统`）。

---

## 6. 已知约束 · Xcode 版本兼容

> ⚠️ **重要**：Liquid Glass API 仅存在于 **Xcode 26 (iOS 26 SDK)**。

代码使用 `#if compiler(>=6.2)` 隔离：

```swift
#if compiler(>=6.2)
if #available(iOS 26.0, *) {
    content.glassEffect(.regular, in: .rect(cornerRadius: 14))
} else {
    content.background(... .ultraThinMaterial)
}
#else
// Xcode 16 (Swift 6.0) 下 fallback
content.background(... .ultraThinMaterial)
#endif
```

| 编译器 | 第三主题视觉 |
|---|---|
| Xcode 26 (Swift 6.2+) | ✅ 真玻璃（折射、反光、互动、流变） |
| Xcode 16.x (Swift 6.0) | ⚠️ ultraThinMaterial 近似（保留切换入口和架构） |

**升级 Xcode 26 后无需任何代码改动**，重新编译即自动激活真玻璃。

---

## 7. 文件清单

| 路径 | 说明 |
|---|---|
| `CoinFlow/Theme/LiquidGlassRealTheme.swift` | 新增·真玻璃 token + 修饰器 + 背景 |
| `CoinFlow/Theme/LiquidGlassATheme.swift` | 修改·三态枚举 + 桥接修饰器接入第三分支 |
| `CoinFlow/Features/Settings/AppearanceSettingsView.swift` | 修改·主题段升级为 3 卡 VStack |
| `CoinFlow/Features/Settings/SettingsView.swift` | 修改·`appearanceSummaryText` 三态取名 |
| `CoinFlow.xcodeproj/project.pbxproj` | 修改·新增 LiquidGlassRealTheme 4 处引用 |

---

## 8. 验证

```bash
# 当前 Xcode 16.4 下应当 BUILD SUCCEEDED
xcodebuild -project CoinFlow.xcodeproj -scheme CoinFlow \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

预期：

- ✅ Xcode 16.4：BUILD SUCCEEDED，第三主题切换可见，视觉为 ultraThinMaterial 半透
- ✅ Xcode 26 + iOS 26 设备：BUILD SUCCEEDED，第三主题进入真玻璃模式（折射、反光、互动）
