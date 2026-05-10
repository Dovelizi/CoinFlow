#!/usr/bin/env python3
"""
Generate the CoinFlow iOS App Xcode project (M2).

Features vs M1:
- SwiftPM remote package dependencies (Firebase + GRDB+SQLCipher)
- Resources in nested subdirectories (Resources/GoogleService-Info.plist)
- Info.plist keys for microphone / speech-recognition / NSCameraUsage
- Idempotent: re-running overwrites .xcodeproj.

Usage:
    python3 scripts/gen_xcodeproj.py
"""

from __future__ import annotations

import secrets
from pathlib import Path
from textwrap import dedent

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "CoinFlow"
BUNDLE_ID = "com.lemolli.coinflow.app"
DEPLOYMENT_TARGET = "16.0"
# 注：每次重新运行本脚本后，需在 Xcode → CoinFlow target → Signing & Capabilities
# 手动选一次 Team（Personal Team 个人 free 账号）。无法在脚本里固化 Team ID
# 因为 free 个人账号的 Team ID 每个 Apple ID 不同，且不在 keychain 里可读。
SWIFT_VERSION = "5.9"

# --------------------------------------------------------------------------
# Source files (compiled into the app target)
# --------------------------------------------------------------------------
SOURCE_FILES: list[str] = [
    # M1
    "App/CoinFlowApp.swift",
    "Theme/NotionTheme.swift",
    "Theme/NotionTheme+Aliases.swift",
    "Theme/NotionFont.swift",
    "Theme/KeyboardDoneToolbar.swift",
    "Config/AppConfig.swift",
    "Data/Database/Schema.swift",
    "Data/Database/Migrations.swift",
    "Data/Database/DatabaseManager.swift",
    "Data/Database/SQLBinder.swift",
    "Data/Models/Ledger.swift",
    "Data/Models/Category.swift",
    "Data/Models/Record.swift",
    "Data/Models/VoiceSession.swift",
    "Data/Repositories/RecordRepository.swift",
    "Data/Repositories/CategoryRepository.swift",
    "Data/Repositories/LedgerRepository.swift",
    # M9-Fix4 — OCR 截图归档存储
    "Data/Storage/ScreenshotStore.swift",
    # M3.1 — Seeding
    "Data/Seed/DefaultSeeder.swift",
    "Data/Repositories/RecordChangeNotifier.swift",
    # M3.2 — Records UI
    "Features/Common/SymbolColor.swift",
    "Features/Common/AmountFormatter.swift",
    "Features/Common/DateGrouping.swift",
    "Features/Records/RecordsListViewModel.swift",
    "Features/Records/RecordsListView.swift",
    "Features/Records/RecordRow.swift",
    "Features/Records/RecordsLayout.swift",
    "Features/Records/Components/InlineStatsBar.swift",
    "Features/Records/Components/EmptyRecordsView.swift",
    "Features/Records/Components/RecordGridView.swift",
    "Features/NewRecord/NewRecordViewModel.swift",
    "Features/NewRecord/NewRecordModal.swift",
    "Features/NewRecord/CategoryPickerSheet.swift",
    # M3.3 — Detail / Categories
    "Features/RecordDetail/RecordDetailViewModel.swift",
    "Features/RecordDetail/RecordDetailSheet.swift",
    "Features/Categories/CategoryListView.swift",
    # M4 — Capture / OCR
    "Features/Capture/OCREngine.swift",
    "Features/Capture/ReceiptParser.swift",
    "Features/Capture/QuotaService.swift",
    "Features/Capture/OCRRouter.swift",
    "Features/Capture/CaptureConfirmView.swift",
    "Features/Capture/PhotoPicker.swift",
    # M5 — Voice multi-bill
    "Data/Repositories/VoiceSessionRepository.swift",
    "Features/Voice/ASREngine.swift",
    "Features/Voice/ASRRouter.swift",
    "Features/Voice/AudioRecorder.swift",
    "Features/Voice/ParsedBill.swift",
    "Features/Voice/BillsLLMParser.swift",
    "Features/Voice/VoiceWizardViewModel.swift",
    "Features/Voice/VoiceRecordingSheet.swift",
    "Features/Voice/VoiceParsingView.swift",
    "Features/Voice/VoiceWizardStepView.swift",
    "Features/Voice/VoiceSummaryView.swift",
    "Features/Voice/VoiceWizardContainerView.swift",
    # M6 — Privacy / Security / Settings
    "Data/Repositories/UserSettingsRepository.swift",
    "Security/BiometricAuthService.swift",
    "App/PrivacyShieldView.swift",
    "App/BiometricLockView.swift",
    "Features/Settings/SettingsView.swift",
    "Features/Settings/BackTapSetupView.swift",
    "Features/Capture/CoinFlowCaptureIntent.swift",
    "Features/Capture/ScreenshotInbox.swift",
    "Features/Voice/BillsVisionLLMClient.swift",
    # M6 后期 — 全局 Tab 导航（3 tab + 左右滑动）
    "Features/Main/MainTabView.swift",
    "Features/Main/HomeMainView.swift",
    "Features/Main/StatsHubView.swift",
    # V2 — Stats 深度分析（8 子页面 + ViewModel + 色族 token）
    "Theme/NotionColor.swift",
    "Features/Stats/StatsViewModel.swift",
    "Features/Stats/StatsAnalysisHostView.swift",
    "Features/Stats/Views/StatsMainView.swift",
    "Features/Stats/Views/StatsTrendView.swift",
    "Features/Stats/Views/StatsYearView.swift",
    "Features/Stats/Views/StatsHourlyView.swift",
    "Features/Stats/Views/StatsGaugeView.swift",
    "Features/Stats/Views/StatsSankeyView.swift",
    "Features/Stats/Views/StatsWordCloudView.swift",
    "Features/Stats/Views/StatsBudgetView.swift",
    "Features/Stats/Views/StatsAABalanceView.swift",
    "Features/Stats/Views/StatsCategoryDetailView.swift",
    # M6-B — 云服务真接入
    "Features/Voice/LLMTextClient.swift",
    "Features/Voice/BillsPromptBuilder.swift",
    # M7-Fix13 — 商户品牌图标识别
    "Features/Capture/MerchantBrand.swift",
    # M7 — 交互一致性修复（Onboarding / Sync / Data IO / Coordinator）
    "Features/Common/MainCoordinator.swift",
    "Features/Onboarding/OnboardingView.swift",
    "Features/Sync/SyncStatusView.swift",
    "Features/Settings/DataImportExportView.swift",
    # M9 — 飞书多维表格同步（取代 Firebase / E2EE）
    "Data/Feishu/FeishuConfig.swift",
    "Data/Feishu/FeishuTokenManager.swift",
    "Data/Feishu/FeishuBitableClient.swift",
    "Data/Sync/RecordBitableMapper.swift",
    "Data/Sync/RemoteRecordPuller.swift",
    "Data/Sync/SyncQueue.swift",
    "Data/Sync/SyncLogger.swift",
    "Data/Sync/SyncTrigger.swift",
    # App runtime state
    "App/AppState.swift",
    # Theme — Dark Glass 主题（原文件未注册到脚本，2026-05-10 补回）
    "Theme/LiquidGlassATheme.swift",
    # Common 工具（原未注册）
    "Features/Common/TabBarVisibility.swift",
    "Features/Common/InteractivePopEnabler.swift",
    # Capture 相机选择器（原未注册）
    "Features/Capture/CameraPicker.swift",
]

