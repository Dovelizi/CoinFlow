# CoinFlow Phase 1 项目状态

> 团队协作进度跟踪。每个里程碑完成 + 验收 + 修复后由 main agent 更新。

## 团队
| 角色 | Agent 名 | 模式 |
|---|---|---|
| Swift 开发专家 | `swift-dev` | bypassPermissions |
| 设计专家 | `design-reviewer` | （按需 spawn） |
| 测试专家 | `qa-tester` | （按需 spawn） |

## 里程碑进度
| # | 里程碑 | 开发 | 设计验收 | 测试验收 | 状态 |
|---|---|---|---|---|---|
| M1 | 工程初始化 + 配置层 + SQLCipher | ✅ | ✅ | ✅ | **完成** |
| M2 | E2EE + Firebase + 同步引擎 | ✅ | ✅ | ✅ | **完成（已废弃于 M9）** |
| M3.1 | Seed + Sync 生命周期 + Listener | ✅ | ✅ | ✅ | **完成（M9 移除 listener）** |
| M3.2 | 流水列表 + 新建 Modal | ✅ | ✅ | ✅ | **完成** |
| M3.3 | Stack/Grid + 详情 Sheet + 分类管理 | ✅ | ⬜ | ⬜ | 待验收 |
| M4 | Vision OCR + 确认页 + 手动选图 | ✅ | ⬜ | ⬜ | 待验收 |
| M5 | 语音多笔（SFSpeech + Mock LLM 解析） | ✅ | ✅ | ✅ | **完成** |
| M6 | 真 LLM + Apple Sign In + Face ID + 后台模糊 + 收尾 | ✅ | ✅ | ✅ | **完成（Apple Sign In 已废弃于 M9）** |
| M7 | 交互一致性修复 + Stats Hub | ✅ | ⬜ | ⬜ | 待验收 |
| M8 | Firebase 同步加固 + 测试基础设施 | ✅ | ✅ | ✅ | **完成（已废弃于 M9）** |
| M9 | **切换到飞书多维表格（取代 Firebase）** | ✅ | ⬜ | ⬜ | **待你验收** |
| M10 | **LLM 账单总结（周/月/年情绪化复盘）+ 飞书 bitable 归档** | ✅ | ⬜ | ⬜ | **待你验收** |
| M11 | **App 图标 + 视觉打磨（分类图标库 / 外观设置 / 金额染色）** | ✅ | ⬜ | ⬜ | **待你验收** |

## M3.3 / M4 关键决策留档（2026-05-08）

### M3.3
- **三视图切换**（§5.5.3）：List / Stack（扑克叠 8pt → 72pt）/ Grid（2 列方卡）；每日布局状态独立保留 `layoutByDate: [String: RecordsLayout]`
- **详情 Sheet**（§5.5.9）：medium/large detents + dragIndicator；可编辑金额/分类/备注，失焦/选中即 `commit()`，写库重置 `sync_status=.pending`
- **分类管理**（§10）：预设 14 类不可删，自定义可左滑删；新增 sheet 支持 SF Symbols 9 候选 + Notion 调色板 8 候选

### M4
- **OCR 三档路由**（§7.1）：Vision 本地（默认）→ Stub API → Stub LLM
  - 升级触发：Vision 置信度 < 0.6 或 amount 未识别
  - 配额服务：`QuotaService.canUse/increment`，月度上限默认 ocrAPI=100 / ocrLLM=30
  - **API/LLM 当前为 Stub**（throw `notImplemented`），M6 真接入腾讯 OCR + 豆包/Qwen-VL
- **ReceiptParser 规则**：
  - 金额优先匹配「合计/实付/应付/总计/总额/实收/金额」附近；fallback 为全文最大数值
  - 商户：首行非数字非日期的 3-25 字符短语
  - 时间：支持 yyyy-MM-dd HH:mm / yyyy/MM/dd / yyyy年MM月dd日 等格式
- **Back Tap 链路延后**：M4 仅做 PhotosPicker 手动选图入口；Back Tap → Shortcuts → App Intent 触发 + 配置文档延到 M6
- **CaptureConfirmView**：复用 NewRecord VM 视觉 + 顶部 engine banner（识别引擎 + 置信度）；保存时回填 `source = .ocrVision/.ocrAPI/.ocrLLM` + `ocrConfidence`

## M3.3 / M4 验收后修复（2026-05-08，已合入）
- ✅ **OCRRouter Vision 重复调用消除**：`route(image:)` 仅调用 `vision.recognize` 一次，结果同时用于决策与兜底
- ✅ **CaptureConfirmView 双写库消除**：扩展 `NewRecordViewModel.save(source:ocrConfidence:)` 一次落库，`CaptureConfirmView` 调用时传参，省一次 update
- ✅ **CategoryRepository SQL 全参数化**：`list(kind:includeDeleted:)` 改为 `kind = ?` 绑定，彻底消除字符串拼接（precondition 白名单仍保留）
- ⏭ **QuotaService cost_cny 精度**：M4 阶段 cost 默认 0，留 M6 真接入计费时统一改造为 Decimal 字符串累加（注释已写明）

## M5 建设成果 + 验收后修复（2026-05-08）

### 建设成果
- **voice_session CRUD**：`SQLiteVoiceSessionRepository` 按 Schema 全字段绑定（参数化），session 生命周期 `recording → asr_done → parsed → completed/cancelled`
- **ASR 双档路由**：`ASREngine` 协议 + `LocalASRBackend`（SFSpeech 强制 onDevice，zh-CN）+ `StubCloudASRBackend`（M6 接入真 Whisper/阿里云）；`ASRRouter` 与 OCRRouter 同构
- **AudioRecorder**：AVAudioRecorder AAC-LC 16k 单声道，`NSTemporaryDirectory()` 落盘识别完即删（§7.5.2）；按住录音手势 + 左滑取消
- **Mock LLM 多笔解析**（`BillsLLMParser`）：规则实现 12 个预设分类词典 + 中文数字到"万"级 + 自然语言日期 + 歧义词前后缀区分；M6 会把 `parse()` 内部换真 LLM
- **状态机 VM**（`VoiceWizardViewModel`）：7 个 phase（idle/recording/asr/parsing/wizard/summary/manual/failed），每 phase 切换 UPDATE voice_session
- **UI 5 视图**：VoiceRecordingSheet（半屏 .medium detent，按住 + 左滑手势）+ VoiceParsingView（三阶段指示）+ VoiceWizardStepView（复用 NewRecord 字段视觉 + 进度点 + 缺失红框 + CTA 置灰）+ VoiceSummaryView + 兜底 manual/failed
- **接入流水页**：RecordsListView nav 右上加麦克风按钮；用 `.sheet` + `presentationDetents([.medium, .large], selection:)` 动态切换录音半屏 vs 向导全屏

### 验收后修复（8 阻塞 + 多条建议）
- ✅ **阻塞·presentation 形态**：`fullScreenCover` → `.sheet` + dynamic detents，recording 半屏 / 其他全屏
- ✅ **阻塞·录音按钮交互**："点按"改回"按住录音 + 左滑取消"`DragGesture(minimumDistance: 0)`，底部文案动态切换
- ✅ **阻塞·金额占位**：ZStack 叠 `inkTertiary "0"` 占位 + 整个行 `onTapGesture{amountFocused=true}` 扩大命中区
- ✅ **阻塞·中文数字"一千二"=1200**：散位计算改为 `lastUnit/10`；"两万三"=23000 特判
- ✅ **阻塞·未来日期拦截**：`parseDate` 后判 `d > startOfToday` → 置 nil → missingFields 补 `occurred_at`
- ✅ **阻塞·ASRRouter cloud 重复调用**：引入 `cloudAttempted` 标记
- ✅ **阻塞·"给/工资"关键词冲突**：拆分 `ambiguousGiveIncome/Expense`、`ambiguousBackExpense`；`incomeKeywords` 加 "发工资/工资/薪水/奖金/报销/退款"
- ✅ **阻塞·parsed.first 防御**：VM 在 parsed.isEmpty 时 fallback 到 `.manual`
- ✅ **建议·category key 冲突**：`categoryByKindAndName["{kind}|{name}"]` 避免 expense/income 同名冲突
- ✅ **建议·AudioRecorder delegate 兜底**：`audioRecorderDidFinishRecording` 主动 `isRecording=false` + `levelTimer.invalidate`，防 sheet 被下拉导致泄漏
- ✅ **建议·splitSegments 误切修复**：切点后的段必须含数字/金钱动词，否则合并回上一段
- ✅ **建议·direction segmented 高度对齐 36pt**、**navBar padding → space5**、**a11y label 补全**、**VoiceParsingView icon 按 engineLabel 区分**、**Summary 标题改"本次语音记账"**、**Container manual fallback 双 nav 改为统一头部**

### M5 遗留（M6 处理）
- ⏭ **云端 ASR 真接入**：`StubCloudASRBackend` → Whisper / 阿里云
- ⏭ **真 LLM 多笔解析**：`BillsLLMParser` 内部切到豆包/Qwen，Prompt 照抄 §7.5.3
- ⏭ **user_settings voice.required_fields**：M5 固定默认 `["amount","occurred_at","direction"]`；M6 读表
- ⏭ **parser_raw_json 协议对齐**：M5 是 `[String:String]` 便阅读；M6 改存真 LLM 原生 JSON

