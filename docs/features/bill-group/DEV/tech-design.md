# 账单分组 · 技术设计

## 方案概述

在 `Record` 上新增 `billGroupId` 字段，新建 `BillGroup` 实体（SQLite 表 + Swift 模型），实现账单按事件/项目分组的完整链路：数据模型 → Repository → 新建/编辑 UI → 列表展示 → 统计聚合。

## 涉及文件

### 新增
| 文件 | 说明 |
|------|------|
| `Data/Models/BillGroup.swift` | BillGroup 模型（id/name/sortOrder/isDefault + 时间戳） |
| `Data/Repositories/BillGroupRepository.swift` | SQLiteBillGroupRepository（CRUD + 预设保护） |
| `Features/Stats/Views/StatsBillGroupView.swift` | 账单分组排行详情页 |

### 修改
| 文件 | 改动点 |
|------|--------|
| `Data/Database/Schema.swift` | 新增 `createBillGroup` DDL + `bill_group_id` 列 + 索引 |
| `Data/Database/Migrations.swift` | v8 migration：建表 + ALTER record + 回填 |
| `Data/Models/Record.swift` | 新增 `billGroupId` 字段 |
| `Data/Repositories/RecordRepository.swift` | SQL/columns/bindAll/decode 全部追加 billGroupId；RecordQuery 新增 billGroupId 筛选 |
| `Data/Seed/DefaultSeeder.swift` | 新增 `defaultBillGroupId` 常量 + 播种「日常消费」预设 |
| `Features/NewRecord/NewRecordViewModel.swift` | 新增 billGroup 选择状态 + 加载/保存逻辑 |
| `Features/NewRecord/NewRecordModal.swift` | 「账本」行下方新增「账单分组」选择行 |
| `Features/RecordDetail/RecordDetailViewModel.swift` | 新增 billGroup 编辑 + commit 写入 |
| `Features/RecordDetail/RecordDetailSheet.swift` | 新增账单分组选择行（可编辑模式下） |
| `Features/Records/RecordRow.swift` | `sourceText` → 优先显示账单分组名（个人账本）；AA 占位保持原逻辑 |
| `Features/Stats/StatsViewModel.swift` | 新增 `billGroupSlices` 派生数据 + `recomputeCardPreviews` 加 billGroup 卡 |
| `Features/Stats/StatsAnalysisHostView.swift` | `StatsAnalysisDestination` 新增 `.billGroup` case |
| `Features/Stats/Views/StatsMainView.swift` | 分类构成区域下方新增账单分组 Top5 区块 |
| `Features/Main/StatsHubView.swift` | `allCards` 新增「账单分组」卡片 |
| `Features/Records/RecordsListViewModel.swift` | 新增批量移动分组方法 |
| `Features/Records/RecordsListView.swift` | 批量模式下分组移动入口 |

## 数据流

```
DefaultSeeder.seedIfNeeded()
  → 创建 defaultBillGroupId = "default-bill-group"（name: "日常消费"）

NewRecordModal / RecordDetailSheet
  → BillGroupPickerSheet
  → selectedBillGroup 写入 Record.billGroupId

RecordRow
  → 查 billGroupId → BillGroup.name 展示在金额下方
  → AA 占位流水（sourceKind == .aaSettlement）保持原 sourceText

StatsViewModel.reload()
  → 按 billGroupId 聚合 → billGroupSlices
  → recomputeCardPreviews 生成 .billGroup 卡片预览

StatsBillGroupView
  → 读取 vm.billGroupSlices → 排行列表
```

## Schema 变更 (v8 Migration)

```sql
CREATE TABLE IF NOT EXISTS bill_group (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

ALTER TABLE record ADD COLUMN bill_group_id TEXT;

UPDATE record SET bill_group_id = 'default-bill-group'
WHERE bill_group_id IS NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_record_bill_group
    ON record(bill_group_id) WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_bill_group_name
    ON bill_group(name) WHERE deleted_at IS NULL;
```

## 风险评估

- **Schema migration 回填**：本地 SQLite 单表 < 10000 行，UPDATE 毫秒级完成，无风险
- **RecordRow.sourceText 替换**：AA 占位流水保持原逻辑，仅个人账本流水显示分组名
- **RecordRepository 改动面大**：columns/bindAll/decode/insert/update 全部同步追加，逐位核对防索引错位
- **与现有 BA 需求无冲突**：`docs/features/` 此前为空，无历史功能重叠
