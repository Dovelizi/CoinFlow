# CoinFlow 全量交互审查报告

> **审查日期**：2026-05-08
> **审查范围**：`/CoinFlow/CoinFlow/` 全部页面级 SwiftUI View
> **对照基准**：`/design/screens/` 原型 PNG（83 张）+ `/CoinFlowPreview/` 设计稿代码
> **审查口径**：交互逻辑、页面流转、组件布局、用户交互反馈、动效转场、手势、键盘、空态/loading/错误态、a11y

---

## 1. 对照矩阵概览

| 模块 | 原型 PNG | 主工程 View | Preview 对照 | 实现完整度 | 问题数 |
|---|---|---|---|---|---|
| 00-home | 6（main / empty / quick-action × 2 主题） | `HomeMainView.swift` | `HomeView.swift` | 70% | **5** |
| 01-records-list | 10（main/empty/edit/detail/summary） | `RecordsListView.swift` + `Components/` | `RecordsListView.swift` | 85% | **6** |
| 02-record-edit | 6（main/edit/error） | `NewRecordModal.swift` | `NewRecordModal.swift` | 90% | 2 |
| 03-capture-confirm | 11（main/loading/low-confidence × top+bottom） | `CaptureConfirmView.swift` | `CaptureConfirmView.swift` | 80% | **4** |
| 04-voice-wizard | 8（recording/parsing/wizard-step/field-fix） | `Voice*View.swift` × 5 | `VoiceWizardView.swift` | 90% | 3 |
| 05-stats | 24（hub/budget/sankey/trend/wordcloud/year/hourly/AA/category-detail/gauge/empty/main） | `StatsPlaceholderView.swift` | `StatsView.swift` | **5%（占位）** | **1（巨型缺口）** |
| 09-settings | 4（main/edit） | `SettingsView.swift` + `BackTapSetupView.swift` | `MiscScreensView.SettingsView` | 85% | 2 |
| 10-categories | 6（main/edit/quick-action） | `CategoryListView.swift` | `MiscScreensView.CategoryMgmtView` | 60% | **3** |
| 13-onboarding | 2（main） | **❌ 不存在** | `MiscScreensView.OnboardingView` | **0%** | **1（缺失）** |
| 15-sync-status | 6（main/loading/error） | **❌ 仅 RootView 有 banner** | `MiscScreensView.SyncStatusView` | **15%** | **1（缺失）** |

> 编号说明：每个问题按 `[模块代号-序号]` 标识，severity 分 **P0 阻塞 / P1 重要 / P2 优化**。

---

## 2. 问题清单（按模块 + severity）

### 00-home（首页）

#### [00-1] **P0** quick-action 长按菜单完全缺失
- **原型**：`quick-action-{dark,light}.png` 显示长按"截图记账"卡时弹出贴底 ActionSheet（3 个选项：从相册选择 / 扫描纸质票据 / 敲背 ×2 提示）
- **Preview 对照**：`HomeView.swift` L414-483 完整实现 `quickActionOverlay`
- **现状**：`HomeMainView.swift` 完全无 `LongPressGesture` 与 ActionSheet
- **修复**：在 entryCard 上加 `.simultaneousGesture(LongPressGesture(minimumDuration:0.4))` → 弹出 `actionSheetCard`（结构照搬 Preview）；点击「从相册选择」直接调起 `PhotosPicker`，「敲背」打开 `BackTapSetupView`

#### [00-2] **P1** entryCard 点击行为与 hint 文案不一致
- **现状**：hint 写"敲背两次 / 选相册"和"长按 / 说一句"，但点击 action 仅 `switchTab(.records)` —— 用户被引导切到流水页才能找到入口
- **修复**：截图记账卡点击 → 切 records tab + 立即触发 PhotosPicker；语音记账卡点击 → 切 records tab + 立即触发录音 sheet（通过 `NotificationCenter` 或共享 `@Published trigger`）

#### [00-3] **P1** loadError 字段定义但 UI 不渲染
- **现状**：`HomeViewModel.loadError` 被赋值但首页未展示
- **修复**：在 `topBar` 下加一行红字 inline error，参考 `MiscScreensView.SyncStatusView.errorCard`