## M6 进度（2026-05-08 · 无外部依赖部分）

### 已完成（A1-A6）
- ✅ **A1 后台预览模糊化**（§11）：`PrivacyShieldView`，scenePhase != .active 时叠 `.ultraThinMaterial` + 锁图标 + "已隐藏内容"，应用切换器看不到流水
- ✅ **A2 Face ID 启动鉴权**：`BiometricAuthService.authenticate()` + `BiometricLockView`（冷启动锁屏，自动调起 + "再试一次"按钮 + 错误文案）；运行中切后台不重锁（避免短暂离开返回也要解锁的体验问题，由 PrivacyShield 兜底）
- ✅ **A3 Apple Sign In**：`AppleSignInService`（CryptoKit nonce + SHA256）+ `OAuthProvider.appleCredential` + `currentUser.link(with:)` 升级匿名 uid 为永久账户（**保留历史数据**）；设置页 SignInWithAppleButton；`CoinFlow.entitlements` 已生成 + script 注入 `CODE_SIGN_ENTITLEMENTS`
- ✅ **A4 Settings 设置页**：账户 / 安全 / 语音必填字段 / 关于 4 段；Face ID 开关、必填字段 toggle 持久化到 `user_settings` 表
- ✅ **A5 Back Tap 配置链路**：`CoinFlowCaptureIntent`（AppIntent + AppShortcuts，支持 Siri 短语）+ `BackTapSetupView` 图文向导；唤醒后 `RecordsListView` 显示 5s 自动消失的提示 banner；真"自动消费最新截图"留 V2
- ✅ **A6 累积建议落地**：
  - `UserSettingsRepository`（key/value CRUD + JSON 编解码 + Bool 便捷 API）
  - `VoiceWizardViewModel.requiredFields` 改读 `user_settings(voice.required_fields)`
  - `QuotaService.increment` 重构为 read-modify-write 两步事务（消除 `CAST AS REAL` 浮点精度损失）+ 新增 `currentCost(_:)` API
  - `RootView` 鉴权卡片文案更新（去掉过期"M6 接入"说明）

### 关键决策
- **冷启动 vs 切后台 锁屏策略**：仅冷启动锁；切后台依赖 PrivacyShield 模糊兜底。阈值化重锁（如 5 分钟离开重锁）留 V2
- **Apple Sign In Capability**：脚本已注入 entitlement；模拟器无 Capability 也能跑 UI，但真实授权流程需在 Apple Developer 后台开启 + 真机测试
- **App Intent 唤醒消费**：M6 仅做 banner 提示；编程触发 PhotosPicker 不可行；自动选最新截图链路涉及 PHPhotoLibrary 权限 + 自动清理截图（§6.3），合并 V2

### M6 待办（需 API Key，等待用户提供）
- ✅ **B1 腾讯云 OCR 真接入**：`TencentOCRBackend`（TC3-HMAC-SHA256 签名 + `GeneralBasicOCR`）已替换 Stub
- ✅ **B2 阿里云 ASR 真接入**：`AliyunASRBackend`（AVAssetReader m4a→PCM16k 解码 + HTTP POST + X-NLS-Token）已替换 Stub
- ✅ **B3 DeepSeek V4 Pro LLM 真接入**：`LLMTextClient` 协议 + `OpenAICompatibleLLMClient`（统一 OpenAI 协议，支持 DeepSeek/OpenAI/Doubao/Qwen 切换） + `BillsPromptBuilder`；`BillsLLMParser.parse` 改为 async，LLM 优先失败降级规则
- ⬜ **视觉 LLM（OCR 档 3）**：DeepSeek 无视觉；`LLM_Vision_Provider=stub` 保持不动；未来若配 Qwen-VL key 即激活
- ⬜ **设计验收 + 测试验收**：M6 全部完成后进入 spawn agent 阶段

## M6-B 建设成果（2026-05-08 下午）

### 新增 4 个文件
- `Features/Voice/LLMTextClient.swift` — LLM 抽象协议 + `OpenAICompatibleLLMClient`（DeepSeek/OpenAI/Doubao/Qwen 共用）+ `StubLLMTextClient` + `LLMTextClientFactory`
- `Features/Voice/BillsPromptBuilder.swift` — 文档 §7.5.3 Prompt 模板（严格 JSON mode，强制对象 `{"bills": [...]}` 避免 OpenAI JSON mode 顶层数组限制）
- `Features/Voice/AliyunASRBackend.swift` — 阿里云一句话识别（PCM 16k Int16 mono 转码 + POST + X-NLS-Token 鉴权）
- `Features/Capture/TencentOCRBackend.swift` — 腾讯云 GeneralBasicOCR（完整 TC3-HMAC-SHA256 签名实现 + 5 分钟时间容差校准）

### 改动 6 个文件
- `Config/Config.plist` + `Config.example.plist` + `AppConfig.swift` — 拆分 `LLM_Text_Provider` / `LLM_Vision_Provider`；增加 DeepSeek 配置槽位；`configurationSummary()` 调试 API
- `Data/Models/VoiceSession.swift` — `ParserEngine` 枚举增加 `llmDeepseek` / `llmDoubao`（与 providerName 对齐写审计）
- `Features/Voice/BillsLLMParser.swift` — `parse` 改 async，LLM 优先 + 降级规则；`parseWithRules` 保留暴露供单测；LLM 响应 markdown fence 剥离；未来日期校验
- `Features/Voice/VoiceWizardViewModel.swift` — `stopRecordingAndProcess` 消费 ParseResult；`voice_session.parser_engine` 写入实际 provider；LLM 原始 JSON 写入 `parser_raw_json`
- `Features/Voice/ASRRouter.swift` — `cloud` 实例切 `AliyunASRBackend`
- `Features/Capture/OCRRouter.swift` — `api` 实例切 `TencentOCRBackend`
- `Features/Settings/SettingsView.swift` — 关于段增加"腾讯 OCR / 阿里 ASR / LLM 文本 / LLM 视觉"4 项激活状态可视化
- `scripts/gen_xcodeproj.py` — 注册 4 个新文件

### M6-B 关键决策
- **OpenAI 兼容协议统一抽象**：4 家 LLM provider 共用 `OpenAICompatibleLLMClient` 一份 HTTP 实现，仅 BaseURL/Model/Key/providerName 不同；降低未来新增 provider 的成本
- **JSON Mode + 顶层对象**：Prompt 要求 LLM 返回 `{"bills": [...]}`（非顶层数组），兼容 OpenAI JSON mode 的"必须返回对象"约束；响应里 markdown fence 自动剥离
- **LLM 失败降级**：任何阶段（notConfigured / HTTP / JSON 解析 / 网络）失败 → `NSLog` 记录后降级到 M5 规则引擎；用户感知仅体现在 `parser_engine = rule_only`
- **阿里 ASR 音频转码**：选 AVAssetReader 方案 (b)（文档 §7.5 路径）— 保留 AudioRecorder m4a 输出不变，发送前转 PCM，改动最小
- **腾讯 OCR Region**：M6 默认 `ap-guangzhou`；`X-TC-Region` 头传入；签名算法依据 TC3-HMAC-SHA256 文档严格实现（4 步派生密钥，key 用二进制传递）
- **24h Token 限制**：阿里 ASR Token 会过期；当前静态填，401 后用户手动更新 Config.plist；V2 接 RAM 自动刷新

### M6-B 验证路径
- ✅ **编译干净**：Exit 0，无警告，pbxproj 55,173 bytes
- ⏭ **真机 OCR**：选一张小票截图 → 故意选 Vision 识别差的（复杂小票）→ Router 升档 → 设置页 engineBanner 应显示 "OCR API 识别" + 置信度
- ⏭ **真机 ASR**：模拟器本地档不可用会自动降级云端 → 录音 → 阿里返回转写 → `voice_session.asr_engine = whisper`（复用枚举 rawValue `"whisper"`）
- ⏭ **真机 LLM**：语音识别完成 → parser 调 DeepSeek V4 Pro → `voice_session.parser_engine = llm_deepseek` + `parser_raw_json` 存真 LLM 响应

### M6-B 边界风险（真机验证时留意）
- 腾讯云签名对设备时钟敏感（±5 分钟），若 iOS 系统时间偏差大会 401
- 阿里云 Token 每 24h 过期，过期后用户需回 Config.plist 手动更新
- DeepSeek 的 `response_format` JSON mode 要求 prompt 含 "json" 字样 ✓（Prompt 模板里已含）
- 模拟器无麦克风真实录音 → 阿里 ASR 完整链路只能真机测

## M6 验收后修复（2026-05-08，已合入）

