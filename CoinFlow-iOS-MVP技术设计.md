# CoinFlow · iOS 技术设计文档

> **文档版本**：v2.0（2026-05-10 据 M9 真实落地重写）
> **受众**：iOS 开发者、技术评审、新成员 Onboarding
> **范围**：当前主干 Phase 1（M1–M9）已实现的真实技术形态
> **历史演进**：详见 `CoinFlow/PROJECT_STATE.md` 里程碑日志

---

## 目录

- [1. 产品与技术边界](#1-产品与技术边界)
- [2. 架构总览](#2-架构总览)
- [3. 工程目录](#3-工程目录)
- [4. 数据层](#4-数据层)
- [5. 云端同步（飞书多维表格）](#5-云端同步飞书多维表格)
- [6. 截图 OCR 链路](#6-截图-ocr-链路)
- [7. 语音多笔记账链路](#7-语音多笔记账链路)
- [8. UI / 主题系统](#8-ui--主题系统)
- [9. 安全与隐私](#9-安全与隐私)
- [10. 配置与密钥](#10-配置与密钥)
- [11. 构建与测试](#11-构建与测试)
- [12. 已知边界与未决项](#12-已知边界与未决项)

---

## 1. 产品与技术边界

### 1.1 做什么

- iOS 单端记账 App（SwiftUI，iOS 17+）
- **截图记账**：从相册选图 / Back Tap 触发，OCR + 视觉 LLM 解析为多笔账单
- **语音多笔记账**：按住录音，本地 SFSpeech 转写，LLM 拆分为多笔账单，逐笔向导确认
- **手动记账**：金额 + 分类 + 备注 + 日期 快速录入
- **本地加密存储**：SQLCipher，数据库密钥存 Keychain（`AfterFirstUnlockThisDeviceOnly`）
- **云端同步**：飞书多维表格（用户登录自己的飞书自建应用），明文上行以便在飞书侧直接查看 / 统计 / 汇总
- **隐私**：Face ID 冷启动锁 + 应用切换器模糊遮罩

### 1.2 不做什么

- 不做 Android / Web / Mac / Watch 端
- 不做会员订阅、广告、商业化
- 不做实时多端推送（飞书同步走"手动按钮拉取"，见 §5.4）
- 不做端到端加密（M2 曾做过，M9 因飞书需要明文查看而废弃）
- 不做 AA 账本、投资、资产负债 等 V2+ 模块
- 不做自建后端服务（飞书多维表格即 SoT；如无配置则纯本地）

---

## 2. 架构总览

### 2.1 分层

```
┌─────────────────────────────────────────────────────────┐
│ UI 层（SwiftUI + Notion 主题）                           │
│   Features/{Main,Records,NewRecord,RecordDetail,        │
│             Capture,Voice,Stats,Settings,Sync,          │
│             Categories,Onboarding,Common}               │
└─────────────────────┬───────────────────────────────────┘
                      │ @EnvironmentObject AppState
                      │ @StateObject ViewModels
┌─────────────────────▼───────────────────────────────────┐
│ 应用状态层                                                │
│   App/{AppState, CoinFlowApp, PrivacyShieldView,        │
│        BiometricLockView}                               │
│   Features/Common/MainCoordinator                       │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│ 领域与能力层                                              │
│   Features/Capture  : OCR Router / Receipt Parser /     │
│                       Quota / Screenshot Inbox          │
│   Features/Voice    : ASR Router / LLM Parser /         │
│                       Bills Prompt / Voice Session VM   │
│   Security          : BiometricAuthService              │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│ 数据层                                                    │
│   Data/Database     : SQLCipher + Schema / Migrations   │
│   Data/Repositories : Record / Category / Ledger /      │
│                       VoiceSession / UserSettings       │
│   Data/Models       : Record / Category / Ledger /      │
│                       VoiceSession                      │
│   Data/Sync         : SyncQueue / SyncTrigger /         │
│                       SyncLogger / RecordBitableMapper /│
│                       RemoteRecordPuller                │
│   Data/Feishu       : FeishuConfig / TokenManager /     │
│                       BitableClient                     │
│   Data/Seed         : DefaultSeeder（预设账本+14 分类）   │
│   Data/Storage      : ScreenshotStore                   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 端到端数据流

```
[用户手动新建]
    UI 输入 → NewRecordViewModel → RecordRepository.insert
        → broadcast + SyncTrigger.fire()
        → SyncQueue.tick → FeishuBitableClient.createRecord
        → markSynced + remoteId 回写

[用户截图记账]
    ScreenshotInbox / PhotoPicker → CaptureConfirmView
    → OCRRouter (Vision/LLM)
    → 若 LLM 已配置：BillsLLMParser.parse(source:.ocr)
        → OCRWizardContainerView（复用 VoiceWizardVM 的 wizard/summary）
    → 否则：CaptureConfirmView 单笔模式
    → 用户逐笔确认 / 跳过 / 回跳编辑
    → RecordRepository 批量 insert
    → 同步链路同上

[用户语音记账]
    VoiceRecordingSheet（按住 + 左滑取消）
    → AudioRecorder.m4a（NSTemporaryDirectory 即录即删）
    → ASRRouter (local SFSpeech / cloud stub)
    → BillsLLMParser.parse(source:.voice)
        → 规则引擎（默认）/ LLM（已配置时）
    → VoiceWizardViewModel 驱动 wizard/summary
    → RecordRepository 批量 insert
```

### 2.3 关键设计原则

| 原则 | 落地 |
|---|---|
| 金额永远用 `Decimal` | `record.amount: Decimal`；SQLite TEXT 列存 `String(describing:)` |
| 时间全存 UTC + 保留 IANA 时区 | `occurred_at: INTEGER` 存秒 ts；`timezone: TEXT` 存原始时区 |
| 软删除 | 所有业务表带 `deleted_at`；`voice_session` 例外（用 `status='cancelled'`） |
| SQL 100% 参数化 | 见 `Data/Database/SQLBinder.swift`；动态列名走白名单 |
| LLM / OCR / ASR 路由可降级 | Router 三档：local → api → llm；失败自动降级，不阻塞主流程 |
| 云端同步失败不阻塞 UI | SyncQueue 后台 actor + 指数退避；transient 自动重试，permanent 立即 dead |
| 密钥不进代码 | `Config.plist` gitignore；运行时 `AppConfig` 单例懒读 |

---

## 3. 工程目录

```
CoinFlow/                          # 主工程
├── CoinFlow.xcodeproj
├── CoinFlow/                      # Swift 源码
│   ├── App/
│   │   ├── CoinFlowApp.swift      # @main 入口
│   │   ├── AppState.swift         # 全局 ObservableObject，bootstrap 串行
│   │   ├── PrivacyShieldView.swift
│   │   └── BiometricLockView.swift
│   ├── Config/
│   │   ├── AppConfig.swift        # Config.plist 单例访问器
│   │   ├── Config.plist           # 真实配置（.gitignore）
│   │   └── Config.example.plist   # 模板，可 commit
│   ├── Data/
│   │   ├── Database/              # SQLCipher + Schema + Migrations + SQLBinder
│   │   ├── Feishu/                # 飞书自建应用 HTTP 客户端
│   │   ├── Models/                # Record / Category / Ledger / VoiceSession
│   │   ├── Repositories/          # Record / Category / Ledger / VoiceSession / UserSettings
│   │   ├── Seed/                  # DefaultSeeder
│   │   ├── Storage/               # ScreenshotStore
│   │   └── Sync/                  # SyncQueue / SyncTrigger / SyncLogger / Mapper / Puller
│   ├── Features/
│   │   ├── Capture/               # OCR / Receipt Parser / Quota / Photo Picker / Intent
│   │   ├── Categories/            # 分类管理
│   │   ├── Common/                # AmountFormatter / DateGrouping / MainCoordinator
│   │   ├── Main/                  # MainTabView / HomeMainView / StatsHubView
│   │   ├── NewRecord/             # 新建账单 Modal + VM + 分类 Sheet
│   │   ├── Onboarding/            # OnboardingView
│   │   ├── RecordDetail/          # 详情/编辑 Sheet + VM
│   │   ├── Records/               # 流水列表 + List/Stack/Grid 布局
│   │   ├── Settings/              # 设置 + Back Tap Setup + 数据导入导出
│   │   ├── Stats/                 # 分析主机 + 子图表集合（V2 实装）
│   │   ├── Sync/                  # SyncStatusView
│   │   └── Voice/                 # Voice Wizard 全链路（14 个文件）
│   ├── Resources/
│   ├── Security/                  # BiometricAuthService（Face ID）
│   ├── Theme/                     # NotionTheme / NotionColor / NotionFont
│   └── CoinFlow.entitlements
├── CoinFlowTests/                 # XCTest bundle（见 §11）
├── scripts/
│   ├── gen_xcodeproj.py           # 生成 pbxproj（全脚本化工程，避免 merge 冲突）
│   ├── feishu_e2e.swift           # 飞书全链路集成测试脚本
│   ├── feishu_dump.py             # 调试：拉取表格内容
│   └── feishu_e2e_wiki.py         # 调试：Wiki 模式
├── PROJECT_STATE.md               # 里程碑 / 决策日志
├── API_KEYS.md                    # 密钥配置指南（.gitignore）
└── INTERACTION_{AUDIT,TEST_PLAN}.md
```

工程文件通过 `scripts/gen_xcodeproj.py` 生成，添加新文件后必须在脚本里注册再跑一次。

---

## 4. 数据层

### 4.1 SQLite Schema（v1）

所有建表语句集中在 `Data/Database/Schema.swift`，按依赖顺序建表：`ledger → category → voice_session → record → quota_usage → user_settings`。

#### 4.1.1 核心表：`record`

| 列 | 类型 | 约束 / 说明 |
|---|---|---|
| `id` | TEXT PK | UUID，业务主键 = 飞书记录 |
| `ledger_id` | TEXT NOT NULL | FK → ledger.id |
| `category_id` | TEXT NOT NULL | FK → category.id |
| `amount` | TEXT NOT NULL | `Decimal` 字符串（禁用 Double） |
| `currency` | TEXT NOT NULL DEFAULT 'CNY' | ISO 4217 |
| `occurred_at` | INTEGER NOT NULL | UTC 秒 |
| `timezone` | TEXT NOT NULL | IANA 时区名 |
| `note` | TEXT | 账单描述（= 飞书主键列） |
| `payer_user_id` | TEXT | AA 账本留用（V2） |
| `participants` | TEXT | AA JSON array |
| `source` | TEXT NOT NULL | enum `RecordSource` |
| `ocr_confidence` | REAL | 非 manual 时有值 |
| `voice_session_id` | TEXT | FK → voice_session.id |
| `missing_fields` | TEXT | JSON array |
| `merchant_channel` | TEXT | 微信/支付宝/抖音/银行/其他（OCR 填） |
| `sync_status` | TEXT NOT NULL DEFAULT 'pending' | pending/syncing/synced/failed |
| `remote_id` | TEXT | 飞书 record_id |
| `last_sync_error` | TEXT | |
| `sync_attempts` | INTEGER NOT NULL DEFAULT 0 | 最大 5 |
| `attachment_local_path` | TEXT | OCR 截图落盘路径 |
| `attachment_remote_token` | TEXT | 飞书 file_token |
| `created_at` / `updated_at` | INTEGER NOT NULL | UTC 秒 |
| `deleted_at` | INTEGER | 软删除 |

**索引**：
- `idx_record_ledger_time(ledger_id, occurred_at DESC) WHERE deleted_at IS NULL` — 流水列表
- `idx_record_sync_status(sync_status) WHERE sync_status IN ('pending','failed')` — 同步队列

#### 4.1.2 其他表

- `ledger`：账本（M9 仅默认账本一条；多账本 V2）
- `category`：分类（14 预设 + 用户自定义；`is_preset=1` 不可删）
- `voice_session`：一次语音录音的生命周期日志（`recording → asr_done → parsed → completed/cancelled`）
- `quota_usage`：OCR/LLM 月度配额计数（`(month, engine)` 主键）
- `user_settings`：`key/value/updated_at`，存 Face ID 开关、引导完成标志等

### 4.2 数据库初始化

```swift
// DatabaseManager.swift 关键步骤
1. Keychain 取 256-bit 随机密钥（首次启动生成，accessibility = AfterFirstUnlockThisDeviceOnly）
2. sqlite3_open + PRAGMA key = x'<hex>'  // SQLCipher 第一条必须是 key
3. PRAGMA cipher_page_size = 4096
4. 检测旧未加密库 → 主动清理重建
5. 跑 Migrations（v0 → v1 建全表）
```

### 4.3 Repository 规范

- 所有 SQL **100% 参数化**；动态列名（orderBy / kind）走 `precondition` 白名单
- 所有 INSERT/UPDATE 通过 `SQLBinder` 统一 `Decimal ↔ TEXT`、`Date ↔ INTEGER`、`[String] ↔ JSON` 互转
- 软删除：业务表 `UPDATE … SET deleted_at = ?`；读取时默认 `WHERE deleted_at IS NULL`
- 同步状态 API：`markSyncing / markSynced / markFailed` 三方法**绝不污染 `updated_at`**（M8 关键修复）
- 变更广播：`RecordChangeNotifier.shared.broadcast()` 触发同步 + UI 刷新

---

## 5. 云端同步（飞书多维表格）

### 5.1 方案决策

| 维度 | 选择 | 说明 |
|---|---|---|
| 鉴权模型 | 自建应用 + `tenant_access_token` | 所有客户端共用 App ID/Secret |
| 表格创建 | 首次同步自动 `bitable.app.create` | 在应用 owner 的"我的空间"根目录 |
| 同步范围 | 仅 `record` 表 | Category/Ledger 同步到飞书无意义 |
| 软删除 | "已删除"复选框打勾 | 行不真删，用户可在飞书看完整历史 |
| 反向同步 | 手动按钮（SyncStatusView "从飞书拉取"） | 飞书无客户端级实时推送 |
| 加密 | **不加密**（明文上行） | 飞书要直接统计/查看/汇总 |

### 5.2 飞书多维表格 Schema

主键列：`账单描述`（Text，存 `record.note`，便于飞书侧一眼看懂）

其余 12 字段：`单据ID / 日期 / 金额 / 货币 / 收支 / 分类 / 来源 / 创建时间 / 更新时间 / 已删除 / 附件 / 渠道`

### 5.3 同步生命周期

```
[本地 insert/update/delete]
    ↓ RecordChangeNotifier.broadcast() + SyncTrigger.fire()
    ↓
  detached Task
    └─ SyncQueue.tick(defaultLedgerId)
         ├─ 配置检查：Feishu_App_ID / Secret 必填
         ├─ FeishuTokenManager.getToken()     （actor；过期前 5 min 刷新）
         ├─ FeishuBitableClient.ensureBitableExists()
         │    首次：创建 App + 默认表加 11 字段 + 清预置行
         │    Fast path：已缓存 app_token/table_id → 幂等补齐 owner 权限 + 新字段
         ├─ reconcileSyncingOnLaunch()        （复活上次 crash 残留的 syncing）
         ├─ pendingSync ORDER BY updated_at ASC （FIFO 真实修改时间）
         ├─ filter attempts < 5
         ├─ markSyncing
         └─ for each record:
              ├─ remoteId == nil  → createRecord(fields) → remoteId 回写
              ├─ remoteId != nil  → updateRecord(remoteId, fields)
              │                     （含软删：deleted=true）
              └─ deletedAt && remoteId == nil → markSynced 跳过
                 （建后立删且从未推过，无需再调云）
```

**重试策略**：
- 退避：`1, 2, 4, 8, 16, 32 s`，上限 60 s，±20% 抖动，最小 100 ms 保护
- `FeishuBitableError.isTransient == true`（网络 / 5xx / 429 / code 99991663 / 9499）→ `attempts + 1`，等下次 tick
- `!isTransient`（4xx / notConfigured / decode） → `attempts = maxAttempts` 立即 dead
- UI 点「全部重试」→ `resetDeadRetries()`

**结构化日志**（`SyncLogger`）：
```
[CoinFlow.Sync] level=INFO  phase=tick     | begin
[CoinFlow.Sync] level=INFO  phase=auth     | token ok
[CoinFlow.Sync] level=INFO  phase=fetch    | pending=5
[CoinFlow.Sync] level=INFO  phase=write    recordId=rec-abc | ok
[CoinFlow.Sync] level=FAIL  phase=write    recordId=rec-def attempts=3 code=network | 网络不可用
[CoinFlow.Sync] level=INFO  phase=tick     | end ok=4 fail=1
```

### 5.4 反向同步（手动拉取）

`RemoteRecordPuller.pullAll`：
1. `FeishuBitableClient.searchAllRecords`（200/页分页）
2. `RecordBitableMapper.decode(fields)` → `Record`
3. 本地 `id` 已存在 → 跳过（不覆盖本地未推送的编辑）
4. 本地缺失 → INSERT 到 SQLite（`syncStatus=.synced`）

UI 入口：`SyncStatusView` → "从飞书拉取" 按钮。

### 5.5 关键文件

| 文件 | 职责 |
|---|---|
| `Data/Feishu/FeishuConfig.swift` | App ID/Secret 读取；`app_token` + `table_id` UserDefaults 缓存 |
| `Data/Feishu/FeishuTokenManager.swift` | actor；`tenant_access_token` 获取 + 5 min 提前刷新 |
| `Data/Feishu/FeishuBitableClient.swift` | `ensureBitableExists / createRecord / updateRecord / searchAllRecords`；401/403 自动刷 token 重试 1 次 |
| `Data/Sync/SyncQueue.swift` | actor；tick / 状态机 / 退避 |
| `Data/Sync/SyncTrigger.swift` | detached Task 胶水层；`AppStateAccessor` 弱引用单例 |
| `Data/Sync/SyncLogger.swift` | 结构化日志 |
| `Data/Sync/RecordBitableMapper.swift` | `Record ↔ Feishu fields dict` 双向 |
| `Data/Sync/RemoteRecordPuller.swift` | 手动拉取 |

---

## 6. 截图 OCR 链路

### 6.1 两条入口

- **相册选图**：首页卡片 / 流水页右上相机按钮 → `PhotosPicker` → `CaptureConfirmView`
- **Back Tap**：iOS 系统「轻敲背面」→ Shortcuts 运行 `CoinFlowCaptureIntent`（AppIntent）→ 打时间戳剪贴板 → App 回前台 100 ms 后 `ScreenshotInbox.tryConsumePasteboardImage`

真"自动消费最新截图"涉及 `PHPhotoLibrary` 权限 + 自动清理，V2 处理。

### 6.2 OCR 三档路由（`OCRRouter`）

```
1. Vision 本地（免费，默认首档）
   ├─ 置信度 ≥ 0.6 且 amount 已识别 → 直接使用
   └─ 否则升级
2. 视觉 LLM（如配置 Qwen-VL / Doubao Vision / ModelScope / OpenAI）
   → BillsPromptBuilder(source:.ocr) 提示词
   → 严格 JSON mode 返回 {"bills":[...]}
   → BillsLLMParser 解析
3. 规则兜底（ReceiptParser）
   金额关键词：合计/实付/应付/总计/总额/实收/金额
   商户：首行非数字非日期的 3–25 字符短语
   时间：多格式（yyyy-MM-dd HH:mm / yyyy年MM月dd日 …）
```

配额：`QuotaService` 按月累计，LLM/OCR 档默认 30/100 次上限；RMW 两步事务 + `BEGIN IMMEDIATE` 防并发丢增量。

### 6.3 结果路径

- **LLM 已配置 + rawText 非空** → `OCRWizardContainerView`（复用 `VoiceWizardViewModel` 的 parsing / wizard / summary 链路，支持多笔）
- **否则** → `CaptureConfirmView` 单笔编辑（保留附件/渠道字段）

---

## 7. 语音多笔记账链路

### 7.1 端到端时序

```
VoiceRecordingSheet（半屏 .medium detent）
  按住 → AudioRecorder.start()  AAC-LC 16 k mono → NSTemporaryDirectory
  松开 → AudioRecorder.stop()   即用即删

ASRRouter
  local  : SFSpeechRecognizer 强制 onDevice，zh-CN
  cloud  : StubCloudASRBackend（真实后端已在 M6 计划里；阿里一句话已被 M6-Fix 整合移除）
  → asr_text（带 confidence）

BillsLLMParser.parse(source:.voice)
  LLM 已配置 → OpenAICompatibleLLMClient → 严格 JSON mode
                       ↳ 失败降级
  规则引擎    → 12 预设分类词典 + 中文数字"一千二" + 自然语言日期 + 未来日期拦截

VoiceWizardViewModel（7 phase：idle → recording → asr → parsing → wizard → summary → manual/failed）
  每 phase 切换 UPDATE voice_session

VoiceWizardStepView 逐笔向导
  进度点按钮 → jumpTo(index:) 回跳任意笔
  commitCurrentEdits / jumpTo 前先保存当前笔
  confirmedIds / skippedIds 记录状态，不立即入库

VoiceSummaryView → "查看流水" → finalizeAllToDatabase() 统一 insert
```

### 7.2 关键文件

| 文件 | 职责 |
|---|---|
| `Features/Voice/AudioRecorder.swift` | AVAudioRecorder 封装 + 按住/左滑手势 + delegate 兜底 |
| `Features/Voice/ASREngine.swift` + `ASRRouter.swift` | 协议 + 双档路由 |
| `Features/Voice/BillsPromptBuilder.swift` | §7.5.3 协议严格 JSON mode；`source: .voice / .ocr` 分文案 |
| `Features/Voice/BillsLLMParser.swift` | LLM 优先 + 规则降级；markdown fence 剥离；未来日期校验 |
| `Features/Voice/LLMTextClient.swift` | `OpenAICompatibleLLMClient` 统一 DeepSeek/OpenAI/Doubao/Qwen/ModelScope |
| `Features/Voice/VoiceWizardViewModel.swift` | 7-phase 状态机；`startFromOCRText` 入口供 OCR 多笔复用 |
| `Features/Voice/ParsedBill.swift` | 单笔结构 |

### 7.3 LLM JSON 协议

提示词要求返回**顶层对象**（`{"bills":[...]}`），兼容 OpenAI JSON mode "必须返回对象"约束。每笔字段：
`occurred_at / amount / direction / category / note / missing_fields`。

---

## 8. UI / 主题系统

### 8.1 主题

- 默认 **Notion 风格**（`Theme/NotionTheme.swift`）：深色优先、低饱和、`borderWidth = 0.5 pt`、无 shadow 的 stroke 卡片
- 字体：PingFangSC 封装在 `NotionFont.swift`，iOS 回退内建
- 色板：`NotionColor.swift` + `NotionTheme+Aliases.swift`（语义别名）
- `LiquidGlassATheme.swift` 为可选实验主题，默认未启用
- 全局 `.preferredColorScheme(.dark)`（文档 B10）

### 8.2 关键屏

| 屏 | 入口 | 关键交互 |
|---|---|---|
| `OnboardingView` | 首启 | 钱袋 64 pt + wordmark 36 pt + CTA |
| `MainTabView` | 主容器 | Home / Records / Stats Hub / Settings |
| `HomeMainView` | 首页 | 入口卡（照片/语音）直接承载 sheet；长按 quickActionOverlay |
| `RecordsListView` | 流水 | List / Stack（8→72 pt 扑克叠）/ Grid（2 列）；月份 popover；搜索 inline 动画 |
| `RecordDetailSheet` | 详情 | medium/large detent + dragIndicator；失焦即 commit 重置 `syncStatus=pending` |
| `NewRecordModal` | 新建 | 复用字段卡视觉 |
| `VoiceRecordingSheet` | 按住说话 | dynamic detents（录音半屏 / 其他全屏） |
| `CaptureConfirmView` / `OCRWizardContainerView` | OCR 结果 | 单笔 / 多笔分叉 |
| `CategoryListView` | 分类 | Notion 表头 + edit mode + 预设不可删 |
| `SyncStatusView` | 同步 | hero + queue 真 pending + "立即同步/全部重试/从飞书拉取" |
| `SettingsView` | 设置 | 账户 / 记账 / 同步与数据 / 隐私 / 关于（配置诊断） |
| `StatsHubView` | 统计 | 8 入口卡（V2 实装子图表） |

### 8.3 跨屏意图：`MainCoordinator`

- `MainCoordinator: ObservableObject` + `pendingAction` 枚举
- Records 消费后 `consume(_:)` 清空；避免 NotificationCenter 生命周期问题
- 主路径目前已改为"入口 View 直接承载 sheet"，Coordinator 保留供 tab 切换场景

---

## 9. 安全与隐私

| 能力 | 实现 |
|---|---|
| 本地加密 | SQLCipher v4 + Keychain 256-bit 随机密钥 |
| Face ID 启动锁 | `BiometricAuthService` + `BiometricLockView`；仅冷启动锁（切后台由模糊兜底） |
| 应用切换器模糊 | `PrivacyShieldView`（`scenePhase != .active` 时 `.ultraThinMaterial` + 锁图标） |
| 防并发弹窗 | `BiometricAuthService.inFlight: Task` 重入保护 |
| 生物开关 bootstrap 闪烁修复 | UserDefaults 镜像 `security.biometric_enabled_mirror`；AppState init 同步初值，DB bootstrap 前就生效 |
| 云端加密 | ❌ 不加密（M9 决策：飞书侧需要明文查看/统计） |

**威胁模型**：设备丢失场景由 iOS 系统锁屏 + Keychain `AfterFirstUnlockThisDeviceOnly` + SQLCipher 三层防护。云端账单由用户飞书账号自身安全负责。

---

## 10. 配置与密钥

### 10.1 Config.plist

位于 `CoinFlow/Config/Config.plist`，**已在 `.gitignore`**，必须手动从 `Config.example.plist` 拷贝并填真实值。首次 build 后由 `AppConfig.shared` 懒加载：缺文件 / 缺 key → 返空串（**不崩溃**），仅在调用对应能力时由调用方报错。

| 类别 | 最少配置 | 不配置的后果 |
|---|---|---|
| 飞书 | `Feishu_App_ID` / `Feishu_App_Secret` | 纯本地模式；无云端同步；"立即同步"显示未配置 |
| LLM 文本 | `LLM_Text_Provider = stub` | 语音/OCR 多笔走规则引擎（准确率降低） |
| LLM 视觉 | `LLM_Vision_Provider = stub` | OCR 第 3 档失效，退到 Vision 本地 + 规则解析 |

支持的 LLM 供应商：`deepseek / openai / doubao / qwen / modelscope / stub`，全部走 OpenAI 兼容协议（`LLMTextClient.OpenAICompatibleLLMClient`）。

### 10.2 AppConfig 读取策略

1. 优先 `Bundle.main.url(forResource:"Config", withExtension:"plist")`
2. fallback 到 `Config.example.plist`
3. 再 fallback 到空字典
4. `AppConfig.sourceDescription` / `configurationSummary()` 供 SettingsView 关于页可视化

### 10.3 密钥生命周期

- 真实 key **禁止**出现在任何 `.swift / .md / 注释 / Issue / 聊天消息`
- `.gitignore` 已覆盖 `Config.plist` 和 `API_KEYS.md`
- 轮换流程：控制台撤销 → 本地 Config.plist 填新值 → Clean Build（⇧⌘K）→ Run

---

## 11. 构建与测试

### 11.1 工程生成

```bash
cd CoinFlow
python3 scripts/gen_xcodeproj.py   # 全脚本化生成 pbxproj
open CoinFlow.xcodeproj
```

新增 / 删除 Swift 文件后必须在 `scripts/gen_xcodeproj.py` 的 `SOURCE_FILES` / `TEST_FILES` / `RESOURCE_FILES` 列表里同步，再跑一次脚本。

### 11.2 单元测试（XCTest · 5 suites）

位置：`CoinFlowTests/`

| Suite | 覆盖 |
|---|---|
| `SyncQueueBackoffTests` | 退避 0..7 + 抖动 + 100 ms 保护；shouldRetry 全分支 |
| `SyncStateMachineTests` | `FeishuBitableError.isTransient`；attempts 策略（transient+1 / permanent jump-to-max） |
| `FeishuTokenManagerTests` | `FeishuAuthError` 分类（network/5xx/4xx/apiError/notConfigured） |
| `RecordBitableMapperTests` | encode 基础/收入方向/nil note/软删/全 source；decode 完整/数组文本格式/软删/缺字段抛错 |
| `RecordRepositorySyncTests` | insert/update/delete 状态机 + mark*{Syncing,Synced,Failed} 不污染 `updated_at` + reconcile 复活 + pendingSync FIFO + resetDeadRetries |

运行：
```bash
xcodebuild -scheme CoinFlow -destination 'platform=iOS Simulator,name=iPhone 15' test-without-building
```

### 11.3 飞书端到端集成测试

独立 Swift 脚本（不进 CI 单元测试）：
```bash
swift scripts/feishu_e2e.swift
```
覆盖：获取 `tenant_access_token` → 创建多维表格 + 11 字段 → 写入 → 更新 → 软删 → 拉取全表验证。

### 11.4 持续验证

每次合并必须 ≥：
- `xcodebuild build -scheme CoinFlow` Exit 0
- `xcodebuild test-without-building` 全绿
- `read_lints` 0 diagnostics

---

## 12. 已知边界与未决项

### 12.1 M9 边界风险

- **多设备同步**：无实时推送；用户在 A 设备改，B 设备需手动"从飞书拉取"
- **飞书 token 失效**：99991663 / 401 / 403 自动刷新重试 1 次；持续失败走 5 次重试上限后 dead，用户在 SyncStatusView 点"全部重试"
- **多用户共用一张表**：当前自建应用模式所有客户端写同一张表。不适合公开发布的多租户产品；V2 可切 `user_access_token` + OAuth
- **app_token/table_id 缓存丢失**：UserDefaults 被清会触发再建一张新表，旧表孤儿化
- **默认表预置行**：`bitable.app.create` 自带空白模板行，pull 时"单据ID"为空会进 `decodeFailures` 计数（不影响功能）

### 12.2 V2 规划（不承诺时间点）

- 多账本 + AA 临时共享账本（`ledger.type=shared` 已预留字段）
- Stats Hub 8 个子图表实装
- 真"自动消费最新截图"（`PHPhotoLibrary` + 自动清理）
- 数据导入功能落地（M7 只做了导出）
- `CategoryListView` 的 drag-to-reorder（当前 edit 态仅视觉 handle）
- 字段级 a11y 补全（RecordDetailSheet）

### 12.3 历史决策留档

详见 `CoinFlow/PROJECT_STATE.md` 里程碑日志（M1–M9 每个里程碑的关键决策 / 验收后修复 / 边界风险均有记录）。

---

## 附录：文档 ↔ 代码索引

| 本文档章节 | 对应代码根 |
|---|---|
| §4 数据层 | `CoinFlow/Data/{Database,Models,Repositories}` |
| §5 云端同步 | `CoinFlow/Data/{Sync,Feishu}` |
| §6 OCR 链路 | `CoinFlow/Features/Capture` |
| §7 语音链路 | `CoinFlow/Features/Voice` |
| §8 UI | `CoinFlow/Features/*` + `CoinFlow/Theme` |
| §9 安全 | `CoinFlow/{Security,App/PrivacyShieldView,App/BiometricLockView}` |
| §10 配置 | `CoinFlow/Config` |
| §11 构建测试 | `CoinFlowTests/` + `scripts/gen_xcodeproj.py` |
| §13 LLM 账单总结 | `CoinFlow/Features/Stats/Summary` + `CoinFlow/Data/Feishu/FeishuBitableClient.swift`（summary bitable 部分） + `CoinFlow/Data/Models/BillsSummary.swift` + `CoinFlow/Data/Repositories/BillsSummaryRepository.swift` + `CoinFlow/Resources/Prompts/BillsSummary.system.md` |
---

## 13. M10 · LLM 账单总结

### 13.1 业务定位

每个周期开始时（周一 / 月 1 / 年 1/1），App 主动给用户推送一份"上一周期"的账单情绪化复盘——内容是 LLM 基于本地账单聚合数据生成的 markdown，渲染成浮窗 + 首页 banner，归档到飞书"账单总结"独立 bitable 永久留存。

不做：
- 跨设备数据互通（沿用 M9 决策：飞书无客户端实时推送）
- 用户编辑总结内容（generated content 不可改；如不满意可"重新生成"）
- 多语言（仅中文 prompt，prompt 改语言走代码层）

### 13.2 数据模型

`bills_summary` 表（v4 引入 / v5 修索引），见 `CoinFlow/Data/Database/Schema.swift::createBillsSummary`：

| 列 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `period_kind` | TEXT NOT NULL | "week" / "month" / "year" |
| `period_start` / `period_end` | INTEGER NOT NULL | 毫秒 epoch；周期边界由 `BillsSummaryAggregator.periodBounds` 计算 |
| `total_expense` / `total_income` | TEXT NOT NULL | Decimal 字符串（金额统一用 Decimal） |
| `record_count` | INTEGER NOT NULL | 本周期内未删除的账单笔数 |
| `snapshot_json` | TEXT NOT NULL | 喂给 LLM 的统计快照（重新生成时复用避免再扫表） |
| `summary_text` | TEXT NOT NULL | LLM 返回的完整 markdown |
| `summary_digest` | TEXT NOT NULL | ≤30 字核心洞察（用于喂下次 LLM 做对比） |
| `llm_provider` | TEXT NOT NULL | "modelscope" / "deepseek" / ... |
| `feishu_doc_token` / `feishu_doc_url` | TEXT | 飞书 bitable record_id + base URL |
| `feishu_sync_status` | TEXT NOT NULL | `pending` / `synced` / `failed` / `skipped` |
| `feishu_last_error` | TEXT | 飞书同步失败时的错误描述 |
| `created_at` / `updated_at` / `deleted_at` | INTEGER | 时间戳；软删走 `deleted_at` |

业务唯一键：`UNIQUE INDEX idx_bills_summary_period (period_kind, period_start)` —— v4 写成了 partial index（带 `WHERE deleted_at IS NULL`），SQLite `ON CONFLICT` 不能识别 partial → upsert 报错；v5 修复为完整 unique index（同时让 `BillsSummaryRepository.upsert` 在 `deleted_at IS NOT NULL` 命中时把 `deleted_at` 重置）。

### 13.3 端到端时序

```
[用户主动 / Scheduler 触发]
        └─ BillsSummaryService.generate(kind, force: false)
             ├─ 0. inflight[kind] 已存在 → 复用同一个 Task（同 kind 串行化）
             ├─ 1. 取最近 historyDigestCount=3 条历史 digest
             ├─ 2. BillsSummaryAggregator.aggregate(kind, reference, history)
             │     ↳ 周期边界 + 按 category/direction 聚合 + record_count
             ├─ 3. 阈值检查（force=false）：周≥3 / 月≥5 / 年≥12，不达标抛 .noData
             ├─ 4. BillsSummaryPromptBuilder.build → (system, user)
             │     ↳ system prompt 从 Resources/Prompts/BillsSummary.system.md 加载
             ├─ 5. BillsSummaryLLMClient.complete(system, user)
             │     ↳ OpenAI 兼容 / temperature=0.8 / max_tokens=4000 / stream=false
             │     ↳ content 为 null 时降级取 reasoning_content（modelscope Kimi-K2.5 兜底）
             ├─ 6. stripMarkdownCodeFence + extractDigestFromMarkdown（≤30 字）
             ├─ 7. SQLiteBillsSummaryRepository.upsert（按 kind+period_start 去重；保留旧 id 与 createdAt）
             ├─ 8. NotificationCenter.post(.billsSummaryDidGenerate, userInfo:["summary":...]) on @MainActor
             │     ↳ AppState init 内长驻 observer → @Published var pendingSummaryPush = summary
             │     ↳ HomeMainView .safeAreaInset 监听 → BillsSummaryPushBanner 出现
             └─ 9. Task.detached → BillsSummaryService.syncToFeishu(summaryId)
                   ├─ FeishuConfig 未配置 → status = .skipped
                   ├─ 已有 docToken → updateSummaryRecord
                   │   └─ 1254043/1254004/1254001/1254002 → 清缓存降级 createSummaryRecord
                   └─ 无 docToken → createSummaryRecord
                       └─ 写回 doc_token + doc_url + status=.synced
```

### 13.4 关键文件

| 文件 | 职责 |
|---|---|
| `Data/Models/BillsSummary.swift` | model + `BillsSummaryPeriodKind` + `FeishuSummaryStatus` enum |
| `Data/Repositories/BillsSummaryRepository.swift` | upsert / find / listRecent / softDelete / updateFeishuSync |
| `Data/Sync/SummaryBitableMapper.swift` | `BillsSummary ↔ [String: Any]` 双向；`encode` 抛 `SummaryBitableMapperError.invalidValue` |
| `Data/Feishu/FeishuBitableClient.swift` | 新增 `ensureSummaryBitableExists / createSummaryRecord / updateSummaryRecord` + `FeishuSummaryFieldName` 字段名常量 |
| `Data/Feishu/FeishuConfig.swift` | 新增 `summaryAppToken / summaryTableId / summaryBitableURL` 缓存 + `resetSummaryBitableCache` |
| `Features/Stats/Summary/BillsSummaryService.swift` | actor 编排（generate / syncToFeishu / upsertToFeishu）+ 通知广播 |
| `Features/Stats/Summary/BillsSummaryAggregator.swift` | 周期边界 + 聚合快照 + periodLabel("2026-W19" / "2026-05" / "2026") |
| `Features/Stats/Summary/BillsSummaryPromptBuilder.swift` | system + user prompt 拼装 |
| `Features/Stats/Summary/BillsSummaryLLMClient.swift` | OpenAI 兼容客户端；`content?` + `reasoning_content` 兜底 |
| `Features/Stats/Summary/BillsSummaryScheduler.swift` | App active 时检查"周/月/年是否到了节点"；UserDefaults 节流 |
| `Features/Stats/Summary/PromptResource.swift` | 加载 `Resources/Prompts/*.md` |
| `Features/Stats/Summary/Views/BillsSummaryListView.swift` | 设置页入口 + 调试推送按钮 + 历史按 kind 分组 |
| `Features/Stats/Summary/Views/SummaryFloatingCard.swift` | MarkdownUI 浮窗（自定义 Theme） |
| `Features/Stats/Summary/Views/BillsSummaryPushBanner.swift` | 首页 banner（✕ / 点击 3 次 / 10 分钟超时） |

### 13.5 Prompt 协议

system prompt 全文见 `Resources/Prompts/BillsSummary.system.md`，要点：
- 输出限定 markdown（标题 / 列表 / 表格 / emoji）
- 必含 5 个段落：核心洞察一句话 / 数字面板 / 类别 TOP 3 / 情绪化故事 / 下一周期建议
- 允许大量 emoji 自由发挥（避免每周复盘语气雷同）
- 历史 3 条 digest 作为前置 context，让 LLM 能"对比上次"

### 13.6 跨 tab 通信

```
用户在「设置 → 账单总结」点测试按钮
        ↓
service.generate (actor)
        ↓
upsert 落库
        ↓
NotificationCenter.post(.billsSummaryDidGenerate)  [@MainActor]
        ↓
AppState observer 收到 → @Published pendingSummaryPush = summary
        ↓
HomeMainView (EnvironmentObject) 监听 → safeAreaInset 出现 banner
```

为什么提到 `AppState` 而非 `HomeMainView` 内部 `@State`：`MainTabView` 用条件渲染切 tab 时会销毁子视图，`@State` 不保活；`AppState` 是单例 EnvironmentObject 跨 tab 保活。

Banner 关闭策略（M10-Fix5）：
- ✕ 按钮：1 次点击立即关
- 正文点击：每次点都触发 `onTap`（弹浮窗）；累计第 3 次时同时调 `onDismiss`
- 10 分钟自动关闭（`autoCloseTask = Task { sleep(600s); onDismiss() }`）
- `tapCount` 与计时器都在 banner 内部 `@State`，新 push 进来时通过 `.id(summary.id)` 整体重建归零

### 13.7 边界风险

- **LLM 配额**：每次 ~2k tokens / 年报 ~4k；用户连点测试按钮可能爆配额（actor 仅串行化同 kind，跨 kind 不限）
- **partial index 旧库残留**：v5 已 DROP 重建，冷启动一次即修复
- **首次升级飞书 bitable 自动创建**：与账单表共用 App ID/Secret，不增加新权限；表创建后 owner 协作权限自动加（`ensureBitableOwnerPermission`）
- **banner 内部状态不跨 tab 保活**：`tapCount` 与 10 min 计时在 `HomeMainView` 重建时归零；`pendingSummaryPush` 是保活的，所以重建后 banner 仍出现且重新计时——trade-off 接受

### 13.8 测试

- 单元测试 43/43 通过（M10 service 与 LLM 均为外部 IO，未加单测）
- M10 主路径靠"设置 → 账单总结 → 调试推送 + 切到首页看 banner"手工冒烟覆盖
- 飞书 bitable 写入靠 `BillsSummaryService.syncToFeishu` 路径覆盖（与 M9 账单 bitable 同构）

