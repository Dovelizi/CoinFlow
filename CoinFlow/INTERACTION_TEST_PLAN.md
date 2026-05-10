# CoinFlow 交互一致性测试方案

> **版本**：v1.0
> **作者**：qa-tester
> **基线 audit**：`INTERACTION_AUDIT.md`（2026-05-08，32 项问题 + 5 项跨页面）
> **配套设计稿**：`/design/screens/`（83 PNG）
> **配套 Preview**：`/CoinFlowPreview/CoinFlowPreview/Screens/*.swift`
> **本方案与 dev 修复并行编写，dev 完成对应 audit 项后即可立刻执行；用例独立可运行，不预设前置用例已通过。**

---

## 1. 测试范围与准入条件

### 1.1 测试范围
- 覆盖 audit 报告全部 **32 项问题**（P0×12 / P1×11 / P2×9）
- 覆盖跨页面 **G1-G5**
- 覆盖 **9 个模块**：00-home / 01-records-list / 02-record-edit / 03-capture-confirm / 04-voice-wizard / 05-stats / 09-settings / 10-categories / 13-onboarding / 15-sync-status
- 仅 iOS App，仅竖屏（横屏在范围外）

### 1.2 不在范围
- 后端 API/同步链路真实联调（mock）
- iPad / Mac Catalyst
- 性能压测（>500 笔由专门压测套件覆盖）
- 网络弱信号（<3G）

### 1.3 准入条件（dev 自检通过后再交 qa）
- [ ] `xcodebuild -scheme CoinFlow build` 0 warning 0 error
- [ ] SwiftLint 无 error
- [ ] 应用可冷启动到 MainTabView，不闪退
- [ ] `INTERACTION_AUDIT.md` 中对应 audit 项已 commit 并附 commit hash
- [ ] 提供测试构建包（TestFlight / Archive ipa）

### 1.4 准出条件
- [ ] 全部 P0 用例 100% Pass
- [ ] P1 用例 ≥95% Pass，未通过项需有产品确认豁免
- [ ] P2 用例 ≥90% Pass
- [ ] 全部 E2E 用例 Pass
- [ ] Light/Dark 双主题截图齐全
- [ ] 三机型截图齐全
- [ ] VoiceOver 走查报告无 P0/P1 缺陷

---

## 2. 测试环境矩阵

### 2.1 设备/系统矩阵
| 设备 | 屏幕 | iOS 版本 | 用途 | 必测 |
|---|---|---|---|---|
| iPhone 13 mini | 5.4" / 375×812 | iOS 17.5 | 小屏密度验证、动态字体溢出 | ✅ |
| iPhone 15 Pro | 6.1" / 393×852 | iOS 17.5 | 主推机型、灵动岛兼容 | ✅ |
| iPhone 15 Pro Max | 6.7" / 430×932 | iOS 17.5 | 大屏布局、Stats hub 多卡片 | ✅ |
| iPhone 15（备） | 6.1" / 393×852 | iOS 18.0 beta | 系统兼容回归 | 抽测 |

### 2.2 主题矩阵
| 主题 | 触发方式 | 必测项 |
|---|---|---|
| Light | 系统外观切换 | 全部 UI 用例 |
| Dark | 系统外观切换 | 全部 UI 用例 |
| 跟随系统切换 | 启动后切换系统主题 | 不闪屏、颜色重渲染、所有页面 |

### 2.3 a11y 矩阵
| 项 | 工具 | 标准 |
|---|---|---|
| VoiceOver | iOS 设置 → 辅助功能 | 关键操作 100% 可读，焦点顺序正确 |
| 触达区 | Accessibility Inspector | 所有可点元素 ≥44×44pt |
| 对比度 | Accessibility Inspector / Stark | WCAG AA：正文 4.5:1，大字 3:1 |
| 动态字体 | iOS 设置 → 显示与亮度 → 字体大小 | 最大档位无截断/重叠 |
| 减弱动效 | iOS 设置 → 辅助功能 → 减弱动效 | 关键转场仍可用，无功能损失 |

### 2.4 数据矩阵
| 数据规模 | 触发方式 | 用途 |
|---|---|---|
| 空数据 | 全新装、首次启动 | 空态用例 |
| 小数据 | 5-10 笔记录 | 默认用例 |
| 大数据 | 500 笔分布在 6 个月 | 滚动性能、聚合渲染 |
| 极端数据 | 单条备注 1000 字符 + emoji | 截断测试 |

### 2.5 网络与系统状态
| 状态 | 触发 | 期望 |
|---|---|---|
| 飞行模式 | 控制中心 | 同步失败 banner，本地操作不阻塞 |
| 弱网 4G→3G | Network Link Conditioner | 同步队列 pending，UI 不卡 |
| 后台切换 | Home → 等 30s → 回前台 | 状态保留、无重复请求 |
| 锁屏中通知 | 系统层 | 不影响 app 状态机 |
| 杀进程冷启 | 上滑杀 | 状态可恢复（草稿/onboarding flag）|

---

## 3. 用例清单

> **用例编号规则**：`TC-{模块代号}-{序号}`；模块代号对照 audit 模块号（`00`~`15`，`G` 表示跨页面）。
> **字段说明**：
> - **关联 audit**：对照 `INTERACTION_AUDIT.md` 的 `[模块-序号]`
> - **严重级**：继承 audit 的 P0/P1/P2
> - **自动化可行性**：✅ 强烈建议 / ⚠️ 部分可行 / ❌ 仅手动
> - **对照 PNG**：相对 `/design/screens/` 路径
> - **对照 Preview 行号**：`/CoinFlowPreview/.../Screens/*.swift` 行号

---

### 3.1 模块 00-home（首页）— 8 用例

#### TC-00-01 | quick-action 长按弹出 ActionSheet
- **关联 audit**：[00-1] **P0**
- **前置条件**：在首页（HomeMainView）、无 sheet 弹出
- **操作步骤**：
  1. 长按"截图记账"卡（持续 ≥0.4s）
  2. 观察底部 ActionSheet 出现
  3. 检查 3 个选项："从相册选择" / "扫描纸质票据" / "敲背两次提示"
  4. 点击 ActionSheet 外部空白
