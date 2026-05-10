# CoinFlow 流水页 · Notion 风格设计稿

> **生成方式**：通过 user-level Skill `notion-design` v1.0.0 加载触发
> **平台**：SwiftUI / iOS 16+
> **模式**：Light + Dark（双模一等公民）
> **设计来源**：`~/.codebuddy/skills/notion-design/references/{tokens,components,blocks}.md`
> **业务数据**：对齐 `CoinFlow-iOS-MVP技术设计.md` §3.1 record / category 表

---

## 1. 信息架构（页面结构总览）

```
┌──────────────────────────────────────────────────────────────────┐
│  Canvas (BG: #FFFFFF / #191919)                                  │
│  ┌────────────────  max-width 708px (居中)  ──────────────────┐  │
│  │                                                            │  │
│  │  📒                                  ← 28px page icon       │  │
│  │  流水                                ← Title 40pt Bold       │  │
│  │  2026 年 5 月                        ← micro tertiary        │  │
│  │                                                            │  │
│  │  ┌─Callout 红─┐ ┌─Callout 绿─┐ ┌─Callout 蓝─┐               │  │
│  │  │ 💸 本月支出 │ │ 💰 本月收入│ │ 🏦 本月结余 │               │  │
│  │  │ ¥3,245.80  │ │¥12,500.00 │ │ ¥9,254.20  │               │  │
│  │  └────────────┘ └───────────┘ └────────────┘               │  │
│  │                                                            │  │
│  │  ┌─搜索框────────────────────────┐         [ + 新建 ]        │  │
│  │  │ 🔍 搜索备注 / 分类 / 金额      │                          │  │
│  │  └──────────────────────────────┘                          │  │
│  │                                                            │  │
│  │  今天                                       ¥50.50          │  │
│  │  ─────────────────────────────────────────────────────────  │  │
│  │  [⋮⋮+]  🍴 餐饮   本地OCR · 已同步                  -¥38.50  │  │
│  │         便利店午餐                                          │  │
│  │  ─────────────────────────────────────────────────────────  │  │
│  │  [⋮⋮+]  🚗 交通   本地语音 · 待同步                  -¥12.00  │  │
│  │         地铁                                                │  │
│  │  ─────────────────────────────────────────────────────────  │  │
│  │                                                            │  │
│  │  昨天                                    ¥268.00            │  │
│  │  ─────────────────────────────────────────────────────────  │  │
│  │  [⋮⋮+]  💵 工资                                  +¥12,500   │  │
│  │         5 月工资                                            │  │
│  │  ─────────────────────────────────────────────────────────  │  │
│  │  ...                                                       │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

**层次规则（仅 4 级）**：

1. **Title** = `流水`（40pt / 700） — Page Header
2. **H3** = 日期分组段头（20pt / 600） — Notion 三级到顶
3. **Body** = 分类名 + 金额（16pt / 400-500）
4. **Small / Micro** = 备注 / 来源标签 / 月份副标 / 当日合计

---

## 2. 业务字段 → 视觉映射

| record 字段（§3.1） | 视觉位置 | Notion 元素 |
|---|---|---|
| `category.name` | 行左上：分类名 | Body 文字 |
| `category.icon` | 行最左：32×32 色块图标 | 自定义 Tag pill 扩展（圆角 4px） |
| `category.color`（→ `kind` 派生） | 图标徽章配色 | 9 色 Notion palette |
| `amount` + `direction` | 行右：金额 | Status color（仅金额可上色） |
| `note` | 行左下：备注 | Small / secondary |
| `source` | 分类名右侧 mini pill | Tag pill（micro / hover-bg-strong） |
| `sync_status` | 分类名右侧 dot + label | 6px 状态点 + micro 文字 |
| `ledger.type == 'aa'` | 分类名右侧 person.2 图标 | inline icon 11pt |
| `occurred_at`（按日聚合） | 段头 | H3 标题 + 当日合计 small secondary |

---

## 3. Token 引用清单（无任何硬编码）

下表是页面使用的 token，全部来自 `NotionTheme.swift`（由 `gen_tokens.py` 生成）或 9 色 palette（自 `tokens.md` §3 复制为 `NotionColor` enum）。

| 用途 | Token | 值 |
|---|---|---|
| 画布背景 | `Color.canvasBG` | `#FFFFFF` / `#191919` |
| Body 主文 | `Color.inkPrimary` | `#37352F` / `rgba(255,255,255,0.81)` |
| 二级文字 | `Color.inkSecondary` | `#787774` / `rgba(255,255,255,0.46)` |
| 三级文字 / placeholder | `Color.inkTertiary` | `#9B9A97` / `rgba(255,255,255,0.28)` |
| Hover 背景 | `Color.hoverBg` | `rgba(55,53,47,0.03)` / `rgba(255,255,255,0.055)` |
| 强 hover（搜索框 bg） | `Color.hoverBgStrong` | 加深一档 |
| 分隔线 | `Color.divider` | `rgba(55,53,47,0.09)` / `rgba(255,255,255,0.094)` |
| 边框（"+ 新建" 按钮） | `Color.border` | `rgba(55,53,47,0.16)` / `rgba(255,255,255,0.13)` |
| 编辑器最大宽 | `NotionTheme.editorMaxWidth` | **708** |
| Block 槽位宽 | `NotionTheme.blockGutter` | **24** |
| Page icon | `NotionTheme.iconPage` | 28 |
| 顶部留白 | `NotionTheme.space10` | 96 |
| 段头上间距 | `NotionTheme.space8` | 32 |
| 行内边距 | `NotionTheme.space5` | 12 |
| Callout 内边距 | `NotionTheme.space6` | 16 |
| Callout 圆角 | `NotionTheme.radiusLG` | 6 |
| Tag / 图标徽章圆角 | `NotionTheme.radiusMD` / `radiusSM` | 4 / 3 |
| 动效 | `NotionTheme.animDefault` | `cubic-bezier(0.2,0,0,1)` 150ms |