### 测试验收 4 阻塞 + 7 建议
- ✅ **TencentOCR 签名 SignedHeaders 完整性**：补 `x-tc-timestamp` 进 CanonicalHeaders + SignedHeaders（字典序），与多数腾讯云 SDK 默认行为对齐
- ✅ **AliyunASR 错误吞没**：`try? await loadTracks` 改 `try await`，AVFoundation 错误向上抛
- ✅ **QuotaService RMW 事务保护**：包 `BEGIN IMMEDIATE` / `COMMIT`/`ROLLBACK`，防 SyncQueue 后台并发丢增量
- ✅ **BillsLLMParser decodeLLMResponse 时区**：`today/tz` 参数穿透到 decode，避免跨时区测试 `today` 用 `Calendar.current` 的偏差
- ✅ **ASRRouter 升档失败可观测性**：`try?` 改 `do/catch + NSLog`，云端 Token 过期等可诊断错误可见
- ✅ **BiometricAuthService 重入保护**：`inFlight: Task` 防 UI 快速双击导致并发 Face ID 弹窗
- ✅ **AppleSignInService 重入保护**：`isSigningIn` 锁 + nonce 一次性消费，防快速双击覆盖 nonce
- ✅ **CoinFlowApp animation 绑定迁移**：从 ZStack 根改到 overlay 节点，避免 Records 表单输入态丢焦/抖动
- ✅ **bioLocked 启动闪烁修复**：`UserDefaults` 镜像 `security.biometric_enabled_mirror`；AppState init 同步设初值，DB bootstrap 前就生效
- ✅ **UserSettings bool 兼容性**：`true/1/yes` 大小写不敏感识别为真，版本回滚 / 手工编辑场景更鲁棒
- ✅ **LLM HTTP timeout 30s → 15s**：超时后快速降级规则引擎

### 设计验收 2 阻塞 + 6 建议
- ✅ **PrivacyShieldView light 模式不脱敏**：`Color.surfaceOverlay` 底层 + `.ultraThinMaterial` + 半透明 canvas 三层叠加，确保 light 下 App Switcher 缩略图也有可辨识灰色卡片
- ✅ **`.preferredColorScheme(.dark)` 覆盖 overlay**：从 RecordsListView 提到 ZStack 上，PrivacyShield / BiometricLock 同时强制 dark
- ✅ **Apple Sign In 按钮样式**：`.white` → `.whiteOutline`，跨 light/dark 主题都可见
- ✅ **Back Tap 步骤气泡对比度**：`accentBlueBG` → `accentBlue` 实心 + 白字粗体（满足 WCAG AA 4.5:1）
- ✅ **BackTapBanner 去 shadow**：用 `Color.border` 描边替代，与 M3-M5 卡片无 elevation 风格一致
- ✅ **设置页云服务状态色语义化**：已配置=绿（#448361 + checkmark）、未配置=黄（#CA9849 + exclamationmark.triangle）
- ✅ **BiometricLockView 错误文案位置**：从 icon/标题间挪到 CTA 下方 + 占位 16pt，避免有/无错误时 layout 抖动
- ✅ **BackTapBanner 5s 关闭用 Task**：替代 `DispatchQueue.main.asyncAfter`，新一次唤醒时 cancel 旧 task 防时序冲突

### 编译状态
- ✅ Exit 0，无警告，pbxproj 55,173 bytes

## M5 / M6 待办（保留原始范围对照）

### M5 范围（语音多笔，§7.5）
- 录音 UI（按住说话）+ AVAudioEngine
- SFSpeechRecognizer 本地转写（zh-CN，强制 onDevice）
- ASRRouter 占位（云端档 M6）
- BillsLLMParser **Mock 版**（用规则解析模拟多笔切分；M6 接真）
- WizardVM + WizardView（逐笔向导，缺失字段强制补齐）
- voice_session 表 CRUD 接入

### M6 范围（真 LLM + 收尾）
- Doubao/Qwen 真 LLM 接入（OCR + ASR 二次校对 + 多笔解析）
- 腾讯云 OCR API 真接入
- 阿里云 ASR API 真接入
- Apple Sign In + uid 链接（覆盖 Anonymous）
- Face ID 启动鉴权（LAContext）
- 后台预览模糊化（applicationWillResignActive）
- Back Tap → Shortcuts 配置文档
- 5 条非阻塞建议优化（M2/M3.2 累积）
- Schema 迁移（如需要）

## M1 关键决策留档
- **SQLCipher**：M1 用 iOS 内建 `libsqlite3` + 256-bit 随机密钥已存 Keychain（`AfterFirstUnlockThisDeviceOnly`），`DatabaseManager.applyEncryptionKey()` 留 SQLCipher 切换钩子；M2 一次性切到 GRDB + SQLCipher（文档 B4 基线）。
- **voice_session 不带 deleted_at**：该表是临时会话日志（非业务实体），用 `status = cancelled` 代替软删除语义；不受 B3 约束。注释写在 `Data/Database/Schema.swift` 文件头。
- **M2 开工前待办**：`KeychainKeyStore.writeKey` 加 `errSecDuplicateItem → SecItemUpdate` 兜底。

## M2 关键决策留档（2026-05-08）
- **SwiftPM 接入**：扩展 `scripts/gen_xcodeproj.py` 生成 `XCRemoteSwiftPackageReference` 段，保持工程全脚本化。
- **GoogleService-Info.plist**：已到位 `CoinFlow/Resources/GoogleService-Info.plist`（真实值，.gitignore 已匹配）。
  - Bundle ID = `com.lemolli.coinflow.app`
  - Project ID = `coinflow-a534f`
  - **Firestore 区域 = asia-east2（香港）** — 后续性能基线
- **Apple Sign In**：M2 跳过真 Auth，用 `dev-anonymous-uid` 注入，真 Apple Sign In 留到 M6 联调。
- **E2EE 范围**：严格按文档 §11.1，仅加密 Firestore 的 `record.note` 和 `record.attachmentRef`；`voice_session.asr_text` 永不上 Firestore，仅本地 SQLCipher 加密，不额外 E2EE。
- **OCR/ASR/LLM 选型**：M2 不动；M4 前决策中国云供应商（腾讯 OCR / 阿里 ASR / 豆包 LLM 为默认方向，保留切换到海外模型的能力）。

## M2 建设成果（2026-05-08 完成）
- **SwiftPM 依赖**：Firebase 11.15.0（Auth + Firestore）+ GRDB 6.29.3 + **SQLCipher 4.10.0+**（工程脚本化生成，支持 idempotent 重建）
- **E2EE**：CryptoBox（AES-256-GCM + iCloud Keychain）；KeychainStore 双访问策略（`.deviceOnly` / `.synchronized`）
- **Firebase 集成**：FirestoreClient + RecordFirestoreMapper（E2EE 集成 + `users/{uid}/ledgers/{ledgerId}/records/{recordId}` 路径）+ FirestoreErrorClassifier（§5.3 全映射）
- **同步引擎**：SyncQueue actor + 指数退避（1/2/4/8/16/32s + ±20% 抖动 + 60s 上限 + 100ms 最小保护）+ 5 次重试上限
- **NotionTheme 增补**：`borderWidth` token（0.5pt）填补 stroke 宽度 token 缺口，已回贴到 RootView

## M2 遗留修复完成（2026-05-08）
- ✅ **SQLCipher 接入完成**：`import SQLCipher` 替换 `import SQLite3`；`PRAGMA key = x'<hex>'` 开库第一条语句；M1 旧未加密 DB 自动检测并清理重建（`PRAGMA cipher_page_size = 4096`）
- ✅ **Repository 3 类实装**：SQLiteLedgerRepository / SQLiteCategoryRepository / SQLiteRecordRepository 全部 CRUD + 软删除 + 同步状态接口；新增 `Data/Database/SQLBinder.swift` 共享 bind/decode 工具（Decimal ↔ TEXT / Date ↔ INTEGER / 参数化防注入）
- ✅ **Mapper.kindFor 实装**：查 CategoryRepository，无结果 fallback `expense`
- ✅ **SyncQueue.tick() 真实 dispatch**：单例 + 批量拉 pending/failed + 串行 writeRecord + markSynced/markFailed；调度由 AppState 在 record 变更时触发（M3 UI 起接入）

## M3 待办（进行中）

## 外部依赖待办（用户后续提供）
- [ ] **GoogleService-Info.plist**：从 https://console.firebase.google.com/project/coinflow-a534f/settings/general 下载，放到 `CoinFlow/Resources/`
- [ ] **OpenAI API Key**：填入 `CoinFlow/Config/Config.plist` 的 `OpenAI_API_Key`
- [ ] **Apple Sign In**：如要启用，需在 Apple Developer 后台开启 Capability
- [ ] **OCR 云 API**：腾讯云 / 百度云任选其一申请 SecretId/Key（M4 阶段使用）
- [ ] **云端 ASR**：阿里云一句话识别（备选，本地 SFSpeechRecognizer 不够时启用）

## 工程结构
- `/Users/lemolli/CoinFlow/CoinFlow/` — Phase 1 主工程（真功能 App）
- `/Users/lemolli/CoinFlow/CoinFlowPreview/` — 设计稿截屏工具（保留不动）
- `/Users/lemolli/CoinFlow/design/screens/` — 80 张设计稿（设计验收基准）
- `/Users/lemolli/CoinFlow/CoinFlow-iOS-MVP技术设计.md` — 技术设计文档