- **预期结果**：
  - 步骤 2：ActionSheet 自底部上滑（NotionTheme.animDefault）
  - 步骤 3：3 选项文案、icon、间距与原型一致
  - 步骤 4：ActionSheet 下滑关闭，背景 dim 渐隐
- **对照 PNG**：`00-home/quick-action-{dark,light}.png`
- **对照 Preview 行号**：`HomeView.swift` L414-483
- **自动化可行性**：⚠️（XCUITest 长按 + 元素存在校验）
- **失败时如何复现**：长按时长 < 0.4s → 不应触发；> 0.4s 必须触发；若 simulator 上不灵敏，物理设备复测

#### TC-00-02 | ActionSheet "从相册选择" 调起 PhotosPicker
- **关联 audit**：[00-1] **P0**
- **前置条件**：TC-00-01 步骤 2 已弹出 ActionSheet
- **操作步骤**：点击"从相册选择"
- **预期结果**：ActionSheet 关闭 → 系统 PhotosPicker 弹出（第一次需相册权限弹窗）
- **对照 PNG**：`00-home/quick-action-dark.png`
- **自动化可行性**：⚠️
- **失败时如何复现**：未授权状态下首次必须出权限弹窗；授权后直接出 picker

#### TC-00-03 | ActionSheet "敲背两次提示" 跳转 BackTapSetupView
- **关联 audit**：[00-1] **P0**
- **前置条件**：TC-00-01 ActionSheet 已弹出
- **操作步骤**：点击"敲背两次提示"
- **预期结果**：push 进入 `BackTapSetupView`（含 iOS 系统设置引导文案）
- **对照 PNG**：`09-settings/edit-*.png` 中 BackTap 区域
- **自动化可行性**：✅
- **失败时如何复现**：检查导航栈是否有重复 push

#### TC-00-04 | entryCard 单击跳 records 并触发 PhotosPicker
- **关联 audit**：[00-2] **P1**
- **前置条件**：首页
- **操作步骤**：单击"截图记账"卡
- **预期结果**：
  1. 切换到 records tab
  2. 同步触发 PhotosPicker（通过 MainCoordinator）
- **对照 PNG**：`00-home/main-{dark,light}.png` + `01-records-list/main-*.png`
- **对照 Preview 行号**：N/A（跨 view 协调）
- **自动化可行性**：✅（XCUITest 验证 tabBar selected + sheet 元素出现）
- **失败时如何复现**：检查 `MainCoordinator.triggerPhotoPicker()` 是否被订阅

#### TC-00-05 | entryCard "语音记账"单击触发录音 sheet
- **关联 audit**：[00-2] **P1**
- **前置条件**：首页、麦克风已授权
- **操作步骤**：单击"语音记账"卡
- **预期结果**：切到 records tab + 弹出 `VoiceRecordingSheet`
- **对照 PNG**：`00-home/main-*.png` + `04-voice-wizard/recording-*.png`
- **自动化可行性**：✅
- **失败时如何复现**：未授权时应弹权限弹窗，不应静默失败

#### TC-00-06 | loadError 红字 inline error 渲染
- **关联 audit**：[00-3] **P1**
- **前置条件**：mock `HomeViewModel.loadError = "今日数据加载失败"`
- **操作步骤**：进入首页
- **预期结果**：topBar 下方一行红色（NotionTheme.error）文案，含重试按钮
- **对照 PNG**：参考 `15-sync-status/error-*.png` errorCard 风格
- **对照 Preview 行号**：`MiscScreensView.SyncStatusView.errorCard`
- **自动化可行性**：✅（snapshot test）
- **失败时如何复现**：mock 注入失败 → 验证文案存在 + 颜色 token

#### TC-00-07 | 顶栏 gear 按钮触达区扩到 44×44
- **关联 audit**：[00-4] **P2**
- **前置条件**：首页
- **操作步骤**：点击 gear icon 周围 44pt 框内任意位置（含 icon 外的空白处）
- **预期结果**：均能触发跳转设置页
- **对照 PNG**：`00-home/main-*.png` 右上角
- **自动化可行性**：⚠️（XCUITest 通过坐标 tap 边缘）
- **失败时如何复现**：用 Accessibility Inspector 量 frame 应 ≥44×44

#### TC-00-08 | TabBar 5s 自动隐藏 + 上滑/底部长按重显
- **关联 audit**：[00-5] **P2**
- **前置条件**：在 RecordsListView 内停留 5s 不操作
- **操作步骤**：
  1. 等 5s，验证 tabBar 隐藏
  2. 在底部 16pt 区域长按 0.5s
  3. 验证 tabBar 重显
  4. 等 5s，再用从底向上 10pt 滑动手势
- **预期结果**：步骤 3、4 均能重显，动画与原隐藏对称
- **对照 PNG**：N/A（行为）
- **自动化可行性**：⚠️
- **失败时如何复现**：手势距离/时长不达标→不触发；超过则触发

---

### 3.2 模块 01-records-list（流水列表）— 14 用例

#### TC-01-01 | List 视图渲染（默认）
- **关联 audit**：[01-1] **P0**
- **前置**：5-10 笔记录、当前月
- **操作**：进入流水页，不切换视图
- **预期**：每个日期组按 `DayGroupHeader` 渲染；卡片为 `RecordListRow`；间距 16pt；背景 token 一致
- **PNG**：`01-records-list/main-{dark,light}.png`
- **Preview**：L440-498
- **自动化**：✅ snapshot
- **失败复现**：检查 `layoutByDate` 默认值是否 `.list`

#### TC-01-02 | Stack 视图切换
- **关联**：[01-1] **P0**
- **前置**：日期组展开
- **操作**：点击日期组右侧 segmented 第 2 个 icon（stack）
- **预期**：该日期组切换为 stack 布局（卡片重叠堆叠效果）
- **PNG**：原型同上 segmented 状态
- **自动化**：⚠️（snapshot diff）
- **失败复现**：观察 `layoutByDate[date] == .stack`，UI 应同步更新

#### TC-01-03 | Grid 视图切换
- **关联**：[01-1] **P0**
- **操作**：点击 segmented 第 3 个 icon（grid）
- **预期**：切换为 2 列 grid，每个 cell 显示 icon+amount
- **自动化**：⚠️
- **失败复现**：cell 数量、列数、间距对照 Preview

