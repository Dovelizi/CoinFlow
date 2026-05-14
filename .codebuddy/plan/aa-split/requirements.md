# AA 分账功能 — 需求文档

## 引言

CoinFlow 是一款单用户单设备的本地优先记账应用（SwiftUI + SQLite + 飞书多维表格云同步）。当前主线（M1–M10）所有流水都默认归属到固定的「我的账本」（`default-ledger`，类型 `personal`）。数据模型层已经为 AA 分账预留了 `LedgerType.aa`、`Record.payerUserId`、`Record.participants` 字段，但尚未开放 UI 入口与业务流程。

本期目标是**端到端打通 AA 分账业务**：让用户在记账时能选择把一笔流水投递到一个临时的 **AA 分账账户（公共账本）**，对该账户进行分账成员管理与支付确认；分账完成后把每位成员的应付金额回写为**当前用户个人账户上的一条账单流水**，并在该账单的详情中可追溯到完整的分账上下文。

**关键设计前提（与现有架构对齐）**：

1. **单用户场景**：本 App 没有多端账号/邀请体系。"分账成员"是用户在本地维护的**人名标签**（昵称 + 可选 emoji 头像），不发起真实支付。"支付确认"是用户**单方面勾选**"该成员已把钱给我了"的状态记录。
2. **以现有 `Ledger` 表承载 AA 账户**：每个 AA 分账 = 一个 `type=aa` 的 `Ledger`，带状态字段（`recording / settling / completed`）。
3. **以现有 `Record` 表承载分账内的流水**：`record.ledger_id` 指向 AA Ledger，`record.payer_user_id` 记录"由谁先垫付"，`record.participants` 记录参与该笔分摊的成员 id 列表。
4. **分账完成时的"回写"**：在分账 Ledger 完成结算后，系统按"被请款的成员 → 当前用户"维度，在 `default-ledger` 上为当前用户**新增一条收入流水**（备注关联到 AA Ledger id）；点击该流水可跳转到 AA 分账详情。
5. **B1/B2/B3 不变**：金额一律 `Decimal`、时间一律 UTC + IANA、所有新表带 `deleted_at`。
6. **UI 风格**：沿用 Notion 主题（`NotionTheme` / `NotionFont` / `NotionColor`）+ Liquid Glass 容器；不引入新的设计语言。

## 术语表

| 术语 | 含义 |
|---|---|
| 个人账户 | 当前用户的本地账本，固定 id `default-ledger`，`type = personal` |
| AA 分账账户（公共账本） | 一个 `type = aa` 的 Ledger，承载一次共同消费的所有流水与成员状态 |
| 当前用户 | 持有本设备的唯一用户；在 AA 分账内默认就是"垫付方/收款方" |
| 分账成员 | AA 账本下的人名标签实体，包含昵称、可选头像、应付金额、支付状态 |
| 分账记录中 | AA 账本初始状态：仅记账，不要求成员、不发起结算 |
| 分账结算中 | AA 账本进入结算流程：必须有成员、需要逐一确认每个成员的支付状态 |
| 分账完成 | 所有成员均确认支付：账本只读、自动回写至个人账户 |

## 需求

### 需求 1：AA 分账账户的创建

**用户故事：** 作为一名记账用户，我希望能创建一个 AA 分账账户（如"7月泰国旅行"），以便把这次活动所有共同消费的流水集中到一处，与我的个人账单隔离。

#### 验收标准

1. WHEN 用户在 AA 分账页点击"+ 新建分账"按钮 THEN 系统 SHALL 弹出创建 Sheet，包含输入项：分账名称（必填，1–30 字）、可选备注（≤140 字）、可选封面 emoji。
2. WHEN 用户提交合法的分账名称 THEN 系统 SHALL 在本地创建一条 `Ledger` 记录，`type = aa`、`status = recording`、`created_at = now (UTC)`、`timezone = 当前设备 IANA`。
3. IF 用户输入的分账名称为空或仅含空白 THEN 系统 SHALL 禁用提交按钮并以红框 + "请输入分账名称"提示。
4. WHEN 创建成功 THEN 系统 SHALL 关闭 Sheet、刷新 AA 分账页列表，并把新建账本展示在最顶部，带"分账记录中"状态标签。
5. WHEN 创建成功 THEN 系统 SHALL 通过 `SyncTrigger.fire` 触发一次飞书多维表格同步（沿用现有 `SyncQueue`）。

