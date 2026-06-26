# 技术边界（硬约束）

以下约束摘自 `CoinFlow技术架构文档.md`，所有开发必须遵守。

## 平台与语言
- iOS 26+ / Swift 5.9+ / Xcode 26+ / SwiftUI 100%
- 无 UIKit View 主路径（仅 `AmountTextFieldUIKit` / `NoteTextFieldUIKit` / `CameraPicker` 包 UIKit）

## 架构模式
- **MVVM + Repository**：View + ViewModel（`@Observable` iOS 26）+ Repository
- **禁止** SwiftData / CoreData / VIPER / Clean Architecture
- `@Environment(AppState.self)` 访问全局状态，`@State` 管理局部 UI

## 数据层
- **金额永远用 `Decimal`**，SQLite TEXT 列存 `String(describing:)`，禁用 `Double`
- **SQL 100% 参数化**，动态列名走 `precondition` 白名单
- **软删除**：业务表 `deleted_at`；`voice_session` 用 `status='cancelled'`
- **同步元操作不污染 `updated_at`**

## 主题系统
- 颜色走 `NotionColor` 语义别名，禁止裸写 `Color(hex:)` / 固定 `pt`
- 字体走 `NotionFont` / `NotionTheme` token
- 新增主题：`<Name>Theme.swift` → `<Name>ThemeModifiers.swift` → `AppState` 注册 → `NotionTheme+Aliases.swift` → `AppearanceSettingsView.swift`

## 编码原则（andrej-karpathy）
- **不可变数据优先**：始终创建新对象，不修改现有对象
- **KISS / DRY / YAGNI**
- **不写注释**，除非 WHY（非显而易见的约束、隐患、workaround）
- **小文件**：200-400 行，800 行上限
- **小函数**：50 行上限
- **禁止深层嵌套**：4 层上限，优先 early return