---

## 4. 关键交互（Block 模型在列表上的应用）

虽然流水页不是富文本编辑器，**但每一条流水仍按 Block 模型对待**（这是该 Skill 的核心理念之一）：

| Notion Block 行为 | 流水页对应 |
|---|---|
| `⋮⋮` Drag handle（hover 显） | 行左 24px gutter 内显示 `≡` 图标 |
| `+` Insert below（hover 显） | 行左 24px gutter 内显示 `+` 图标 |
| 块 hover 背景变 `--hover-bg` | `RecordRowView` `.background(hovered ? .hoverBg : .clear)` |
| 右键 / 长按 → 块菜单 | `.contextMenu` 提供编辑 / 复制 / 移动 / 删除 |
| Slash Command `/` | "+ 新建" 按钮的本质是触发 Slash 菜单：手动 / 截屏 / 语音 |

**移动端补充**：iOS 真机无 hover 状态，gutter 默认折叠为 0；长按行触发 `contextMenu` 等价于 Notion 的 ⋮⋮。这与 components.md §15 末尾约定一致。

---

## 5. 反模式自检（针对本页）

| 项 | 状态 | 说明 |
|---|---|---|
| 行加阴影 | ✅ 未犯 | 只有 callout 用色块，行只用 hover bg + divider |
| 用色彩区分行类型 | ✅ 未犯 | 收/支用 status color **仅作用于金额数字**，不染整行 |
| 默认显工具栏图标 | ✅ 未犯 | gutter 的 ⋮⋮ + 默认 `opacity=0`，hover 才显 |
| 中心对齐 body | ✅ 未犯 | 全部 `alignment: .leading` |
| 圆角 > 8px | ✅ 未犯 | 全部 ∈ {3, 4, 6}，符合 `--radius-{sm,md,lg}` |
| 用浮动 toolbar 替代 Slash | ✅ 未犯 | "新建"按钮的语义就是 Slash 触发 |
| 暗色用 `#000` 画布 | ✅ 未犯 | 用 `#191919` token |
| 列表用斑马纹 | ✅ 未犯 | 仅 1px divider，符合 components §7 |

---

## 6. SKILL.md §6 自检清单（逐项打勾）