#### [00-4] **P2** 顶栏 gear 按钮无 `.contentShape(Rectangle())`
- 触达区只在 icon 上，44pt 框内空白处不响应
- **修复**：Button label 加 `.contentShape(Rectangle())`

#### [00-5] **P2** TabBar 5s 自动隐藏后无再次显示手势
- 用户必须横滑 TabView 才能让 tabBar 重现，但在 `RecordsListView` 内左右滑被 ScrollView 拦截
- **修复**：监听全局 `DragGesture(minimumDistance: 10)` 上滑或长按底部 16pt 区域 → 重显 tabBar

---

### 01-records-list（流水列表）

#### [01-1] **P0** RecordsListView 三视图切换器（List/Stack/Grid）原型有 + Preview 实装，主工程**疑似缺失或不一致**
- **原型**：`main-{dark,light}.png` 段头右侧有 3-icon segmented `list/stack/grid`
- **Preview**：`RecordsListView.swift` L440-498 `DayGroupHeader` 完整实现 + `layoutByDate: [String: RecordsLayout]` 状态
- **修复**：core-explorer 报告未明确列出三视图状态切换实现；需对照 `Features/Records/RecordsLayout.swift` + `RecordsListView.swift` + `Components/` 验证；如缺失则照 Preview 补齐

#### [01-2] **P0** 月份 picker popover 缺失
- **原型**：`main-*.png` nav 左侧"5 月 ⌄"点击弹出 12 个月网格 popover
- **Preview**：L683-714 `monthPickerPopover` 实现
- **修复**：照 Preview 实现，nav 左侧 calendar 按钮 → `showMonthPicker.toggle()` → overlay popover

#### [01-3] **P0** 搜索栏 inline 形态 + transition 缺失或不规范
- **原型**：右上 magnifyingglass → nav 下方下滑出现搜索条（move(.top) + opacity）
- **Preview**：L651-679 `searchBarInline` 含 `.transition(.move(edge:.top).combined(with:.opacity))`
- **修复**：保证主工程使用同一 transition；onTap 走 `withAnimation(NotionTheme.animDefault)`

#### [01-4] **P1** detail Sheet detents 一致性
- **原型**：`detail-*.png` 显示 medium 高度
- **现状**：需确认主工程 `RecordDetailSheet` 是否使用 `.presentationDetents([.medium, .large]) + dragIndicator(.visible)`（PROJECT_STATE 自述已做但需验证）

#### [01-5] **P1** 空状态文案不一致
- **原型/Preview** `emptyState`（L726-735）："暂无流水 / 按住首页「按住说话」按钮，或敲背面截图记账"
- **修复**：主工程对齐文案

#### [01-6] **P2** edit-* 截图态显示 swipeActions
- **原型**：`edit-*.png` 显示左滑出"删除 / AA"
- **修复**：`RecordListRow` 加 `.swipeActions(edge: .trailing)` 删除 + `.leading` AA

---

### 02-record-edit（新建/编辑流水）

#### [02-1] **P1** date picker 用 `.wheel` 而非系统默认
- **Preview**：L308-309 `.datePickerStyle(.wheel)` + medium detent
- **修复**：主工程对齐 wheel + 完成按钮 + 半屏 detent

#### [02-2] **P2** ledger picker detent 高度
- **Preview**：`.presentationDetents([.height(280)])` 紧凑
- **修复**：使用 `.height(280)` 而非 `.medium`

---

### 03-capture-confirm（OCR 确认）

#### [03-1] **P0** 备注卡 + 保留截图 toggle 卡缺失
- **原型**：`main-bottom-*.png` 显示底部有「备注」+「附件 / 保留原截图」两张卡片
- **Preview**：L511-598 `noteCard` + `keepScreenshotCard` 完整实现
- **修复**：主工程 `CaptureConfirmView` 在 `recognitionCard` 下方追加这两个 card，使用 `RecognizedRecord.note + keepScreenshot`

#### [03-2] **P0** scrollToBottom 链路缺失
- **Preview**：构造参数 `scrollToBottom: Bool` + `ScrollViewReader.scrollTo("bottomAnchor")`，从相册选图后跳转可定位到 toggle
- **修复**：CaptureConfirmView 加同名参数

