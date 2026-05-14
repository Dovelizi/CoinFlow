# 实施计划

> 基于 [requirements.md](./requirements.md) 的可执行编码任务清单。每个任务都在前一任务的基础上递进，建议按顺序执行。

- [ ] 1. 扩展数据层 Schema 与模型（v6 数据库升级）
   - 在 `Data/Database/Schema.swift` 新增 `createAAMember`、`createAAShare` 建表 SQL 与对应索引
   - 在 `Data/Database/Migrations.swift` 新增 v6 Migration：`ALTER TABLE ledger ADD COLUMN aa_status TEXT / settling_started_at INTEGER / completed_at INTEGER`、`ALTER TABLE record ADD COLUMN aa_settlement_id TEXT`、创建 `aa_member` / `aa_share` 表，全部 `tolerateDuplicateColumn = true`
   - 在 `Data/Models/Ledger.swift` 扩展 `AAStatus` 枚举（`recording / settling / completed`）和 `aaStatus / settlingStartedAt / completedAt` 字段
   - 在 `Data/Models/Record.swift` 增加 `aaSettlementId: String?` 字段
   - 新建 `Data/Models/AAMember.swift`、`Data/Models/AAShare.swift` 两个纯 struct
   - _需求：12.1, 12.2, 12.3, 12.4, 12.5_

- [ ] 2. 实现 AA 仓库层（Repository）
   - 在 `Data/Repositories/LedgerRepository.swift` 增加 AA 相关查询：`listAA(status:includeArchived:)`、`updateAAStatus(id:status:settlingStartedAt:completedAt:)`，并扩展 columns / decode 以读写新增 3 列
   - 新建 `Data/Repositories/AAMemberRepository.swift`：`insert / update / softDelete / list(ledgerId:) / find(id:) / countByStatus(ledgerId:)`
   - 新建 `Data/Repositories/AAShareRepository.swift`：`upsert / deleteByRecordId / deleteByMemberId / listByLedger(ledgerId:) / sumByMember(ledgerId:memberId:)`
   - 在 `Data/Repositories/RecordRepository.swift` 扩展 `record` 列读写 `aa_settlement_id`，并新增 `findByAASettlementId(_:)`
   - _需求：12.1, 12.3, 12.4, 12.5_

- [ ] 3. 实现 AA 业务核心服务 `AASplitService`
   - 新建 `Features/AASplit/AASplitService.swift`，提供：
     - `createSplit(name:emoji:note:) throws -> Ledger`（需求 1）
     - `startSettlement(ledgerId:) throws`（需求 5.2，事务内更新状态 + 触发同步）
     - `revertToRecording(ledgerId:) throws`（需求 5.5、11.1，清空成员支付状态草稿）
     - `recomputeShares(ledgerId:) throws`（需求 7.2/7.3，按"金额 / 参与者数"重算 `aa_share`，参与者为 0 时归当前用户）
     - `setCustomShare(recordId:memberId:amount:) throws` + `validateCustomBalance(recordId:) -> Decimal?`（需求 7.4、7.5）
     - `markPaid / unmarkPaid(memberId:)`（需求 8.2/8.3）
     - `completeSettlement(ledgerId:) throws -> [Record]`（需求 9，事务内：更新 ledger 状态 → 为 paid 且应付>0 的成员写 default-ledger 收入流水 → 处理"非当前用户付款"的对称支出 → 触发 RecordChangeNotifier + SyncTrigger.fire）
   - 全程使用 `Decimal`，所有写库操作通过 `DatabaseManager.withHandle` 事务包裹
   - _需求：1.2, 1.5, 5.2, 5.5, 7.1-7.7, 8.2, 8.3, 9.1-9.5, 11.1, 11.2, 11.4_

- [ ] 4. 接入新建流水的"AA 分账"切换控件
   - 在 `Features/NewRecord/NewRecordViewModel.swift` 增加 `@Published var selectedAALedger: Ledger?`，把 `save()` 中的 `ledgerId` 改为 `selectedAALedger?.id ?? self.ledgerId`，并在选中 AA 时把 `payerUserId = AppState.currentUserId ?? "me"`
   - 在 `Features/NewRecord/NewRecordModal.swift` 顶部加"个人账户 / AA 分账"分段控件 + 已选 AA 徽标（`AA · {名称}`），点击徽标可切回个人或重新选择
   - 新建 `Features/AASplit/AALedgerPickerSheet.swift`：仅列出 `aaStatus = recording` 的账本（按 `created_at DESC`），空态时引导跳到创建 Sheet
   - 同样在 `VoiceWizardViewModel.confirmCurrent` / `finalizeAllToDatabase` 与 `CaptureConfirmView` 保存路径暴露 `aaLedgerId` 参数（默认 nil 走个人账户）
   - _需求：3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [ ] 5. AA 分账主页（列表 + 创建入口）
   - 新建 `Features/AASplit/AASplitListView.swift`：顶部 `StatsSubNavBar`、状态 Tab（全部 / 记录中 / 结算中 / 已完成）、列表卡片（名称 + 状态徽标 + 累计金额 + 流水数 + 最近时间）、空态、左滑归档/删除
   - 新建 `Features/AASplit/AASplitListViewModel.swift`：聚合 `LedgerRepository.listAA` + `RecordRepository.sumByLedger` + `AAMemberRepository.list`，订阅 `RecordChangeNotifier`
   - 新建 `Features/AASplit/AASplitCreateSheet.swift`：分账名称（1–30 字校验）+ 备注（≤140 字）+ emoji 封面，调用 `AASplitService.createSplit`
   - 在 `Features/Stats/Views/StatsAABalanceView.swift` 替换占位为"导航到 AASplitListView"的入口卡片，保留 V2 banner 文案体系；在 `Features/Main/StatsHubView.swift` 的 `destinationView(.aa)` 路由改指向新页面
   - 全程使用 `NotionTheme / NotionFont / NotionColor`，状态徽标按 accentBlue/accentOrange/accentGreen 三色
   - _需求：1.1, 1.3, 1.4, 2.1-2.6, 13.1-13.7_