### 需求 2：AA 分账列表页展示

**用户故事：** 作为一名记账用户，我希望进入 AA 分账页时能直观看到所有 AA 账户、它们的状态、累计金额和最近活动，以便快速找到目标账本。

#### 验收标准

1. WHEN 用户进入 AA 分账页 THEN 系统 SHALL 按 `created_at DESC` 列出全部未软删除的 `type = aa` 的 Ledger。
2. WHEN 列表渲染 THEN 系统 SHALL 在每条卡片上展示：名称、状态徽标（记录中/结算中/已完成，三种颜色）、累计金额（该 Ledger 下未删除流水合计）、流水数、最近一笔时间。
3. WHEN 列表为空 THEN 系统 SHALL 显示 `StatsEmptyState` 风格的空态图，标题"还没有 AA 分账"，主按钮"立即创建"。
4. WHEN 用户在列表中按状态切换 Tab（"全部 / 记录中 / 结算中 / 已完成"）THEN 系统 SHALL 即时过滤列表，无需网络请求。
5. WHEN 用户点击列表项 THEN 系统 SHALL 通过 `NavigationStack` 进入 AA 分账详情页。
6. WHEN 用户在 AA 列表项上左滑 THEN 系统 SHALL 提供"归档"和"删除"两个动作；删除走软删除（`deleted_at`）并支持 30 天内通过设置页恢复（沿用已有软删除惯例）。

### 需求 3：记账时选择 AA 分账账户

**用户故事：** 作为一名记账用户，我希望在新建流水时能选择把这笔记到某个 AA 分账账户，以便保留默认走个人账户的轻量体验，又能在团体消费场景一键投递到指定 AA 账本。

#### 验收标准

1. WHEN 用户进入新建流水（`NewRecordModal`）/ 语音记账 / OCR 记账确认页 THEN 系统 SHALL 默认选择"个人账户"作为目标账本，无需任何额外操作即可保存。
2. WHEN 用户在新建流水页点击"AA 分账"切换控件 THEN 系统 SHALL 弹出一个**仅展示状态为 `recording` 的 AA 账本**的选择 Sheet（按 `created_at DESC`）。
3. IF 当前不存在任何状态为 `recording` 的 AA 账本 THEN 系统 SHALL 在选择 Sheet 内展示空态 + "立即创建分账"按钮，点击后跳转到需求 1 的创建流程。
4. WHEN 用户选中一个 AA 账本 THEN 系统 SHALL 关闭 Sheet，返回新建流水页，并在标题栏显示已选 AA 账本名称的徽标（如"AA · 7月泰国"）。
5. WHEN 用户保存流水 AND 已选择 AA 账本 THEN 系统 SHALL 把 `record.ledger_id` 写为该 AA 账本 id，`record.payer_user_id` 写为当前用户 id（沿用 `AppState.currentUserId`，若无则用 `"me"` 占位），`record.participants` 暂留 nil（结算时再填）。
6. WHEN 用户在已选 AA 账本的状态下再次点击徽标 THEN 系统 SHALL 提供"切回个人账户"操作，并把 ledgerId 回滚为 `DefaultSeeder.defaultLedgerId`。
7. WHEN AA 账本由于状态切换不再是 `recording`（被结算）THEN 该账本 SHALL 不再出现在新建流水的选择 Sheet 中。

### 需求 4：AA 分账详情页 — "记录中"阶段

**用户故事：** 作为一名记账用户，在 AA 分账"记录中"阶段，我希望能聚焦于记录共同消费、不被强制添加成员，以便在外旅行/聚餐时快速记账。

#### 验收标准