#### [03-3] **P1** loading 骨架屏不规范
- **原型**：`loading-*.png` 显示 4 行不等宽灰条 + ProgressView + "正在识别截图…"
- **Preview**：L294-326 完整骨架
- **修复**：对照 Preview 实现 4-row skeleton + 动态宽度 `[120, 180, 90, 140]`

#### [03-4] **P1** 字段级低置信度黄边框 + questionmark.circle.fill 图标
- **原型**：低置信度字段右侧有黄色 `?` icon + 1.5pt 黄色 stroke
- **Preview**：L401-439 `fieldRow` confidence 路径
- **修复**：照 Preview 实现 `FieldConfidence.borderColor` + 黄色 question icon

---

### 04-voice-wizard（语音多笔向导）

#### [04-1] **P1** parsing 阶段 list 三阶段进度细节
- **原型**：`parsing-*.png` 显示 3 行：「音频转文字 ✓ 完成」「拆分多笔账单 [⏳进行中…]」「字段缺失检测 (灰)」
- **Preview**：L315-358 `stageList` 完整实现
- **现状**：主工程 `VoiceParsingView` 据 PROJECT_STATE 已做"三阶段指示"，需核对是否区分 `done / active / pending` 三态视觉

#### [04-2] **P1** wizard-step 进度点 broken 态高亮
- **原型**：`field-fix-*.png` 显示进度点中"待补全的笔"用黄色 `!` 标识
- **Preview**：L492-517 `progressDot` `isBroken` 分支
- **修复**：主工程 `VoiceWizardStepView` 进度点对齐 3 态（current 蓝 / done 绿 ✓ / broken 黄 !）

#### [04-3] **P2** 录音 sheet header 的 ASR 档位胶囊
- **Preview**：L246-258 `tierPill(.local)` 绿点+档位文案
- **修复**：主工程 `VoiceRecordingSheet` 顶部加同款 tier pill

---

### 05-stats（统计 — **巨型缺口**）

#### [05-1] **P0🔥** 整个 Stats 模块仅占位，24 张原型 0 实现
- **原型**：24 张图覆盖 Hub 入口、月度趋势、桑基图、词云、预算环、AA 结算、分类详情、Gauge、小时分布、年视图、空态、main
- **Preview**：`StatsView.swift` 实现完整（118k 字符代码）
- **现状**：`StatsPlaceholderView.swift` 仅 126 行占位"深度分析即将上线"
- **决策点**：
  - **方案 A（推荐当前阶段）**：保留占位但**改为 Hub 入口卡片**，照搬 Preview 的 `hub-*.png` 实现，列出 8-10 个子页面入口；子页面 V2 实现，每个入口跳转一个 ComingSoon 子页（沿用占位文案）
  - **方案 B（重投入）**：完整移植 Preview StatsView 的 24 个子模块，工作量极大
  - **方案 C（最小修复）**：保持占位，但补全文案 + 改用 Notion 风 hub-style icon grid，避免"敬请期待"廉价感
- **建议**：dev agent 执行**方案 A**（Hub 入口 + 占位子页），24 张图分阶段在 V2 实装

---

### 09-settings（设置）

#### [09-1] **P1** 设置页结构与原型/Preview 不完全一致
- **Preview MiscScreensView.SettingsView**（L71-292）：5 大组（账户 / 记账 / 同步与数据 / 隐私 / 关于）
- **现状**：主工程 `SettingsView.swift` 是 4 段（账户 / 安全 / 语音必填字段 / 关于）—— 缺「记账」「同步与数据」「隐私」组
- **修复**：补齐缺失组；至少补"分类管理"入口 + "同步状态"入口（→ 跳 SyncStatusView）+ "数据导入/导出"入口

#### [09-2] **P2** importExport 子页面缺失
- **原型 edit-*.png** 是数据导入/导出页（CSV/JSON/完整备份 + 从 CSV 导入 + 从其他记账 App 迁移）
- **Preview MiscScreensView.SettingsView .importExport** 完整实现
- **修复**：新增 `DataImportExportView.swift`，作为 SettingsView 子页

---

### 10-categories（分类管理）

