//  RecordBitableMapperTests.swift
//  CoinFlowTests · M9
//
//  Record ↔ 飞书 Bitable fields dict 双向映射测试。
//  - 字段齐全 encode（含分类 directionLabel 推导）
//  - 软删 deletedAt 映射到"已删除"复选框
//  - 备注 nil → 空字串
//  - decode 缺字段抛 missingRequiredField
//  - decode 文本字段兼容飞书数组格式 [{"text": "..."}]
//
//  测试用真实 SQLCipher DB（DatabaseManager + Seed），让 directionLabel/categoryDisplayName
//  能查到真实分类数据。

import XCTest
@testable import CoinFlow

@MainActor
final class RecordBitableMapperTests: XCTestCase {

    private var foodCategoryId: String = ""
    private var salaryCategoryId: String = ""

    override func setUp() async throws {
        try await super.setUp()
        _ = try DatabaseManager.shared.bootstrap()
        // 确保有预设分类供 mapper 现查
        _ = try DefaultSeeder.seedIfNeeded()
        let cats = try SQLiteCategoryRepository.shared.list(kind: nil, includeDeleted: false)
        if let food = cats.first(where: { $0.kind == .expense }) {
            foodCategoryId = food.id
        }
        if let salary = cats.first(where: { $0.kind == .income }) {
            salaryCategoryId = salary.id
        }
    }

    // MARK: - encode

    func test_encode_basic_expense_record() throws {
        let r = makeRecord(id: "r-1", categoryId: foodCategoryId,
                           amount: Decimal(string: "99.99")!,
                           note: "周末聚餐")
        let fields = try RecordBitableMapper.encode(r)

        XCTAssertEqual(fields[FeishuFieldName.billId] as? String, "r-1")
        XCTAssertEqual(fields[FeishuFieldName.amount] as? Double ?? 0, 99.99, accuracy: 0.001)
        XCTAssertEqual(fields[FeishuFieldName.currency] as? String, "CNY")
        XCTAssertEqual(fields[FeishuFieldName.direction] as? String, "支出")
        // Q1=A：note 写入主键列「账单描述」，不再写独立「备注」字段
        XCTAssertEqual(fields[FeishuFieldName.billDescription] as? String, "周末聚餐")
        XCTAssertNil(fields[FeishuFieldName.note], "不应写入独立\"备注\"字段（已合并到主键列）")
        XCTAssertEqual(fields[FeishuFieldName.source] as? String, "手动")
        XCTAssertEqual(fields[FeishuFieldName.deleted] as? Bool, false)
        XCTAssertNotNil(fields[FeishuFieldName.occurredAt] as? Int64)
        XCTAssertNotNil(fields[FeishuFieldName.createdAt] as? Int64)
    }

    func test_encode_income_record_directionMapsToIncome() throws {
        guard !salaryCategoryId.isEmpty else {
            throw XCTSkip("没有收入预设分类，跳过")
        }
        let r = makeRecord(id: "r-2", categoryId: salaryCategoryId,
                           amount: Decimal(8000),
                           note: nil)
        let fields = try RecordBitableMapper.encode(r)
        XCTAssertEqual(fields[FeishuFieldName.direction] as? String, "收入")
    }

    func test_encode_nil_note_becomesEmptyString() throws {
        let r = makeRecord(id: "r-3", categoryId: foodCategoryId,
                           amount: Decimal(10), note: nil)
        let fields = try RecordBitableMapper.encode(r)
        XCTAssertEqual(fields[FeishuFieldName.billDescription] as? String, "")
    }

    func test_encode_softDeleted_setsDeletedTrue() throws {
        var r = makeRecord(id: "r-4", categoryId: foodCategoryId,
                           amount: Decimal(20), note: "x")
        r.deletedAt = Date()
        let fields = try RecordBitableMapper.encode(r)
        XCTAssertEqual(fields[FeishuFieldName.deleted] as? Bool, true)
    }

    func test_encode_allSourceLabels() throws {
        let mapping: [(RecordSource, String)] = [
            (.manual,     "手动"),
            (.ocrVision,  "截图OCR-Vision"),
            (.ocrAPI,     "截图OCR-API"),
            (.ocrLLM,     "截图OCR-LLM"),
            (.voiceLocal, "语音-本地"),
            (.voiceCloud, "语音-云端")
        ]
        for (src, label) in mapping {
            var r = makeRecord(id: "src-\(src.rawValue)", categoryId: foodCategoryId,
                               amount: Decimal(1), note: nil)
            r.source = src
            let fields = try RecordBitableMapper.encode(r)
            XCTAssertEqual(fields[FeishuFieldName.source] as? String, label,
                           "source=\(src) → \(label)")
        }
    }

    // MARK: - decode