1. WHEN 用户进入 `recording` 状态的 AA 分账详情页 THEN 系统 SHALL 顶部展示账本名、累计金额、流水数、状态徽标"分账记录中"。
2. WHEN 用户在该页 THEN 系统 SHALL 展示主操作"+ 添加流水"按钮，点击后复用 `NewRecordModal` 并锁定 ledgerId 为当前 AA 账本。
3. WHEN 系统渲染流水列表 THEN 系统 SHALL 按日期分组（沿用 `DateGrouping`），每行展示分类图标、备注、金额、时间，与现有 `RecordRow` 一致。
4. WHEN 用户在该页 THEN 系统 SHALL 在底部展示醒目按钮"开始结算"，点击后进入需求 5 的状态切换流程。
5. IF 当前 AA 账本下没有任何流水 THEN "开始结算"按钮 SHALL 置灰并附文案"先添加至少一笔流水再结算"。
6. WHEN 用户在 `recording` 状态下编辑/删除某条流水 THEN 系统 SHALL 直接复用 `RecordDetailSheet`，无任何额外限制。

### 需求 5：分账状态从"记录中"切换到"结算中"

**用户故事：** 作为一名分账发起人，我希望在结束消费阶段后能进入"结算中"状态，以便补齐成员名单、进行金额分摊。

#### 验收标准

1. WHEN 用户点击"开始结算" THEN 系统 SHALL 弹出确认 Sheet，提示：进入结算后该账本将不再出现在新建流水的可选列表，并要求用户至少添加 1 个分账成员。
2. WHEN 用户确认 THEN 系统 SHALL 在同一事务中：①把 `aa_split.status` 更新为 `settling`、②写入 `settling_started_at`、③触发同步。
3. WHEN 进入结算中 THEN 系统 SHALL 引导用户进入"成员配置"步骤（详见需求 6）。
4. WHEN 进入结算中 THEN AA 账本下的所有流水 SHALL 被标记为只读（不允许金额、分类、时间、ledger 调整；可调整的仅为分摊参与者，详见需求 7），用户尝试编辑时给出 toast"账本已结算中，如需修改请先回退到记录中"。
5. WHEN 用户在结算中页面点击"回退到记录中" THEN 系统 SHALL 二次确认后把状态回滚为 `recording`，并清空临时分摊草稿（成员保留）。

### 需求 6：分账成员管理

**用户故事：** 作为一名分账发起人，我希望能在结算阶段灵活地添加、修改、删除分账成员，以便准确反映本次共同消费的真实参与者。

#### 验收标准

1. WHEN 用户在结算中页面进入"成员"区块 THEN 系统 SHALL 展示成员列表（昵称 + 可选头像 emoji + 应付小计），并提供"+ 添加成员"按钮。
2. WHEN 用户点击"+ 添加成员" THEN 系统 SHALL 弹出输入框；用户输入昵称（必填、1–20 字、同账本内不可重名）后系统 SHALL 在本地新增一条 `aa_member` 记录（`status = pending`）。
3. WHEN 用户长按或左滑成员 THEN 系统 SHALL 提供"修改昵称"和"删除"。
4. IF 该成员尚未被任何流水的"参与者"勾选 THEN 删除 SHALL 直接执行（软删 `deleted_at`）。
5. IF 该成员已被流水勾选为参与者 THEN 删除前系统 SHALL 提示"该成员参与了 N 笔流水，删除会把这些流水的应付额回收"，确认后 SHALL 把这些流水中该成员从参与者列表移除并重算分摊。
6. IF 该成员已经被标记为"已支付" THEN 删除按钮 SHALL 置灰，需先撤销支付确认才能删除。
7. WHEN 系统在常用昵称建议中读取 `@AppStorage("aa.preview.nicknames")` 中的历史昵称 THEN 用户 SHALL 能从下拉提示中一键复用（与现有 `AAMemberAddSheet` 习惯保持一致）。

### 需求 7：分账金额计算与调整

**用户故事：** 作为一名分账发起人，我希望系统能根据每笔流水的"参与者"自动平均分摊，并允许我在必要时手动调整每位成员的应付额，以便处理"我请这顿"或"AA 不均"的情况。

#### 验收标准

