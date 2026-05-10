---
name: CoinFlow-iOS-MVP-技术设计文档
overview: 为 CoinFlow（个人 + 好友 AA 场景的 iOS 记账 App）输出可直接落地的 MVP 技术设计文档，覆盖飞书 Bitable 作为唯一真相源的同步、Back Tap 截屏识别链路、三档识别配额路由、AA 临时共享账本、用户确认流程，附飞书 OpenAPI 示例与 iOS 代码骨架。
todos:
  - id: verify-baseline
    content: 使用 [subagent:code-explorer] 通读 `记账APP产品规划.md`，提取与本设计相关的基线条款（金额、时区、软删除、SQLite、Face ID、KPI），生成基线引用清单
    status: completed
  - id: verify-feishu-api
    content: 通过 web 检索飞书开放平台官方文档，确认 Bitable OpenAPI 鉴权方式、records CRUD 路径与限额、字段类型、协作权限粒度、Webhook 能力，输出已验证清单
    status: completed
  - id: verify-ios-api
    content: 通过 web 检索 Apple Developer 文档，确认 Back Tap → Shortcuts 链路、App Group 截图传递、Vision 中文 OCR、App Intents vs URL Scheme 取舍，输出已验证清单
    status: completed
  - id: write-skeleton
    content: 编写文档骨架：元信息、目标/非目标、与产品规划关系、架构总览（Mermaid 模块图 + 数据流图）、未验证假设声明
    status: completed
    dependencies:
      - verify-baseline
      - verify-feishu-api
      - verify-ios-api
  - id: write-data-and-sync
    content: 编写数据模型（SQLite DDL + Bitable 字段映射表）、飞书云端集成（鉴权 + CRUD HTTP 示例）、同步引擎（队列状态机 + 重试 + 错误码表）三章
    status: completed
    dependencies:
      - write-skeleton
  - id: write-capture-and-ocr
    content: 编写截屏识别链路（Back Tap → Shortcuts → App 时序图 + 配置步骤）、三档识别路由（决策树 + 配额管理）、用户确认流程状态机三章
    status: completed
    dependencies:
      - write-skeleton
  - id: write-collab-and-extension
    content: 编写 AA 临时共享账本（Bitable 协作 + 结算算法）、动态分类扩展（schema + UI 流程）、安全隐私（SQLCipher + Keychain + 风险声明）三章
    status: completed
    dependencies:
      - write-data-and-sync
  - id: write-code-skeletons
    content: 编写关键 Swift 代码骨架（Back Tap 接收、Vision OCR、飞书 API 客户端、同步队列、配额路由），每段 30-80 行，附 Apple/飞书 文档 URL
    status: completed
    dependencies:
      - write-capture-and-ocr
      - write-collab-and-extension
  - id: write-milestone-and-appendix
    content: 编写 MVP 4-6 周工程拆分里程碑表 + 附录（官方文档 URL 索引、Mermaid 全景图、未决问题清单）
    status: completed
    dependencies:
      - write-code-skeletons
  - id: self-check
    content: 执行文档质量自检（API URL 完整性、字段映射一致性、状态机不冲突、阈值量化、与产品规划基线无冲突），修复缺口后定稿
    status: completed
    dependencies:
      - write-milestone-and-appendix
---

## 产品概述

为 CoinFlow（个人 + 好友 AA 场景的 iOS 记账 App）输出一份可直接落地的 MVP 技术设计文档（Markdown 格式），作为现有 `记账APP产品规划.md` 的 V1 技术落地版。文档须覆盖飞书多维表格作为唯一云端真相源的同步机制、Back Tap 截屏识别链路、三档识别配额路由、AA 临时共享账本、用户确认流程，并附飞书 OpenAPI 调用示例与 iOS 关键 API 代码骨架，开发者可照着写代码。

## 核心功能（文档须涵盖的章节）

- **架构总览**：Mermaid 模块图与端到端数据流图
- **数据模型**：SQLite 本地表结构 + 飞书 Bitable 字段映射表
- **飞书云端集成**：OpenAPI 鉴权、Bitable CRUD、同步触发时机
- **同步引擎**：离线优先队列、重试退避、错误码处理（本地 SQLite 仅作离线缓存，飞书 Bitable 为 SoT）
- **截屏识别链路**：Back Tap → Shortcuts 自动截屏 → 唤起 App → OCR → 弹出确认页
- **三档识别路由**：本地 Vision 优先 → OCR API 限额 → LLM 付费兜底（含降级决策树与配额管理）
- **用户确认流程**：状态机（待确认 / 已确认 / 待同步 / 已同步 / 失败）
- **AA 临时共享账本**：基于 Bitable 多人协作 + 结算计算
- **动态分类扩展**：自定义收支分类的 schema 与 UI 流程
- **安全隐私**：Face ID、SQLCipher、Keychain 密钥管理
- **关键代码骨架**：Swift 片段（Back Tap Shortcut JSON、Vision OCR、飞书 API 客户端、同步队列）
- **工程拆分与里程碑**：4-6 周 MVP 拆解

