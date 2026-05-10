# CoinFlow

一个 iOS 原生记账 App，把"拍一下 / 说一句"变成规整账单，并让你的账本同步到自己的飞书多维表格，方便在飞书侧做统计与长期归档。

- 平台：iOS 17+，SwiftUI，Xcode 15+
- 主题：Notion 风格（深色优先，低饱和，无 shadow 的 stroke 卡片）
- 数据：本地 SQLCipher 加密；云端同步到用户自己的飞书多维表格（明文上行以便在飞书侧查看/统计）
- 状态：Phase 1（M1–M9）已完成，进入真机打磨期

> 完整技术设计请看 [`CoinFlow-iOS-MVP技术设计.md`](./CoinFlow-iOS-MVP技术设计.md)
> 里程碑 / 决策日志请看 [`CoinFlow/PROJECT_STATE.md`](./CoinFlow/PROJECT_STATE.md)

---

## 功能

- **截图记账**：从相册选图或通过 Back Tap 触发，走「Vision OCR → 视觉 LLM → 规则兜底」三档路由；支持一张截图解析多笔账单，逐笔向导确认
- **语音多笔记账**：按住说话（左滑取消），本地 SFSpeechRecognizer 转写（强制 onDevice），LLM 拆分为多笔账单，逐笔向导中可回跳编辑
- **手动快速记账**：金额 + 分类 + 备注 + 日期，一个 Modal 搞定
- **流水列表**：List / Stack（扑克叠）/ Grid 三视图切换；月份 popover；搜索；滑删
- **分类管理**：14 个预设分类（不可删）+ 自定义；SF Symbols 图标 + Notion 调色板
- **云端同步**：飞书多维表格自建应用；增量推送 + 手动拉取；失败自动退避重试
- **隐私**：Face ID 冷启动锁 + 应用切换器模糊遮罩
- **Back Tap → Shortcuts → AppIntent** 唤醒链路（真"自动消费最新截图"V2 处理）

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
  - 任选 1 家填即可；推荐 ModelScope（免费额度 + 多模型可选）或 DeepSeek（中文最快）

详细填写指南见 [`CoinFlow/API_KEYS.md`](./CoinFlow/API_KEYS.md)。

### 4. 运行

Xcode 里选 Simulator 或真机 → ⌘R。

首次启动会走 `OnboardingView`，之后进入 `MainTabView`。

---

## 仓库结构

```
.
├── CoinFlow/                       # 主工程目录
│   ├── CoinFlow.xcodeproj          # Xcode 工程（由脚本生成，勿手动改）
│   ├── CoinFlow/                   # Swift 源码（App / Config / Data / Features / Theme / Security …）
│   ├── CoinFlowTests/              # XCTest 单元测试
│   ├── scripts/
│   │   ├── gen_xcodeproj.py        # 工程脚本化生成
│   │   └── feishu_e2e.swift        # 飞书全链路集成测试
│   ├── PROJECT_STATE.md            # 里程碑 / 决策日志
│   ├── API_KEYS.md                 # 密钥填写指南（.gitignore）
│   └── INTERACTION_{AUDIT,TEST_PLAN}.md
├── CoinFlow-iOS-MVP技术设计.md      # 技术设计文档
├── CoinFlowPreview/                # 设计稿截屏工具（可忽略）
├── design/                         # 80 张设计稿（设计验收基准）
└── README.md                       # 本文件
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

# 单元测试（5 个 suite）
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

---

## 安全与密钥

- `Config.plist` 和 `API_KEYS.md` 已在 `.gitignore`，不会被 Git 追踪
- 真实 API Key **禁止**出现在任何 `.swift / .md / 提交信息 / 聊天消息`
- 轮换 key：控制台撤销旧的 → 本地 `Config.plist` 填新值 → Xcode ⇧⌘K Clean → ⌘R Run

如果你曾经在任何位置（聊天、截图、日志、分支）暴露过真实 key，**请先去对应控制台轮换**，再继续开发/提交。

---

## FAQ

**Q：没配飞书能用吗？**
A：能。纯本地模式下所有记账功能都工作，只是设置页同步状态会显示"未配置"。

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

---

## License

See `LICENSE` if present, otherwise treat as private / all rights reserved.
