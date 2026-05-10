//  FeishuBitableClient.swift
//  CoinFlow · M9 · 飞书多维表格 HTTP 客户端
//
//  职责：
//  - ensureBitableExists()：首次调用时自动创建多维表格 + 11 字段
//  - createRecord(fields)：新建一行；返回飞书 record_id 写回本地 remoteId
//  - updateRecord(recordId, fields)：按 recordId 更新行（含软删 = 把"已删除"打勾）
//  - searchAllRecords()：手动拉取场景，分页拉全表
//
//  鉴权：Authorization: Bearer {tenant_access_token}
//  错误处理：401/403 自动刷 token 重试 1 次；其他错误向上抛分类错误。
//
//  设计：actor 隔离（避免多并发 ensureBitableExists 竞争创建多张表）；
//  与 @MainActor UI 层通过 await 调用即可，不强制绑到 MainActor。

import Foundation

// MARK: - Errors

enum FeishuBitableError: Error, LocalizedError {
    case notConfigured
    case authFailed(underlying: Error)
    case network(underlying: Error)
    case httpStatus(code: Int, body: String)
    case apiError(code: Int, msg: String, raw: String)
    case decodeFailed(reason: String)
    case bitableNotInitialized

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "飞书未配置（缺 App ID / Secret）"
        case .authFailed(let e):       return "飞书鉴权失败：\(e.localizedDescription)"
        case .network(let e):          return "飞书网络异常：\(e.localizedDescription)"
        case .httpStatus(let c, _):    return "飞书 HTTP 错误 \(c)"
        case .apiError(let c, let m, _): return "飞书 API code=\(c) msg=\(m)"
        case .decodeFailed(let r):     return "飞书响应解析失败：\(r)"
        case .bitableNotInitialized:   return "多维表格未初始化"
        }
    }

    /// 网络/5xx/限流(429) 视为 transient
    var isTransient: Bool {
        switch self {
        case .network: return true
        case .httpStatus(let c, _): return c >= 500 || c == 429
        case .authFailed(let e):
            if let a = e as? FeishuAuthError { return a.isTransient }
            return true
        case .apiError(let c, _, _):
            // 飞书常见 transient code：99991663 (token 即将过期)、9499 (限流)
            return c == 99991663 || c == 9499
        case .notConfigured, .decodeFailed, .bitableNotInitialized: return false
        }
    }
}

// MARK: - Field schema

/// 飞书多维表格中"账单"表的字段名常量（中文，用户在飞书里能直接看懂）。
///
/// Q1=A 映射：record.note 写入主键列「账单描述」；不再额外建「备注」字段。
enum FeishuFieldName {
    /// 主键列（Text）。Q1=A：存 record.note 的内容（备注/账单描述）
    static let billDescription = "账单描述"
    /// 业务主键（UUID，= record.id），独立 Text 列用于去重与关联
    static let billId      = "单据ID"
    static let occurredAt  = "日期"
    static let amount      = "金额"
    static let currency    = "货币"
    static let direction   = "收支"
    static let category    = "分类"
    /// @deprecated M9-Fix1 已合并到 billDescription（主键列）；保留常量供旧 mapper 过渡
    static let note        = "备注"
    static let source      = "来源"
    static let createdAt   = "创建时间"
    static let updatedAt   = "更新时间"
    static let deleted     = "已删除"
    /// M9-Fix4：附件字段（type=17 Attachment），用于归档 OCR 截图
    static let attachment  = "附件"
    /// M9-Fix5：支付渠道（type=3 SingleSelect：微信/支付宝/抖音/银行/其他），仅 OCR 账单填
    static let channel     = "渠道"
}

/// 远端搜索回来的行（带 record_id），用于手动拉取重建本地。
struct FeishuRemoteRow {
    let recordId: String         // 飞书 record_id
    let fields: [String: Any]    // 原始字段 dict（由 RecordBitableMapper.decode 处理）
}

// MARK: - Client