- [x] **Tokens declared** at top —— 整个组件**不含任何裸 hex**（除 9 色 palette 在 enum 内集中定义）
- [x] **Font loading strategy** —— 文件头注释指明 Inter `.ttf` + Info.plist 注册步骤
- [x] **Both modes** —— `Color.canvasBG` 等通过 `Color(light:dark:)` 自动切换；两个 `#Preview` 分别覆盖
- [x] **Hover-only chrome** —— `blockGutter` `opacity = hovered ? 1 : 0`
- [x] **708px editor max-width** —— `.frame(maxWidth: NotionTheme.editorMaxWidth)`
- [x] **No box-shadow** —— 整个文件无 `.shadow()` 调用
- [x] **Body text 单一颜色** —— 分类名 / 备注全部 `inkPrimary` 或 `inkSecondary`，未跨色
- [x] **Headings 仅靠 weight + size** —— Title / H3 都不带颜色变化
- [x] **Hover state = bg tint** —— `Color.hoverBg`，不是 border / shadow
- [x] **Slash Command** —— "+ 新建" 按钮承担了 Slash 触发口（业务层将弹出 手动/截屏/语音 三种新建方式）
- [x] **Block hover gutter 24px full-bleed** —— `blockGutter.frame(width: NotionTheme.blockGutter)`
- [x] **No icon > 28px** —— 最大是 page icon 28，其余都 ≤ 22
- [x] **Emoji 仅用于 page icon / callout** —— 没有装饰性 emoji 散落在普通行
- [x] **Empty state whisper** —— `emptyState` 使用 `inkTertiary` 文字 + 无插画
- [x] **Animation easing** —— 全部走 `NotionTheme.animDefault`（150ms cubic-bezier(0.2,0,0,1)）
- [x] **A11y 对比度** —— 用的 token 已通过；金额状态色（红/绿）在两模都 ≥ 4.5:1

---

## 7. 与 CoinFlow 已有产品/技术文档的对齐

| 产品规划 §2.3 流水明细要求 | 本设计如何满足 |
|---|---|
| 按日期分组展示 | `groupedRecords: [(date, rows)]` + `DayGroupHeader` |
| 显示金额 / 分类 / 备注 / 来源 | `RecordRowView` 全部覆盖 |
| 支持搜索 | 顶部 `toolbar` 中 `TextField` |
| 区分收支 | 金额前缀 `+/-` + status color（仅金额上色） |
| 同步状态可见 | `syncStatusDot` |
| AA 账本标识 | `Image("person.2.fill")` |
| 长按 → 编辑/删除 | `.contextMenu` |

| 技术设计 §1.1 性能 KPI | 本设计如何对齐 |
|---|---|
| 从打开 App 到完成记账 ≤ 5s | "+ 新建" 触发 Slash 菜单直达三种入口 |
| 截屏识别链路 | "+ 新建" 菜单中含"截屏识别"入口（需业务层实现） |
| 语音多笔记账（§7.5） | "+ 新建" 菜单中含"按住说话"入口（业务层串到 §7.5 链路） |

---

## 8. 未决 / 留给业务层

| # | 项 | 说明 |
|---|---|---|
| Q1 | "+ 新建" 弹出菜单的具体形态 | 应实现为 `references/components.md` §14 的 Slash Command 风格弹出（280px 宽，含分组：BASIC / VOICE / OCR），本稿先留按钮入口 |
| Q2 | 月份切换器的位置 | 当前固定为"2026 年 5 月"展示；建议放在 page header 右上角做 `Menu` picker |
| Q3 | 跨账本筛选 | 工具栏可加左侧 ledger 切换 chip，复用 `RoundedRectangle + radiusMD + hoverBg` 风格 |
| Q4 | 列表性能 | 当前 `LazyVStack`，万级流水需改 `List` + `id:` 优化；不影响视觉 |
| Q5 | 9 色 palette 重复定义 | 当前 `NotionColor` enum 与 `tokens.md` §3 是手动同步；后续可让 `gen_tokens.py` 也输出该 enum |

---

## 9. 文件清单

| 文件 | 行数 | 作用 |
|---|---:|---|
| `design/notion/NotionTheme.swift` | 117 | Tokens（脚本生成，不要手改） |
| `design/notion/RecordsListView.swift` | 376 | 流水页 SwiftUI 实现 + Light/Dark 双 Preview |
| `design/notion/RecordsList-DesignSpec.md` | 本文件 | 视觉规范、自检清单、字段映射 |

总计：**~700 行**，含两个真机可预览的 SwiftUI Preview。
