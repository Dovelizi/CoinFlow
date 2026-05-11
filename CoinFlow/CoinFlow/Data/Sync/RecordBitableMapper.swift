//  RecordBitableMapper.swift
//  CoinFlow · M9 · 飞书多维表格字段映射
//
//  Record ↔ 飞书 Bitable fields dict 互转。**完全明文，无加密**。
//  - 飞书 DateTime 字段：值为 Int64 毫秒时间戳
//  - 飞书 Number 字段：Double（项目内 Decimal 转 Double 仅用于"飞书展示"，本地仍是 Decimal）
//  - 飞书 SingleSelect 字段：值为 option 的 name 字符串
//  - 飞书 Checkbox 字段：值为 Bool
//
//  注意：分类（categoryId）→ 名称的映射在 encode 时通过 SQLiteCategoryRepository 现查现用。

import Foundation

enum RecordBitableMapperError: Error, LocalizedError {
    case missingRequiredField(String)
    case invalidValue(field: String, raw: String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let n): return "Bitable 行缺少必要字段 \(n)"
        case .invalidValue(let f, let r):  return "Bitable 行字段 \(f) 值非法：\(r)"
        }
    }
}

enum RecordBitableMapper {

    // MARK: - Local → Bitable

    /// 把 Record 转换为飞书 fields dict。
    ///
    /// Q1=A 映射策略：record.note 写入主键列「账单描述」；
    /// 为兼容旧自动建表模式（备注独立列）的表，同时也写一份到「备注」字段（若表里有该列）。
    ///
    /// M9-Fix4：附件映射——若 record.attachmentRemoteToken 非空，写入「附件」字段
    /// （飞书 Attachment 字段格式：[{"file_token": "..."}, ...]）。
    static func encode(_ record: Record) throws -> [String: Any] {
        let categoryName = categoryDisplayName(for: record.categoryId)
        let direction = directionLabel(for: record.categoryId)
        let noteValue = record.note ?? ""
        var fields: [String: Any] = [
            FeishuFieldName.billDescription: noteValue,   // 主键列
            FeishuFieldName.billId:     record.id,
            FeishuFieldName.occurredAt: Int64(record.occurredAt.timeIntervalSince1970 * 1000),
            FeishuFieldName.amount:     (record.amount as NSDecimalNumber).doubleValue,
            FeishuFieldName.currency:   record.currency,
            FeishuFieldName.direction:  direction,
            FeishuFieldName.category:   categoryName,
            FeishuFieldName.source:     sourceLabel(record.source),
            FeishuFieldName.createdAt:  Int64(record.createdAt.timeIntervalSince1970 * 1000),
            FeishuFieldName.updatedAt:  Int64(record.updatedAt.timeIntervalSince1970 * 1000),
            FeishuFieldName.deleted:    record.deletedAt != nil
        ]
        // M9-Fix4：附件
        if let token = record.attachmentRemoteToken, !token.isEmpty {
            fields[FeishuFieldName.attachment] = [["file_token": token]]
        }
        // M9-Fix5：渠道（OCR 账单才有，手动账单为 nil 时不写避免污染空选项）
        if let channel = record.merchantChannel, !channel.isEmpty {
            fields[FeishuFieldName.channel] = channel
        }
        return fields
    }

