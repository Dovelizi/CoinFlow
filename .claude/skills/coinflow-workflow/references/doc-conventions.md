# 文档归档规范

## 目录结构

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
