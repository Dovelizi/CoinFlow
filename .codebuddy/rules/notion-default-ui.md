---
description: CoinFlow 项目默认 UI 风格 = Notion。任何 UI / 视觉 / 组件 / 页面相关任务自动加载 user-level skill `notion-design` 并按其规范执行。
alwaysApply: false
globs: **/*.swift,**/*.tsx,**/*.jsx,**/*.vue,**/*.html,**/*.css,**/*.kt
---

# CoinFlow UI 默认风格 = Notion

## 触发条件（项目级）

只要本项目（CoinFlow）内的请求满足以下任一，自动加载 user-level skill **`notion-design`**，无需用户显式说"Notion 风格"：

- 涉及创建 / 修改 / 评审 任何视觉组件、页面、布局、样式
- 涉及生成 SwiftUI / React / Vue / HTML / CSS UI 代码
- 涉及生成 design tokens / theme 文件

## 例外

- 用户在本次对话中**显式声明**要换其他设计语言（如"用 Material 3 重做"）→ 不加载 notion-design
- 纯后端 / 纯逻辑 / 纯文档任务 → 不加载

## 与 user-level skill 的关系

- 全局其他项目仍按 `notion-design` SKILL.md 的"严格触发"约定（必须显式提及 Notion）
- 本规则仅放宽 CoinFlow 项目内的触发条件