#### [10-1] **P0** Notion 数据库表风格表头 + 表格行布局缺失
- **原型 main-*.png**：表头「名称 / 类型 / 已用」三列 + 数据行（icon+名称 / 类型胶囊 / 已用次数）
- **Preview MiscScreensView.CategoryMgmtView**（L298-589）：完整 `tableHeader` + `tableRow` 实现
- **现状**：主工程 `CategoryListView.swift` 是单文件简版，需对照表格风重做
- **修复**：照 Preview 重写为 Notion table 风（表头 + drag handle + name+icon + type pill + usedCount + 删除按钮）

#### [10-2] **P0** edit 模式（左侧 drag handle + 右侧 minus.circle.fill 红色删除）缺失
- **原型 edit-*.png** 显示 edit 态进入后每行左侧 `line.3.horizontal` + 右侧红色 `−`
- **Preview**：edit mode 完整实现
- **修复**：照 Preview 加 `Mode.edit` 状态切换

#### [10-3] **P1** quick-action（添加分类 sheet）缺失
- **原型 quick-action-*.png** 显示添加分类的贴底 sheet（图标预览 + 名称输入 + 6 icon 选择 + 9 颜色 palette）
- **Preview L462-588** `addOverlay + addSheetCard` 完整实现
- **修复**：照 Preview 实现 sheet，使用 `presentationDetents([.large])`

---

### 13-onboarding（启动引导）— **完全缺失**

#### [13-1] **P0** 整个 Onboarding 模块未实现
- **原型 main-*.png**：钱袋 64pt icon + "CoinFlow" 36pt + slogan + 底部"开启 CoinFlow"按钮
- **Preview MiscScreensView.OnboardingView**（L595-642）完整实现
- **现状**：主工程入口直接进 `MainTabView`，无首次启动引导
- **修复**：
  1. 新增 `Features/Onboarding/OnboardingView.swift`（照搬 Preview）
  2. 在 `AppState` 加 `@Published hasCompletedOnboarding: Bool`，从 `UserDefaults` 持久化
  3. `CoinFlowApp.swift` 根据该 flag 决定显示 OnboardingView 或 MainTabView
  4. CTA 按钮触发 `hasCompletedOnboarding = true` → 进入主流程（同时可触发匿名登录）

---

### 15-sync-status（同步状态）— **基本缺失**

#### [15-1] **P0** 独立同步状态页缺失
- **原型 main/loading/error-*.png**：独立全屏页含 hero icon+title+subtitle / 同步队列 / 错误详情 / 历史记录 / 底部"立即同步/暂停同步/全部重试"按钮
- **Preview MiscScreensView.SyncStatusView**（L648-922）完整实现
- **现状**：主工程仅 `RootView` 有同步状态卡片（属于调试用），无独立页
- **修复**：
  1. 新增 `Features/Sync/SyncStatusView.swift`（照搬 Preview）
  2. 接 `AppState.syncQueue` / `AppState.dataState` 真实数据
  3. 在 SettingsView 增加入口：`同步与数据 → 同步状态 → 跳转此页`
  4. 三态切换基于 `SyncQueue` 当前状态（synced/syncing/failed）

---

## 3. 全局交互问题（跨页面）

### G1. **P0** 全局 Onboarding flag 设计与持久化
- 关联 [13-1]：增加 `UserDefaults` key `onboarding.completed`（mirror 到 `UserSettings` 表）

### G2. **P1** PhotosPicker 与录音 sheet 的全局触发链路
- 关联 [00-1] [00-2]：建议引入 `MainCoordinator: ObservableObject`，提供 `triggerPhotoPicker()` / `triggerVoiceRecording()` 方法，HomeMainView 与 RecordsListView 都消费该 coordinator

### G3. **P2** 系统字体回退检测
- 多处使用 `.custom("PingFangSC-Semibold", size:)`，未注册 fallback；非中文设备会回退系统字体导致字重不一致
- 修复：定义 `Font.pingFang(_ weight:size:)` helper 内置 `[.custom("PingFangSC-...", fixedSize:), .system(weight:)]` 回退

### G4. **P2** 强制 dark mode 与 `.preferredColorScheme(.dark)` 位置
- 已知 PROJECT_STATE 提到提到 ZStack 上修复了 records 页输入态丢焦，但 light 主题原型从未验证；需 design-reviewer 走查 light 模式

### G5. **P2** a11y label 覆盖度参差
- HomeMainView gear/entryCard 已有；MainTabView tabItem 已有；RecordsListView 行级 + RecordDetailSheet 内字段全无 accessibilityLabel