1. WHEN 用户在结算中进入"流水分摊"步骤 THEN 系统 SHALL 列出本账本全部流水（仅展开支出方向），每行右侧展示"参与者"芯片组（默认全选所有成员 + 当前用户）。
2. WHEN 用户点选/取消选某成员的参与状态 THEN 系统 SHALL 实时按"金额 / 参与者数"重算该笔流水的人均应付，并更新成员侧的累计应付。
3. IF 一笔流水的参与者数量为 0 THEN 系统 SHALL 视为"由当前用户独自承担"，不计入任何成员应付。
4. WHEN 用户点击某笔流水进入"高级模式" THEN 系统 SHALL 允许对每位参与者设置自定义金额（输入框走 `AmountInputGate`，单笔不超 1 亿）。
5. IF 自定义模式下各参与者金额之和与流水金额不一致 THEN 系统 SHALL 在该笔流水下方红字提示"差额：¥X.XX"，并阻塞结算完成动作。
6. WHEN 系统计算每位成员"应付总额" THEN 系统 SHALL 取该成员在所有未删除流水里的应付额累加，使用 `Decimal` 全程参与，最终展示保留 2 位小数（沿用 `AmountFormatter`）。
7. WHEN 用户在某笔流水上把"付款人"切换为非当前用户 THEN 系统 SHALL 把 `record.payer_user_id` 改为对应成员，并在结算完成时按"成员之间相互找平"的方向回写（详见需求 9）。

### 需求 8：成员支付确认

**用户故事：** 作为一名分账发起人，我希望能逐一勾选每位成员"已经把钱给我了"，并看到支付进度，以便清楚追踪谁还没结。

#### 验收标准

1. WHEN 用户进入结算中的"支付确认"步骤 THEN 系统 SHALL 展示成员列表：头像、昵称、应付总额、支付状态（待支付 / 已支付）、确认时间。
2. WHEN 用户点击某成员的"标记已支付" THEN 系统 SHALL 在 `aa_member` 上更新 `status = paid`、`paid_at = now`，并在 UI 上把该行变绿。
3. WHEN 用户点击已支付成员的"撤销" THEN 系统 SHALL 弹二次确认后把 `status` 回滚为 `pending`、清空 `paid_at`。
4. WHEN 系统渲染顶部进度条 THEN SHALL 展示"已支付 N / 全部 M  ¥已收 / ¥应收"。
5. IF 任意成员 `status = pending` THEN 底部"完成结算"按钮 SHALL 置灰并附文案"还有 N 位成员未确认支付"。
6. WHEN 用户的所有 `aa_member` 都达到 `status = paid` THEN "完成结算"按钮 SHALL 启用为强调色。
7. IF 某成员应付总额为 0（被排除出所有流水）THEN 系统 SHALL 自动判定该成员为已支付，不阻塞结算完成。

### 需求 9：分账完成与个人账户回写

**用户故事：** 作为一名分账发起人，分账完成后我希望系统自动把每位成员还我的钱作为收入流水写入我的个人账单，并能从该流水追溯到完整的分账明细，以便统一统计、回看。

#### 验收标准

1. WHEN 用户点击"完成结算" THEN 系统 SHALL 在单个 SQLite 事务内：①把 AA Ledger 状态更新为 `completed`、②写入 `completed_at`、③对每位 `paid_at != null` 且 `应付额 > 0` 的成员，在 `default-ledger` 上插入一条**收入流水**。
2. WHEN 系统插入回写收入流水 THEN 该流水 SHALL 满足：`category_id = preset-income-transfer`、`amount = 该成员应付总额`、`occurred_at = 成员 paid_at`、`note = "AA · {账本名} · {成员昵称}"`、`source = .manual`、`payer_user_id = 该成员 id`、`participants = nil`，并在新增字段 `aa_settlement_id` 中写入 AA Ledger id（详见需求 12）。
3. WHEN 回写流水生成后 THEN 系统 SHALL 通过 `RecordChangeNotifier` 通知 `RecordsListView` / `StatsViewModel` 刷新。
4. WHEN 系统检测到本次分账中存在"付款人不是当前用户"的流水 THEN 系统 SHALL 同时为当前用户写入相应的**支出流水**（`category_id = preset-expense-other`、note 标注"AA · {账本名} · 应付给 {付款人}"），以保证账目对称（场景：朋友先垫，我事后还）。
5. IF 回写过程中任意一步失败 THEN 系统 SHALL 整体回滚事务，AA Ledger 保持 `settling` 状态，并向用户提示"结算未完成：{错误}"。
6. WHEN 完成结算 THEN AA 详情页 SHALL 切换为只读模式，顶部显示"已完成 · {completed_at 本地时间}"标签，底部不再展示"开始结算/完成结算"按钮，但保留"查看回写流水"快捷入口。
7. WHEN 用户在 `RecordsListView` 点击一条带 `aa_settlement_id` 的流水 THEN 系统 SHALL 在 `RecordDetailSheet` 中显示一个"AA 分账详情"链接行，点击后导航到对应 AA 账本详情。

