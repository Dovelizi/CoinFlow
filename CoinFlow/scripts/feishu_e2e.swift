#!/usr/bin/env swift
//  feishu_e2e.swift
//  CoinFlow · M9 · 飞书多维表格端到端集成测试
//
//  独立 Swift 脚本，跑全链路：
//    T1 获取 tenant_access_token
//    T2 创建多维表格 + 11 字段
//    T3 写入测试 record
//    T4 更新该 record（改金额）
//    T5 软删该 record（"已删除"打勾）
//    T6 拉取全表，验证软删标记可见
//
//  使用：
//    cd CoinFlow && swift scripts/feishu_e2e.swift

import Foundation

// MARK: - Config 读取

let configURL = URL(fileURLWithPath: "CoinFlow/Config/Config.plist")
guard let configData = try? Data(contentsOf: configURL),
      let plist = try? PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any] else {
    print("❌ 无法读取 \(configURL.path)")
    exit(1)
}
let appID = (plist["Feishu_App_ID"] as? String) ?? ""
let appSecret = (plist["Feishu_App_Secret"] as? String) ?? ""
guard !appID.isEmpty, !appSecret.isEmpty else {
    print("❌ Config.plist 缺少 Feishu_App_ID / Feishu_App_Secret")
    exit(1)
}
print("✓ Config 读取成功: appID=\(appID.prefix(20))...")

let host = "https://open.feishu.cn"
let session = URLSession.shared

// MARK: - HTTP helpers

enum HTTPError: Error { case bad(Int, String); case empty; case decode }

func httpJSON(method: String, path: String, body: [String: Any]?,
              headers: [String: String] = [:]) async throws -> [String: Any] {
    var req = URLRequest(url: URL(string: host + path)!)
    req.httpMethod = method
    req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if let body = body {
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
    } else if method == "POST" {
        req.httpBody = "{}".data(using: .utf8)
    }
    req.timeoutInterval = 15
    let (data, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw HTTPError.empty }
    let bodyStr = String(data: data, encoding: .utf8) ?? ""
    if http.statusCode < 200 || http.statusCode >= 300 {
        throw HTTPError.bad(http.statusCode, bodyStr)
    }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw HTTPError.decode
    }
    let code = (obj["code"] as? Int) ?? -1
    if code != 0 {
        throw HTTPError.bad(code, "API err: \(obj["msg"] as? String ?? "?") | body=\(bodyStr.prefix(300))")
    }
    return (obj["data"] as? [String: Any]) ?? [:]
}

func extractText(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    if let arr = v as? [[String: Any]] {
        return arr.compactMap { $0["text"] as? String }.joined()
    }
    return nil
}

// MARK: - 飞书 API

func getTenantAccessToken() async throws -> String {
    var req = URLRequest(url: URL(string: "\(host)/open-apis/auth/v3/tenant_access_token/internal")!)
    req.httpMethod = "POST"
    req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    let body = ["app_id": appID, "app_secret": appSecret]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    req.timeoutInterval = 10
    let (data, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw HTTPError.empty }
    let raw = String(data: data, encoding: .utf8) ?? ""
    if http.statusCode < 200 || http.statusCode >= 300 {
        throw HTTPError.bad(http.statusCode, raw)
    }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HTTPError.decode }
    let code = (obj["code"] as? Int) ?? -1
    if code != 0 {
        throw HTTPError.bad(code, "API err: \(obj["msg"] as? String ?? "?") | body=\(raw.prefix(300))")
    }
    guard let token = obj["tenant_access_token"] as? String, !token.isEmpty else {
        throw HTTPError.decode
    }
    return token
}