    /// 从飞书 fields 解码回 Record（手动拉取场景）。
    static func decode(fields: [String: Any], remoteRecordId: String) throws -> Record {
        // M9-Fix6：飞书文本字段返回格式 [{"text": "...", "type": "text"}]，不能直接 as? String
        // 统一用 textValue helper 兼容裸字符串和数组两种形式
        guard let id = textValue(fields[FeishuFieldName.billId]), !id.isEmpty else {
            throw RecordBitableMapperError.missingRequiredField(FeishuFieldName.billId)
        }
        guard let occurredMs = numberValue(fields[FeishuFieldName.occurredAt]) else {
            throw RecordBitableMapperError.missingRequiredField(FeishuFieldName.occurredAt)
        }
        guard let amountDouble = numberValue(fields[FeishuFieldName.amount]) else {
            throw RecordBitableMapperError.missingRequiredField(FeishuFieldName.amount)
        }
        let currency = singleSelectValue(fields[FeishuFieldName.currency]) ?? "CNY"
        let categoryName = textValue(fields[FeishuFieldName.category]) ?? "其他"
        // Q1=A：note 优先从主键列「账单描述」读；兼容旧模式（独立「备注」列）
        let note = textValue(fields[FeishuFieldName.billDescription])
                ?? textValue(fields[FeishuFieldName.note])
        let sourceRaw = singleSelectValue(fields[FeishuFieldName.source]) ?? "手动"
        let createdMs = numberValue(fields[FeishuFieldName.createdAt])
        let updatedMs = numberValue(fields[FeishuFieldName.updatedAt])
        let isDeleted = boolValue(fields[FeishuFieldName.deleted]) ?? false
        // M9-Fix5：渠道
        let merchantChannel = singleSelectValue(fields[FeishuFieldName.channel])
        // M9-Fix7：附件 file_token——飞书拉回时回填到 attachmentRemoteToken，
        // 详情页 RemoteAttachmentLoader 据此按需从云端拉图
        let attachmentToken = attachmentTokenValue(fields[FeishuFieldName.attachment])

        let categoryId = resolveCategoryId(name: categoryName)
        let amount = NSDecimalNumber(value: amountDouble).decimalValue

        let occurredAt = Date(timeIntervalSince1970: occurredMs / 1000.0)
        let createdAt: Date = createdMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? occurredAt
        let updatedAt: Date = updatedMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? occurredAt
        let deletedAt: Date? = isDeleted ? updatedAt : nil

        return Record(
            id: id,
            ledgerId: "",                  // 调用方回填默认账本
            categoryId: categoryId,
            amount: amount,
            currency: currency,
            occurredAt: occurredAt,
            timezone: TimeZone.current.identifier,
            note: (note?.isEmpty ?? true) ? nil : note,
            payerUserId: nil,
            participants: nil,
            source: parseSource(sourceRaw),
            ocrConfidence: nil,
            voiceSessionId: nil,
            missingFields: nil,
            merchantChannel: merchantChannel,
            syncStatus: .synced,
            remoteId: remoteRecordId,
            lastSyncError: nil,
            syncAttempts: 0,
            attachmentLocalPath: nil,
            attachmentRemoteToken: attachmentToken,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    // MARK: - Helpers (encode side)

    private static func sourceLabel(_ s: RecordSource) -> String {
        switch s {
        case .manual:     return "手动"
        case .ocrVision:  return "截图OCR-Vision"
        case .ocrAPI:     return "截图OCR-API"
        case .ocrLLM:     return "截图OCR-LLM"
        case .voiceLocal: return "语音-本地"
        case .voiceCloud: return "语音-云端"
        }
    }

    private static func directionLabel(for categoryId: String) -> String {
        do {
            if let cat = try SQLiteCategoryRepository.shared.find(id: categoryId) {
                return cat.kind == .income ? "收入" : "支出"
            }
        } catch {
            // ignore；fallback 支出
        }
        return "支出"
    }

    private static func categoryDisplayName(for categoryId: String) -> String {
        do {
            if let cat = try SQLiteCategoryRepository.shared.find(id: categoryId) {
                return cat.name
            }
        } catch {
            // ignore
        }
        return "其他"
    }

    // MARK: - Helpers (decode side)

    private static func parseSource(_ label: String) -> RecordSource {
        switch label {
        case "手动":            return .manual
        case "截图OCR-Vision":  return .ocrVision
        case "截图OCR-API":     return .ocrAPI
        case "截图OCR-LLM":     return .ocrLLM
        case "语音-本地":       return .voiceLocal
        case "语音-云端":       return .voiceCloud
        default:                return .manual
        }
    }

    private static func resolveCategoryId(name: String) -> String {
        do {
            let all = try SQLiteCategoryRepository.shared.list(kind: nil, includeDeleted: false)
            if let hit = all.first(where: { $0.name == name }) {
                return hit.id
            }
            if let other = all.first(where: { $0.name == "其他" }) {
                return other.id
            }
            if let any = all.first {
                return any.id
            }
        } catch {
            // ignore
        }
        return "default-other-category"
    }

    private static func numberValue(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int    { return Double(i) }
        if let i64 = v as? Int64 { return Double(i64) }
        if let s = v as? String, let d = Double(s) { return d }
        return nil
    }

    private static func boolValue(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let i = v as? Int  { return i != 0 }
        if let s = v as? String { return s == "true" || s == "1" }
        return nil
    }

    /// 飞书文本字段返回为：`[{"text": "xxx", "type": "text"}, ...]` 数组；也可能是裸字符串
    private static func textValue(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let arr = v as? [[String: Any]] {
            let parts = arr.compactMap { $0["text"] as? String }
            return parts.isEmpty ? nil : parts.joined()
        }
        return nil
    }

    /// 飞书单选字段返回为字符串（写入时也写字符串）
    private static func singleSelectValue(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let d = v as? [String: Any], let n = d["text"] as? String { return n }
        return nil
    }

    /// 飞书附件字段返回结构：`[{"file_token": "...", "name": "...", ...}, ...]`。
    /// 取第一个非空的 file_token；都为空则返回 nil。
    private static func attachmentTokenValue(_ v: Any?) -> String? {
        guard let arr = v as? [[String: Any]] else { return nil }
        for item in arr {
            if let t = item["file_token"] as? String, !t.isEmpty {
                return t
            }
        }
        return nil
    }
}
