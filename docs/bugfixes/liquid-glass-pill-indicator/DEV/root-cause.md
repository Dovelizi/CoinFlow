# Liquid Glass 主题 Bar 导航胶囊 indicator 不可见 · 根因分析

## 问题现象
Liquid Glass 主题下，底部 TabBar 胶囊的选中高亮 indicator 不可见（或极弱），拖拽交互的"放大镜悬浮气泡"效果也消失。

## 复现步骤
1. 切换到 Liquid Glass 主题
2. 观察底部 TabBar 的选中态胶囊高亮
3. 按住胶囊拖动 —— indicator 不会浮起放大

## 根因定位

在 animal-island-theme 分支上，commit `e5c3f37` 将 `indicatorView` 从 `.overlay()` 移到了 `.background()`:

```
// master（正常）:
.appTabPillBackground()
.contentShape(Capsule())
.coordinateSpace(name: "tabbar")
.fixedSize()
.overlay(indicatorView.allowsHitTesting(false))  ← indicator 在 fixedSize 之后、玻璃层之上

// animal-island-theme（问题）:
.appTabPillBackground()
.background(indicatorView.allowsHitTesting(false))  ← indicator 在 fixedSize 之前、玻璃层之下
.contentShape(Capsule())
.coordinateSpace(name: "tabbar")
.fixedSize()
```

两个问题叠加导致 Liquid Glass 下 indicator 完全不可见：

1. **渲染层级错误**：Liquid Glass 的 `.appTabPillBackground()` 使用 `.glassEffect(.regular.interactive(), in: .capsule)`，这是一个前景玻璃层。indicator 在 `.background()` 中处于玻璃层**后面**，被玻璃模糊遮盖。master 分支 indicator 在 `.overlay()` 中，位于玻璃层**上面**，清晰可见。

2. **fixedSize 裁切**：indicator 使用 `.position()` 做绝对定位，依赖 `.overlay()` 的默认不裁切特性溢出胶囊边界（拖拽放大时凸出上下边缘）。`.background()` 在 `.fixedSize()` 之前应用，indicator 的溢出部分被锁死的 frame 裁切。

Notion 和 Animal Island 主题不受影响是因为它们的 pill 背景使用 `.background()` 实现（Capsule + fill），第二个 `.background()` 只是叠在更底层，indicator 虽然也在背后但仍能穿透 pill 的半透明填充可见。

## 影响范围
仅 Liquid Glass 主题的 TabBar indicator 渲染，不影响其他主题和功能。