actor FeishuBitableClient {

    static let shared = FeishuBitableClient()
    private init() {}

    private let tokenManager = FeishuTokenManager.shared
    private let session: URLSession = .shared
    private let host = "https://open.feishu.cn"

    /// 防止并发 ensureBitableExists 同时建多张表
    private var bootstrapTask: Task<Void, Error>?

    /// M9-Fix3：本次进程内是否已尝试过给 owner 加权限。每次启动 App 至少补一次（幂等）。
    private var ownerGrantedThisSession = false
    /// M9-Fix4：本次进程内是否已补过字段（fast path 下补齐新版本新增字段，如「附件」）
    private var fieldsEnsuredThisSession = false

    // MARK: - Bitable bootstrap

    /// 保证多维表格存在；不存在则创建（带主表 + 11 字段）。幂等。
    func ensureBitableExists() async throws {
        if FeishuConfig.hasBitable {
            // Fast path：缓存有效，但本次进程还没补过以下两件事就主动补（幂等 API）：
            //   1) owner 协作者权限 (M9-Fix3)
            //   2) 最新版本新增的字段，如「附件」(M9-Fix4)
            // 用于：App 升级后已建表的存量用户首次启动时自动补齐
            if let appToken = FeishuConfig.bitableAppToken,
               let tableId = FeishuConfig.billsTableId {
                if !ownerGrantedThisSession {
                    ownerGrantedThisSession = true
                    await grantOwnerPermissionIfNeeded(appToken: appToken)
                }
                if !fieldsEnsuredThisSession {
                    fieldsEnsuredThisSession = true
                    try? await ensureFieldsComplete(appToken: appToken, tableId: tableId)
                }
            }
            return
        }
        guard FeishuConfig.isConfigured else {
            throw FeishuBitableError.notConfigured
        }
        // 串行化重入
        if let task = bootstrapTask {
            try await task.value
            return
        }
        let task = Task<Void, Error> { try await self.doBootstrap() }
        bootstrapTask = task
        defer { bootstrapTask = nil }
        try await task.value
        // bootstrap 内部已 grant + ensureFields；标记防本进程重复补
        ownerGrantedThisSession = true
        fieldsEnsuredThisSession = true
    }

    private func doBootstrap() async throws {
        // 重检（外层无锁的 fast path 已检查过；这里防并发后再次进入）
        if FeishuConfig.hasBitable { return }

        if FeishuConfig.isWikiMode {
            // Wiki 模式：用户在飞书 Wiki 下建好多维表格 + 指定 table_id，App 不再自动建表
            try await bootstrapInWikiMode()
        } else {
            // 自动建表模式（fallback）：在用户"我的空间"根目录创建新的多维表格
            try await bootstrapInAutoCreateMode()
        }
    }

    // MARK: - Wiki 模式 bootstrap

    /// 用户指定了 Wiki Node Token + Table Id 时走这里。
    /// 把 Wiki node_token 换成真实 bitable obj_token，补齐缺失字段，删预置空白行。
    private func bootstrapInWikiMode() async throws {
        let wikiNodeToken = FeishuConfig.wikiNodeToken
        let tableId = FeishuConfig.configuredTableId

        // Step 1: Wiki node_token → 真实 bitable app_token (obj_token)
        let nodeResp: [String: Any] = try await callAPI(
            method: "GET",
            path: "/open-apis/wiki/v2/spaces/get_node?token=\(wikiNodeToken)",
            body: nil
        )
        guard let node = nodeResp["node"] as? [String: Any],
              let objType = node["obj_type"] as? String,
              objType == "bitable",
              let appToken = node["obj_token"] as? String,
              !appToken.isEmpty else {
            throw FeishuBitableError.decodeFailed(
                reason: "Wiki node 不是多维表格（obj_type=\(nodeResp["node"].map { String(describing: $0) } ?? "nil"))"
            )
        }
        let title = (node["title"] as? String) ?? ""
        let bitableURL = "https://my.feishu.cn/wiki/\(wikiNodeToken)?table=\(tableId)"

        // Step 2: 确保 table 存在 + 补齐缺失字段（不改/不删用户已建的字段）
        try await ensureFieldsComplete(appToken: appToken, tableId: tableId)

        // Step 3: 删除预置空白行（如果用户/飞书自动插入的空行还在）
        await cleanupEmptyRows(appToken: appToken, tableId: tableId)

        // Step 4: 持久化
        FeishuConfig.bitableAppToken = appToken
        FeishuConfig.billsTableId = tableId
        FeishuConfig.bitableURL = bitableURL
        SyncLogger.info(phase: "feishu.bootstrap",
                        "Wiki mode ready: title=\(title) app_token=\(appToken) table_id=\(tableId)")
    }

    // MARK: - 自动建表模式 bootstrap（fallback）

    private func bootstrapInAutoCreateMode() async throws {
        // Step 1: 创建多维表格 App
        let appName = "CoinFlow 账单"
        let folderToken = FeishuConfig.folderToken
        var createBody: [String: Any] = ["name": appName]
        if !folderToken.isEmpty {
            createBody["folder_token"] = folderToken
        }
        let createResp: [String: Any] = try await callAPI(
            method: "POST",
            path: "/open-apis/bitable/v1/apps",
            body: createBody
        )
        guard let appData = createResp["app"] as? [String: Any],
              let appToken = appData["app_token"] as? String,
              !appToken.isEmpty,
              let tableId = appData["default_table_id"] as? String,
              !tableId.isEmpty else {
            throw FeishuBitableError.decodeFailed(
                reason: "创建 App 未返回 app_token / default_table_id"
            )
        }
        let bitableURL = (appData["url"] as? String) ?? ""

        // Step 2: 处理飞书新建 App 自带的预置字段（主键改名 + 删非主键预置字段）
        try await normalizePresetFields(appToken: appToken, tableId: tableId)

        // Step 3: 补齐缺失字段
        try await ensureFieldsComplete(appToken: appToken, tableId: tableId)

        // Step 4: 删预置空白行
        await cleanupEmptyRows(appToken: appToken, tableId: tableId)

        // Step 4.5: M9-Fix3 给配置的用户加 full_access 协作者权限（用户能在飞书直接编辑表）
        await grantOwnerPermissionIfNeeded(appToken: appToken)

        // Step 5: 持久化
        FeishuConfig.bitableAppToken = appToken
        FeishuConfig.billsTableId = tableId
        FeishuConfig.bitableURL = bitableURL
        SyncLogger.info(phase: "feishu.bootstrap",
                        "Auto-create mode ready: app_token=\(appToken) table_id=\(tableId) url=\(bitableURL)")
    }

    // MARK: - Bootstrap 工具函数

    /// 自动建表模式：把飞书默认的"文本"主键改名为目标主键名，删掉其它非主键预置字段。
    /// 主键命名遵循"账单描述"语义（Q1=A：主键列存备注/描述，与 Wiki 表已有结构一致）。
    private func normalizePresetFields(appToken: String, tableId: String) async throws {
        let listResp: [String: Any] = try await callAPI(
            method: "GET",
            path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields",
            body: nil
        )
        let existingItems = (listResp["items"] as? [[String: Any]]) ?? []
        for item in existingItems {
            guard let fieldId = item["field_id"] as? String else { continue }
            let isPrimary = (item["is_primary"] as? Bool) ?? false
            let name = (item["field_name"] as? String) ?? ""
            if isPrimary {
                // 主键改名为「账单描述」（若名字已是目标值则跳过）
                if name != FeishuFieldName.billDescription {
                    _ = try? await callAPI(
                        method: "PUT",
                        path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields/\(fieldId)",
                        body: ["field_name": FeishuFieldName.billDescription, "type": 1]
                    ) as [String: Any]
                }
            } else {
                // 删非主键预置字段（单选/日期/附件 等）
                _ = try? await callAPI(
                    method: "DELETE",
                    path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields/\(fieldId)",
                    body: nil
                ) as [String: Any]
            }
        }
    }

    /// 通用"补齐字段"：list 现有字段，只为缺失的字段调 POST /fields；
    /// 已存在的字段（不管类型对不对）一律不动（Wiki 模式尊重用户已有设计）。
    private func ensureFieldsComplete(appToken: String, tableId: String) async throws {
        let listResp: [String: Any] = try await callAPI(
            method: "GET",
            path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields",
            body: nil
        )
        let existingItems = (listResp["items"] as? [[String: Any]]) ?? []
        let existingNames: Set<String> = Set(
            existingItems.compactMap { $0["field_name"] as? String }
        )

        // 期望的 10 个非主键字段（主键"账单描述"映射备注，不重复建）
        // type 1=文本 2=数字 3=单选 5=日期时间 7=复选框
        let desiredFields: [[String: Any]] = [
            ["field_name": FeishuFieldName.billId,     "type": 1],
            ["field_name": FeishuFieldName.occurredAt, "type": 5],
            ["field_name": FeishuFieldName.amount,     "type": 2],
            ["field_name": FeishuFieldName.currency,   "type": 3,
             "property": ["options": [
                ["name": "CNY"], ["name": "USD"], ["name": "HKD"], ["name": "EUR"], ["name": "JPY"]
             ]]],
            ["field_name": FeishuFieldName.direction,  "type": 3,
             "property": ["options": [["name": "支出"], ["name": "收入"]]]],
            ["field_name": FeishuFieldName.category,   "type": 1],
            ["field_name": FeishuFieldName.source,     "type": 3,
             "property": ["options": [
                ["name": "手动"], ["name": "截图OCR-Vision"], ["name": "截图OCR-API"],
                ["name": "截图OCR-LLM"], ["name": "语音-本地"], ["name": "语音-云端"]
             ]]],
            ["field_name": FeishuFieldName.createdAt,  "type": 5],
            ["field_name": FeishuFieldName.updatedAt,  "type": 5],
            ["field_name": FeishuFieldName.deleted,    "type": 7],
            ["field_name": FeishuFieldName.attachment, "type": 17],
            ["field_name": FeishuFieldName.channel,    "type": 3,
             "property": ["options": [
                ["name": "微信"], ["name": "支付宝"], ["name": "抖音"],
                ["name": "银行"], ["name": "其他"]
             ]]]
        ]
        for def in desiredFields {
            guard let name = def["field_name"] as? String,
                  !existingNames.contains(name) else { continue }
            do {
                _ = try await callAPI(
                    method: "POST",
                    path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields",
                    body: def
                ) as [String: Any]
                SyncLogger.info(phase: "feishu.bootstrap", "added field: \(name)")
            } catch FeishuBitableError.apiError(let code, _, _) where code == 1254014 {
                // 重名字段；忽略
                continue
            }
        }
    }

    /// 删除表里 fields=[] 的预置空白行（飞书新建 App 自带 10 条 / Wiki 里用户也可能留了空行）
    private func cleanupEmptyRows(appToken: String, tableId: String) async {
        do {
            let searchResp = try await callAPI(
                method: "POST",
                path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/search?page_size=500",
                body: [:]
            )
            let items = (searchResp["items"] as? [[String: Any]]) ?? []
            let emptyIds: [String] = items.compactMap { item in
                guard let rid = item["record_id"] as? String,
                      let fields = item["fields"] as? [String: Any],
                      fields.isEmpty else { return nil }
                return rid
            }
            if !emptyIds.isEmpty {
                _ = try? await callAPI(
                    method: "POST",
                    path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/batch_delete",
                    body: ["records": emptyIds]
                )
                SyncLogger.info(phase: "feishu.bootstrap",
                                "deleted \(emptyIds.count) empty preset rows")
            }
        } catch {
            SyncLogger.warn(phase: "feishu.bootstrap",
                            "skip preset row cleanup: \(error.localizedDescription)")
        }
    }

    /// M9-Fix3 · 给配置的用户加 full_access 协作者权限。
    /// - 自建应用 tenant_access_token 创建的多维表格，应用 owner（用户）默认只有"查看"权限
    /// - 调 drive.permissions.members.create 把用户加为 full_access 后，用户就能在飞书直接编辑
    /// - 仅在 Config.plist 配了 Feishu_Owner_Open_ID 时生效；幂等：重复 add 飞书会返回成功
    /// - 失败不阻塞同步（属于"用户体验增强"非致命）
    private func grantOwnerPermissionIfNeeded(appToken: String) async {
        let openID = FeishuConfig.ownerOpenID
        guard !openID.isEmpty else {
            SyncLogger.info(phase: "feishu.bootstrap",
                            "skip grant owner perm: Feishu_Owner_Open_ID 未配置")
            return
        }
        do {
            _ = try await callAPI(
                method: "POST",
                path: "/open-apis/drive/v1/permissions/\(appToken)/members?type=bitable&need_notification=false",
                body: [
                    "member_type": "openid",
                    "member_id": openID,
                    "perm": "full_access"
                ]
            )
            SyncLogger.info(phase: "feishu.bootstrap",
                            "granted full_access to owner openid=\(openID.prefix(15))...")
        } catch {
            // 非致命：用户依然能在飞书里看到表（只是只读权限）；管理员可以手动改
            SyncLogger.warn(phase: "feishu.bootstrap",
                            "grant owner perm failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD

    /// 新建一行；返回飞书 record_id（写回本地 Record.remoteId）。
    func createRecord(fields: [String: Any]) async throws -> String {
        try await ensureBitableExists()
        guard let appToken = FeishuConfig.bitableAppToken,
              let tableId = FeishuConfig.billsTableId else {
            throw FeishuBitableError.bitableNotInitialized
        }
        let resp: [String: Any] = try await callAPI(
            method: "POST",
            path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records",
            body: ["fields": fields]
        )
        guard let recordObj = resp["record"] as? [String: Any],
              let recordId = recordObj["record_id"] as? String,
              !recordId.isEmpty else {
            throw FeishuBitableError.decodeFailed(reason: "create record 未返回 record_id")
        }
        return recordId
    }

    /// 按 record_id 更新一行字段（含软删=把"已删除"打勾）。
    func updateRecord(recordId: String, fields: [String: Any]) async throws {
        try await ensureBitableExists()
        guard let appToken = FeishuConfig.bitableAppToken,
              let tableId = FeishuConfig.billsTableId else {
            throw FeishuBitableError.bitableNotInitialized
        }
        _ = try await callAPI(
            method: "PUT",
            path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/\(recordId)",
            body: ["fields": fields]
        ) as [String: Any]
    }

    /// 拉取全表（手动同步用），分页直到取完。
    /// - Returns: 飞书所有行（含已删除标记的，调用方自行过滤）
    func searchAllRecords() async throws -> [FeishuRemoteRow] {
        try await ensureBitableExists()
        guard let appToken = FeishuConfig.bitableAppToken,
              let tableId = FeishuConfig.billsTableId else {
            throw FeishuBitableError.bitableNotInitialized
        }
        var out: [FeishuRemoteRow] = []
        var pageToken: String? = nil
        let pageSize = 200  // 飞书 search 最大 500，取保守值
        repeat {
            var query: [String] = ["page_size=\(pageSize)"]
            if let t = pageToken, !t.isEmpty {
                let escaped = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
                query.append("page_token=\(escaped)")
            }
            let path = "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/search?" + query.joined(separator: "&")
            // search 接口必须 POST 带 body（即使 body 为空 {}）
            let resp: [String: Any] = try await callAPI(
                method: "POST",
                path: path,
                body: [:]
            )
            if let items = resp["items"] as? [[String: Any]] {
                for item in items {
                    guard let rid = item["record_id"] as? String,
                          let fields = item["fields"] as? [String: Any] else { continue }
                    out.append(FeishuRemoteRow(recordId: rid, fields: fields))
                }
            }
            let hasMore = (resp["has_more"] as? Bool) ?? false
            pageToken = hasMore ? (resp["page_token"] as? String) : nil
        } while pageToken != nil && !(pageToken?.isEmpty ?? true)
        return out
    }

    // MARK: - 附件上传（M9-Fix4）

    /// 上传截图到飞书素材库，返回 file_token。
    /// - Parameter data: JPEG 字节
    /// - Parameter recordId: 用于生成飞书可读的文件名 `coinflow-{recordId}.jpg`
    /// - Returns: 飞书 file_token（写入 bitable 附件字段时用）
    func uploadAttachment(data: Data, recordId: String) async throws -> String {
        try await ensureBitableExists()
        guard let appToken = FeishuConfig.bitableAppToken else {
            throw FeishuBitableError.bitableNotInitialized
        }
        let token: String
        do {
            token = try await tokenManager.getToken()
        } catch {
            throw FeishuBitableError.authFailed(underlying: error)
        }
        // multipart/form-data 字段说明（飞书 docs）：
        // file_name / parent_type=bitable_image / parent_node=<app_token> / size=<bytes> / file=<binary>
        let fileName = "coinflow-\(recordId).jpg"
        let boundary = "----coinflow-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("file_name", value: fileName)
        appendField("parent_type", value: "bitable_image")
        appendField("parent_node", value: appToken)
        appendField("size", value: "\(data.count)")
        // file 字段（binary）
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "\(host)/open-apis/drive/v1/medias/upload_all")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 30 // 截图较大，给宽松超时

        let (respData, response): (Data, URLResponse)
        do {
            (respData, response) = try await session.data(for: req)
        } catch {
            throw FeishuBitableError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FeishuBitableError.decodeFailed(reason: "no HTTPURLResponse")
        }
        let bodyStr = String(data: respData, encoding: .utf8) ?? ""
        if http.statusCode < 200 || http.statusCode >= 300 {
            throw FeishuBitableError.httpStatus(code: http.statusCode, body: bodyStr)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            throw FeishuBitableError.decodeFailed(reason: "JSON 解析失败")
        }
        let code = (obj["code"] as? Int) ?? -1
        if code != 0 {
            let msg = (obj["msg"] as? String) ?? "unknown"
            throw FeishuBitableError.apiError(code: code, msg: msg, raw: bodyStr)
        }
        guard let dataObj = obj["data"] as? [String: Any],
              let fileToken = dataObj["file_token"] as? String,
              !fileToken.isEmpty else {
            throw FeishuBitableError.decodeFailed(reason: "upload 响应缺 file_token")
        }
        return fileToken
    }

    // MARK: - HTTP core

    /// 通用 API 调用：自动注入 token；401/403 自动刷新 1 次；
    /// 解析飞书统一响应壳 `{code, msg, data}`，返回 data 字典；其它错误向上抛。
    /// - Parameter body: 请求体；GET / DELETE 等无 body 接口传 nil
    private func callAPI(method: String,
                         path: String,
                         body: [String: Any]?) async throws -> [String: Any] {
        return try await callAPIInternal(method: method, path: path, body: body, retried: false)
    }

    private func callAPIInternal(method: String,
                                 path: String,
                                 body: [String: Any]?,
                                 retried: Bool) async throws -> [String: Any] {
        let token: String
        do {
            token = try await tokenManager.getToken()
        } catch {
            throw FeishuBitableError.authFailed(underlying: error)
        }
        guard let url = URL(string: host + path) else {
            throw FeishuBitableError.decodeFailed(reason: "URL 拼接失败：\(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // 飞书 search 接口要求 POST + 合法 JSON body（即使内容是 {}）
        // GET / DELETE 不带 body
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw FeishuBitableError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FeishuBitableError.decodeFailed(reason: "no HTTPURLResponse")
        }
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        // 401/403 → 刷 token 重试 1 次
        if (http.statusCode == 401 || http.statusCode == 403) && !retried {
            _ = try? await tokenManager.invalidateAndRefresh()
            return try await callAPIInternal(method: method, path: path,
                                             body: body, retried: true)
        }
        if http.statusCode < 200 || http.statusCode >= 300 {
            throw FeishuBitableError.httpStatus(code: http.statusCode, body: bodyStr)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeishuBitableError.decodeFailed(reason: "JSON 解析失败")
        }
        let code = (obj["code"] as? Int) ?? -1
        if code != 0 {
            let msg = (obj["msg"] as? String) ?? "unknown"
            // token 失效特例 99991663 → 刷 token 重试 1 次
            if code == 99991663 && !retried {
                _ = try? await tokenManager.invalidateAndRefresh()
                return try await callAPIInternal(method: method, path: path,
                                                 body: body, retried: true)
            }
            throw FeishuBitableError.apiError(code: code, msg: msg, raw: bodyStr)
        }
        if let data = obj["data"] as? [String: Any] { return data }
        return [:]
    }
}