#### TC-01-04 | 月份 picker popover 弹出
- **关联**：[01-2] **P0**
- **前置**：流水页 nav 栏
- **操作**：点击 nav 左侧"5 月 ⌄"
- **预期**：popover 弹出，3×4 网格 12 个月，当前月高亮蓝色描边
- **PNG**：`01-records-list/main-*.png`
- **Preview**：L683-714
- **自动化**：✅
- **失败复现**：popover anchor 应在按钮下方；点击月份后立即关闭并切换数据

#### TC-01-05 | 月份切换数据刷新
- **关联**：[01-2] **P0**
- **操作**：在月份 popover 选 4 月
- **预期**：列表刷新为 4 月数据；nav 标题改为"4 月"
- **自动化**：✅
- **失败复现**：mock 4 月有 3 笔；切换后行数应为 3

#### TC-01-06 | 搜索栏 inline 出现 transition
- **关联**：[01-3] **P0**
- **操作**：点击右上 magnifyingglass
- **预期**：nav 下方下滑出搜索条（`.move(edge:.top).combined(with:.opacity)`，duration ≈ NotionTheme.animDefault）
- **PNG**：`01-records-list/main-*.png`
- **Preview**：L651-679
- **自动化**：⚠️ snapshot 多帧
- **失败复现**：减弱动效模式下应仍可见，但无动画

#### TC-01-07 | 搜索关键字过滤
- **关联**：[01-3] **P0**
- **操作**：搜索框输入"咖啡"
- **预期**：列表实时过滤含"咖啡"的记录（备注/分类/对方）
- **自动化**：✅
- **失败复现**：mock 1 笔咖啡 + 4 笔其他 → 应剩 1 行

#### TC-01-08 | 搜索栏关闭手势
- **关联**：[01-3] **P0**
- **操作**：再次点击 magnifyingglass / 点击 cancel
- **预期**：搜索栏向上收起，过滤恢复
- **自动化**：✅

#### TC-01-09 | RecordDetailSheet detents
- **关联**：[01-4] **P1**
- **操作**：点击列表中一行
- **预期**：sheet 弹出，默认 medium 高度，可拖到 large；dragIndicator 可见
- **PNG**：`01-records-list/detail-*.png`
- **自动化**：⚠️
- **失败复现**：检查 `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`

#### TC-01-10 | 空状态文案
- **关联**：[01-5] **P1**
- **前置**：清空所有数据
- **操作**：进入流水页
- **预期**：显示"暂无流水 / 按住首页「按住说话」按钮，或敲背面截图记账"，icon 居中
- **PNG**：`01-records-list/empty-*.png`
- **Preview**：L726-735
- **自动化**：✅ snapshot
- **失败复现**：文案逐字对齐

#### TC-01-11 | swipeActions 删除
- **关联**：[01-6] **P2**
- **操作**：在 RecordListRow 上左滑
- **预期**：右侧露出红色"删除"按钮，点击后 row 消失，触发 haptic
- **PNG**：`01-records-list/edit-*.png`
- **自动化**：⚠️

#### TC-01-12 | swipeActions AA 拆账
- **关联**：[01-6] **P2**
- **操作**：在 row 上右滑（leading）
- **预期**：左侧露出"AA"按钮 → 点击后弹出 AA 拆账 sheet
- **自动化**：⚠️

#### TC-01-13 | 列表 500 笔滚动性能
- **关联**：[01-1] 边界
- **前置**：mock 500 笔分散在 6 个月
- **操作**：从顶部滚到底部 + 反向
- **预期**：60fps 不掉帧（Instruments Time Profiler ≤ 16ms / frame）；内存平稳无泄漏
- **自动化**：⚠️（XCUITest 滚动 + Instruments）
- **失败复现**：开 Time Profiler 录制 10s 滚动

#### TC-01-14 | 后台切换状态保留
- **关联**：跨页面
- **操作**：在搜索状态下 → 按 Home → 等 30s → 回前台
- **预期**：搜索框仍打开 + 关键字保留 + 滚动位置保留
- **自动化**：⚠️

---

### 3.3 模块 02-record-edit（新建/编辑）— 6 用例

#### TC-02-01 | wheel datePicker 半屏 detent
- **关联**：[02-1] **P1**
- **操作**：点击日期字段
- **预期**：半屏 sheet（medium）+ wheel style picker + 顶部"完成"按钮
- **PNG**：`02-record-edit/edit-*.png`
- **Preview**：L308-309
- **自动化**：⚠️ snapshot

#### TC-02-02 | ledger picker height 280
- **关联**：[02-2] **P2**
- **操作**：点击账本字段
- **预期**：detent 高度恰好 280pt（紧凑），不是 medium
- **自动化**：⚠️
- **失败复现**：用 Accessibility Inspector 量 sheet 高度

#### TC-02-03 | 表单必填校验
- **关联**：基础
- **操作**：清空金额，点击保存
- **预期**：金额字段红边 + 文案"请输入金额"，焦点回到金额输入
- **PNG**：`02-record-edit/error-*.png`
- **自动化**：✅

#### TC-02-04 | 金额超长输入
- **关联**：边界
- **操作**：输入 999999999999.99
- **预期**：保留小数 2 位 + 千分位；不溢出 cell
- **自动化**：✅

#### TC-02-05 | 备注超长截断
- **关联**：边界
- **操作**：备注输入 1000 字符（含 emoji）
- **预期**：可滚动输入；保存成功；详情页正确换行/不溢出
- **自动化**：⚠️

#### TC-02-06 | 编辑模式预填 + 保存
- **关联**：基础
- **操作**：从详情页点"编辑" → 修改金额 → 保存
- **预期**：表单预填全部字段；保存后列表与详情更新；不出现重复记录
- **自动化**：✅

---

### 3.4 模块 03-capture-confirm（OCR 确认）— 9 用例

#### TC-03-01 | loading 骨架屏 4 行
- **关联**：[03-3] **P1**
- **前置**：从相册选图后立即进入
- **操作**：观察 loading 阶段
- **预期**：4 行灰条宽度依次 [120, 180, 90, 140]pt + ProgressView + 文案"正在识别截图…"
- **PNG**：`03-capture-confirm/loading-{dark,light}.png`
- **Preview**：L294-326
- **自动化**：✅ snapshot
- **失败复现**：宽度逐项核对；文案逐字核对

