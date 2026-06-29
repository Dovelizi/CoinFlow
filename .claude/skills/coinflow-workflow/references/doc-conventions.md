# 文档归档规范

## 目录结构

```
docs/
├── PROJECT_PLAN.md                    # 总规划（需求+Bug+Polish 索引）
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
├── bugfixes/                          # /bugfix 命令产出
│   └── <bug-name>/                    # kebab-case
│       ├── DEV/
│       │   ├── root-cause.md
│       │   └── fix-notes.md
│       └── QA/
│           ├── test-cases.md
│           └── verification-report.md
└── polish/                            # /polish 命令产出
    └── <polish-name>/                 # kebab-case
        ├── UI/
        │   └── design-spec.md
        ├── DEV/
        │   └── implementation-notes.md
        └── QA/
            ├── visual-diff.md
            └── test-report.md
```

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

### UI design-spec.md（/polish）
```markdown
# <名称> · UI 设计规范
## 现状分析（before）
## 改造方案

### 方案 A（推荐）/ 方案 B / ...
| 维度 | 规范 |
|------|------|
| 布局 | 间距/对齐/层级 |
| 颜色 | 前景/背景/边框 · light/dark |
| 字体 | 字号/字重/行高 |
| 形状 | 圆角/阴影/边框 |
| 动效 | 过渡类型/时长/触发条件 |
| 交互 | 按压反馈/手势区域/状态态 |
| 主题 | Notion/Liquid Glass/Animal Island |

## 用户确认
- [ ] 方案确认
```

### QA visual-diff.md（/polish）
```markdown
# <名称> · 视觉差异报告
## 对比

| 区域 | Before | After | 差异 | 状态 |
|------|--------|-------|------|------|
| 截图 → | | | ⬜ |

## 测量清单
- [ ] 间距 ≤2pt 偏差
- [ ] 字号匹配设计规范
- [ ] 动效时长/曲线一致
- [ ] 三主题无异常
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