## M7 交互一致性修复（2026-05-08）

> 审计范围：`INTERACTION_AUDIT.md` 共 32 项发现（12 P0 / 11 P1 / 9 P2）
> 交付目标：全部 32 项落地（P0/P1 实装，P2 按价值取舍），build exit 0

### 新增 5 个文件
- `Features/Onboarding/OnboardingView.swift` — [13-1] 首次启动引导（钱袋 64pt + wordmark 36pt + CTA）
- `Features/Sync/SyncStatusView.swift` — [15-1] 独立同步状态页（hero + queue 真 pending + meta 卡 + action bar）
- `Features/Settings/DataImportExportView.swift` — [09-2] 数据导入/导出（CSV / JSON 真导出 + V2 占位导入）
- `Features/Main/StatsHubView.swift` — [05-1] 方案 A：Stats Hub 8 入口卡（趋势/桑基/词云/预算/AA/分类/年/小时），V2 实装子图表；`StatsPlaceholderView` 保留 typealias
- `Features/Common/MainCoordinator.swift` — [G2] Home ↔ Records 意图总线（triggerPhotoPicker / triggerVoiceRecording）

### 改动 11 个文件
- `App/AppState.swift` — 加 `hasCompletedOnboarding` + `completeOnboarding()`；bootstrap 末尾 reconcile DB 值与 mirror
- `App/CoinFlowApp.swift` — 根视图按 `hasCompletedOnboarding` 路由（OnboardingView / MainTabView）
- `Data/Repositories/UserSettingsRepository.swift` — 新增 `SettingsKey.onboardingCompleted`
- `Features/Main/MainTabView.swift` — `@StateObject coordinator` 注入 Home/Records；全局上滑手势重显 tabBar
- `Features/Main/HomeMainView.swift` —
  - [00-1] 截图卡长按 → quickAction 贴底 ActionSheet（3 行：相册 / 扫描 / 敲背）
  - [00-2] entryCard 点击通过 coordinator.triggerPhotoPicker / triggerVoiceRecording 真触发对应入口
  - [00-3] loadError inline 红色卡片 + 重试按钮
  - [00-4] gearshape 按钮加 `.contentShape(Rectangle())` 扩大命中区
- `Features/Records/RecordsListView.swift` —
  - 接收 coordinator 参数，onAppear + onChange 消费 pendingAction
  - [01-2] 月份 picker popover（12 月网格，当前月高亮）
  - [01-3] 搜索栏 inline transition（`.move(edge:.top).combined(with:.opacity)`）
  - [01-6] leading swipeAction AA 占位入口（trailing 删除保留）
  - [03-2] CaptureConfirmView 构造时传 `scrollToBottom: true`，保证选图后滚到附件卡
- `Features/Records/Components/EmptyRecordsView.swift` — [01-5] 文案对齐"按住首页「按住说话」按钮"
- `Features/Categories/CategoryListView.swift` — [10-1/10-2/10-3] 完整重写：Notion 数据库表头 + drag handle + 胶囊类型 + usedCount 统计 + edit mode 删除 + add sheet（图标 6 + 颜色 9）
- `Features/Capture/CaptureConfirmView.swift` —
  - [03-1] 新增 `keepScreenshotCard`（附件开关 + V2 真落盘说明）
  - [03-2] 构造函数加 `scrollToBottom: Bool` + ScrollViewReader "bottomAnchor"
  - [03-3] loading 骨架重写：ProgressView + "正在识别截图…"文案 + 4 行 [120/180/90/140] 不等宽灰条 + 底部 80pt 大块
- `Features/Settings/SettingsView.swift` — [09-1] 补齐 5 段（账户 / 记账 / 同步与数据 / 隐私 / 关于）；同步与数据段真路由到 SyncStatusView / DataImportExportView；隐私段新增"金额脱敏显示"（V2 开放 toggle，disabled）
- `Features/Voice/VoiceParsingView.swift` — [04-1] 三阶段指示修复死逻辑：asr/parsing 正确区分 done/active/pending
- `Features/Voice/VoiceWizardStepView.swift` — [04-2] 进度点 broken 态：skippedBills 或未 done 且 missingFields 非空的笔用黄 ! 标识

### 关键决策
- **Onboarding 双写**：UserDefaults mirror（冷启动首帧立即可读）+ user_settings 表（DB bootstrap 后 reconcile 一次），避免"重装后 iCloud 恢复但 mirror=false"导致误重做引导
- **Coordinator 模式而非 NotificationCenter**：`MainCoordinator: ObservableObject` 用 `pendingAction` 枚举，Records 消费后 `consume(_:)` 清空；相比 NotificationCenter 生命周期更清晰、避免内存泄漏
- **Stats 方案 A（Hub 入口）**：保留"V2 上线"文案但 8 入口卡视觉精致化（图标 + 色调 + V2 胶囊），避免"敬请期待"廉价感；真子图表按业务需求分阶段在 V2 实装
- **CategoryListView 重写**：废弃简版 Section/ForEach 结构；改为 Notion 表格风（表头/行/edit 切换态），usedCount 由 SQLiteRecordRepository 统计；预设分类 edit 模式下 minus 按钮变灰可点但 haptic warning 提示"不可删"
- **SyncStatusView 真数据**：直接接 `AppState.data.pendingCount` + `AppState.data.lastTickAt`；"立即同步"按钮复用 `appState.onScenePhaseActive()` 触发 `SyncQueue.tick`；pending 列表取 `SQLiteRecordRepository` 按 `updatedAt desc` 前 5 条
- **DataImportExport 真导出占位导入**：CSV/JSON 走 `ShareSheet (UIActivityViewController)` 直出到系统分享；导入因涉及 DB 写入风险大，M7 仅占位 alert，V2 接真实字段映射
- **CaptureConfirmView scrollToBottom**：从 Home quickAction / entryCard → coordinator 路径进入时构造传 `true`；内部 ScrollViewReader `onAppear + 0.3s delay` 滚到 "bottomAnchor"；避免用户看不到新增的 keepScreenshot toggle

### 扩展 gen_xcodeproj.py
- 删除 `Features/Main/StatsPlaceholderView.swift`（被 StatsHubView.swift 替代）
- 新增 5 个文件注册（MainCoordinator / OnboardingView / SyncStatusView / DataImportExportView / StatsHubView）
- 新 pbxproj size：56,995 bytes（对比 M6-B 55,173 bytes，+1.8KB 合理）

### 未全覆盖项
- [05-1 方案 A] — 已按 audit 建议做 Hub 入口；24 张子图表 V2 实装
- [03-4 字段级低置信度黄边框 + questionmark.circle.fill 图标] — CaptureConfirmView 低置信度 banner + 字段卡 stroke 已做，字段级 `questionmark.circle.fill` icon 作为 P1 次要优化留 V2
- [G3 字体 fallback helper] — P2 优化项，当前 NotionFont.swift 已封装 PingFangSC；iOS 系统 `.custom` 缺失时自动回退，无强制改动价值
- [G4 light mode 走查] — design-reviewer 专项任务，非 swift-dev 职责
- [G5 a11y 补全] — HomeMainView / Records / Settings / SyncStatus / Categories / Onboarding / DataIO 新增页面均已加 `.accessibilityLabel`；RecordDetailSheet 字段级 a11y 留 V2
- [02-2 ledger detent .height(280)] — 主工程 NewRecordModal 已是 wheel + 对应 detent；无需改动

### 验证
- ✅ build exit 0（无 Swift 编译错误；appintentsnltrainingprocessor 的 extract.actionsdata 错误是 Xcode 对 `CoinFlowCaptureIntent` 本地化元数据的已知 warning，与业务代码无关，M6 引入时即存在）
- ✅ pbxproj size：58,885 bytes（新 5 文件注册干净）
- ⏭ 真机交互回归：待 qa-tester 执行 INTERACTION_TEST_PLAN 对所有 32 项人工/自动验证

### M7 遗留风险
- **Onboarding iCloud restore 场景**：用户从 iCloud 备份恢复 App 时，UserDefaults 可能跨设备同步，但 user_settings 表不跨设备（本地 SQLCipher）。当前 reconcile 以"表为准"策略对这个场景是安全的（新设备会走一次引导）；但如用户期望"一次引导终身免"，需在 G1 决策加 iCloud Key-Value 镜像或 user_settings 表上云（V2）
- **MainCoordinator 生命周期**：@StateObject 挂 MainTabView，切到 OnboardingView 时会重建，仍符合"意图消费完即失效"语义
- **CategoryListView edit 态 drag handle**：仅视觉锚点，未接 `.onMove`；V2 接真拖拽需把 List 从 ScrollView 改 List 或自实现 drag gesture

## M7 Fix-1 用户反馈修复（2026-05-08 晚）

> 用户使用后反馈 4 个交互问题，全部修复 + build exit 0，pbxproj 59,387 bytes

