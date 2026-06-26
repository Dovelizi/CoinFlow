# CoinFlow

CoinFlow 是一个 iOS 原生记账 App，让"拍一下 / 说一句"变成规整账单，并支持将账本同步到自己的飞书多维表格，方便在飞书侧做统计与长期归档。

本地使用 SQLCipher 加密存储所有账单数据，数据库密钥存于 Keychain。云端同步走飞书多维表格自建应用，用户自带飞书账号即可使用，无需自建后端。

- **平台**：iOS 26+，SwiftUI（100%），Xcode 26+
- **主题**：Notion 风格（深色优先）+ 液态玻璃 + Animal Island（动物森友会），三套主题一键切换
- **数据**：本地 SQLCipher 256-bit AES 加密；云端明文上行至飞书多维表格
- **状态**：Phase 1（M1–M11）已全部交付，进入真机打磨期

> 完整技术架构请看 [`CoinFlow技术架构文档.md`](./CoinFlow技术架构文档.md)
> 里程碑 / 决策日志请看 [`CoinFlow/PROJECT_STATE.md`](./CoinFlow/PROJECT_STATE.md)

---

## 功能概述

### 三种记账方式

- **截图记账**：从相册选图或通过 Back Tap 触发，走「Vision OCR → 视觉 LLM → 规则兜底」三档路由；支持一张截图解析多笔账单，逐笔向导确认；自动识别金额、商户、日期
- **语音多笔记账**：按住说话（左滑取消），本地 SFSpeechRecognizer 转写（强制 onDevice，不上传云端），LLM 拆分为多笔账单，逐笔向导中可回跳编辑；支持"中午吃面 12.5，奶茶 18"这种自然语言
- **手动快速记账**：金额 + 分类 + 备注 + 日期，一个 Modal 完成；支持金额数字键盘 + 常用金额快捷输入

### 账单管理

- **流水列表**：List / Stack（扑克叠）/ Grid 三视图自由切换；按月筛选；搜索；滑删
- **账单详情**：点击任意账单展开详情 Sheet，支持编辑金额、分类、备注，修改即自动落库
- **分类管理**：14 个预设分类（不可删）+ 自定义分类；100+ SF Symbols 图标库（按 group 浏览）+ Notion 调色板 8 色可选

### AA 分账

- **分账账本**：创建 AA 分账单，添加成员，录入共享消费后自动计算每人应付金额
- **分账详情**：实时查看每个人的应付/已付/待付状态，支持逐笔确认结算

### 智能分析

- **统计面板**：首页 StatsHub 卡片 + 完整统计页，支持收支趋势图、分类饼图、词云、年度/月度/小时热力图
- **LLM 账单总结**：每周一 / 月初 / 年初自动生成上一周期的情绪化复盘（MarkdownUI 浮窗），首页 banner 推送；支持用户手动触发周报/月报/年报
- **总结归档**：总结自动同步到飞书"账单总结"独立多维表格，支持长期检索

### 云端同步

- **飞书多维表格**：增量推送 + 手动拉取；失败自动指数退避重试（最多 5 次）
- **纯本地模式**：不配飞书也能正常使用所有记账功能
- **附件归档**：OCR 截图同步到飞书素材库，云端 file_token 为唯一权威副本

### 多主题

- **Notion 风格**：深色优先、低饱和、stroke 卡片，项目默认主题
- **液态玻璃**：iOS 26+ Liquid Glass 毛玻璃效果
- **Animal Island（动物森友会）**：温暖大地色系 + 大圆角 pill 形 + 游戏按键立体感 + 柔和动效

### 安全与隐私

- **Face ID / Touch ID 启动锁**：冷启动强制验证
- **应用切换器模糊遮罩**：`scenePhase != .active` 时自动覆盖隐私层
- **本地数据全量加密**：SQLCipher 256-bit AES，密钥存 Keychain `AfterFirstUnlockThisDeviceOnly`
- **密钥不进代码**：API Key 走 `Config.plist`（已 `.gitignore`），运行时懒加载

### 其他

- **Back Tap 快捷唤醒**：iOS 系统设置 → 辅助功能 → 背部轻点 → Shortcuts → CoinFlow 截图记账
- **外观设置**：金额染色策略（自动 / 收入绿 / 支出红 / 全 mono）+ 分类色微调
- **数据导入导出**：支持 JSON 格式全量导出/导入

