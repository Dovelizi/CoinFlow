---
name: coinflow-workflow
description: CoinFlow 项目开发流程规范 — 三个命令（/plan /feature /bugfix）、三角色协作（BA/DEV/QA）、技术边界约束
version: 2.0.0
---

# CoinFlow 开发流程规范

---

## 技术边界（硬约束）

以下约束摘自 `CoinFlow技术架构文档.md`，所有开发必须遵守：

### 平台与语言
- iOS 26+ / Swift 5.9+ / Xcode 26+ / SwiftUI 100%
- 无 UIKit View 主路径（仅 `AmountTextFieldUIKit` / `NoteTextFieldUIKit` / `CameraPicker` 包 UIKit）

### 架构模式
- **MVVM + Repository**：View + ViewModel（`@Observable` iOS 26）+ Repository
- **禁止** SwiftData / CoreData / VIPER / Clean Architecture
- `@Environment(AppState.self)` 访问全局状态，`@State` 管理局部 UI

### 数据层
- **金额永远用 `Decimal`**，SQLite TEXT 列存 `String(describing:)`，禁用 `Double`
- **SQL 100% 参数化**，动态列名走 `precondition` 白名单
- **软删除**：业务表 `deleted_at`；`voice_session` 用 `status='cancelled'`
- **同步元操作不污染 `updated_at`**

### 主题系统
- 颜色走 `NotionColor` 语义别名，禁止裸写 `Color(hex:)` / 固定 `pt`
- 字体走 `NotionFont` / `NotionTheme` token
- 新增主题：`<Name>Theme.swift` → `<Name>ThemeModifiers.swift` → `AppState` 注册 → `NotionTheme+Aliases.swift` → `AppearanceSettingsView.swift`

### 编码原则（andrej-karpathy）
- **不可变数据优先**：始终创建新对象，不修改现有对象
- **KISS / DRY / YAGNI**
- **不写注释**，除非 WHY（非显而易见的约束、隐患、workaround）
- **小文件**：200-400 行，800 行上限
- **小函数**：50 行上限
- **禁止深层嵌套**：4 层上限，优先 early return

---

## 三个命令

### 命令 1：`/plan` — 需求讨论

**用途**：基于当前项目整体功能及架构，讨论需求方向，不进入开发。

**流程**：
1. 阅读 `CoinFlow技术架构文档.md` 了解当前架构边界
2. 阅读 `docs/PROJECT_PLAN.md` 了解已完成功能与进行中需求
3. 与用户探讨需求可行性、影响范围、优先级
4. 产出讨论结论，更新 `docs/PROJECT_PLAN.md`「待开始需求」表

**进入条件**：用户提出模糊想法或方向性需求，尚未形成明确的功能边界。

**产出**：PROJECT_PLAN.md 中待开始需求记录。

**不进开发**：此阶段仅讨论和规划，不做 BA/DEV/QA 流程，不创建 feature 文件夹。

---

### 命令 2：`/feature` — 新需求开发

**用途**：将明确需求经过 BA→DEV→QA 流程完整交付。

**进入条件**：需求已经过 `/plan` 讨论，明确了边界和优先级。

**三角色流程**：

```
用户确认需求
    │
    ▼
┌─────────────────────────────────────────────┐
│ Role 1: BA（需求澄清者）                      │
│                                              │
│ 使用 /brainstorming skill 与用户探讨：        │
│   - 需求边界与范围                            │
│   - 用户故事与验收标准                         │
│   - 依赖与风险                                │
│                                              │
│ 产出: docs/features/<name>/BA/requirements.md │
└──────────────┬──────────────────────────────┘
               │ BA 完成
               ▼
┌─────────────────────────────────────────────┐
│ Role 2: DEV（开发者）                         │
│                                              │
│ 1. 阅读 BA/requirements.md                   │
│ 2. 撰写技术设计文档，验证可行性                │
│ 3. 严格遵循技术边界 + andrej-karpathy 编码原则 │
│ 4. 编写代码 + 单元测试（80%+ 覆盖）            │
│                                              │
│ 产出: docs/features/<name>/DEV/              │
│       ├── tech-design.md                     │
│       └── implementation-notes.md            │
└──────────────┬──────────────────────────────┘
               │ DEV 完成
               ▼
┌─────────────────────────────────────────────┐
│ Role 3: QA（测试者）                         │
│                                              │
│ 1. 阅读 BA/requirements.md + DEV/tech-design.md │
│ 2. 编写测试用例                               │
│ 3. 真机模拟测试（必须真机，iOS 26.x）          │
│ 4. 发现问题 → 提回 DEV 修复 → 重新验证         │
│ 5. 循环直到全部通过                           │
│ 6. 通知用户验收                               │
│                                              │
│ 产出: docs/features/<name>/QA/               │
│       ├── test-cases.md                      │
│       └── test-report.md                     │
└──────────────┬──────────────────────────────┘
               │ QA 全部通过
               ▼
          用户验收 → 更新 PROJECT_PLAN.md
```