# --------------------------------------------------------------------------
# Test source files (compiled into the unit-test bundle target).
# 路径相对仓库根目录（即 /CoinFlow/CoinFlowTests/...）。
# --------------------------------------------------------------------------
TEST_FILES: list[str] = [
    "CoinFlowTests/SyncQueueBackoffTests.swift",
    "CoinFlowTests/SyncStateMachineTests.swift",
    "CoinFlowTests/RecordRepositorySyncTests.swift",
    "CoinFlowTests/FeishuTokenManagerTests.swift",
    "CoinFlowTests/RecordBitableMapperTests.swift",
]

# --------------------------------------------------------------------------
# Resource files (copied into the app bundle)
# --------------------------------------------------------------------------
RESOURCE_FILES: list[str] = [
    "Config/Config.example.plist",
    "Config/Config.plist",
]

# --------------------------------------------------------------------------
# SwiftPM remote package dependencies
# Each entry → one XCRemoteSwiftPackageReference.
# --------------------------------------------------------------------------
SPM_PACKAGES: list[dict] = [
    {
        "repo":     "https://github.com/groue/GRDB.swift",
        "minVer":   "6.29.0",
        "products": ["GRDB"],
        # NOTE: 标准 GRDB 直接链接系统 libsqlite3.dylib，**不支持** PRAGMA key 加密。
        # SQLCipher 由独立 SPM 包提供 sqlite3_* 符号；
        # Repository 层不再 `import GRDB`，而是用更轻量的 SQLCipher + 自写 DAO。
    },
    {
        "repo":     "https://github.com/sqlcipher/SQLCipher.swift",
        "minVer":   "4.10.0",
        "products": ["SQLCipher"],
        # 文档 §11 要求的 SQLCipher 4.10.0+ 官方 SPM 包。
        # 提供 `sqlite3_*` 符号（已附 SQLITE_HAS_CODEC），本地 DatabaseManager
        # `import SQLCipher` 后可直接调用 `sqlite3_key(...)` 启用 256-bit AES 加密。
    },
]