#### TC-03-02 | 高置信度字段渲染
- **关联**：[03-4] **P1**
- **前置**：mock 字段全部 confidence ≥0.9
- **操作**：识别完成
- **预期**：所有字段无黄边、无 question icon
- **PNG**：`03-capture-confirm/main-bottom-*.png`
- **Preview**：L401-439
- **自动化**：✅

#### TC-03-03 | 低置信度字段黄边 + 问号
- **关联**：[03-4] **P1**
- **前置**：mock 金额 confidence 0.4
- **预期**：金额字段 1.5pt 黄色 stroke + 右侧 `questionmark.circle.fill` 黄色 icon
- **PNG**：`03-capture-confirm/low-confidence-{top,bottom}-*.png`
- **自动化**：✅ snapshot
- **失败复现**：颜色取 `NotionTheme.warning`

#### TC-03-04 | 备注卡渲染 + 输入
- **关联**：[03-1] **P0**
- **前置**：识别完成（loaded 态）
- **操作**：滚动到底；点击备注卡输入"差旅"
- **预期**：
  - 备注卡 title "备注"，placeholder "可选"
  - 输入"差旅" → `RecognizedRecord.note == "差旅"`
- **PNG**：`03-capture-confirm/main-bottom-*.png`
- **Preview**：L511-598
- **自动化**：✅
- **失败复现**：ViewModel binding 检查

#### TC-03-05 | 保留截图 toggle 卡
- **关联**：[03-1] **P0**
- **操作**：toggle "保留原截图"
- **预期**：toggle 状态持久化到 `RecognizedRecord.keepScreenshot`；toggle 颜色 NotionTheme.accent
- **PNG**：`03-capture-confirm/main-bottom-*.png`
- **Preview**：L511-598
- **自动化**：✅

#### TC-03-06 | scrollToBottom 自动定位
- **关联**：[03-2] **P0**
- **前置**：从首页 entry 卡跳入，传 `scrollToBottom = true`
- **操作**：进入 CaptureConfirmView
- **预期**：识别完成后自动 `scrollTo("bottomAnchor", anchor:.bottom)`，备注/toggle 卡可见
- **PNG**：N/A（行为）
- **Preview**：L 含 `ScrollViewReader`
- **自动化**：⚠️
- **失败复现**：从相册选图入口反复进入应保持一致

#### TC-03-07 | 字段编辑保存
- **关联**：基础
- **操作**：手动改金额为 99.50 → 点保存
- **预期**：进入流水页 + 顶部出现新记录；OCR confidence 字段不再显示黄边
- **自动化**：✅

#### TC-03-08 | 识别失败重试
- **关联**：基础
- **前置**：mock OCR 抛错
- **预期**：显示错误卡 + "重试"按钮 + "手动录入"按钮；点击"手动录入"跳到 `NewRecordModal`
- **自动化**：✅

#### TC-03-09 | 后台切换识别中断恢复
- **关联**：边界
- **操作**：识别中按 Home → 30s → 回前台
- **预期**：识别继续完成 OR 提示"识别已暂停，点击重试"
- **自动化**：⚠️

---

### 3.5 模块 04-voice-wizard（语音多笔向导）— 8 用例

#### TC-04-01 | 录音 sheet header tier pill
- **关联**：[04-3] **P2**
- **前置**：打开 VoiceRecordingSheet
- **预期**：顶部胶囊：绿点 + "本地识别 · 极速" / 蓝点 + "云端识别 · 高精度"，根据当前 ASR 档位
- **PNG**：`04-voice-wizard/recording-*.png`
- **Preview**：L246-258
- **自动化**：✅ snapshot

#### TC-04-02 | 录音波形动画
- **关联**：基础
- **预期**：按住"按住说话"录音时波形条 24-32 根上下浮动，幅度跟麦输入
- **PNG**：`04-voice-wizard/recording-*.png`
- **自动化**：⚠️

#### TC-04-03 | parsing 三阶段视觉
- **关联**：[04-1] **P1**
- **前置**：录音结束进入 VoiceParsingView
- **预期**：3 行：
  1. "音频转文字"+ 绿色 ✓ + "完成"
  2. "拆分多笔账单" + 蓝色 ProgressView + "进行中…"
  3. "字段缺失检测" + 灰色 dot + 灰文字 "等待中"
- **PNG**：`04-voice-wizard/parsing-{dark,light}.png`
- **Preview**：L315-358
- **自动化**：✅ snapshot
- **失败复现**：done/active/pending 三态颜色 token 检查

#### TC-04-04 | wizard-step 进度点 3 态
- **关联**：[04-2] **P1**
- **前置**：解析得到 3 笔，第 2 笔字段缺失（broken）
- **预期**：进度条 3 个点：
  - 第 1 笔（done）：绿色 ✓
  - 第 2 笔（broken）：黄色 `!`
  - 第 3 笔（pending）：灰色空心
  - 当前 highlighted 用蓝色描边
- **PNG**：`04-voice-wizard/wizard-step-*.png` + `field-fix-*.png`
- **Preview**：L492-517
- **自动化**：✅ snapshot

#### TC-04-05 | wizard 逐笔编辑保存
- **关联**：基础
- **操作**：在每笔编辑面板修改金额 → 下一笔
- **预期**：每笔状态在进度点同步更新；最后一笔后进入 summary
- **自动化**：✅

#### TC-04-06 | field-fix 缺失字段补全
- **关联**：基础
- **前置**：第 2 笔金额缺失
- **操作**：进入第 2 笔，金额标黄边 + 焦点自动落在金额输入
- **预期**：填入金额后黄边消失，进度点变绿
- **PNG**：`04-voice-wizard/field-fix-*.png`
- **自动化**：✅

#### TC-04-07 | parsing 失败回退
- **关联**：边界
- **前置**：mock 拆分失败
- **预期**：显示错误卡 + "重新录音" + "手动逐笔录入"
- **自动化**：✅

#### TC-04-08 | 录音权限拒绝
- **关联**：边界
- **前置**：麦克风权限 denied
- **操作**：触发录音
- **预期**：弹出权限引导卡 + "去设置"按钮跳系统设置
- **自动化**：⚠️

---