---

### 命令 3：`/bugfix` — Bug 修复

**用途**：根据用户描述修复问题，走 DEV→QA 流程（无 BA 阶段）。

**流程**：

```
用户报告 Bug
    │
    ▼
┌─────────────────────────────────────────────┐
│ Role 2: DEV                                 │
│                                              │
│ 1. 复现问题 + 根因分析                        │
│ 2. 设计修复方案                               │
│ 3. 编码修复 + 自测                            │
│                                              │
│ 产出: docs/bugfixes/<name>/DEV/              │
│       ├── root-cause.md                      │
│       └── fix-notes.md                       │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│ Role 3: QA                                  │
│                                              │
│ 1. 编写回归测试用例                           │
│ 2. 真机验证修复 + 回归测试（iOS 26.x）         │
│ 3. 不通过 → 提回 DEV                         │
│ 4. 通过 → 通知用户确认                        │
│                                              │
│ 产出: docs/bugfixes/<name>/QA/               │
│       ├── test-cases.md                      │
│       └── verification-report.md             │
└──────────────┬──────────────────────────────┘
               │
               ▼
          用户确认 → 更新 PROJECT_PLAN.md
```

---

## 文档归档规范

```
docs/
├── PROJECT_PLAN.md                    # 总规划（需求+Bug 索引）
├── features/                          # /feature 命令产出
│   └── <feature-name>/                # kebab-case
│       ├── BA/
│       │   └── requirements.md
│       ├── DEV/
│       │   ├── tech-design.md
│       │   └── implementation-notes.md
│       └── QA/
│           ├── test-cases.md
│           └── test-report.md
└── bugfixes/                          # /bugfix 命令产出
    └── <bug-name>/                    # kebab-case
        ├── DEV/
        │   ├── root-cause.md
        │   └── fix-notes.md
        └── QA/
            ├── test-cases.md
            └── verification-report.md
```

---

## 文档模板

### BA requirements.md
```markdown
# <需求名称>
## 背景与动机
## 用户故事
## 功能范围（做什么 / 不做什么）
## 验收标准
## 依赖与风险
```

### DEV tech-design.md
```markdown
# <需求名称> · 技术设计
## 方案概述
## 涉及文件
## 数据流 / 交互流程
## Schema 变更（如有）
## 主题适配（如是 UI 需求）
## 风险评估
```

### DEV root-cause.md（Bugfix）
```markdown
# <Bug 名称> · 根因分析
## 问题现象
## 复现步骤
## 根因定位
## 影响范围
```

### QA test-cases.md
```markdown
# <需求/Bug 名称> · 测试用例
## 测试环境
- 设备：iPhone XX（iOS 26.x）
- 模式：深色 / 浅色

| # | 场景 | 前置条件 | 操作步骤 | 预期结果 | 实际结果 | 状态 |
|---|------|---------|---------|---------|---------|------|
```

---

## 关联技能

| 阶段 | 技能 |
|------|------|
| 需求澄清（/feature） | `/brainstorming` |
| 需求讨论（/plan） | 架构文档 + PROJECT_PLAN |
| 编码原则（/feature, /bugfix） | `andrej-karpathy-skills:karpathy-guidelines` |
| 架构参考 | `coinflow-patterns` |
| 架构文档 | `CoinFlow技术架构文档.md` |