## 已对齐基线（来自现有产品规划）

金额用 `Decimal`、时间存 UTC + 用户时区、软删除 + 30 天回收站、本地 SQLite、Face ID 锁、记账 ≤ 5 秒。

## 边界（不做）

不重写产品规划；不覆盖 Android / Web / Mac / Watch；不做会员订阅；不做社区；不做投资 / 信用卡深度模块；不含完整可运行项目，每模块代码骨架控制在 30-80 行。

## 文档形态与定位

- **产物**：单一 Markdown 文件 `CoinFlow-iOS-MVP技术设计.md`，与现有 `记账APP产品规划.md` 并列存放于工作目录根
- **受众**：iOS 开发者（直接照写代码）+ 技术评审
- **定位**：现有产品规划 V1 章节的技术落地版，不重写产品规划，作用域严格收窄
- **风格**：简体中文 + Mermaid 图 + 表格 + 代码块（Swift / JSON / HTTP）
- **首部声明**：标注 `[Contains Unverified Assumptions]`，列出"已验证 / 待验证"清单，每个外部 API 附官方文档 URL

## 技术栈（写入文档的选型）

| 层 | 选型 | 备注 |
| --- | --- | --- |
| 端 | iOS 16+ / Swift 5.9+ / SwiftUI + 少量 UIKit | 与产品规划对齐 |
| 本地存储 | SQLite + SQLCipher | 加密强制；用 GRDB.swift 作 ORM |
| 云端 SoT | 飞书多维表格 Bitable | 经 OpenAPI 读写 |
| 鉴权 | tenant_access_token（自建应用） | user_access_token 用于 AA 场景授权 |
| OCR | 本地 Apple Vision `VNRecognizeTextRequest`（中文） | iOS 14+ 支持简中 |
| OCR API | 腾讯 / 百度通用印刷体 OCR（任选其一） | 走配额路由第二档 |
| LLM 兜底 | 多模态视觉模型 API（如 GPT-4o / Gemini） | 付费，仅在置信度低 / 失败时调用 |
| 手势触发 | iOS Back Tap → Shortcuts → URL Scheme / App Intents | Back Tap 必须经 Shortcuts 中转 |
| 截屏传递 | Shortcuts 截屏 Action → 写入 App Group 共享容器 → App 启动读取 |  |
| 同步队列 | OperationQueue + Combine + 指数退避 | 离线优先 |
| 密钥管理 | iOS Keychain Services | 飞书 App Secret / OCR API Key |


## 实施策略

**分阶段编写文档**：第一阶段做严格的 web 检索验证（飞书 / Apple 官方文档），不预先编造任何接口签名；第二阶段基于验证结果填充章节；第三阶段补 Mermaid 图与代码骨架；第四阶段做内部一致性校验（如 SQLite 表与 Bitable 字段映射对得上、状态机与同步引擎不矛盾）。

**接口示例真实性原则**：所有飞书 OpenAPI 路径、参数、字段类型必须来自官方开发者文档；所有 iOS API 用法必须能在 Apple Developer 文档查到；不允许"看起来像"的伪代码。

## 关键决策与权衡

1. **飞书 Bitable 作为 SoT 而非自建后端**：个人 + 好友场景数据量小（百级到千级条目/月），Bitable 自带权限/分享/可视化，零运维。代价：受 Bitable QPS 与字段类型约束，无法做复杂事务。**应对**：本地 SQLite 缓存吸收写入抖动 + 同步队列序列化提交。
2. **本地 SQLite 仅缓存而非双写**：避免双向同步冲突复杂度。所有写操作先入本地 + 入"待同步队列"，由队列单向推送到 Bitable，Bitable 成功 ack 后本地标记 `synced`。**代价**：离线期间多端不一致由"最后同步时间"显式提示用户。
3. **Back Tap 链路必须经 Shortcuts 中转**：iOS 不允许 Back Tap 直接触发第三方 App。**应对**：文档提供完整 Shortcuts 配置步骤截图占位 + URL Scheme / App Intents 接收端代码。
4. **三档识别用配额路由而非自动降级**："配额路由" = 优先用免费档，免费档置信度低于阈值（如 < 0.6）或失败时升级；同时用户可在设置全局选档与单次覆盖。本地 Vision 命中率优先 → 节省成本。
5. **AA 共享账本基于 Bitable 协作权限**：临时账本对应一张独立 Bitable 表，活动结束归档。结算计算在客户端做（避免依赖飞书公式表达力）。