### 3.6 模块 05-stats（统计 Hub）— 12 用例

> 按 audit 决策方案 A：Hub 入口 + 8 子页占位

#### TC-05-01 | StatsHubView 入口卡片渲染
- **关联**：[05-1] **P0**
- **前置**：进入 stats tab
- **预期**：Hub 入口：8 张卡片网格（趋势/桑基/词云/预算/AA/分类详情/年视图/小时分布），每张含 icon+title+1 行 description
- **PNG**：`05-stats/hub-{dark,light}.png`
- **Preview**：StatsView.swift hub 部分
- **自动化**：✅ snapshot

#### TC-05-02 | Hub 卡片点击进入占位子页
- **关联**：[05-1] **P0**
- **操作**：点击"月度趋势"卡
- **预期**：push 进入 ComingSoon 子页（标题"月度趋势 · V2 即将上线" + 返回按钮）
- **自动化**：✅

#### TC-05-03 | 8 个子页跳转全覆盖
- **关联**：[05-1]
- **预期**：每张卡片均能正确 push，返回保持滚动位置
- **自动化**：✅
- **失败复现**：导航栈 push/pop 计数应平衡

#### TC-05-04 | 大屏 Hub 自适应
- **关联**：[05-1]
- **前置**：iPhone 15 Pro Max
- **预期**：Hub 卡片网格自适应（建议 2 列 → 大屏可 2 列大尺寸）
- **自动化**：✅ snapshot 三机型

#### TC-05-05 | 小屏 Hub 不溢出
- **前置**：iPhone 13 mini
- **预期**：8 张卡片完整可见 + 可滚动；title/desc 不截断
- **自动化**：✅

#### TC-05-06 | Stats 空数据 hub 仍渲染
- **前置**：清空所有记录
- **预期**：Hub 入口仍展示，子页打开后显示"暂无数据"占位
- **自动化**：✅

#### TC-05-07 | hub 卡片 a11y label
- **预期**：每卡 `accessibilityLabel` = "{title}，{description}，进入 V2 占位页"
- **自动化**：✅

#### TC-05-08 | hub 子页返回手势
- **操作**：从子页右滑返回
- **预期**：iOS 标准手势可用
- **自动化**：✅

#### TC-05-09 | 切 tab 不重建 Hub
- **操作**：stats → records → stats
- **预期**：Hub 滚动位置保留
- **自动化**：⚠️

#### TC-05-10 | dark/light 切换 Hub 重渲
- **预期**：颜色 token 全部跟随主题；无 hardcoded 色值
- **自动化**：✅ snapshot 双主题

#### TC-05-11 | hub 减弱动效模式
- **前置**：开启 reduce motion
- **预期**：卡片点击仍可用，无 spring 弹性
- **自动化**：⚠️

#### TC-05-12 | hub VoiceOver 焦点顺序
- **预期**：从左上 → 右下逐卡读出，无跳跃
- **自动化**：⚠️

---

### 3.7 模块 09-settings（设置）— 8 用例

#### TC-09-01 | 5 段分组完整渲染
- **关联**：[09-1] **P1**
- **预期**：5 段：账户 / 记账 / 同步与数据 / 隐私 / 关于；每段标题 + 分隔符
- **PNG**：`09-settings/main-{dark,light}.png`
- **Preview**：L71-292
- **自动化**：✅ snapshot

#### TC-09-02 | 记账组入口完整
- **关联**：[09-1] **P1**
- **预期**：记账组含"分类管理" / "账本管理" / "默认币种" / "语音必填字段"
- **自动化**：✅

#### TC-09-03 | 同步与数据组入口
- **关联**：[09-1] **P1**
- **预期**：含"同步状态"（→ SyncStatusView）/"数据导入/导出"（→ DataImportExportView）
- **自动化**：✅

#### TC-09-04 | 隐私组入口
- **关联**：[09-1] **P1**
- **预期**：含"应用锁" / "OCR 处理位置" / "敲背设置" / "隐私政策"
- **自动化**：✅

#### TC-09-05 | DataImportExportView 渲染
- **关联**：[09-2] **P2**
- **操作**：从 Settings → 数据导入/导出
- **预期**：3 大块：导出（CSV/JSON/完整备份）/ 导入（从 CSV）/ 迁移（从其他 App）
- **PNG**：`09-settings/edit-*.png`
- **Preview**：MiscScreensView L .importExport
- **自动化**：✅

#### TC-09-06 | CSV 导出文件生成
- **操作**：点击"导出 CSV"
- **预期**：弹出系统 share sheet，可保存到文件
- **自动化**：⚠️

#### TC-09-07 | 设置项跳转返回
- **预期**：所有子页面右滑返回保留滚动位置
- **自动化**：✅

#### TC-09-08 | 关于页版本号显示
- **预期**：显示 app 版本号 + build 号 + 隐私政策/服务条款
- **自动化**：✅

---

### 3.8 模块 10-categories（分类管理）— 11 用例

#### TC-10-01 | Notion 表格风表头渲染
- **关联**：[10-1] **P0**
- **预期**：表头 3 列："名称" / "类型" / "已用"，列宽与原型一致；分隔线浅灰
- **PNG**：`10-categories/main-{dark,light}.png`
- **Preview**：L298-589 `tableHeader`
- **自动化**：✅ snapshot

#### TC-10-02 | 表格行渲染
- **关联**：[10-1] **P0**
- **预期**：每行：emoji icon + 名称 / type pill（支出黄/收入绿）/ 已用次数右对齐
- **自动化**：✅ snapshot

#### TC-10-03 | edit 模式切换
- **关联**：[10-2] **P0**
- **操作**：点击右上"编辑"按钮
- **预期**：每行左侧出现 `line.3.horizontal` drag handle + 右侧红色 `minus.circle.fill`
- **PNG**：`10-categories/edit-*.png`
- **Preview**：edit mode 实现
- **自动化**：✅ snapshot

#### TC-10-04 | edit 模式拖拽排序
- **关联**：[10-2] **P0**
- **操作**：长按 drag handle 上下拖动
- **预期**：行排序更新；松手后顺序持久化
- **自动化**：⚠️
- **失败复现**：再进一次设置应保留新顺序