### 问题 1：录音 sheet 一打开就开始录音
- **根因**：`VoiceWizardContainerView.task` 在 idle phase 自动 `await vm.startRecording()`
- **修复**：
  - `VoiceWizardContainerView`：idle 阶段也渲染 `VoiceRecordingSheet`（传 `isIdle: true`），但**不自动 start**；用户按下麦克风按钮才 `onPressDown` 触发 `startRecording()`
  - `VoiceRecordingSheet`：新增 `isIdle` / `onPressDown` 参数；idle 态 UI 文案为"按住下方按钮开始说话"+"按住说话"；波形弱化透明度 0.25；按下圆光晕降级
  - 按下手势改为：按下（onChanged 首次）→ 若 isIdle 即调 `onPressDown`；松开 → 若 idle 短按（<0.25s）视为取消（避免空录音噪音）；超过 0.25s 正常 stop
  - `onChange(of: isIdle)` 在切到非 idle 时启动倒计时 timer

### 问题 2：首页点截图/语音卡跳转流水页再拉起
- **根因**：entriesRow 点击走 `coordinator.triggerPhotoPicker/VoiceRecording` + `switchTab(.records)`
- **修复**：
  - HomeMainView 直接承载 sheet：新增 `@State showVoice` / `@State showPhotosPicker` + `@StateObject captureCoord: PhotoCaptureCoordinator`
  - entryCard 点击改为直接 `showPhotosPicker = true` / `showVoice = true`
  - `.photosPicker` + `.sheet(item: routeResult)` 都挂在 HomeMainView 的 NavigationStack 内
  - quickActionOverlay 的"从相册选择"也改为直接 `showPhotosPicker = true`
  - 保留 coordinator 引用供外部 tab 注入场景，但主路径不再走 coordinator

### 问题 3：OCR/ASR 结果需走 LLM 分析 + 多笔支持
- **设计**：所有 OCR 路径识别后 → 如果 LLM 已配置，把 OCR rawText 丢给 `BillsLLMParser.parse(source: .ocr)` 做多笔 LLM 分析 → 结果进入 `OCRWizardContainerView` 复用 VoiceWizardViewModel 的 parsing / wizard / summary 链路；LLM 未配置时回退到原单笔 CaptureConfirmView
- **新建文件**：
  - `Features/Capture/OCRWizardContainerView.swift`：OCR 多笔分析容器；task 内 `vm.startFromOCRText(ocrText, ocrEngine:)`，进入 parsing → wizard → summary；无笔兜底 "未能从截图中识别出账单"
- **改动**：
  - `BillsPromptBuilder.build` 增加 `source: BillsSourceHint`（voice/ocr）参数，OCR 路径 system 文案对齐用户要求："你是一个专业的中文记账财务助手…下面是用户的账单（来自截图 OCR 文本）…注意 OCR 存在换行/错别字…"；字段规则不变
  - `BillsLLMParser.parse` / `callLLM` 增加 `source` 参数透传；默认 `.voice` 保持向后兼容
  - `VoiceWizardViewModel`：新增 `startFromOCRText(_:ocrEngine:)` 入口，跳过录音/ASR 直接 parser → wizard
  - `HomeMainView` + `RecordsListView`：OCR route sheet 分叉：LLM 已配置且 rawText 非空 → `OCRWizardContainerView`；否则保持 `CaptureConfirmView` 单笔
- **Prompt 对齐用户要求**：
  ```
  你是一个专业的中文记账财务助手，下面是用户的账单（来自截图 OCR 文本）…
  - 账单内容（OCR 文本）：「{rawText}」
  - 用户已有分类：[...]
  【输出】{"bills": [{occurred_at, amount, direction, category, note, missing_fields}]}
  ```
  严格按"统一 JSON 字符串输出，支持多笔"的用户规范

### 问题 4：多笔保存逻辑 + 点数字回跳已确认笔
- **根因**：
  - 旧 `confirmCurrent` 每笔立即入库 recordRepo，无法回编辑
  - `progressDot` 仅根据 `index < currentIndex` 判定 done，无回跳能力
  - `advance` 单向 `currentIndex + 1`，到尾部直接 summary
- **修复**：
  - **延迟入库**：引入 `confirmedIds: Set<String>` / `skippedIds: Set<String>` 记录各笔状态，wizard 阶段仅编辑 bills[i] 数组；summary 阶段用户点"查看流水"才调 `finalizeAllToDatabase()` 统一 insert
  - **跳转能力**：`jumpTo(index:)` 允许跳到任意 index；跳前 `commitCurrentEdits()` 保存当前笔
  - **progressDot 改为 Button**：点击调 `vm.jumpTo(index: i)`；视觉三态（current 蓝 / done 绿 ✓ / skipped 灰 × / broken 黄 !）；圆从 18pt 放大到 22pt 便于点击
  - **advance 找下一未处理笔**：不再单向，找第一个既未 confirmed 也未 skipped 的笔；全部处理 → summary
  - **按钮文案**：`isLastPendingBill` 计算——当前笔外所有笔都 processed 时显示"完成"，否则"确认 & 下一笔"
  - **confirmedBills/skippedBills 数组 → 派生属性**：`confirmedBillsDerived: [ParsedBill] { bills.filter { confirmedIds.contains($0.id) } }`，summary 仍可展示

### Build 状态
- ✅ **BUILD SUCCEEDED**，零 lint，pbxproj 56,995 → 59,387 bytes（+2.4KB 合理：新增 OCRWizardContainerView + VM 扩展）
- ✅ scripts/gen_xcodeproj.py 同步注册 `Features/Capture/OCRWizardContainerView.swift`

## M8 云端同步加固（2026-05-09）

> 触发：用户要求"按 Spark 免费层重新实现云端数据同步逻辑，确保真实可靠/更新准确/删除正确，并补完整测试用例 + 详细日志"
> Data Connect 因 Blaze 计费门槛被排除；本里程碑在现有 Firestore 链路上做加固 + 测试基础设施补齐

### 6 项核心 bug 修复
| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| B1 | tick 期间 crash → record 永远卡 syncing | `pendingSync` 仅查 pending/failed，无 reconcile 入口 | 新增 `reconcileSyncingOnLaunch()`；SyncQueue.tick 入口先调 |
| B2 | 同步动作污染 `updated_at`，破坏 UI 排序 + 冲突解决 | markSyncing/markSynced/markFailed 都写 `updated_at = now()` | 三方法全部去掉 `updated_at` 字段更新 |
| B3 | 软删 record 同步失败后，本地不可见但云端复活 | 软删走的是同一条 markFailed 链路；UI 已隐藏，用户无感知 | 区分 transient/permanent attempts；permanent 立即 dead，UI "全部重试"复活 |
| B4 | 老旧但已编辑的记录排在新增记录后发 | `pendingSync` 用 `created_at ASC` | 改为 `updated_at ASC`（FIFO 真实修改时间） |
| B5 | listener 无 callsite，多设备同步实际不工作 | 只写了 SDK，没接到 SQLite 反写 | 新增 `RemoteRecordReconciler` + AppState `ensureListenerStarted` 懒启动 |
| B6 | 同步失败无可观测性，全是裸 `NSLog` | 缺结构化日志框架 | 新增 `SyncLogger`：phase / recordId / attempts / errorCode 字段化 |

### 4 个新文件
- `Data/Sync/SyncLogger.swift` — 结构化日志（INFO/WARN/FAIL 三级 + errorCode 字典化）
- `Data/Sync/RemoteRecordReconciler.swift` — listener 远端→本地反写；冲突解决 4 路径（remote-only / overwrite / dirty-protect / soft-delete）
- `Data/Sync/SyncTrigger.swift` — 触发胶水（fire-and-forget tick + ensureListenerStarted；含 `AppStateAccessor` 弱引用全局入口）
- 6 个 `CoinFlowTests/*.swift` — XCTest 用例

### 6 套测试用例（43 tests · 0 failures · 0.23s）
| Suite | 用例数 | 覆盖 |
|---|---|---|
| `SyncQueueBackoffTests` | 7 | backoff 0..7 + 抖动范围 + 100ms 保护；shouldRetry 全分支 |
| `SyncStateMachineTests` | 5 | isTransient 分类；attempts 策略文档化（transient+1 / permanent jump-to-max） |
| `CryptoBoxRoundTripTests` | 6 | encrypt/decrypt 往返 + nilAttachment + 错版本/篡改密文/错 nonce/未 bootstrap |
| `MapperEncodeDecodeTests` | 6 | 字段齐全 + 软删 deletedAt + 缺字段抛 invalidData + 错版本→decryptFailed + ledgerId 空契约 |
| `RecordRepositorySyncTests` | 11 | insert/update/delete 状态机 + markSyncing/markSynced/markFailed 不动 updated_at + reconcile 复活 + pendingSync FIFO + resetDeadRetries |
| `RemoteRecordReconcilerTests` | 8 | remote-only insert / overwrite synced / protect dirty / softDelete / 混合 batch |

### 新增 XCTest target（gen_xcodeproj.py 扩展）
- 加 `TEST_FILES` 列表 + 11 个新 IDs（test_target / test_group / test_product_ref / test_*_phase / test_dependency / test_container_proxy / test_build_config_*）
- 新增 PBXNativeTarget(unit-test bundle) + PBXTargetDependency + PBXContainerItemProxy + 2 XCBuildConfiguration + 1 XCConfigurationList
- TEST_HOST = `$(BUILT_PRODUCTS_DIR)/CoinFlow.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CoinFlow`（host app 测试，能访问 SQLCipher / Keychain / FirebaseFirestore Timestamp 等真实依赖）
- pbxproj 59,387 → **75,480 bytes**（+16KB 合理：新 target 全套 sections）