---

## 快速上手

### 1. 克隆仓库

```bash
git clone <your-fork-url> CoinFlow
cd CoinFlow
```

### 2. 生成 Xcode 工程

工程文件是脚本化生成的（避免多人改 pbxproj 冲突）：

```bash
cd CoinFlow
python3 scripts/gen_xcodeproj.py
open CoinFlow.xcodeproj
```

### 3. 配置密钥

拷贝示例配置：

```bash
cp CoinFlow/CoinFlow/Config/Config.example.plist CoinFlow/CoinFlow/Config/Config.plist
```

打开 `Config.plist`，按需填入：

- **飞书自建应用（可选，不填就是纯本地模式）**
  - 去 [飞书开放平台](https://open.feishu.cn/app) 创建企业自建应用
  - 加权限 `bitable:app`（以及 `wiki:wiki:readonly` 如果用 Wiki 模式）
  - 发布后复制 `App ID` / `App Secret` 填进去
  - 首次同步时 App 会自动在你飞书"我的空间"建一张名为"CoinFlow 账单"的多维表格
- **LLM Provider（可选，不填就走规则引擎）**
  - 支持 DeepSeek / Qwen / Doubao / ModelScope / OpenAI，都走 OpenAI 兼容协议
  - `LLM_Text_Provider` 管语音多笔解析；`LLM_Vision_Provider` 管截图 OCR 第 3 档
  - `LLM_Summary_Provider`（M10）管账单总结；推荐 modelscope Kimi-K2.5（长 context + 中文好）
  - 任选 1 家填即可；推荐 ModelScope（免费额度 + 多模型可选）或 DeepSeek（中文最快）

详细填写指南见 [`CoinFlow/API_KEYS.md`](./CoinFlow/API_KEYS.md)。

### 4. 运行

Xcode 里选 Simulator 或真机 → ⌘R。

首次启动会走 `OnboardingView`，之后进入 `MainTabView`。

---

## 仓库结构

```
.
├── CoinFlow/                              # 主工程目录
│   ├── CoinFlow.xcodeproj                 # Xcode 工程（由脚本生成，勿手动改）
│   ├── CoinFlow/                          # Swift 源码
│   │   ├── App/                           # 应用入口 + 全局状态
│   │   ├── Config/                        # 配置中心 + 密钥管理
│   │   ├── Data/                          # 数据层（Database / Models / Repositories / Sync / Feishu / Seed / Storage）
│   │   ├── Features/                      # 业务模块
│   │   │   ├── AASplit/                   # AA 分账
│   │   │   ├── Capture/                   # 截图 OCR 记账
│   │   │   ├── Categories/                # 分类管理
│   │   │   ├── Common/                    # 跨模块共享工具
│   │   │   ├── Main/                      # 首页 + Tab 导航
│   │   │   ├── NewRecord/                 # 新建账单
│   │   │   ├── Onboarding/                # 首次引导
│   │   │   ├── RecordDetail/              # 账单详情
│   │   │   ├── Records/                   # 流水列表
│   │   │   ├── Settings/                  # 设置 + 外观
│   │   │   ├── Stats/                     # 统计分析 + LLM 总结
│   │   │   ├── Sync/                      # 同步状态页
│   │   │   └── Voice/                     # 语音记账
│   │   ├── Resources/                     # Assets + LLM Prompts
│   │   ├── Security/                      # 生物认证
│   │   └── Theme/                         # 三套主题系统
│   ├── CoinFlowTests/                     # XCTest 单元测试
│   ├── scripts/
│   │   ├── gen_xcodeproj.py               # 工程脚本化生成
│   │   └── feishu_e2e.swift               # 飞书全链路集成测试
│   ├── PROJECT_STATE.md                   # 里程碑 / 决策日志
│   ├── API_KEYS.md                        # 密钥填写指南（.gitignore）
│   └── INTERACTION_{AUDIT,TEST_PLAN}.md
├── CoinFlow技术架构文档.md                  # 技术架构文档
├── CoinFlow-iOS-MVP技术设计.md              # 技术设计文档（M9 阶段重写）
└── README.md                              # 本文件
```

---

## 开发

### 新增文件

1. 在 Swift 源码里写代码
2. 在 `scripts/gen_xcodeproj.py` 的 `SOURCE_FILES` / `TEST_FILES` / `RESOURCE_FILES` 列表里注册路径
3. 重跑 `python3 scripts/gen_xcodeproj.py`

### 构建 / 测试

```bash
cd CoinFlow

# 构建
xcodebuild -scheme CoinFlow -destination 'platform=iOS Simulator,name=iPhone 15' build

# 单元测试（6 个 suite）
xcodebuild -scheme CoinFlow -destination 'platform=iOS Simulator,name=iPhone 15' test-without-building

# 飞书端到端集成测试（需要 Config.plist 真实密钥 + 网络）
swift scripts/feishu_e2e.swift
```

### 编码约定

- **金额永远用 `Decimal`**，SQLite TEXT 列存 `String(describing:)`，禁用 `Double`
- **SQL 100% 参数化**，动态列名（orderBy / kind）走 `precondition` 白名单
- **同步元操作不污染 `updated_at`**：`markSyncing / markSynced / markFailed` 不改该字段
- **软删除**：业务表 `deleted_at`；`voice_session` 例外（用 `status='cancelled'`）
- **主题 token**：颜色走 `NotionColor`，字体走 `NotionFont`，间距走 `NotionTheme.space*`，不要裸写 `Color(hex:)` / 固定 pt
- **不可变数据**：始终创建新对象，不修改现有对象

---

## 安全与密钥

- `Config.plist` 和 `API_KEYS.md` 已在 `.gitignore`，不会被 Git 追踪
- 真实 API Key **禁止**出现在任何 `.swift / .md / 提交信息 / 聊天消息`
- 轮换 key：控制台撤销旧的 → 本地 `Config.plist` 填新值 → Xcode ⇧⌘K Clean → ⌘R Run

如果你曾经在任何位置（聊天、截图、日志、分支）暴露过真实 key，**请先去对应控制台轮换**，再继续开发/提交。

---

## FAQ

**Q：没配飞书能用吗？**
A：能。纯本地模式下所有记账功能都正常工作，只是设置页同步状态会显示"未配置"。

**Q：为什么云端不加密？**
A：M9 决策。飞书多维表格的主要价值是让用户自己在飞书侧做统计/查看/汇总，加密会让这个价值归零。账单数据敏感度由用户自己的 iOS 设备锁 + iCloud 备份策略 + 飞书账号安全共同负责。

**Q：为什么用飞书而不是 iCloud / Firebase / 自建后端？**
A：
- iCloud：没有表结构化查询能力，用户无法直接在 iCloud 里做报表
- Firebase：Blaze 计费门槛 + 国内网络不稳 + E2EE ciphertext 与 GraphQL 强类型列冲突
- 自建后端：个人 App 运营成本过高，且安全压力大
- 飞书多维表格：用户自带账号、免运维、原生表格视图、免费额度够用

**Q：AppIntent / Back Tap 真能"自动消费最新截图"吗？**
A：目前只做了剪贴板打时间戳 + 100ms 回前台探测，真"自动选最新截图"涉及 `PHPhotoLibrary` 权限 + 自动清理，V2 处理。

**Q：多设备同步为什么要手动拉？**
A：飞书没有客户端级实时推送。你在 A 设备改了账单，B 设备打开 App 后去 `设置 → 同步状态 → 从飞书拉取` 即可。

**Q：账单总结是怎么触发的？看不到 banner 怎么办？**
A：调度器在 App 进入前台（`scenePhase == .active`）时检查"今天是不是周一/月 1/年 1/1"，按需触发对应 kind；UserDefaults 节流确保每天最多触发一次。如果想立刻测试：去`设置 → 账单总结 → 点周报/月报/年报按钮`，10–15 秒后浮窗出现，切到首页 tab 即可看到推送 banner（10 分钟内点击 3 次 / 点 ✕ / 等待超时任一关闭）。

**Q：账单总结的飞书归档在哪？**
A：与账单流水**不在同一张表**。首次成功生成总结时，App 会在你飞书"我的空间"自动建一张名为「CoinFlow 账单总结」的独立 bitable，含周期标签 / 总收入 / 总支出 / 一句话洞察 / 完整总结 / LLM 模型等 12 列。bitable URL 在 `设置 → 关于 → 配置诊断` 显示。

---

## License

See `LICENSE` if present, otherwise treat as private / all rights reserved.
