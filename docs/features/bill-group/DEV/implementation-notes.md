# 账单分组 · 实现笔记

## 文件变更清单

### 新增 (4)
| 文件 | 说明 |
|------|------|
| `Data/Models/BillGroup.swift` | BillGroup 模型 |
| `Data/Repositories/BillGroupRepository.swift` | SQLiteBillGroupRepository CRUD |
| `Features/NewRecord/BillGroupPickerSheet.swift` | 分组选择 Sheet |
| `Features/Stats/Views/StatsBillGroupView.swift` | 分组排行详情页 |

### 修改 (14)
| 文件 | 改动 |
|------|------|
| `Data/Database/Schema.swift` | 新增 bill_group DDL + 索引 + tableNames |
| `Data/Database/Migrations.swift` | v7→v8；新增 v8 migration |
| `Data/Models/Record.swift` | 新增 billGroupId 字段 |
| `Data/Repositories/RecordRepository.swift` | SQL/columns/bindAll/decode 全更新；RecordQuery 新增 billGroupId 筛选 |
| `Data/Seed/DefaultSeeder.swift` | 新增 defaultBillGroupId + 播种 |
| `Features/NewRecord/NewRecordViewModel.swift` | billGroup 选择 + save() 写入 |
| `Features/NewRecord/NewRecordModal.swift` | 账单分组选择行 + sheet |
| `Features/RecordDetail/RecordDetailViewModel.swift` | billGroup 编辑 + isDirty/commit |
| `Features/RecordDetail/RecordDetailSheet.swift` | 账单分组行 + sheet |
| `Features/Records/RecordRow.swift` | sourceText → 账单分组名 |
| `Features/Voice/VoiceWizardViewModel.swift` | Record 构造追加 billGroupId |
| `Features/AASplit/AASplitService.swift` | 2 处 Record 构造追加 billGroupId |
| `Features/Stats/StatsViewModel.swift` | 新增 billGroupSlices + 卡片预览 |
| `Features/Stats/StatsAnalysisHostView.swift` + `StatsHubView.swift` + `StatsMainView.swift` | 路由/卡片/区块 |

## 设计决策

- AA 占位流水（sourceKind == .aaSettlement）保持 AA 相关展示，不显示账单分组名
- 默认分组 ID `default-bill-group` 固定，幂等播种
- 选中 AA 账本时不显示账单分组行，AA 流水始终写 defaultBillGroupId

## 后续迭代
- 账单列表批量移动流水到分组
- 账单分组管理页（创建/重命名/排序）
- 飞书同步字段映射