func createBitable(authHeaders: [String: String])
    async throws -> (appToken: String, tableId: String, url: String)
{
    let appResp = try await httpJSON(
        method: "POST",
        path: "/open-apis/bitable/v1/apps",
        body: ["name": "CoinFlow E2E 测试 \(Int(Date().timeIntervalSince1970))"],
        headers: authHeaders
    )
    guard let appData = appResp["app"] as? [String: Any],
          let appToken = appData["app_token"] as? String,
          let tableId = appData["default_table_id"] as? String else {
        throw HTTPError.decode
    }
    let url = (appData["url"] as? String) ?? ""

    // 处理飞书新建 App 自带的 4 个预置字段（与 iOS Bootstrap 一致）：
    //   - "文本"主键 → 改名为「账单描述」（用于存 record.note）
    //   - 其余非主键预置字段（"单选" / "日期" / "附件"）→ 全部删除
    let listURL = URL(string: "\(host)/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields")!
    var listReq = URLRequest(url: listURL)
    listReq.httpMethod = "GET"
    for (k, v) in authHeaders { listReq.setValue(v, forHTTPHeaderField: k) }
    let (listData, _) = try await session.data(for: listReq)
    let listObj = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
    let items = (listObj?["data"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
    for item in items {
        guard let fieldId = item["field_id"] as? String else { continue }
        let isPrimary = (item["is_primary"] as? Bool) ?? false
        if isPrimary {
            _ = try? await httpJSON(
                method: "PUT",
                path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields/\(fieldId)",
                body: ["field_name": "账单描述", "type": 1],
                headers: authHeaders
            )
        } else {
            // DELETE 不带 body
            var delReq = URLRequest(url: URL(string: "\(host)/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields/\(fieldId)")!)
            delReq.httpMethod = "DELETE"
            for (k, v) in authHeaders { delReq.setValue(v, forHTTPHeaderField: k) }
            _ = try? await session.data(for: delReq)
        }
    }

    // 加剩余 10 个字段（不再建独立「备注」列，note 写入主键「账单描述」）
    let fieldDefs: [[String: Any]] = [
        ["field_name": "单据ID", "type": 1],
        ["field_name": "日期", "type": 5],
        ["field_name": "金额", "type": 2],
        ["field_name": "货币", "type": 3,
         "property": ["options": [["name": "CNY"], ["name": "USD"], ["name": "HKD"]]]],
        ["field_name": "收支", "type": 3,
         "property": ["options": [["name": "支出"], ["name": "收入"]]]],
        ["field_name": "分类", "type": 1],
        ["field_name": "来源", "type": 3,
         "property": ["options": [
            ["name": "手动"], ["name": "截图OCR-Vision"], ["name": "截图OCR-API"],
            ["name": "截图OCR-LLM"], ["name": "语音-本地"], ["name": "语音-云端"]
         ]]],
        ["field_name": "创建时间", "type": 5],
        ["field_name": "更新时间", "type": 5],
        ["field_name": "已删除", "type": 7]
    ]
    for def in fieldDefs {
        do {
            _ = try await httpJSON(
                method: "POST",
                path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields",
                body: def,
                headers: authHeaders
            )
        } catch HTTPError.bad(let code, _) where code == 1254014 {
            continue
        }
    }

    // 删除飞书新建 App 自带的预置空白行
    do {
        let searchResp = try await httpJSON(
            method: "POST",
            path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/search?page_size=100",
            body: [:],
            headers: authHeaders
        )
        let items = (searchResp["items"] as? [[String: Any]]) ?? []
        let emptyIds: [String] = items.compactMap { item in
            guard let rid = item["record_id"] as? String,
                  let fields = item["fields"] as? [String: Any],
                  fields.isEmpty else { return nil }
            return rid
        }
        if !emptyIds.isEmpty {
            _ = try? await httpJSON(
                method: "POST",
                path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/batch_delete",
                body: ["records": emptyIds],
                headers: authHeaders
            )
            print("✓ 删除 \(emptyIds.count) 条预置空白行")
        }
    } catch {
        // ignore
    }
    return (appToken, tableId, url)
}

func createRecord(appToken: String, tableId: String,
                  fields: [String: Any],
                  authHeaders: [String: String]) async throws -> String {
    let resp = try await httpJSON(
        method: "POST",
        path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records",
        body: ["fields": fields],
        headers: authHeaders
    )
    guard let r = resp["record"] as? [String: Any],
          let rid = r["record_id"] as? String else {
        throw HTTPError.decode
    }
    return rid
}

func updateRecord(appToken: String, tableId: String,
                  recordId: String, fields: [String: Any],
                  authHeaders: [String: String]) async throws {
    _ = try await httpJSON(
        method: "PUT",
        path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/\(recordId)",
        body: ["fields": fields],
        headers: authHeaders
    )
}

func searchAllRecords(appToken: String, tableId: String,
                      authHeaders: [String: String]) async throws -> [[String: Any]] {
    let resp = try await httpJSON(
        method: "POST",
        path: "/open-apis/bitable/v1/apps/\(appToken)/tables/\(tableId)/records/search?page_size=100",
        body: [:],
        headers: authHeaders
    )
    return (resp["items"] as? [[String: Any]]) ?? []
}

// MARK: - 主流程

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

Task {
    defer { semaphore.signal() }
    do {
        // T1
        print("\n═══ T1 获取 tenant_access_token ═══")
        let token = try await getTenantAccessToken()
        print("✓ token=\(token.prefix(15))...")
        let auth = ["Authorization": "Bearer \(token)"]

        // T2
        print("\n═══ T2 创建多维表格 + 11 字段 ═══")
        let (appToken, tableId, url) = try await createBitable(authHeaders: auth)
        print("✓ app_token=\(appToken)")
        print("✓ table_id=\(tableId)")
        print("✓ url=\(url)")

        // T3
        print("\n═══ T3 写入测试 record ═══")
        let testId = "e2e-test-\(Int(Date().timeIntervalSince1970))"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let writeFields: [String: Any] = [
            "账单描述": "E2E 测试 · 写入",
            "单据ID": testId,
            "日期": nowMs,
            "金额": 99.99,
            "货币": "CNY",
            "收支": "支出",
            "分类": "餐饮",
            "来源": "手动",
            "创建时间": nowMs,
            "更新时间": nowMs,
            "已删除": false
        ]
        let recordId = try await createRecord(
            appToken: appToken, tableId: tableId,
            fields: writeFields, authHeaders: auth
        )
        print("✓ 写入成功 record_id=\(recordId)")

        // T4
        print("\n═══ T4 更新 record（金额 99.99 → 199.99）═══")
        var updateFields = writeFields
        updateFields["金额"] = 199.99
        updateFields["账单描述"] = "E2E 测试 · 更新"
        updateFields["更新时间"] = Int64(Date().timeIntervalSince1970 * 1000)
        try await updateRecord(
            appToken: appToken, tableId: tableId,
            recordId: recordId, fields: updateFields, authHeaders: auth
        )
        print("✓ 更新成功")

        // T5
        print("\n═══ T5 软删 record（已删除 = true，行不真删）═══")
        var deleteFields = updateFields
        deleteFields["已删除"] = true
        deleteFields["账单描述"] = "E2E 测试 · 已软删"
        try await updateRecord(
            appToken: appToken, tableId: tableId,
            recordId: recordId, fields: deleteFields, authHeaders: auth
        )
        print("✓ 软删成功（行仍存在，已删除=true）")

        // T6
        print("\n═══ T6 拉取全表 ═══")
        let rows = try await searchAllRecords(
            appToken: appToken, tableId: tableId, authHeaders: auth
        )
        print("✓ 拉取 \(rows.count) 行")
        let me = rows.first { row in
            guard let f = row["fields"] as? [String: Any] else { return false }
            let id = (f["单据ID"] as? String) ?? extractText(f["单据ID"]) ?? ""
            return id == testId
        }
        if let me = me, let fields = me["fields"] as? [String: Any] {
            let amountVal = (fields["金额"] as? Double) ?? 0
            let deletedVal = (fields["已删除"] as? Bool) ?? false
            print("✓ 找到测试行：金额=\(amountVal) 已删除=\(deletedVal)")
            if abs(amountVal - 199.99) > 0.01 {
                print("⚠ 金额未更新到 199.99 (实际=\(amountVal))")
                exitCode = 1
            }
            if !deletedVal {
                print("⚠ 已删除字段未变 true")
                exitCode = 1
            }
        } else {
            print("⚠ 未在拉取结果中找到 testId=\(testId)")
            exitCode = 1
        }

        if exitCode == 0 {
            print("\n✅ 全部 6 步通过")
            print("\n💡 你可以打开飞书查看刚刚创建的多维表格：")
            print("   \(url)")
            print("\n💡 表里应当能看到一条测试行（金额=199.99，已删除=true）")
        } else {
            print("\n⚠ 部分步骤未达预期，请检查日志")
        }
    } catch HTTPError.bad(let code, let msg) {
        print("\n❌ HTTP 失败：code=\(code) msg=\(msg.prefix(500))")
        exitCode = 1
    } catch {
        print("\n❌ 失败：\(error)")
        exitCode = 1
    }
}

semaphore.wait()
exit(exitCode)