#### TC-10-05 | edit 模式删除
- **关联**：[10-2] **P0**
- **操作**：点击红色 minus → 弹出系统"删除"按钮 → 确认
- **预期**：行消失；已用记录的分类不允许删除（弹出 alert "该分类下还有 N 笔记录"）
- **自动化**：✅
- **失败复现**：mock 该分类已用 5 笔 → 必须拦截

#### TC-10-06 | 退出 edit 模式
- **操作**：右上"完成"
- **预期**：drag handle / minus 消失；表格回到只读态
- **自动化**：✅

#### TC-10-07 | quick-action add sheet 弹出
- **关联**：[10-3] **P1**
- **操作**：点击右上"+"
- **预期**：贴底 sheet（presentationDetents([.large])），含 icon 预览 + 名称输入 + 6 icon 选择 + 9 颜色 palette
- **PNG**：`10-categories/quick-action-{dark,light}.png`
- **Preview**：L462-588
- **自动化**：✅ snapshot

#### TC-10-08 | add sheet icon/color 选择联动预览
- **关联**：[10-3] **P1**
- **操作**：选 icon "🍔" + 颜色 红色
- **预期**：顶部预览实时更新为红色背景 + 🍔
- **自动化**：✅

#### TC-10-09 | add sheet 保存
- **关联**：[10-3] **P1**
- **操作**：填名称"夜宵" → 保存
- **预期**：sheet 关闭，表格新增"夜宵"行（已用 0）
- **自动化**：✅

#### TC-10-10 | add sheet 名称必填校验
- **操作**：名称为空 → 保存
- **预期**：保存按钮 disabled 或弹出红字校验
- **自动化**：✅

#### TC-10-11 | 大量分类（30+）滚动
- **前置**：mock 50 个分类
- **预期**：表格平滑滚动，表头 sticky
- **自动化**：⚠️

---

### 3.9 模块 13-onboarding（启动引导）— 6 用例

#### TC-13-01 | 全新装首次启动进入 Onboarding
- **关联**：[13-1] **P0**
- **前置**：删除 app 重装；UserDefaults 清空
- **操作**：启动
- **预期**：直接进入 OnboardingView，不进 MainTabView
- **PNG**：`13-onboarding/main-{dark,light}.png`
- **Preview**：L595-642
- **自动化**：✅
- **失败复现**：检查 `AppState.hasCompletedOnboarding == false` 时路由

#### TC-13-02 | Onboarding 视觉规范
- **关联**：[13-1] **P0**
- **预期**：钱袋 icon 64pt 居中 + "CoinFlow" 36pt + slogan + 底部"开启 CoinFlow"按钮（NotionTheme.accent 背景）
- **PNG**：同上
- **自动化**：✅ snapshot 双主题

#### TC-13-03 | "开启" 按钮动作
- **关联**：[13-1] **P0**
- **操作**：点击底部 CTA
- **预期**：
  1. `hasCompletedOnboarding = true` 写入 UserDefaults + UserSettings 表
  2. 转场到 MainTabView（默认首页）
  3. 触发匿名登录（如设计要求）
- **自动化**：✅
- **失败复现**：xcrun simctl 验证 UserDefaults key

#### TC-13-04 | Onboarding 完成后不再显示
- **关联**：[13-1] **P0** + G1
- **前置**：TC-13-03 已完成
- **操作**：杀进程 → 重启
- **预期**：直接进 MainTabView，不再显示 Onboarding
- **自动化**：✅

#### TC-13-05 | 卸载重装重置
- **关联**：G1
- **前置**：完成过 onboarding
- **操作**：删除 app → 重装 → 启动
- **预期**：重新进入 Onboarding
- **自动化**：⚠️

#### TC-13-06 | iCloud restore 场景（产品决策点）
- **关联**：G1 边界
- **前置**：iCloud 备份已包含 UserDefaults
- **操作**：从备份恢复后启动
- **预期**：根据产品决策——若 mirror UserSettings 则跳过；否则重新展示
- **自动化**：❌ 仅手动
- **失败复现**：产品需明确决策记录

---

### 3.10 模块 15-sync-status（同步状态）— 9 用例

#### TC-15-01 | SyncStatusView 路由可达
- **关联**：[15-1] **P0**
- **操作**：Settings → 同步与数据 → 同步状态
- **预期**：push 进入独立全屏页
- **自动化**：✅

#### TC-15-02 | synced 态渲染
- **关联**：[15-1] **P0**
- **前置**：mock `SyncQueue.state == .synced`
- **预期**：hero icon checkmark.circle 绿色 + title "已同步" + subtitle 显示最近同步时间 + 队列空 + 历史列表
- **PNG**：`15-sync-status/main-{dark,light}.png`
- **Preview**：L648-922
- **自动化**：✅ snapshot

#### TC-15-03 | syncing 态渲染
- **关联**：[15-1] **P0**
- **前置**：mock state == .syncing，队列 3 项
- **预期**：hero ProgressView + title "同步中…" + 队列 3 行（每行 spinning indicator）
- **PNG**：`15-sync-status/loading-*.png`
- **自动化**：✅ snapshot

#### TC-15-04 | failed 态渲染
- **关联**：[15-1] **P0**
- **前置**：mock state == .failed
- **预期**：hero exclamationmark.triangle 红色 + title "同步失败" + 错误详情卡 + 历史 + 底部"全部重试"按钮
- **PNG**：`15-sync-status/error-*.png`
- **自动化**：✅ snapshot

#### TC-15-05 | "立即同步"按钮
- **关联**：[15-1] **P0**
- **操作**：synced 态点击"立即同步"
- **预期**：触发同步 → 状态切到 syncing → 完成回 synced
- **自动化**：⚠️

#### TC-15-06 | "暂停同步"按钮
- **关联**：[15-1] **P0**
- **操作**：syncing 态点击"暂停"
- **预期**：队列 pause；状态显示"已暂停"；按钮变"恢复同步"
- **自动化**：⚠️

#### TC-15-07 | "全部重试"按钮
- **关联**：[15-1] **P0**
- **操作**：failed 态点击"全部重试"
- **预期**：所有 failed item 重新入队，状态切 syncing
- **自动化**：⚠️

#### TC-15-08 | 飞行模式同步行为
- **前置**：开启飞行模式
- **操作**：触发同步
- **预期**：状态切 failed + 错误文案"无网络连接"
- **自动化**：⚠️