- [ ] 6. AA 分账详情页（recording 阶段）
   - 新建 `Features/AASplit/AASplitDetailView.swift` + `AASplitDetailViewModel.swift`
   - 顶部 hero：账本名 + emoji + 状态徽标 + 累计金额 + 流水数
   - 流水列表：复用 `RecordRow` + `DateGrouping`，点击进入 `RecordDetailSheet`
   - 主操作"+ 添加流水"复用 `NewRecordModal(ledgerId: 当前 AA)`
   - 底部"开始结算"按钮：流水为空时置灰且文案"先添加至少一笔流水再结算"，点击后弹出二次确认 → `AASplitService.startSettlement`
   - _需求：4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 5.1, 5.2_

- [ ] 7. 结算中页面：成员管理 + 流水分摊
   - 在 `AASplitDetailView` 中增加"settling"模式，分三个区块（成员 / 分摊 / 支付确认）
   - 新建 `Features/AASplit/AAMemberManageSection.swift`：列表 + "+添加成员"输入框（昵称 1–20 字、同账本去重，从 `@AppStorage("aa.preview.nicknames")` 拉历史昵称建议）+ 长按"修改/删除"，删除时按需求 6.4/6.5/6.6 分支处理（无关联直接软删 / 有关联弹确认 + 重算 / 已支付置灰）
   - 新建 `Features/AASplit/AAShareEditSection.swift`：列出本账本支出流水，每行右侧渲染参与者芯片（默认全选），切换时调用 `AASplitService.recomputeShares`；点击"高级模式"展开按成员自定义金额输入（用 `AmountTextFieldUIKit`），实时显示差额红字
   - 流水编辑被锁：尝试编辑时 toast"账本已结算中，如需修改请先回退到记录中"
   - 顶部新增"回退到记录中"按钮，按需求 11.1 处理已支付成员的二次确认
   - _需求：5.3, 5.4, 5.5, 6.1-6.7, 7.1-7.7, 11.1, 11.2_

- [ ] 8. 支付确认 + 完成结算
   - 在 `AASplitDetailView` settling 模式下新增 `AAPaymentConfirmSection.swift`：成员行（头像 + 昵称 + 应付总额 + 状态 + 确认时间）、"标记已支付" / "撤销"按钮
   - 顶部进度条：`已支付 N / 全部 M  ¥已收 / ¥应收`
   - 应付额为 0 的成员自动判定 paid（需求 8.7）
   - 底部"完成结算"按钮：所有成员 paid 才启用，置灰时附文案"还有 N 位成员未确认支付"
   - 点击完成 → 调用 `AASplitService.completeSettlement`，成功后切换为 completed 只读态、刷新 `RecordsListView`、显示"已完成 · {本地时间}"标签 + "查看回写流水"快捷入口；失败时 toast 错误并保持 settling 状态
   - _需求：8.1-8.7, 9.1-9.6, 11.4_

- [ ] 9. 已完成态 + 回写流水反向链接 + 异常恢复
   - 在 `AASplitDetailView` 实现 completed 只读模式：成员 / 流水列表全部只读、隐藏所有结算操作按钮、提供"导出 CSV"按钮（沿用 `DataImportExportView` 工具方法生成账本名/流水/成员/应付/状态的 CSV 走系统分享）
   - 在 `Features/RecordDetail/RecordDetailSheet.swift` 增加"AA 分账详情"行：`record.aaSettlementId != nil` 时展示，点击导航到对应 `AASplitDetailView`；若 AA 已软删则展示"该分账已删除"灰态（需求 11.5）
   - 在 `Features/Records/RecordsListView.swift` 的行渲染上为带 `aaSettlementId` 的流水加一个小 AA 标签
   - 启动恢复：在 `App/AppState.swift` 启动序列检查 `ledger where aa_status = 'settling'` 的账本，进入对应详情页时弹出"上次结算中断，是否继续？"提示（需求 11.4）
   - _需求：9.6, 9.7, 10.1-10.4, 11.4, 11.5_

- [ ] 10. 飞书同步兼容 + 单元测试 + E2E 验证
   - 在 `Data/Sync/RecordBitableMapper.swift` 让其对 `aa_settlement_id`、新表 `aa_member` / `aa_share` 采用"忽略未识别字段"策略（需求 12.6），不阻塞既有同步
   - 新增单元测试：
     - `CoinFlowTests/AASplitServiceTests.swift`：分摊计算（均分 / 自定义 / 差额检测）、状态机转换（recording↔settling→completed）、completeSettlement 事务回滚
     - `CoinFlowTests/Migrations_v6_Tests.swift`：升级到 v6 后旧数据完整、可读写新字段、duplicate column 容错
   - E2E 用例（手动跑）：创建 AA → 3 笔流水 → 进入结算 → 加 2 个成员 → 平均分摊 → 全部确认支付 → 完成 → 回写流水出现在个人账单本月收入；冷启动 1s 内首屏；既有 personal 路径所有单测仍通过（需求 14.1-14.5）
   - _需求：12.6, 12.7, 14.1, 14.2, 14.3, 14.4, 14.5_