### 需求 10：分账完成后的归档与查询

**用户故事：** 作为一名长期用户，我希望已完成的 AA 分账能被妥善归档、可被检索回看，以便在数月后还能查到当时的明细。

#### 验收标准

1. WHEN AA 分账列表的"已完成"Tab 被选中 THEN 系统 SHALL 列出所有 `status = completed` 且未软删除的账本，按 `completed_at DESC` 排序。
2. WHEN 用户进入已完成账本详情 THEN 系统 SHALL 展示完整快照：成员列表、流水列表、每位成员的应付/已付时间，全部只读。
3. WHEN 用户在已完成详情页点击"导出" THEN 系统 SHALL 生成一份 CSV（账本名、流水、成员、应付、状态）保存到系统分享面板（沿用 `DataImportExportView` 的导出能力）。
4. WHEN 用户在 AA 列表对已完成账本左滑选择"归档" THEN 系统 SHALL 写入 `Ledger.archived_at`，归档后默认从列表隐藏，可在"全部"Tab 切换"含归档"开关查看。

### 需求 11：异常情况处理

**用户故事：** 作为一名分账发起人，我希望在数据冲突、操作中断、状态异常等情况下系统能引导我恢复，以便不丢失本次分账数据。

#### 验收标准

1. WHEN 用户在结算中切到记录中 AND 当前已有部分成员标记为已支付 THEN 系统 SHALL 弹出二次确认："回退会清空所有支付确认状态，是否继续？"，确认后才执行。
2. IF 用户在结算成员配置过程中删除最后一位成员 THEN 系统 SHALL 提示"至少保留 1 位成员才能继续结算"，删除动作被拒。
3. IF 用户在 AA 账本详情页操作时账本被另一个设备同步修改（飞书多维表格回拉）THEN 系统 SHALL 在合并冲突时以 `updated_at DESC` 为准，并 toast "数据已更新"。
4. WHEN 系统在写入回写流水时崩溃或被强杀 THEN 应用下次启动 SHALL 通过 `aa_split.status = settling AND has_pending_writeback = 1` 标记侦测到未完成状态，并在用户进入该账本时提示"上次结算中断，是否继续？"。
5. IF 任意 AA 账本被软删除 THEN 与其相关的回写流水 SHALL 仍保留在个人账单中（数据完整性优先），但其 "AA 分账详情"链接 SHALL 显示"该分账已删除"。

### 需求 12：数据模型与持久化

**用户故事：** 作为一名开发者，我希望 AA 分账的所有持久化字段以最小侵入的方式扩展现有 Schema，以便平滑兼容历史数据并保持飞书同步能力。

#### 验收标准

