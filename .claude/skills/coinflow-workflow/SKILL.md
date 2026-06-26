---
name: coinflow-workflow
description: CoinFlow 项目开发流程规范 — 三个命令（/plan /feature /bugfix）、三角色协作（BA/DEV/QA）
version: 2.2.0
---

# CoinFlow 开发流程规范

## 快速开始

| 命令 | 用途 | 角色 |
|------|------|------|
| `/plan` | 需求方向讨论，不进开发 | 用户 + AI |
| `/feature` | 新需求完整交付 | BA → DEV → QA |
| `/bugfix` | Bug 修复 | DEV → QA |

所有命令执行前必须先做**历史检查**（扫描 `docs/features/` + `docs/bugfixes/`），避免冲突与重复修复。

## 关键约束（摘要）

开发必须遵守 `CoinFlow技术架构文档.md` 的技术边界：
- iOS 26+ / SwiftUI 100% / MVVM + Repository / 禁止 SwiftData & CoreData
- 金额用 `Decimal` / SQL 参数化 / 软删除
- 编码遵循 andrej-karpathy 原则（KISS/DRY/YAGNI/不可变/小文件小函数）

> 完整约束见 [`references/tech-boundaries.md`](references/tech-boundaries.md)

## 参考资料

| 参考文件 | 内容 |
|---------|------|
| [`references/commands.md`](references/commands.md) | 三个命令的完整流程图与详细说明 |
| [`references/historical-check.md`](references/historical-check.md) | 历史检查流程、分类重点、回归判定规则 |
| [`references/doc-conventions.md`](references/doc-conventions.md) | 文档归档目录结构 + 所有模板 |
| [`references/tech-boundaries.md`](references/tech-boundaries.md) | 技术边界（平台/架构/数据层/主题/编码原则） |
| `CoinFlow技术架构文档.md` | 项目整体架构文档（技术边界的权威来源） |
| `docs/PROJECT_PLAN.md` | 项目总规划与进度 |

## 关联技能

| 阶段 | 技能 |
|------|------|
| 需求澄清（/feature） | `/brainstorming` |
| 编码原则 | `andrej-karpathy-skills:karpathy-guidelines` |
| 架构参考 | `coinflow-patterns` |
