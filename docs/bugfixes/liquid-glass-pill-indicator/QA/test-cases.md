# Liquid Glass 主题 Bar 导航胶囊 indicator · 测试用例

## 测试环境
- 设备：iPhone（iOS 26.x）
- 模式：深色 / 浅色
- 主题：Liquid Glass（真玻璃）

| # | 场景 | 前置条件 | 操作步骤 | 预期结果 | 实际结果 | 状态 |
|---|------|---------|---------|---------|---------|------|
| 1 | Liquid Glass 选中态 indicator 可见 | 切换到 Liquid Glass 主题 | 查看底部 TabBar，观察选中 tab（首页） | 选中 tab 有白色半透明胶囊高亮 indicator，清晰可见 | | ⬜ |
| 2 | 点击切 tab 后 indicator 跟随 | Liquid Glass 主题 | 点击"账单"tab | indicator 平滑移动到账单 tab，高亮可见 | | ⬜ |
| 3 | 拖拽 capsule indicator 跟手 | Liquid Glass 主题 | 按住底部胶囊向左/右缓慢拖动 | indicator 跟手移动，hover 态 tab 展开为宽态高亮 | | ⬜ |
| 4 | 拖拽松手后 indicator 吸附 | Liquid Glass 主题 | 拖动到相邻 tab 上方松手 | indicator 气泡收缩后吸附到目标 tab，页面正确切换 | | ⬜ |
| 5 | 拖拽放大镜悬浮效果 | Liquid Glass 主题 | 按住胶囊拖动 | indicator 放大（scale x1.28, y1.85），浮起气泡视觉 | | ⬜ |
| 6 | Liquid Glass 浅色模式 | Liquid Glass 主题 + 系统浅色 | 重复步骤 1-5 | indicator 在浅色背景下仍清晰可见 | | ⬜ |
| 7 | 主题切换回归 Notion | Liquid Glass → 切到 Notion 主题 | 观察 TabBar indicator | Notion indicator 正常显示，无退化 | | ⬜ |
| 8 | 主题切换回归 Animal Island | Liquid Glass → 切到 Animal Island 主题 | 观察 TabBar indicator | Animal Island indicator 正常显示，无退化 | | ⬜ |