#### TC-15-09 | 历史记录列表分页
- **预置**：mock 50 条历史
- **预期**：列表分页加载，无内存暴涨
- **自动化**：⚠️

---

### 3.11 跨页面 G 系列 — 6 用例

#### TC-G1-01 | Onboarding flag 持久化
- **关联**：G1 **P0**
- **预期**：`UserDefaults.standard.bool(forKey:"onboarding.completed")` 与 `UserSettings.hasCompletedOnboarding` 双写一致
- **自动化**：✅

#### TC-G2-01 | MainCoordinator 触发 PhotosPicker
- **关联**：G2 **P1**
- **前置**：注入测试 Coordinator
- **操作**：调用 `coordinator.triggerPhotoPicker()`
- **预期**：当前 records tab 弹出 PhotosPicker；若不在 records tab 应自动切
- **自动化**：✅

#### TC-G2-02 | MainCoordinator 触发 VoiceRecording
- **关联**：G2 **P1**
- **预期**：触发后 `VoiceRecordingSheet` 弹出
- **自动化**：✅

#### TC-G3-01 | 字体回退在英文设备
- **关联**：G3 **P2**
- **前置**：模拟器 Region = US，无 PingFang
- **操作**：浏览所有页面
- **预期**：自动 fallback 到 SF Pro，字重视觉接近，无系统默认字体出现
- **自动化**：⚠️ snapshot 对比

#### TC-G4-01 | Light 主题全模块走查
- **关联**：G4 **P2**
- **前置**：系统切 Light
- **操作**：依次进入所有 9 模块
- **预期**：每模块文字/背景/边框/阴影对比度达标 WCAG AA；无 dark-only hardcoded 颜色泄漏
- **自动化**：✅ snapshot

#### TC-G5-01 | a11y label 覆盖率审计
- **关联**：G5 **P2**
- **工具**：Accessibility Inspector → Audit
- **预期**：
  - HomeMainView gear/entryCard ✓
  - MainTabView tabItem ✓
  - RecordsListView 行 + RecordDetailSheet 字段：每个交互元素均有 label
- **自动化**：⚠️
- **失败复现**：列表打印缺失 label 的元素 ID

---

## 4. 跨页面 E2E 链路用例（6 条）

> 每条 E2E 串联多 audit 项，用于回归整体链路完整性。

### TC-E2E-01 | 冷启动 → Onboarding → 首页 → 截图记账完整链路
- **串联**：[13-1] [00-2] [03-1] [03-2] + G2
- **步骤**：
  1. 全新装启动 → 进入 Onboarding
  2. 点"开启 CoinFlow" → 进入 HomeMainView
  3. 单击"截图记账"卡 → 切 records tab + PhotosPicker 弹出
  4. 选一张餐厅小票图
  5. 进入 CaptureConfirmView，loading 4 行骨架 → 识别完成
  6. 自动 scrollToBottom → 备注卡 + 保留截图 toggle 可见
  7. 输入备注"工作餐"，关闭 toggle
  8. 保存 → 回到 records 列表，第一条为新建记录
- **预期**：每步过渡丝滑，无闪屏；最终列表数+1
- **自动化**：⚠️
- **失败复现**：每步打 break point 验证 state

### TC-E2E-02 | 长按 quick-action → 敲背设置 → 触发记账
- **串联**：[00-1] [00-3] 设置链路
- **步骤**：
  1. 首页长按"截图记账"卡
  2. ActionSheet 选"敲背两次提示"
  3. 进入 BackTapSetupView，点"去系统设置"
  4. （手动）模拟敲背两次（物理设备需启用）
  5. 验证回到 app 后弹出 PhotosPicker
- **自动化**：❌ 全手动

### TC-E2E-03 | 语音多笔完整向导
- **串联**：[04-1] [04-2] [04-3] + G2
- **步骤**：
  1. 首页单击"语音记账" → 录音 sheet 弹出
  2. tier pill 显示"本地识别 · 极速"
  3. 按住"按住说话" 3s → 说"今天午餐 28 块，下午奶茶 18，晚饭 60 块" → 松手
  4. 进入 VoiceParsingView，三阶段动画依次完成
  5. 进入 VoiceWizardStepView，3 个进度点（其中 1 个 broken）
  6. 逐笔确认/补全 → 完成
  7. 进入 summary，3 笔均出现在 records 列表顶部
- **自动化**：⚠️ 录音部分需物理设备

### TC-E2E-04 | 流水列表 三视图 + 月份切 + 搜索 + 删除
- **串联**：[01-1] [01-2] [01-3] [01-6]
- **步骤**：
  1. 进入 records，默认 list 视图
  2. 切 stack → grid → 回 list
  3. 月份 picker 切到 4 月
  4. 搜索"咖啡" → 列表过滤
  5. 关闭搜索 → 列表恢复
  6. 左滑首行 → 删除 → 行消失
  7. 切回 5 月 → 数据正确
- **自动化**：⚠️

### TC-E2E-05 | 设置链路全覆盖
- **串联**：[09-1] [09-2] [10-1~10-3] [15-1]
- **步骤**：
  1. Settings → 5 段可见
  2. 记账组 → 分类管理 → 表格风渲染
  3. 进入 edit → 拖排序 → 完成
  4. 退出后点"+" → add sheet → 新建分类
  5. 返回 Settings → 同步与数据 → 同步状态 → SyncStatusView 渲染
  6. 返回 → 数据导入/导出 → 导出 CSV
- **自动化**：⚠️

### TC-E2E-06 | 主题切换在所有页面无副作用
- **串联**：G4
- **步骤**：
  1. 启动 app（Dark）
  2. 依次进入 9 个模块
  3. 切 Light（控制中心或设置）
  4. 反向遍历 9 个模块
  5. 再切回 Dark
- **预期**：无闪屏、无颜色残留、状态保留
- **自动化**：⚠️

---

## 5. 边界与异常场景

### 5.1 数据边界
| 场景 | 触发 | 预期 |
|---|---|---|
| 空数据 | 全新装 | 各模块空态文案与 PNG 一致 |
| 大数据 500 笔 | mock seed | 列表/统计不卡，60fps |
| 单笔金额 1e12 | 手输 | 金额格式化不溢出 |
| 备注 1000 字符 | 手输 | 滚动可见，详情不溢出 |
| 50+ 分类 | mock | 表格滚动表头 sticky |
| 历史记录 1000 条 | mock | 同步页分页加载 |