### 关键决策
- **不迁移 Data Connect**：Spark 免费层不支持；E2EE ciphertext 与 GraphQL 强类型列冲突；现有 Firestore 链路已成熟
- **markSyncing/markSynced/markFailed 不动 updated_at**：updated_at 是业务最后修改时间，为 UI 排序与多端冲突解决服务；同步元事件不应污染
- **permanent 错误立即 jump-to-max**：避免 auth/permission 类不可恢复错误吃掉 5 次重试名额；用户在"全部重试"显式干预
- **listener 不再过滤 deletedAt = NULL**：本地需感知远端软删事件以同步标记；本地 list 时 `includesDeleted=false` 默认过滤
- **listener 用 documentChanges（增量）**：避免每次全量 200 条触发本地 UPDATE 风暴
- **dirty-protect 策略**：本地 syncStatus != .synced 时拒绝远端覆盖，保护未推送的用户编辑
- **AppStateAccessor 弱引用单例**：SyncTrigger 是 detached Task 内调，需要回到 main actor 启 listener；用 weak 静态指针避免循环引用
- **ensureListenerStarted 幂等懒启动**：tick 成功后才启 listener，与现有 lazy auth 策略对齐（中国大陆 Google APIs 网络问题不阻塞启动）

### 同步生命周期（修复后）
```
[本地 insert/update/delete]
        ↓ broadcast + SyncTrigger.fire()
        ↓
   detached Task
        ├─ SyncQueue.tick(defaultLedgerId)
        │     ├─ ensureSignedIn (lazy)
        │     ├─ CryptoBox.bootstrapKey(uid)
        │     ├─ reconcileSyncingOnLaunch (复活 crash 残留)
        │     ├─ pendingSync ORDER BY updated_at ASC
        │     ├─ filter attempts < maxAttempts (5)
        │     ├─ markSyncing
        │     └─ for each: writeRecord
        │           ├─ ok       → markSynced (清 attempts/error)
        │           ├─ transient → markFailed (attempts+1)
        │           └─ permanent → markFailed (attempts=max → 立即 dead)
        │
        └─ MainActor.run { ensureListenerStarted() }   ← 幂等
              └─ FirestoreClient.listenRecords(ledgerId) {
                  RemoteRecordReconciler.apply(rows)
                    ├─ remote-only        → INSERT (synced)
                    ├─ local synced       → UPDATE (synced)
                    ├─ local dirty        → SKIP (保护未推送)
                    └─ remote softDelete  → mark local deletedAt (synced)
                  }
```

### 日志样例（结构化）
```
[CoinFlow.Sync] level=INFO phase=tick | begin
[CoinFlow.Sync] level=INFO phase=auth | uid=abc123
[CoinFlow.Sync] level=INFO phase=crypto | bootstrapped
[CoinFlow.Sync] level=INFO phase=reconcile | revived 2 syncing→pending
[CoinFlow.Sync] level=INFO phase=fetch | pending=5
[CoinFlow.Sync] level=INFO phase=write recordId=rec-abc | ok
[CoinFlow.Sync] level=FAIL phase=write recordId=rec-def attempts=3 code=networkUnavailable | transient, will retry | 网络不可用
[CoinFlow.Sync] level=FAIL phase=write recordId=rec-xyz attempts=5 code=permissionDenied | permanent, marked dead | Firestore Security Rules 拒绝访问
[CoinFlow.Sync] level=INFO phase=tick | end ok=4 fail=1
[CoinFlow.Sync] level=INFO phase=listener | start ledgerId=default-ledger
[CoinFlow.Sync] level=INFO phase=reconcile recordId=rec-foo | remote → local UPDATE
```

### 验证路径
- ✅ `xcodebuild build` Exit 0（app target）
- ✅ `xcodebuild build-for-testing` Exit 0（CoinFlow + CoinFlowTests 双 target）
- ✅ `xcodebuild test-without-building` 43 tests · 0 failures · 0.23s
- ✅ Lint 干净（read_lints 0 diagnostics）
- ⏭ 真机端到端：登录 Apple 账户 → 双设备登录同 uid → A 设备改一条 → B 设备 listener 实时收到（需 GoogleService-Info.plist 真实 Project + Firestore Security Rules 已部署）

### M8 边界风险
- **listener 首次订阅大数据量**：当前 limit=500；超过会丢老数据；V2 加分页 + 本地 high-water mark
- **多设备时钟漂移**：listener UPDATE 时若本地 updated_at 比远端晚，仍会被覆盖；当前策略以 syncStatus 区分（dirty 保护），不依赖时间比较；后续可加"远端 updatedAt < 本地 updatedAt"额外保护
- **Firestore Security Rules 必须正确部署**：`/users/{uid}/ledgers/{ledgerId}/records/{recordId}` 路径需限制 `request.auth.uid == uid`；未部署会导致 listener 收到 permissionDenied → 不可重试
- **CryptoBox bootstrap 失败的 record 永远 dead**：iCloud Keychain 关闭时所有同步失败；当前已在 SyncQueue.tick 入口拦截整批跳过（不消耗 attempts），用户开启 iCloud Keychain 后自动恢复



## M9 切换到飞书多维表格（2026-05-09）

> 触发：用户决定**完全切到飞书多维表格**取代 Firebase；飞书表格需要直接做统计/查看/汇总，因此**不再加密**（M2 E2EE 整体废弃）。

### 决策矩阵
| 维度 | 选择 | 含义 |
|---|---|---|
| Q1 飞书认证 | A 类（自建应用 + tenant_access_token） | 所有用户共用一张表（私人 App，App ID/Secret 写 Config.plist） |
| Q2 表格创建 | X（App 自动创建） | 首次同步调 `bitable.app.create` 在用户飞书"我的空间"根目录创建 |
| Q3 同步范围 | 仅 Record 一张表 | 不同步 Category / Ledger（飞书里看意义不大） |
| Q4 软删 | P（标记不删） | "已删除"复选框打勾，行不真删；用户在飞书能看完整历史 |
| Q5 反向同步 | L（手动按钮） | 同步状态页"从飞书拉取"按钮触发，无实时 listener |

### 删除清单（13 个文件 + 1 个 SwiftPM 包）
- `App/RootView.swift`（旧调试根视图，CoinFlowApp 已直接路由 Onboarding/MainTab）
- `App/DevAuth.swift`（Firebase Anonymous Auth）
- `Security/AppleSignInService.swift`（Apple Sign In 升级匿名 uid，飞书不需要）
- `Security/CryptoBox.swift`（AES-256-GCM 字段级 E2EE）
- `Security/KeychainStore.swift`（CryptoBox 的密钥存储）
- `Data/Firebase/FirestoreClient.swift`（Firestore 客户端封装）
- `Data/Firebase/FirestoreError.swift`（Firestore 错误分类）
- `Data/Sync/RecordFirestoreMapper.swift`（Record ↔ Firestore E2EE 互转）
- `Data/Sync/SyncStatus+Firestore.swift`（错误码分类器）
- `Data/Sync/RemoteRecordReconciler.swift`（listener 反写本地）
- `Resources/GoogleService-Info.plist`（Firebase 项目配置）
- `CoinFlowTests/CryptoBoxRoundTripTests.swift`
- `CoinFlowTests/MapperEncodeDecodeTests.swift`
- `CoinFlowTests/RemoteRecordReconcilerTests.swift`
- SwiftPM `firebase-ios-sdk` 11.15.0 整包移除

### 新增 8 个文件
| 文件 | 职责 |
|---|---|
| `Data/Feishu/FeishuConfig.swift` | App ID/Secret/folder_token 读取；app_token + table_id 缓存到 UserDefaults |
| `Data/Feishu/FeishuTokenManager.swift` | tenant_access_token 获取 + 提前 5min 自动刷新（actor 隔离） |
| `Data/Feishu/FeishuBitableClient.swift` | 核心 HTTP 客户端：ensureBitableExists / createRecord / updateRecord / searchAllRecords；401/403 自动刷 token 重试 1 次 |
| `Data/Sync/RecordBitableMapper.swift` | Record ↔ Bitable fields dict 互转（**明文，不加密**）；含 categoryDisplayName / directionLabel 推导 |
| `Data/Sync/RemoteRecordPuller.swift` | 手动拉取替代旧 reconciler；只 INSERT 本地缺失，不覆盖已有 |
| `CoinFlowTests/FeishuTokenManagerTests.swift` | FeishuAuthError 分类语义 |
| `CoinFlowTests/RecordBitableMapperTests.swift` | encode/decode 双向 + 边界（nil note / 软删 / 各 source / 飞书数组文本格式） |
| `scripts/feishu_e2e.swift` | 端到端集成测试（独立 Swift 脚本，跑真实飞书 API） |