1. WHEN 数据库升级到 v6 THEN 系统 SHALL `ALTER TABLE ledger ADD COLUMN aa_status TEXT`（取值 `recording / settling / completed`，对 `personal` 行可为 NULL）。
2. WHEN 数据库升级到 v6 THEN 系统 SHALL `ALTER TABLE ledger ADD COLUMN settling_started_at INTEGER` 与 `ALTER TABLE ledger ADD COLUMN completed_at INTEGER`，全部容忍 duplicate column。
3. WHEN 数据库升级到 v6 THEN 系统 SHALL 创建新表 `aa_member`：`id TEXT PK`、`ledger_id TEXT NOT NULL REFERENCES ledger(id)`、`name TEXT NOT NULL`、`avatar_emoji TEXT`、`status TEXT NOT NULL DEFAULT 'pending'`、`paid_at INTEGER`、`sort_order INTEGER NOT NULL DEFAULT 0`、`created_at INTEGER NOT NULL`、`updated_at INTEGER NOT NULL`、`deleted_at INTEGER`，并建唯一索引 `(ledger_id, name)`（不含软删行）。
4. WHEN 数据库升级到 v6 THEN 系统 SHALL 创建新表 `aa_share`：`id TEXT PK`、`record_id TEXT NOT NULL REFERENCES record(id)`、`member_id TEXT NOT NULL REFERENCES aa_member(id)`、`amount TEXT NOT NULL`（Decimal 字符串）、`is_custom INTEGER NOT NULL DEFAULT 0`、`created_at/updated_at/deleted_at`，并建索引 `(record_id)` 与 `(member_id)`。
5. WHEN 数据库升级到 v6 THEN 系统 SHALL `ALTER TABLE record ADD COLUMN aa_settlement_id TEXT`，用于把回写流水关联到 AA Ledger（容忍 duplicate column）。
6. WHEN 系统对 AA 相关写操作触发飞书同步 THEN 系统 SHALL 沿用现有 `SyncQueue` 流程，不引入新的同步通道；新增表/字段在 `RecordBitableMapper` 中按"忽略未识别字段"策略处理（V1 不阻塞）。
7. WHEN 用户清理飞书远端数据后冷启动 THEN AA 分账数据 SHALL 仍以本地 SQLite 为唯一权威来源，不发起破坏性回拉。

### 需求 13：UI/UX 一致性

**用户故事：** 作为一名 CoinFlow 用户，我希望 AA 分账页和现有页面在视觉、交互、动效、暗黑模式上完全一致，以便没有"被嫁接"的感觉。

#### 验收标准

1. WHEN 渲染 AA 分账页/详情页 THEN 系统 SHALL 全程使用 `NotionTheme` 颜色 / `NotionFont` 字号 / `NotionColor` 强调色，禁止引入新的色板。
2. WHEN 用户在 AA 列表上下滚动 THEN 系统 SHALL 沿用 `ThemedBackgroundLayer(kind: .stats)` 背景层与现有 `StatsHubView` 模块视觉一致。
3. WHEN 用户从底部 Tab 进入 AA 分账 THEN 入口 SHALL 在 `MainTabView` 现有"统计 → AA 分账"卡片基础上扩展（替换/升级现有 `StatsAABalanceView` 占位），不在主 Tab 新增新条目。
4. WHEN 用户在金额输入相关任意输入框 THEN 系统 SHALL 沿用 `AmountInputGate` 校验、`AmountTextFieldUIKit` 控件、键盘工具条（`KeyboardAccessoryToolbar`）。
5. WHEN 系统响应触觉反馈 THEN SHALL 沿用 `Haptics.tap()`，不新增其他触觉模式。
6. WHEN 用户切换暗黑模式 THEN AA 全部页面 SHALL 自动适配（颜色由 NotionTheme 通过 `colorScheme` 提供）。
7. WHEN 状态徽标渲染 THEN SHALL 用三种语义色：记录中 = `accentBlue`、结算中 = `accentOrange`、已完成 = `accentGreen`（从 NotionColor 取，不新建变量）。

### 需求 14：成功标准与验证

**用户故事：** 作为产品负责人，我希望本期上线后能通过一组明确的验证用例确认 AA 分账主流程闭环可用。

#### 验收标准

1. WHEN 端到端跑"创建 AA → 加 3 笔流水 → 进入结算 → 加 2 个成员 → 平均分摊 → 全部确认支付 → 完成" THEN 系统 SHALL 在不到 30 秒内完成全部交互，无崩溃、无脏数据。
2. WHEN 完成结算 THEN 个人账户的本月收入 SHALL 增加 `Σ 各成员应付`，月统计、年统计、桑基图均同步反映。
3. WHEN 用户冷启动 App THEN AA 列表数据 SHALL 在 1s 内完成首屏渲染（沿用现有 SQLite 查询性能基线）。
4. WHEN 飞书同步开启 THEN 至少 1 条 AA 流水 SHALL 在网络可用时被推送到飞书多维表格（`record_status = synced`）。
5. WHEN 跑现有单元测试套件 THEN 既有用例 SHALL 全部通过（不破坏 personal 路径）。

