# Liquid Glass 主题 Bar 导航胶囊 indicator · 修复笔记

## 改动文件
- `CoinFlow/Features/Main/MainTabView.swift`

## 改动 1：indicator 位置恢复 overlay

`indicatorView` 从 `.background()` 移回 `.overlay()`，恢复到 master 分支的修饰符顺序：

```
// Before:
.appTabPillBackground()
.background(indicatorView.allowsHitTesting(false))  // indicator 在玻璃之下
.contentShape(Capsule())
.coordinateSpace(name: "tabbar")
.fixedSize()

// After:
.appTabPillBackground()
.contentShape(Capsule())
.coordinateSpace(name: "tabbar")
.fixedSize()
.overlay(indicatorView.allowsHitTesting(false))      // indicator 在玻璃之上
```

原因：
- Liquid Glass 的 `.glassEffect()` 是前景玻璃层，indicator 必须在 overlay 中才能不被玻璃遮盖
- `.overlay()` 在 `.fixedSize()` 之后，indicator 的 `.position()` 溢出不受 frame 限制

## 改动 2：移除 Liquid Glass indicator 的 material 背景

移除了 `indicatorShape(highlighted:)` 中 `.isEnabled` 分支的 `.background(.ultraThinMaterial, in: Capsule())`：

```
// Before:
Capsule()
    .fill(...)
    .background(.ultraThinMaterial, in: Capsule())  // ← 在 overlay 中会模糊遮挡下层 tab 内容
    .overlay(Capsule().strokeBorder(...))

// After:
Capsule()
    .fill(...)
    .overlay(Capsule().strokeBorder(...))
```

原因：indicator 现在在 `.overlay()` 中处于 tab 内容之上，`.ultraThinMaterial` 会产生毛玻璃模糊效果，导致下方 icon 和文字不可见。移除后仅保留半透明 fill + stroke，既能区分选中态又不遮挡内容。

## 关键点
1. Notion / Animal Island 主题不受影响（它们的 indicator 无 material 背景）
2. 两项改动需同时生效：仅改 overlay 会让 material 遮挡内容；仅去 material 不改 overlay 则 indicator 会被 glassEffect 遮盖