---

## 4. 修复优先级总览

| 优先级 | 数量 | 主要问题 |
|---|---|---|
| **P0 阻塞** | 12 | Stats 占位 / Onboarding 缺失 / SyncStatus 缺失 / Categories 表格化 / Home quick-action / Records 三视图&月份popover&搜索条 / Capture 备注&附件卡 |
| **P1 重要** | 11 | entryCard 行为对齐 / parsing 三阶段 / wizard-step 进度点 / Settings 5 段对齐 / quick-action sheet / loading 骨架 / 低置信度黄边 / Coordinator |
| **P2 优化** | 9 | TabBar 重显手势 / a11y / 字体回退 / contentShape / detent 微调 / swipeActions / loadError 渲染 / ledger detent / wheel datePicker |

**总计 32 项 audit 发现**

---

## 5. 修复执行计划（交付给 swift-dev）

### Phase A — P0 巨型缺口（约 60% 工作量）
1. **新建 OnboardingView**（`Features/Onboarding/`）+ `AppState.hasCompletedOnboarding` + `CoinFlowApp` 路由
2. **新建 SyncStatusView**（`Features/Sync/`）+ 接 `SyncQueue` 实数据 + Settings 入口
3. **重写 CategoryListView 为 Notion 表格风** + edit mode + add sheet
4. **Stats Hub 化**（不实现 24 子页）：保留 placeholder 文件改为 `StatsHubView`，列出 8 入口卡片（趋势/桑基/词云/预算/AA/分类/年视图/小时分布），每个入口暂时跳"V2 即将上线"占位
5. **CaptureConfirmView 补 noteCard + keepScreenshotCard + scrollToBottom**
6. **HomeMainView 补 quick-action longPress + ActionSheet**
7. **RecordsListView 三视图段头切换 + 月份 popover + 搜索 inline transition** 核对/补齐

### Phase B — P1 行为细节
8. **entryCard 行为对齐**：引入 `MainCoordinator` 触发 PhotosPicker / VoiceRecording
9. **VoiceParsingView 三阶段视觉对齐**（done/active/pending）
10. **VoiceWizardStepView 进度点 broken 态对齐**
11. **SettingsView 补齐 5 段**：账户 / 记账 / 同步 / 隐私 / 关于
12. **DataImportExportView**（Settings 子页）
13. **CategoryMgmt add sheet**（10-3）
14. **CaptureConfirmView loading 骨架 + 字段黄边**
15. **HomeMainView loadError UI 渲染**

### Phase C — P2 优化
16. TabBar 重显手势、a11y 补全、字体 fallback、contentShape、detent 微调、swipeActions

---

## 6. 验证检查点（交付给 qa-tester）

每项修复必须有可观测的验证标准。详见 `INTERACTION_TEST_PLAN.md`（由 qa-tester 产出）。

核心验证套件：
- **冷启动 → Onboarding → 主流程**链路
- **首页 quick-action 长按 → ActionSheet → 各分支**
- **流水列表 三视图切换 + 月份 popover + 搜索 transition**
- **新建/编辑 表单校验 + 各 picker detent**
- **截图确认 loading → loaded → 低置信度 → 备注/toggle → 保存**
- **语音多笔 录音 → parsing 三阶段 → 向导逐笔 → field-fix → summary**
- **设置 5 段 + 数据导入导出 + 同步状态页**
- **分类管理 表格 + edit 拖拽/删除 + add sheet**
- **同步状态 三态 + 错误详情 + 重试**

---

## 7. 边界风险（Boundary Warnings）

- **Stats Hub 方案 A** 假设你接受"V2 实装具体子图表"；若需 M7 内全做完，工作量约 +4-5 天
- **Coordinator 引入** 影响多处现有 `@StateObject` 注入路径，可能引发 view 重建；建议小步重构 + 逐 view 验证
- **Onboarding 写 UserDefaults** 卸载重装后 onboarding 会重做 ✓ 符合预期；但 iCloud restore 场景下用户可能不希望再次看到，需在 G1 决策时确认

---

**审查完成。下一步**：spawn `swift-dev` 执行 Phase A+B+C 修复 + spawn `qa-tester` 编写验证用例（并行）。