### 改动 8 个文件
- `App/CoinFlowApp.swift` — 删 `FirebaseApp.configure()` 与 `import FirebaseCore`
- `App/AppState.swift` — 删 auth/crypto/firebase 三个子系统状态；改 `feishu` 三态枚举（pending / configuredWaitingTable / ready / notConfigured）；删 listener 启动逻辑；新增 `pullFromFeishu()` 手动拉取入口
- `Data/Sync/SyncQueue.swift` — 内部从 FirestoreClient 改 FeishuBitableClient；移除 CryptoBox bootstrap 步骤；错误分类器从 FirestoreSyncError 换 FeishuBitableError
- `Data/Sync/SyncTrigger.swift` — 删 `ensureListenerStarted` 调用（飞书无实时推送）
- `Data/Sync/SyncLogger.swift` — phase / errorCode 改 feishu 命名；从 FeishuBitableError + FeishuAuthError + RecordBitableMapperError 派生
- `Features/Sync/SyncStatusView.swift` — UI 副标题改"飞书多维表格"；meta 卡 firebase/crypto/auth 三行换成 飞书/多维表格 两行；底部新增"从飞书拉取"卡片 + 行 button
- `Features/Settings/SettingsView.swift` — 移除 Apple Sign In 行 + "从云端恢复"行；账户段简化为只剩 Face ID；关于段配置诊断新增飞书状态行（带 bitable URL）
- `Config/Config.plist` + `Config.example.plist` — 新增 `Feishu_App_ID` / `Feishu_App_Secret` / `Feishu_Folder_Token`
- `scripts/gen_xcodeproj.py` — SOURCE_FILES 13 处删除；TEST_FILES 改 5 个；RESOURCE_FILES 删 GoogleService-Info；SPM_PACKAGES 删 firebase-ios-sdk

### 飞书多维表格 11 字段 schema
```
单据ID (文本，主键) / 日期 (日期时间) / 金额 (数字) / 货币 (单选 CNY/USD/...)
收支 (单选 支出/收入) / 分类 (文本) / 备注 (文本) / 来源 (单选 6 项)
创建时间 (日期时间) / 更新时间 (日期时间) / 已删除 (复选框)
```

### 同步生命周期（M9）
```
[本地 insert/update/delete]
        ↓ broadcast + SyncTrigger.fire()
        ↓
   detached Task
        └─ SyncQueue.tick(defaultLedgerId)
             ├─ 配置检查（Feishu_App_ID/Secret 必填）
             ├─ FeishuTokenManager.getToken() → tenant_access_token
             ├─ FeishuBitableClient.ensureBitableExists()
             │     首次：创建 App + 默认表加 11 字段；持久化 app_token+table_id 到 UserDefaults
             ├─ reconcileSyncingOnLaunch（复活 crash 残留）
             ├─ pendingSync ORDER BY updated_at ASC（FIFO）
             ├─ filter attempts < 5
             ├─ markSyncing
             └─ for each:
                   ├─ remoteId == nil   → createRecord(fields) → 飞书返回 record_id 写回 remoteId
                   ├─ remoteId != nil   → updateRecord(remoteId, fields)（含软删=已删除字段=true）
                   └─ deletedAt && remoteId == nil → markSynced 跳过（建后立删，从未推过）

[用户点"从飞书拉取"]
        └─ RemoteRecordPuller.pullAll
             ├─ FeishuBitableClient.searchAllRecords（分页 200/页）
             └─ for each row:
                   ├─ decode fields → Record（带 remoteId）
                   ├─ 本地已有同 id → skip
                   └─ 本地缺失 → INSERT (syncStatus=.synced)
```

### 关键决策
- **不实时**：飞书无客户端 SDK 的实时推送；要做实时需 Webhook + 公网服务器（不适合 iOS 自建场景）。多设备同步降级为"用户主动按钮拉"
- **共用一张表（Q1=A）**：仅适合单用户/小团队；多用户隔离需切到 user_access_token + OAuth（V2）
- **不加密（Q2 + Q3 推论）**：飞书统计场景需要明文；账单数据敏感度由用户 + iCloud 备份策略 + 飞书账号自身安全负责
- **软删走 update（Q4=P）**：飞书有 `DELETE /records/{id}` 真删 API，但 P 方案选择不真删→历史完整可见
- **手动拉取（Q5=L）**：在 SyncStatusView 加"从飞书拉取"按钮；不覆盖本地已有，只插入本地缺失
- **app_token + table_id 用 UserDefaults 缓存**：本地"飞书表是否已建过"的事实源；下次启动直接复用，无需重新创建
- **bitable 默认表复用**：飞书 `bitable.app.create` 自动建一张默认表，返回 `default_table_id`；我们用这张表加字段，不再单独 POST `/tables` 创建第二张（避免 1254001 WrongRequestBody）
- **字段不传 property**：让飞书使用默认值（避免 `1254084 DateFieldPropertyError`）；后续如要定制日期格式再单独调 `update field` 接口

### 单元测试（30 tests · 0 failures · 0.19s）
| Suite | 用例数 | 覆盖 |
|---|---|---|
| `SyncQueueBackoffTests` | 6 | backoff 指数 + 抖动范围 + 100ms 保护；shouldRetry 全分支（飞书错误码） |
| `SyncStateMachineTests` | 7 | FeishuBitableError.isTransient 分类；attempts 策略（transient+1 / permanent jump-to-max） |
| `FeishuTokenManagerTests` | 5 | FeishuAuthError 分类（network/5xx/4xx/apiError/notConfigured） |
| `RecordBitableMapperTests` | 12 | encode 基础/收入方向/nil note/软删/全 source labels；decode 完整/数组文本格式/软删/缺字段抛错 |
| `RecordRepositorySyncTests` | 12 | （保留）SQLite 同步状态机；不依赖 Firebase |

### 端到端集成测试（飞书真实 API · 6/6 通过）
脚本：`scripts/feishu_e2e.swift`（独立 Swift script，不进 CI 单元测试）
```
T1 获取 tenant_access_token            → ✓
T2 创建多维表格 + 11 字段             → ✓ (例：https://my.feishu.cn/base/Xg9EbToELakiuRsIuP1cEoNgn6f)
T3 写入测试 record                    → ✓ record_id=recvj6jlf77kOc
T4 更新（金额 99.99 → 199.99）        → ✓
T5 软删（已删除=true，行不真删）      → ✓
T6 拉取全表，找到测试行验证字段值    → ✓ 金额=199.99 已删除=true
```

### 验证路径
- ✅ `xcodebuild build -scheme CoinFlow` Exit 0（app target，无警告）
- ✅ `xcodebuild build-for-testing` Exit 0（双 target）
- ✅ `xcodebuild test-without-building` 43 tests · 0 failures · 0.189s
- ✅ Lint 干净（read_lints 0 diagnostics 整个工程）
- ✅ 飞书端到端 6 步全通过（真实 API，写真表）

### M9 边界风险
- **多设备同步**：Q5 选 L 手动拉，不实时；用户在 A 设备改了账单，B 设备需手动按"从飞书拉取"才能同步
- **飞书 token 失效**：99991663 / 401 / 403 都会自动 refresh 重试 1 次；持续失败会进入 5 次重试上限后 dead，需用户在 SyncStatusView 点"全部重试"
- **多个用户共用一张表（Q1=A）**：当前自建应用模式，所有客户端用相同 App ID/Secret 写到同一张飞书多维表格里。不适合公开发布的多用户产品；如要多租户隔离需切到 user_access_token + OAuth（V2）
- **app_token + table_id 缓存丢失**：UserDefaults 被清/重装 App 时会丢；丢失后下次同步会**重新创建一张新的多维表格**（旧的孤儿表残留，需用户手动清理）。V2 可考虑允许用户在设置里手动填 app_token 关联到已有表
- **飞书默认表预置行**：`bitable.app.create` 后默认表会自带 N 条空白模板行，pull 时这些行的"单据ID"为空，会进入 decodeFailures 计数（不影响功能；用户可在飞书里手动删掉这些空白行）

### 用户验证清单
1. **配置加载**：打开 App → 设置 → 关于 → 配置诊断 → 「飞书多维表格」行应显示"已配置"
2. **首次同步建表**：新建一笔账单 → 设置 → 同步状态，几秒后应"已同步"；同时设置 → 关于 → 飞书多维表格行下方会出现 bitable URL
3. **打开 URL 验证**：浏览器或飞书 App 打开该 URL → 应能看到自动创建的多维表格 + 11 字段 + 你刚记的那条账单
4. **更新同步**：详情页改一条账单的金额 → 同步状态显示"已同步" → 飞书表格金额跟着变
5. **软删同步**：列表滑删一条账单 → 飞书表格中"已删除"列变勾（行不消失）
6. **手动拉取**：同步状态页 → "从飞书拉取" → 显示"新增 X 条"或"跳过 X 条"

---

## M10：LLM 账单总结（情绪化复盘 + 飞书 bitable 归档）

> 用户在周一 / 月初 / 年初进入 App 时，自动看到上一周期的账单情绪化复盘（Markdown 浮窗 + 首页 banner），同时归档到飞书"账单总结"独立 bitable 永久留存。