    func test_decode_validRow_roundtrip() throws {
        let now = Date()
        let fields: [String: Any] = [
            FeishuFieldName.billId:          "remote-1",
            FeishuFieldName.occurredAt:      Int64(now.timeIntervalSince1970 * 1000),
            FeishuFieldName.amount:          12.5,
            FeishuFieldName.currency:        "CNY",
            FeishuFieldName.direction:       "支出",
            FeishuFieldName.category:        "餐饮",
            FeishuFieldName.billDescription: "测试",       // Q1=A：主键列
            FeishuFieldName.source:          "手动",
            FeishuFieldName.createdAt:       Int64(now.timeIntervalSince1970 * 1000),
            FeishuFieldName.updatedAt:       Int64(now.timeIntervalSince1970 * 1000),
            FeishuFieldName.deleted:         false
        ]
        let r = try RecordBitableMapper.decode(fields: fields, remoteRecordId: "rec-x")
        XCTAssertEqual(r.id, "remote-1")
        XCTAssertEqual(r.amount, Decimal(string: "12.5"))
        XCTAssertEqual(r.currency, "CNY")
        XCTAssertEqual(r.note, "测试")
        XCTAssertEqual(r.syncStatus, .synced)
        XCTAssertEqual(r.remoteId, "rec-x")
        XCTAssertNil(r.deletedAt)
    }

    /// 兼容旧自动建表模式的 decode：备注在独立「备注」字段里时也能解出
    func test_decode_legacyNoteField_stillWorks() throws {
        let now = Date()
        let fields: [String: Any] = [
            FeishuFieldName.billId:     "legacy-1",
            FeishuFieldName.occurredAt: Int64(now.timeIntervalSince1970 * 1000),
            FeishuFieldName.amount:     5.0,
            FeishuFieldName.note:       "老格式备注",   // 老模式下独立的「备注」列
            FeishuFieldName.source:     "手动"
        ]
        let r = try RecordBitableMapper.decode(fields: fields, remoteRecordId: "rec-legacy")
        XCTAssertEqual(r.note, "老格式备注")
    }

    func test_decode_textArrayFormat() throws {
        // 飞书查询接口对文本字段返回 [{"text": "...", "type": "text"}]
        let now = Date()
        let fields: [String: Any] = [
            FeishuFieldName.billId:          "remote-2",
            FeishuFieldName.occurredAt:      Int64(now.timeIntervalSince1970 * 1000),
            FeishuFieldName.amount:          7.0,
            FeishuFieldName.billDescription: [["text": "Hello ", "type": "text"], ["text": "World"]],
            FeishuFieldName.category:        [["text": "餐饮"]],
            FeishuFieldName.source:          "手动"
        ]
        let r = try RecordBitableMapper.decode(fields: fields, remoteRecordId: "rec-y")
        XCTAssertEqual(r.note, "Hello World")
    }

    func test_decode_softDeletedRow_setsDeletedAt() throws {
        let now = Date()
        let fields: [String: Any] = [
            FeishuFieldName.billId:     "remote-3",
            FeishuFieldName.occurredAt: Int64(now.timeIntervalSince1970 * 1000),
            FeishuFieldName.amount:     10.0,
            FeishuFieldName.source:     "手动",
            FeishuFieldName.deleted:    true
        ]
        let r = try RecordBitableMapper.decode(fields: fields, remoteRecordId: "rec-z")
        XCTAssertNotNil(r.deletedAt)
    }

    func test_decode_missingBillId_throws() throws {
        let fields: [String: Any] = [
            FeishuFieldName.occurredAt: Int64(Date().timeIntervalSince1970 * 1000),
            FeishuFieldName.amount: 1.0
        ]
        XCTAssertThrowsError(try RecordBitableMapper.decode(
            fields: fields, remoteRecordId: "x"
        )) { err in
            guard let e = err as? RecordBitableMapperError,
                  case .missingRequiredField(let f) = e else {
                XCTFail("应抛 missingRequiredField")
                return
            }
            XCTAssertEqual(f, FeishuFieldName.billId)
        }
    }

    func test_decode_missingAmount_throws() throws {
        let fields: [String: Any] = [
            FeishuFieldName.billId: "rid",
            FeishuFieldName.occurredAt: Int64(Date().timeIntervalSince1970 * 1000)
        ]
        XCTAssertThrowsError(try RecordBitableMapper.decode(
            fields: fields, remoteRecordId: "x"
        )) { err in
            guard let e = err as? RecordBitableMapperError,
                  case .missingRequiredField = e else {
                XCTFail("应抛 missingRequiredField")
                return
            }
        }
    }

    // MARK: - Helpers

    private func makeRecord(id: String,
                            categoryId: String,
                            amount: Decimal,
                            note: String?) -> Record {
        let now = Date()
        return Record(
            id: id,
            ledgerId: DefaultSeeder.defaultLedgerId,
            categoryId: categoryId,
            amount: amount,
            currency: "CNY",
            occurredAt: now,
            timezone: "Asia/Shanghai",
            note: note,
            payerUserId: nil,
            participants: nil,
            source: .manual,
            ocrConfidence: nil,
            voiceSessionId: nil,
            missingFields: nil,
            merchantChannel: nil,
            syncStatus: .pending,
            remoteId: nil,
            lastSyncError: nil,
            syncAttempts: 0,
            attachmentLocalPath: nil,
            attachmentRemoteToken: nil,
            aaSettlementId: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }
}