# --------------------------------------------------------------------------
# Info.plist keys to inject via INFOPLIST_KEY_* build settings
# --------------------------------------------------------------------------
INFOPLIST_KEYS: dict[str, str] = {
    "INFOPLIST_KEY_CFBundleLocalizations": "zh-Hans en",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription":
        "用于录制您口述的账单内容；音频识别完成即从设备删除，不上传到服务器。",
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription":
        "用于将您的语音转写为账单文字；转写结果仅保存在您的本地加密数据库。",
    "INFOPLIST_KEY_NSCameraUsageDescription":
        "用于拍摄账单小票并识别金额分类（未来版本启用）。",
    "INFOPLIST_KEY_NSPhotoLibraryUsageDescription":
        "用于从相册选择账单截图进行识别（未来版本启用）。",
    "INFOPLIST_KEY_NSFaceIDUsageDescription":
        "启用 Face ID 启动鉴权后，App 冷启动时需要您验证身份才能查看流水。",
    "INFOPLIST_KEY_UIBackgroundModes": "remote-notification",
}


def uuid24() -> str:
    return secrets.token_hex(12).upper()


def quote_if_needed(s: str) -> str:
    return f'"{s}"' if any(c in s for c in '+ /') else s


def generate() -> str:
    ids = {
        "project":          uuid24(),
        "main_group":       uuid24(),
        "products_group":   uuid24(),
        "src_group":        uuid24(),
        "packages_group":   uuid24(),
        "target":           uuid24(),
        "build_config_list_proj":   uuid24(),
        "build_config_list_target": uuid24(),
        "build_config_proj_debug":   uuid24(),
        "build_config_proj_release": uuid24(),
        "build_config_target_debug":   uuid24(),
        "build_config_target_release": uuid24(),
        "sources_phase":    uuid24(),
        "frameworks_phase": uuid24(),
        "resources_phase":  uuid24(),
        "app_product_ref":  uuid24(),
        # Test target IDs
        "test_target":              uuid24(),
        "test_group":               uuid24(),
        "test_product_ref":         uuid24(),
        "test_sources_phase":       uuid24(),
        "test_frameworks_phase":    uuid24(),
        "test_resources_phase":     uuid24(),
        "test_dependency":          uuid24(),
        "test_container_proxy":     uuid24(),
        "test_build_config_list":   uuid24(),
        "test_build_config_debug":  uuid24(),
        "test_build_config_release":uuid24(),
    }

    # file + build refs for each Swift/resource file
    file_refs: dict[str, str] = {}
    build_files: dict[str, str] = {}
    for f in SOURCE_FILES + RESOURCE_FILES:
        file_refs[f] = uuid24()
        build_files[f] = uuid24()
    # Test files: separate ref pool（PBXBuildFile 进 test sources phase）
    test_file_refs: dict[str, str] = {}
    test_build_files: dict[str, str] = {}
    for f in TEST_FILES:
        test_file_refs[f] = uuid24()
        test_build_files[f] = uuid24()

    # SwiftPM per-package / per-product ids
    pkg_refs: list[dict] = []
    for p in SPM_PACKAGES:
        p2 = dict(p)
        p2["ref_id"] = uuid24()
        p2["product_ids"] = {prod: uuid24() for prod in p["products"]}
        p2["build_ids"] = {prod: uuid24() for prod in p["products"]}
        pkg_refs.append(p2)

    # ------------------------------------------------------------
    # Collect group hierarchy by splitting file paths into tuples.
    # ------------------------------------------------------------
    def collect_groups() -> dict[tuple[str, ...], list[str]]:
        groups: dict[tuple[str, ...], list[str]] = {}
        for f in SOURCE_FILES + RESOURCE_FILES:
            parts = f.split("/")
            key = () if len(parts) == 1 else tuple(parts[:-1])
            groups.setdefault(key, []).append(f)
        return groups

    folder_files = collect_groups()
    # Ensure every ancestor path (including root "()" = src_group) is registered.
    all_paths: set[tuple[str, ...]] = {()}
    for p in folder_files.keys():
        for i in range(len(p) + 1):
            all_paths.add(tuple(p[:i]))

    folder_ids: dict[tuple[str, ...], str] = {}
    for path in all_paths:
        folder_ids[path] = ids["src_group"] if path == () else uuid24()

    def children_of(path: tuple[str, ...]) -> list[tuple[str, str]]:
        children: list[tuple[str, str]] = []
        sub_paths = sorted({
            p for p in folder_ids.keys()
            if len(p) == len(path) + 1 and p[: len(path)] == path
        })
        for sp in sub_paths:
            children.append((folder_ids[sp], sp[-1]))
        for f in sorted(folder_files.get(path, [])):
            children.append((file_refs[f], Path(f).name))
        return children

    # ------------------------------------------------------------
    # Section: PBXBuildFile
    # ------------------------------------------------------------
    bf_lines: list[str] = []
    for f in SOURCE_FILES:
        bf_lines.append(
            f"\t\t{build_files[f]} /* {Path(f).name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_refs[f]} /* {Path(f).name} */; }};"
        )
    for f in RESOURCE_FILES:
        bf_lines.append(
            f"\t\t{build_files[f]} /* {Path(f).name} in Resources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_refs[f]} /* {Path(f).name} */; }};"
        )
    # SwiftPM product build refs
    for p in pkg_refs:
        for prod in p["products"]:
            bf_lines.append(
                f"\t\t{p['build_ids'][prod]} /* {prod} in Frameworks */ = {{isa = PBXBuildFile; "
                f"productRef = {p['product_ids'][prod]} /* {prod} */; }};"
            )
    # Test sources build refs
    for f in TEST_FILES:
        bf_lines.append(
            f"\t\t{test_build_files[f]} /* {Path(f).name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {test_file_refs[f]} /* {Path(f).name} */; }};"
        )
    build_file_section = "\n".join(bf_lines)

    # ------------------------------------------------------------
    # Section: PBXFileReference
    # ------------------------------------------------------------
    fr_lines = [
        f"\t\t{ids['app_product_ref']} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; "
        f"path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    ]
    for f in SOURCE_FILES:
        name = Path(f).name
        fr_lines.append(
            f"\t\t{file_refs[f]} /* {quote_if_needed(name)} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; "
            f"path = {quote_if_needed(name)}; sourceTree = \"<group>\"; }};"
        )
    for f in RESOURCE_FILES:
        name = Path(f).name
        # Xcode's CopyPlistFile builtin rule has a known quirk where relative
        # path resolution through nested groups drops ancestor segments; the
        # safe fix is to pin each resource plist to SOURCE_ROOT with its full
        # relative path.
        rel_path = f"{PROJECT_NAME}/{f}"
        fr_lines.append(
            f"\t\t{file_refs[f]} /* {quote_if_needed(name)} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = text.plist.xml; name = {quote_if_needed(name)}; "
            f"path = {quote_if_needed(rel_path)}; sourceTree = SOURCE_ROOT; }};"
        )
    # Test bundle product reference
    fr_lines.append(
        f"\t\t{ids['test_product_ref']} /* {PROJECT_NAME}Tests.xctest */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.cfbundle; includeInIndex = 0; "
        f"path = {PROJECT_NAME}Tests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    # Test source files (path relative to SOURCE_ROOT, since CoinFlowTests/
    # is a sibling to the CoinFlow/ source folder)
    for f in TEST_FILES:
        name = Path(f).name
        fr_lines.append(
            f"\t\t{test_file_refs[f]} /* {quote_if_needed(name)} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; name = {quote_if_needed(name)}; "
            f"path = {quote_if_needed(f)}; sourceTree = SOURCE_ROOT; }};"
        )
    file_ref_section = "\n".join(fr_lines)

    # ------------------------------------------------------------
    # Section: PBXGroup
    # ------------------------------------------------------------
    group_blocks: list[str] = []
    group_blocks.append(
        f"\t\t{ids['main_group']} = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{ids['src_group']} /* {PROJECT_NAME} */,\n"
        f"\t\t\t\t{ids['test_group']} /* {PROJECT_NAME}Tests */,\n"
        f"\t\t\t\t{ids['products_group']} /* Products */,\n"
        f"\t\t\t);\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    group_blocks.append(
        f"\t\t{ids['products_group']} /* Products */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{ids['app_product_ref']} /* {PROJECT_NAME}.app */,\n"
        f"\t\t\t\t{ids['test_product_ref']} /* {PROJECT_NAME}Tests.xctest */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = Products;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    # CoinFlowTests group
    test_kids = "\n".join(
        f"\t\t\t\t{test_file_refs[f]} /* {Path(f).name} */,"
        for f in sorted(TEST_FILES)
    )
    group_blocks.append(
        f"\t\t{ids['test_group']} /* {PROJECT_NAME}Tests */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n{test_kids}\n\t\t\t);\n"
        f"\t\t\tpath = {PROJECT_NAME}Tests;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    for path, gid in folder_ids.items():
        kids = children_of(path)
        kids_lines = "\n".join(
            f"\t\t\t\t{cid} /* {cname} */," for cid, cname in kids
        )
        if path == ():
            block = (
                f"\t\t{gid} /* {PROJECT_NAME} */ = {{\n"
                f"\t\t\tisa = PBXGroup;\n"
                f"\t\t\tchildren = (\n{kids_lines}\n\t\t\t);\n"
                f"\t\t\tpath = {PROJECT_NAME};\n"
                f"\t\t\tsourceTree = \"<group>\";\n"
                f"\t\t}};"
            )
        else:
            folder_name = path[-1]
            block = (
                f"\t\t{gid} /* {folder_name} */ = {{\n"
                f"\t\t\tisa = PBXGroup;\n"
                f"\t\t\tchildren = (\n{kids_lines}\n\t\t\t);\n"
                f"\t\t\tpath = {quote_if_needed(folder_name)};\n"
                f"\t\t\tsourceTree = \"<group>\";\n"
                f"\t\t}};"
            )
        group_blocks.append(block)
    groups_section = "\n".join(group_blocks)

    # ------------------------------------------------------------
    # Section: PBXSourcesBuildPhase / PBXResourcesBuildPhase / PBXFrameworksBuildPhase
    # ------------------------------------------------------------
    sources_phase_files = "\n".join(
        f"\t\t\t\t{build_files[f]} /* {Path(f).name} in Sources */," for f in SOURCE_FILES
    )
    resources_phase_files = "\n".join(
        f"\t\t\t\t{build_files[f]} /* {Path(f).name} in Resources */," for f in RESOURCE_FILES
    )
    # Frameworks phase: only SwiftPM products
    frameworks_phase_files_lines: list[str] = []
    for p in pkg_refs:
        for prod in p["products"]:
            frameworks_phase_files_lines.append(
                f"\t\t\t\t{p['build_ids'][prod]} /* {prod} in Frameworks */,"
            )
    frameworks_phase_files = "\n".join(frameworks_phase_files_lines)

    # ------------------------------------------------------------
    # Section: XCRemoteSwiftPackageReference + XCSwiftPackageProductDependency
    # ------------------------------------------------------------
    remote_pkg_lines: list[str] = []
    for p in pkg_refs:
        remote_pkg_lines.append(
            f"\t\t{p['ref_id']} /* XCRemoteSwiftPackageReference \"{Path(p['repo']).stem}\" */ = {{\n"
            f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
            f"\t\t\trepositoryURL = \"{p['repo']}\";\n"
            f"\t\t\trequirement = {{\n"
            f"\t\t\t\tkind = upToNextMajorVersion;\n"
            f"\t\t\t\tminimumVersion = {p['minVer']};\n"
            f"\t\t\t}};\n"
            f"\t\t}};"
        )
    remote_pkg_section = "\n".join(remote_pkg_lines)

    product_dep_lines: list[str] = []
    for p in pkg_refs:
        for prod in p["products"]:
            product_dep_lines.append(
                f"\t\t{p['product_ids'][prod]} /* {prod} */ = {{\n"
                f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
                f"\t\t\tpackage = {p['ref_id']} /* XCRemoteSwiftPackageReference \"{Path(p['repo']).stem}\" */;\n"
                f"\t\t\tproductName = {prod};\n"
                f"\t\t}};"
            )
    product_dep_section = "\n".join(product_dep_lines)

    # Project.packageReferences + Target.packageProductDependencies snippets
    project_pkg_refs_lines = "\n".join(
        f"\t\t\t\t{p['ref_id']} /* XCRemoteSwiftPackageReference \"{Path(p['repo']).stem}\" */,"
        for p in pkg_refs
    )
    target_pkg_product_deps_lines: list[str] = []
    for p in pkg_refs:
        for prod in p["products"]:
            target_pkg_product_deps_lines.append(
                f"\t\t\t\t{p['product_ids'][prod]} /* {prod} */,"
            )
    target_pkg_product_deps = "\n".join(target_pkg_product_deps_lines)

    # ------------------------------------------------------------
    # Info.plist keys (injected via INFOPLIST_KEY_* build settings)
    # ------------------------------------------------------------
    infoplist_lines: list[str] = []
    for k, v in INFOPLIST_KEYS.items():
        # Escape double quotes inside value
        esc = v.replace("\\", "\\\\").replace("\"", "\\\"")
        infoplist_lines.append(f"\t\t\t\t{k} = \"{esc}\";")
    infoplist_keys_block = "\n".join(infoplist_lines)

    # ------------------------------------------------------------
    # Test target — extra sections (PBXSourcesBuildPhase / PBXNativeTarget /
    # PBXTargetDependency / PBXContainerItemProxy / 2 XCBuildConfiguration /
    # 1 XCConfigurationList)
    # ------------------------------------------------------------
    test_sources_phase_files = "\n".join(
        f"\t\t\t\t{test_build_files[f]} /* {Path(f).name} in Sources */,"
        for f in TEST_FILES
    )
    test_extra_build_file_section = (
        f"\t\t{ids['test_sources_phase']} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n{test_sources_phase_files}\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
        f"\t\t{ids['test_frameworks_phase']} /* Frameworks */ = {{\n"
        f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
        f"\t\t{ids['test_resources_phase']} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    test_native_target = (
        f"\t\t{ids['test_target']} /* {PROJECT_NAME}Tests */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {ids['test_build_config_list']} "
        f"/* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}Tests\" */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{ids['test_sources_phase']} /* Sources */,\n"
        f"\t\t\t\t{ids['test_frameworks_phase']} /* Frameworks */,\n"
        f"\t\t\t\t{ids['test_resources_phase']} /* Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n\t\t\t);\n"
        f"\t\t\tdependencies = (\n"
        f"\t\t\t\t{ids['test_dependency']} /* PBXTargetDependency */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = {PROJECT_NAME}Tests;\n"
        f"\t\t\tpackageProductDependencies = (\n\t\t\t);\n"
        f"\t\t\tproductName = {PROJECT_NAME}Tests;\n"
        f"\t\t\tproductReference = {ids['test_product_ref']} "
        f"/* {PROJECT_NAME}Tests.xctest */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";\n"
        f"\t\t}};"
    )
    test_dependency_section = (
        f"\t\t{ids['test_dependency']} /* PBXTargetDependency */ = {{\n"
        f"\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {ids['target']} /* {PROJECT_NAME} */;\n"
        f"\t\t\ttargetProxy = {ids['test_container_proxy']} /* PBXContainerItemProxy */;\n"
        f"\t\t}};"
    )
    test_container_proxy_section = (
        f"\t\t{ids['test_container_proxy']} /* PBXContainerItemProxy */ = {{\n"
        f"\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {ids['project']} /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {ids['target']};\n"
        f"\t\t\tremoteInfo = {PROJECT_NAME};\n"
        f"\t\t}};"
    )
    test_buildconfig_section = (
        f"\t\t{ids['test_build_config_debug']} /* Debug */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";\n"
        f"\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        f"\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
        f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};\n"
        f"\t\t\t\tMARKETING_VERSION = 1.0;\n"
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.tests;\n"
        f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;\n"
        f"\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};\n"
        f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
        f"\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/{PROJECT_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{PROJECT_NAME}\";\n"
        f"\t\t\t}};\n"
        f"\t\t\tname = Debug;\n"
        f"\t\t}};\n"
        f"\t\t{ids['test_build_config_release']} /* Release */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";\n"
        f"\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        f"\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
        f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};\n"
        f"\t\t\t\tMARKETING_VERSION = 1.0;\n"
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.tests;\n"
        f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;\n"
        f"\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};\n"
        f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
        f"\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/{PROJECT_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{PROJECT_NAME}\";\n"
        f"\t\t\t}};\n"
        f"\t\t\tname = Release;\n"
        f"\t\t}};"
    )
    test_buildconfig_list_section = (
        f"\t\t{ids['test_build_config_list']} "
        f"/* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}Tests\" */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{ids['test_build_config_debug']} /* Debug */,\n"
        f"\t\t\t\t{ids['test_build_config_release']} /* Release */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};"
    )

    # ------------------------------------------------------------
    # Final template assembly
    # ------------------------------------------------------------
    pbxproj = dedent(f"""\
        // !$*UTF8*$!
        {{
        \tarchiveVersion = 1;
        \tclasses = {{
        \t}};
        \tobjectVersion = 60;
        \tobjects = {{

        /* Begin PBXBuildFile section */
        {build_file_section}
        /* End PBXBuildFile section */

        /* Begin PBXFileReference section */
        {file_ref_section}
        /* End PBXFileReference section */

        /* Begin PBXFrameworksBuildPhase section */
        \t\t{ids['frameworks_phase']} /* Frameworks */ = {{
        \t\t\tisa = PBXFrameworksBuildPhase;
        \t\t\tbuildActionMask = 2147483647;
        \t\t\tfiles = (
        {frameworks_phase_files}
        \t\t\t);
        \t\t\trunOnlyForDeploymentPostprocessing = 0;
        \t\t}};
        /* End PBXFrameworksBuildPhase section */

        /* Begin PBXGroup section */
        {groups_section}
        /* End PBXGroup section */

        /* Begin PBXNativeTarget section */
        \t\t{ids['target']} /* {PROJECT_NAME} */ = {{
        \t\t\tisa = PBXNativeTarget;
        \t\t\tbuildConfigurationList = {ids['build_config_list_target']} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */;
        \t\t\tbuildPhases = (
        \t\t\t\t{ids['sources_phase']} /* Sources */,
        \t\t\t\t{ids['frameworks_phase']} /* Frameworks */,
        \t\t\t\t{ids['resources_phase']} /* Resources */,
        \t\t\t);
        \t\t\tbuildRules = (
        \t\t\t);
        \t\t\tdependencies = (
        \t\t\t);
        \t\t\tname = {PROJECT_NAME};
        \t\t\tpackageProductDependencies = (
        {target_pkg_product_deps}
        \t\t\t);
        \t\t\tproductName = {PROJECT_NAME};
        \t\t\tproductReference = {ids['app_product_ref']} /* {PROJECT_NAME}.app */;
        \t\t\tproductType = "com.apple.product-type.application";
        \t\t}};
        {test_native_target}
        /* End PBXNativeTarget section */

        /* Begin PBXContainerItemProxy section */
        {test_container_proxy_section}
        /* End PBXContainerItemProxy section */

        /* Begin PBXTargetDependency section */
        {test_dependency_section}
        /* End PBXTargetDependency section */

        /* Begin PBXProject section */
        \t\t{ids['project']} /* Project object */ = {{
        \t\t\tisa = PBXProject;
        \t\t\tattributes = {{
        \t\t\t\tBuildIndependentTargetsInParallel = 1;
        \t\t\t\tLastSwiftUpdateCheck = 1640;
        \t\t\t\tLastUpgradeCheck = 1640;
        \t\t\t\tTargetAttributes = {{
        \t\t\t\t\t{ids['target']} = {{
        \t\t\t\t\t\tCreatedOnToolsVersion = 16.4;
        \t\t\t\t\t}};
        \t\t\t\t}};
        \t\t\t}};
        \t\t\tbuildConfigurationList = {ids['build_config_list_proj']} /* Build configuration list for PBXProject "{PROJECT_NAME}" */;
        \t\t\tcompatibilityVersion = "Xcode 15.0";
        \t\t\tdevelopmentRegion = "zh-Hans";
        \t\t\thasScannedForEncodings = 0;
        \t\t\tknownRegions = (
        \t\t\t\t"zh-Hans",
        \t\t\t\ten,
        \t\t\t\tBase,
        \t\t\t);
        \t\t\tmainGroup = {ids['main_group']};
        \t\t\tpackageReferences = (
        {project_pkg_refs_lines}
        \t\t\t);
        \t\t\tproductRefGroup = {ids['products_group']} /* Products */;
        \t\t\tprojectDirPath = "";
        \t\t\tprojectRoot = "";
        \t\t\ttargets = (
        \t\t\t\t{ids['target']} /* {PROJECT_NAME} */,
        \t\t\t\t{ids['test_target']} /* {PROJECT_NAME}Tests */,
        \t\t\t);
        \t\t}};
        /* End PBXProject section */

        /* Begin PBXResourcesBuildPhase section */
        \t\t{ids['resources_phase']} /* Resources */ = {{
        \t\t\tisa = PBXResourcesBuildPhase;
        \t\t\tbuildActionMask = 2147483647;
        \t\t\tfiles = (
        {resources_phase_files}
        \t\t\t);
        \t\t\trunOnlyForDeploymentPostprocessing = 0;
        \t\t}};
        /* End PBXResourcesBuildPhase section */

        /* Begin PBXSourcesBuildPhase section */
        \t\t{ids['sources_phase']} /* Sources */ = {{
        \t\t\tisa = PBXSourcesBuildPhase;
        \t\t\tbuildActionMask = 2147483647;
        \t\t\tfiles = (
        {sources_phase_files}
        \t\t\t);
        \t\t\trunOnlyForDeploymentPostprocessing = 0;
        \t\t}};
        {test_extra_build_file_section}
        /* End PBXSourcesBuildPhase section */

        /* Begin XCBuildConfiguration section */
        \t\t{ids['build_config_proj_debug']} /* Debug */ = {{
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {{
        \t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
        \t\t\t\tCLANG_ANALYZER_NONNULL = YES;
        \t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
        \t\t\t\tCLANG_ENABLE_MODULES = YES;
        \t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
        \t\t\t\tCOPY_PHASE_STRIP = NO;
        \t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
        \t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
        \t\t\t\tENABLE_TESTABILITY = YES;
        \t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;
        \t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
        \t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
        \t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
        \t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
        \t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
        \t\t\t\t\t"DEBUG=1",
        \t\t\t\t\t"$(inherited)",
        \t\t\t\t);
        \t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
        \t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
        \t\t\t\tONLY_ACTIVE_ARCH = YES;
        \t\t\t\tSDKROOT = iphoneos;
        \t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
        \t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
        \t\t\t}};
        \t\t\tname = Debug;
        \t\t}};
        \t\t{ids['build_config_proj_release']} /* Release */ = {{
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {{
        \t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
        \t\t\t\tCLANG_ANALYZER_NONNULL = YES;
        \t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
        \t\t\t\tCLANG_ENABLE_MODULES = YES;
        \t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
        \t\t\t\tCOPY_PHASE_STRIP = NO;
        \t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
        \t\t\t\tENABLE_NS_ASSERTIONS = NO;
        \t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
        \t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;
        \t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
        \t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
        \t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
        \t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
        \t\t\t\tSDKROOT = iphoneos;
        \t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
        \t\t\t\tVALIDATE_PRODUCT = YES;
        \t\t\t}};
        \t\t\tname = Release;
        \t\t}};
        \t\t{ids['build_config_target_debug']} /* Debug */ = {{
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {{
        \t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
        \t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
        \t\t\t\tCODE_SIGN_ENTITLEMENTS = "{PROJECT_NAME}/{PROJECT_NAME}.entitlements";
        \t\t\t\tCODE_SIGN_STYLE = Automatic;
        \t\t\t\tCURRENT_PROJECT_VERSION = 1;
        \t\t\t\tENABLE_PREVIEWS = YES;
        \t\t\t\tGENERATE_INFOPLIST_FILE = YES;
        {infoplist_keys_block}
        \t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
        \t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
        \t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
        \t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
        \t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
        \t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
        \t\t\t\t\t"$(inherited)",
        \t\t\t\t\t"@executable_path/Frameworks",
        \t\t\t\t);
        \t\t\t\tMARKETING_VERSION = 1.0;
        \t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
        \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
        \t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
        \t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
        \t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
        \t\t\t}};
        \t\t\tname = Debug;
        \t\t}};
        \t\t{ids['build_config_target_release']} /* Release */ = {{
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {{
        \t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
        \t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
        \t\t\t\tCODE_SIGN_ENTITLEMENTS = "{PROJECT_NAME}/{PROJECT_NAME}.entitlements";
        \t\t\t\tCODE_SIGN_STYLE = Automatic;
        \t\t\t\tCURRENT_PROJECT_VERSION = 1;
        \t\t\t\tENABLE_PREVIEWS = YES;
        \t\t\t\tGENERATE_INFOPLIST_FILE = YES;
        {infoplist_keys_block}
        \t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
        \t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
        \t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
        \t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
        \t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
        \t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
        \t\t\t\t\t"$(inherited)",
        \t\t\t\t\t"@executable_path/Frameworks",
        \t\t\t\t);
        \t\t\t\tMARKETING_VERSION = 1.0;
        \t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
        \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
        \t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
        \t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
        \t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
        \t\t\t}};
        \t\t\tname = Release;
        \t\t}};
        {test_buildconfig_section}
        /* End XCBuildConfiguration section */

        /* Begin XCConfigurationList section */
        \t\t{ids['build_config_list_proj']} /* Build configuration list for PBXProject "{PROJECT_NAME}" */ = {{
        \t\t\tisa = XCConfigurationList;
        \t\t\tbuildConfigurations = (
        \t\t\t\t{ids['build_config_proj_debug']} /* Debug */,
        \t\t\t\t{ids['build_config_proj_release']} /* Release */,
        \t\t\t);
        \t\t\tdefaultConfigurationIsVisible = 0;
        \t\t\tdefaultConfigurationName = Release;
        \t\t}};
        \t\t{ids['build_config_list_target']} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */ = {{
        \t\t\tisa = XCConfigurationList;
        \t\t\tbuildConfigurations = (
        \t\t\t\t{ids['build_config_target_debug']} /* Debug */,
        \t\t\t\t{ids['build_config_target_release']} /* Release */,
        \t\t\t);
        \t\t\tdefaultConfigurationIsVisible = 0;
        \t\t\tdefaultConfigurationName = Release;
        \t\t}};
        {test_buildconfig_list_section}
        /* End XCConfigurationList section */

        /* Begin XCRemoteSwiftPackageReference section */
        {remote_pkg_section}
        /* End XCRemoteSwiftPackageReference section */

        /* Begin XCSwiftPackageProductDependency section */
        {product_dep_section}
        /* End XCSwiftPackageProductDependency section */
        \t}};
        \trootObject = {ids['project']} /* Project object */;
        }}
        """)

    return pbxproj


def main() -> int:
    proj_dir = ROOT / f"{PROJECT_NAME}.xcodeproj"
    proj_dir.mkdir(exist_ok=True)
    pbxproj_path = proj_dir / "project.pbxproj"
    pbxproj_path.write_text(generate(), encoding="utf-8")
    print(f"[ok] wrote {pbxproj_path}  ({pbxproj_path.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