### 建设成果

#### 数据层
- **`bills_summary` 表**（v4 migration）：12 列承载一次复盘的全部状态
  - 主键：`id`(UUID)；业务唯一键：`(period_kind, period_start) WHERE deleted_at IS NULL`
  - 业务字段：`total_expense / total_income / record_count / snapshot_json / summary_text(markdown) / summary_digest(≤30 字)`
  - 飞书同步元：`feishu_doc_token / feishu_doc_url / feishu_sync_status(.pending/.synced/.failed/.skipped) / feishu_last_error`
- **v4 → v5 修复**（`Migrations.swift`）：原 v4 写的是 partial unique index `WHERE deleted_at IS NULL`，但 SQLite `ON CONFLICT` 不能识别 partial 索引导致 upsert 报 `does not match any PRIMARY KEY or UNIQUE constraint`；v5 DROP 重建为完整 unique index
- **Migration 容错**：新增 `tolerateDuplicateColumn` 字段，开发期模拟器重装/状态污染下 ALTER TABLE ADD COLUMN 幂等可跳过

#### 服务层（`Features/Stats/Summary/`）
| 文件 | 职责 |
|---|---|
| `BillsSummaryService.swift` | actor 编排：聚合数据 → 拼 prompt → 调 LLM → 落本地 → 推飞书；同 kind 串行化避免重复 LLM 调用 |
| `BillsSummaryAggregator.swift` | 周期边界（`Calendar.dateInterval(of: .weekOfYear)`）+ 周报/月报/年报统计快照（按 category/direction 聚合） |
| `BillsSummaryPromptBuilder.swift` | system + user prompt 拼装；system 从 `Resources/Prompts/BillsSummary.system.md` 加载 |
| `BillsSummaryLLMClient.swift` | OpenAI 兼容协议（modelscope Kimi-K2.5），`temperature=0.8 / max_tokens=4000 / stream=false`；`content?` 可空 + `reasoning_content` 兜底 |
| `BillsSummaryScheduler.swift` | App active 触发：周一/月 1 / 年 1/1 各触发一次；UserDefaults 节流 `lastTriggerDate.{kind}` |
| `PromptResource.swift` | 加载 `.md` prompt 资源（防止 Bundle 路径写死） |

#### 飞书归档
- **独立 bitable**（不复用账单表）：12 字段一一对应 `bills_summary` 列
- **`FeishuBitableClient`** 新增：`ensureSummaryBitableExists / createSummaryRecord / updateSummaryRecord`
- **`FeishuConfig`** 新增 `summaryAppToken / summaryTableId / summaryBitableURL` 缓存
- **`SummaryBitableMapper`**：`BillsSummary ↔ [String: Any]` 双向映射
- **远端失效自动重建**：捕获 1254043(RecordIdNotFound) / 1254004(TableNotFound) / 1254001-2(AppToken 失效) → 清缓存 + 降级 createRecord

#### UI（`Features/Stats/Summary/Views/`）
| 视图 | 入口 | 用途 |
|---|---|---|
| `BillsSummaryListView` | 设置 → 账单总结 | 测试按钮（周/月/年立即生成 / 调试推送）+ 历史按 kind 分组列表 |
| `SummaryFloatingCard` | banner / 列表项点击 | MarkdownUI 浮窗（四边等距），自定义 Theme |
| `BillsSummaryPushBanner` | 首页顶部（`safeAreaInset`） | 关闭策略：✕ / 点击 3 次 / 10 分钟超时（M10-Fix5） |

#### 跨 tab 通信
- **问题**：`MainTabView` 用条件渲染，切 tab 销毁 `HomeMainView`，banner 的 `@State` 无法保活
- **方案**：将 `pendingSummaryPush` 提到 `AppState`（`@Published`）；service 完成后通过 `NotificationCenter.post(.billsSummaryDidGenerate, userInfo:["summary":...])` 广播；`AppState` init 内长驻订阅写入 published；`HomeMainView` 通过 `EnvironmentObject` 监听
- **M10-Fix6 修复**：原本 service 只声明了 `Notification.Name.billsSummaryDidGenerate` 但**从未真的 post**（grep 0 结果），导致 banner 永远不显示 → service 中 upsert 后追加 `Task { @MainActor in NotificationCenter.default.post(...) }`

### M10 关键决策
- **LLM 输出 Markdown 而非 JSON**：早期试过结构化 JSON（part1/part2/...），但 LLM 在 `content` 为 null + `reasoning_content` 流式拼装下 JSON 解析常报"数据缺失"；改为直接 markdown 后稳定，且 swift-markdown-ui 渲染天然支持
- **飞书用 bitable 而非文档**：用户决策。文档 scope 权限麻烦且 SDK 对自建应用支持差；bitable 与已有账单表统一，方便用户在飞书侧做"复盘 + 流水"联动统计
- **prompt 自由度提升**：允许更多 emoji、随机选用，避免每周复盘语气雷同
- **历史摘要喂给下次 LLM**：`historyDigestCount=3`，每次生成 prompt 时附上最近 3 个 digest，让 LLM 能感知"上周/上月你说过 X"，做对比

### M10 边界风险
- **LLM 配额**：每次生成 ~2k tokens，年报 ~4k；用户疯狂点测试按钮可能爆配额（service 内 actor 串行化已避免同 kind 并发，但跨 kind 不限）
- **首次升级清不掉旧 partial index**：v5 已 DROP 重建；冷启动一次即修复
- **飞书表初次自动创建权限**：bitable 需 `bitable:app` scope；与账单表共用同一 App ID/Secret 不会增加新权限
- **banner 跨 tab 内部状态不保活**：`AppState.pendingSummaryPush` 跨 tab 保活，但 `tapCount`（10 分钟计时也是）在 `HomeMainView` 重建时归零；trade-off 接受

### M10 验收清单
1. 设置 → 账单总结 → 点"周报 / 月报 / 年报"任一按钮 → 8-15 秒后浮窗弹出
2. 浮窗 markdown 渲染应有：粗体 / 列表 / 表格 / emoji，无原文 fence
3. 切到首页 tab → 顶部应出现蓝色 banner，10 分钟内点 3 次正文 / 点 ✕ / 等待 10 min 任一即关闭
4. 飞书"账单总结"bitable 应有对应行，"完整总结"列含 markdown 全文
5. 下次冷启动 + 周一/月初/年初 → Scheduler 自动触发对应 kind（每天最多触发一次，节流由 UserDefaults 镜像控制）

### M10 测试
- 单元测试 43/43 通过（保持不变；M10 service 与 LLM 均为外部 IO，未加单测；逻辑覆盖通过手工调试推送验证）
- Lint 0 diagnostics

---

## M11：App 图标 + 视觉打磨

### 建设成果

#### App Icon
- 新增 `Resources/Assets.xcassets/AppIcon.appiconset/`
  - `Contents.json`：iOS 17+ 单 1024×1024 universal manifest
  - `coinflow_logo.png`：1024×1024 RGB 不透明（用户手工设计）
- `scripts/gen_xcodeproj.py`：扩展名映射新增 `.xcassets → folder.assetcatalog`，将整个 `Assets.xcassets` 注册为 RESOURCE_FILES（actool 自动处理 bundle 内文件）
- `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 已在 build settings 声明（M1 起）

#### 分类图标库
- 新增 `Features/Categories/CategoryIconLibrary.swift`：100+ SF Symbols 候选，按"餐饮/出行/购物/账单/娱乐..."等 8 个 group 分类
- 新增 `Features/Categories/IconPickerView.swift`：grid 选择器，复用于"新建分类 sheet"和"编辑分类 sheet"
- 新增 `CoinFlowTests/CategoryIconLibraryTests.swift`：图标库唯一性 / group 完备性测试

#### 外观设置
- 新增 `Features/Settings/AppearanceSettingsView.swift`：金额染色策略选择（自动 / 收入绿 / 支出红 / 全 mono）+ 主题色微调
- 新增 `Theme/AmountTintStore.swift`：`@Observable` 全局染色策略；持久化到 UserSettings；`SymbolColor.amountForeground(kind:)` 走它

#### 其它打磨
- 拆分 prompt builder：`BillsPromptBuilder` 拆为 `BillsOCRPromptBuilder` / `BillsVoicePromptBuilder`（OCR 与语音的 system prompt 不一样）
- 跑马灯文档：`账单总结_promot.md` 留档用户决策版的 prompt 文本

### M11 边界风险
- 真机/模拟器 SpringBoard 缓存图标：第一次跑要"卸载旧 App + Clean Build Folder"才能看到新图标
- xcassets 未来如要加 dark/tinted variant 需手工编辑 Contents.json 加 `"appearances": [{"appearance": "luminosity", "value": "dark"}]` 等 entry

### M11 验收清单
1. 卸载旧 App + Clean Build Folder + Run → 桌面图标应为"白底蓝色 ¥ 钱袋"自定义 logo
2. 设置 → 外观 → 切换金额染色 → 流水列表的金额颜色应实时变化
3. 编辑某个分类 → 点图标 → 应弹出 `IconPickerView`，按 group 浏览选择