## 性能与可靠性要点

- **同步队列幂等**：每条记录带本地 UUID 作业务主键，飞书 Bitable 用 `record_id` 关联，重复提交用 UUID 去重
- **OCR 性能**：Vision 在主线程外执行，识别耗时目标 < 1s（本地档），文档中标注超时降级阈值（如 3s）
- **配额管理**：OCR API 月用量本地计数 + Keychain 持久化，超限自动转 LLM
- **退避策略**：飞书 99991400 限流码触发指数退避（1s → 2s → 4s → ... 上限 60s）
- **冷启动**：App Group 容器中检测到新截图 → 直接进入确认页，跳过首页（达成"打开到记账 ≤ 5 秒"）

## 安全与隐私要点（写入文档）

- **SQLCipher** 加密本地 DB，密钥存 Keychain
- **飞书 App Secret** 不出现在客户端代码；MVP 阶段用自建应用 + tenant_access_token，**承认风险**：Secret 存在客户端有泄露风险，文档明确标注"V2 需引入轻量后端代理换 token"
- **OCR / LLM API Key** 同上
- **截屏内容**：识别后立即从 App Group 删除，不持久化原图
- **Face ID** 进入 App 即锁

## 文件输出（仅一个新文件）

```
/Users/lemolli/CoinFlow/
├── 记账APP产品规划.md                    # [现有] 不修改
└── CoinFlow-iOS-MVP技术设计.md           # [NEW] 本次产出
```

**`CoinFlow-iOS-MVP技术设计.md` 内部章节结构**：

1. 文档元信息 + `[Contains Unverified Assumptions]` 声明 + 已验证 / 待验证清单
2. 目标 / 非目标 / 受众 / 与产品规划的关系
3. 架构总览（Mermaid 模块图 + 端到端数据流图）
4. 数据模型（SQLite DDL + Bitable 字段映射表）
5. 飞书云端集成（鉴权流程图 + Bitable CRUD HTTP 示例 + 同步触发时机）
6. 同步引擎（队列状态机 + 重试策略 + 错误码处理表）
7. 截屏识别链路（Back Tap → Shortcuts → App 启动 → OCR 时序图 + Shortcuts 配置步骤）
8. 三档识别路由（决策树 + 配额管理 + Swift 路由器骨架）
9. 用户确认流程（状态机 + UI 流程图）
10. AA 临时共享账本（Bitable 协作权限说明 + 结算算法）
11. 动态分类扩展（分类 schema + UI 流程）
12. 安全与隐私（密钥管理 + SQLCipher 配置 + 风险声明）
13. 关键代码骨架（Swift：Back Tap 接收 / Vision OCR / 飞书 API 客户端 / 同步队列 / 配额路由）
14. MVP 工程拆分（4-6 周里程碑表）
15. 附录：官方文档 URL 索引、Mermaid 全景图、未决问题清单

## 文档质量自检清单（写完后须过一遍）

- [ ] 所有飞书 API 路径与参数有官方文档 URL 引用
- [ ] 所有 iOS API 用法有 Apple Developer 文档 URL 引用
- [ ] SQLite 表字段与 Bitable 字段映射 1:1 对应无遗漏
- [ ] 同步队列状态机与确认流程状态机不冲突
- [ ] 三档识别路由的降级条件量化（具体置信度阈值、超时时间）
- [ ] 边界异常路径已点出（飞书限流、OCR 失败、截图丢失、Face ID 拒绝）
- [ ] 与现有产品规划基线（Decimal、UTC、软删除、SQLCipher、Face ID）无冲突

## Agent Extensions

### SubAgent

- **code-explorer**
- Purpose：探查工作目录现状、确认 `记账APP产品规划.md` 中与本设计相关的基线条款（金额精度、时区、软删除、SQLite、Face ID、5 秒 KPI），避免文档与现有规划冲突
- Expected outcome：输出"产品规划基线引用清单"，本设计文档中所有引用产品规划的地方有精确的章节锚点（如 `§2.1`、`§10.1`）

### MCP

- **tms_rd_mcp / iwiki_get_doc**
- Purpose：检索可能存在的飞书 Bitable OpenAPI 内部文档与 iOS Vision / Shortcuts 实践沉淀，补充官方文档外的踩坑经验
- Expected outcome：若有相关 iWiki 文档，作为参考来源补充到文档"参考资料"附录；无则跳过，不阻塞主流程