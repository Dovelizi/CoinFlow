---
name: coinflow-patterns
description: Coding patterns extracted from CoinFlow — SwiftUI bill-tracking iOS app with multi-theme design system, MVVM architecture, and CI/CD pipeline
version: 1.0.0
source: local-git-analysis
analyzed_commits: 200
---

# CoinFlow Patterns

Coding conventions and architecture patterns extracted from the CoinFlow iOS app repository.

## Commit Conventions

This project uses a **dual convention** — both gitmoji-style and conventional commits:

### Gitmoji-style (preferred for feature/UI work)
```
:new:          New feature
:bug:          Bug fix
:fix:          UI polish / improvement
:construction_worker:  CI/CD changes
```

### Conventional commits (preferred for CI/deployment work)
```
fix:           Bug fix or build fix
feat:          Feature
chore:         Maintenance
init:          Initial commit
```

**Scoped commits** use `type(scope):` format, e.g. `fix(theme):`, `fix(build):`.

## Architecture

```
CoinFlow/CoinFlow/
├── App/              # App entry (AppState.swift)
├── Config/           # Build configuration
├── Data/
│   ├── Database/     # SQLCipher + migrations (DatabaseManager, Schema)
│   ├── Feishu/       # Feishu/Lark API integration
│   ├── Models/       # Swift data models (Record, Category, Ledger, AAShare…)
│   ├── Repositories/ # Data access layer
│   ├── Seed/         # Seed data
│   ├── Storage/      # Local persistence
│   └── Sync/         # Cloud sync logic
├── Features/
│   ├── AASplit/      # AA bill splitting
│   ├── Capture/      # OCR receipt capture
│   ├── Categories/   # Category management
│   ├── Common/       # Shared utilities (AmountFormatter, MainCoordinator…)
│   ├── Main/         # Home tab + StatsHub
│   ├── NewRecord/    # Record creation modal
│   ├── Onboarding/   # First-launch onboarding
│   ├── RecordDetail/ # Record detail sheet
│   ├── Records/      # Record list with Components/
│   ├── Settings/     # Settings + Appearance + DataImportExport
│   ├── Stats/        # Analysis dashboard + Summary/ + Views/
│   ├── Sync/         # Sync status UI
│   └── Voice/        # Voice input + LLM parsing
├── Resources/
│   ├── Assets.xcassets/
│   └── Prompts/      # LLM prompt templates
├── Security/         # Keychain + encryption
└── Theme/            # Design system (see Theme Patterns below)
```

## SwiftUI + MVVM Pattern

Every feature follows **View + ViewModel** separation:

```
Feature/FeatureName/FeatureView.swift        ← SwiftUI view
Feature/FeatureName/FeatureViewModel.swift    ← @Observable class (iOS 26+)
```

- ViewModels use iOS 26 `@Observable` macro (NOT `@ObservableObject` / `@Published`)
- Views use `@State` for local UI state, `@Bindable` for ViewModel binding
- Sheets are presented with `.sheet(isPresented:)` or `@Environment(\.dismiss)`
- `@Environment(\.modelContext)` NOT used — persistence is via Repository pattern, not SwiftData

## Theme System

Themes are defined as **enum namespaces with static tokens**, NOT protocols:

```swift
enum AnimalIslandTheme {           // AnimalIslandTheme.swift
    static let radiusSM: CGFloat = 12
    static let radiusMD: CGFloat = 18
    static let colorPrimary = ...
    static let fontBody = ...
}

enum LiquidGlassATheme { ... }     // Separate file per theme
enum NotionTheme { ... }           // Base/default theme
```

### Theme files that often change together
When adding/modifying theme tokens, these files typically need updates:

| File | Purpose |
|------|---------|
| `<ThemeName>Theme.swift` | Design tokens (colors, radii, spacing, fonts) |
| `<ThemeName>ThemeModifiers.swift` | ViewModifiers applying the tokens |
| `NotionTheme+Aliases.swift` | Semantic aliases mapping theme tokens to semantic names |
| `PressableButtonStyle.swift` | Shared button styling |
| `NotionFont.swift` | Font definitions |

### Adding a new theme
1. Create `CoinFlow/CoinFlow/Theme/<Name>Theme.swift` with token enum
2. Create `CoinFlow/CoinFlow/Theme/<Name>ThemeModifiers.swift` with ViewModifiers
3. Add theme case to the theme enum in `AppState.swift`
4. Register aliases in `NotionTheme+Aliases.swift`
5. Add to `AppearanceSettingsView.swift` picker

## Data Layer

### Repository Pattern
Repositories encapsulate database access. Prefer `SQLiteRecordRepository` singleton pattern:

```swift
final class SQLiteRecordRepository {
    static let shared = SQLiteRecordRepository()
    // CRUD: insert, update, delete, find, fetch...
}
```

### Models
Plain Swift structs with `Codable` conformance. Models are in `Data/Models/`.

### Database
- **SQLCipher** for encrypted local storage
- Schema managed via `Schema.swift` and `Migrations.swift`
- `DatabaseManager.shared.bootstrap()` for initialization

## Testing

### Framework & Style
- **XCTest** with `@testable import CoinFlow`
- Tests in `CoinFlowTests/` directory (no subdirectories)
- `@MainActor` on test classes for async support
- `async throws` test methods (XCTest async support)

### Database Testing
Tests use the **real SQLCipher database**, NOT mocks:

```swift
override func setUp() async throws {
    try await super.setUp()
    _ = try DatabaseManager.shared.bootstrap()
    try cleanRecordTable()
    try ensureLedgerAndCategory()
}

override func tearDown() async throws {
    try? cleanRecordTable()
    try await super.tearDown()
}
```

### Test naming
Descriptive names following `test_<method>_<behavior>` pattern:
```swift
func test_insert_setsPendingByDefault() throws { }
func test_update_resetsToPending() throws { }
```

## CI/CD

- **Workflow file**: `.github/workflows/build-ios.yml`
- **Trigger**: Push to feature branches, manual dispatch
- **Output**: Unsigned IPA with ad-hoc code signing
- **Script**: `scripts/gen_xcodeproj.py` generates `.xcodeproj` from Package.swift

## File Size & Organization

- **Many small files**: Features split into focused files (View, ViewModel, Service, etc.)
- **Components subdirectory**: `Features/Records/Components/`, `Features/Stats/Summary/Views/`
- File header comments include module marker: `// CoinFlow · M7 · <description>`

## Navigation

- **Tab-based**: `MainTabView` with 5 tabs (Home, Records, AA, Stats, Settings)
- **Modal sheets**: NewRecord, VoiceWizard, RecordDetail are presented as sheets
- **Coordinator**: `MainCoordinator` in Common for cross-feature navigation
- Tab bar hides on scroll via `TabBarVisibility` preference key