### 5.2 网络边界
| 场景 | 触发 | 预期 |
|---|---|---|
| 飞行模式 | 控制中心 | 同步失败 banner，本地操作不阻塞 |
| 弱网 3G | NLC | UI 不卡，loading 持续显示 |
| 同步中断 | 中途切飞行 | 重新联网后自动恢复 |
| OCR 服务 502 | mock | 错误卡 + 重试/手动录入 |

### 5.3 系统边界
| 场景 | 触发 | 预期 |
|---|---|---|
| 后台 30s 切回 | Home 30s | 状态保留 |
| 杀进程冷启 | 上滑杀 | 草稿/Onboarding flag 保留 |
| 锁屏中通知 | 系统 | 不影响状态机 |
| 仅竖屏锁定 | Info.plist | 横屏不可旋转 |
| 系统主题切换 | 控制中心 | 即时跟随，无闪屏 |
| 减弱动效 | 辅助功能 | 关键转场仍可用 |
| 动态字体最大 | 辅助功能 | 无截断 |
| iOS 17.5 / 18 beta | 不同设备 | 兼容无 crash |

### 5.4 权限边界
| 场景 | 触发 | 预期 |
|---|---|---|
| 麦克风首次拒绝 | 系统弹窗"不允许" | 弹引导卡 + "去设置" |
| 相册首次拒绝 | 系统弹窗"不允许" | 同上 |
| 麦克风 → 设置开启 → 回 app | 系统切换 | 录音可用 |

---

## 6. 验收交付物

### 6.1 截屏命名规范
```
{TC-ID}_{module}_{theme}_{device}.png
示例：TC-00-01_home_dark_iPhone15Pro.png
```
存放路径：`/test-evidence/screenshots/`

### 6.2 录屏命名规范
```
{TC-E2E-ID}_{描述}_{device}.mp4
示例：TC-E2E-01_cold-start-to-capture_iPhone15Pro.mp4
```
存放路径：`/test-evidence/recordings/`

### 6.3 Bug 报告模板
```markdown
## Bug-{YYYYMMDD}-{序号}
- **关联用例**：TC-XX-XX
- **关联 audit**：[模块-序号] (P?)
- **环境**：iPhone 15 Pro / iOS 17.5 / Dark / build 1.0.0(123)
- **复现步骤**：
  1. ...
  2. ...
  3. ...
- **预期**：...
- **实际**：...
- **附件**：截图/录屏链接
- **严重级**：阻塞 / 重要 / 优化
- **建议修复**：...（可选）
```
存放：GitLab / TAPD issue tracker

### 6.4 自动化用例代码位置
- SwiftUI snapshot test：`CoinFlowTests/Snapshots/{Module}Tests.swift`
- XCUITest：`CoinFlowUITests/{Flow}UITests.swift`
- 命名：`test_TC_XX_XX_{description}()`

---

## 7. Sign-off 清单

### 7.1 准入 sign-off（dev → qa）
- [ ] dev 已完成 audit 全部 P0 项 commit
- [ ] dev 自测 build 通过
- [ ] PROJECT_STATE.md 已更新
- [ ] TestFlight build 链接已交付

### 7.2 准出 sign-off（qa → product）
- [ ] P0 用例 100% Pass
- [ ] P1 用例 ≥95% Pass
- [ ] P2 用例 ≥90% Pass
- [ ] 6 条 E2E 用例 Pass
- [ ] 三机型 × 双主题 截图齐全（CSV 清单）
- [ ] VoiceOver 走查报告
- [ ] WCAG AA 对比度报告
- [ ] 性能报告（500 笔列表 60fps）
- [ ] 已知 Bug 列表（按严重级排序）

### 7.3 产品 sign-off
- [ ] iCloud restore 场景决策已记录（G1 边界）
- [ ] Stats Hub 方案 A 接受
- [ ] 余下未通过 P1/P2 项已豁免或排期

---

## 8. 验证执行日志

> 每轮回归在此追加，最新在最上方。模板：

### 第 1 轮 — YYYY-MM-DD
| TC-ID | 严重级 | 设备 | 主题 | 结果 | Bug 链接 | 备注 |
|---|---|---|---|---|---|---|
| TC-00-01 | P0 | 15 Pro | Dark | ⬜ | - | - |
| TC-00-02 | P0 | 15 Pro | Dark | ⬜ | - | - |
| ... | ... | ... | ... | ⬜ | - | - |

> 状态符号：✅ Pass / ❌ Fail / ⚠️ 部分通过 / ⏭️ 跳过 / ⬜ 未执行

---

## 附录 A：用例总数与分布统计

| 模块 | P0 | P1 | P2 | 小计 |
|---|---|---|---|---|
| 00-home | 5 | 1 | 2 | 8 |
| 01-records-list | 8 | 2 | 4 | 14 |
| 02-record-edit | 0 | 1 | 5 | 6 |
| 03-capture-confirm | 4 | 4 | 1 | 9 |
| 04-voice-wizard | 0 | 4 | 4 | 8 |
| 05-stats | 6 | 0 | 6 | 12 |
| 09-settings | 4 | 3 | 1 | 8 |
| 10-categories | 7 | 3 | 1 | 11 |
| 13-onboarding | 4 | 0 | 2 | 6 |
| 15-sync-status | 7 | 0 | 2 | 9 |
| G 跨页面 | 1 | 2 | 3 | 6 |
| **小计** | **46** | **20** | **31** | **97** |

| E2E | 数量 |
|---|---|
| 跨页面端到端 | 6 |

**总计：97 单点用例 + 6 E2E = 103 用例**（≥80 ✅）

---

## 附录 B：自动化覆盖率目标

| 类型 | 用例数 | 自动化目标 |
|---|---|---|
| ✅ 强烈建议 | ~55 | 全部纳入 CI |
| ⚠️ 部分可行 | ~38 | 关键链路纳入 CI，其余手动 |
| ❌ 仅手动 | ~10 | 每轮回归手动执行 |

CI 触发：每次 MR + 每日定时全量。
