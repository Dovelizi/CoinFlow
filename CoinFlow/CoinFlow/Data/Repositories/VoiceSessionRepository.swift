//  VoiceSessionRepository.swift
//  CoinFlow · M5 · §3.1 voice_session
//
//  临时会话日志表 CRUD。产品语义：
//  - 一次录音 → 一行 voice_session → N 条 record（record.voice_session_id 关联）
//  - 无软删除（§Schema 注释）；用 status = .cancelled 表达"终止"
//  - 审计字段 asr_text / parser_raw_json 仅本地，永不上 Firestore（§11.1）

import Foundation
import SQLCipher

protocol VoiceSessionRepository {
    func insert(_ session: VoiceSession) throws
    func update(_ session: VoiceSession) throws
    func find(id: String) throws -> VoiceSession?
    /// 查询最近若干条（debug / 审计用）
    func recent(limit: Int) throws -> [VoiceSession]
}

final class SQLiteVoiceSessionRepository: VoiceSessionRepository {

    static let shared = SQLiteVoiceSessionRepository()
    private init() {}

    private let db = DatabaseManager.shared

    /// 与 Schema.createVoiceSession DDL 严格一致。
    private static let columns = """
    id, started_at, duration_sec, audio_path,
    asr_engine, asr_text, asr_confidence,
    parser_engine, parser_raw_json,
    parsed_count, confirmed_count,
    status, error, created_at
    """

    // MARK: - Insert

    func insert(_ session: VoiceSession) throws {
        let sql = """
        INSERT INTO voice_session (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            try Self.bindAll(stmt, session)
            try stmt.stepDone()
        }
    }

    // MARK: - Update

    func update(_ session: VoiceSession) throws {
        let sql = """
        UPDATE voice_session SET
          started_at = ?, duration_sec = ?, audio_path = ?,
          asr_engine = ?, asr_text = ?, asr_confidence = ?,
          parser_engine = ?, parser_raw_json = ?,
          parsed_count = ?, confirmed_count = ?,
          status = ?, error = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, session.startedAt)
            stmt.bind(2, session.durationSec)
            stmt.bind(3, session.audioPath)
            stmt.bind(4, session.asrEngine.rawValue)
            stmt.bind(5, session.asrText)
            stmt.bind(6, session.asrConfidence)
            stmt.bind(7, session.parserEngine?.rawValue)
            stmt.bind(8, session.parserRawJSON)
            stmt.bind(9, session.parsedCount)
            stmt.bind(10, session.confirmedCount)
            stmt.bind(11, session.status.rawValue)
            stmt.bind(12, session.error)
            stmt.bind(13, session.id)
            try stmt.stepDone()
        }
    }

    // MARK: - Find / Recent

    func find(id: String) throws -> VoiceSession? {
        let sql = "SELECT \(Self.columns) FROM voice_session WHERE id = ? LIMIT 1;"
        return try db.withHandle { handle -> VoiceSession? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, id)
            if try stmt.hasNext() { return Self.decode(stmt) }
            return nil
        }
    }

    func recent(limit: Int) throws -> [VoiceSession] {
        let sql = """
        SELECT \(Self.columns) FROM voice_session
        ORDER BY started_at DESC
        LIMIT ?;
        """
        return try db.withHandle { handle -> [VoiceSession] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, limit)
            var out: [VoiceSession] = []
            while try stmt.hasNext() { out.append(Self.decode(stmt)) }
            return out
        }
    }

    // MARK: - Bind & Decode

    private static func bindAll(_ stmt: PreparedStatement, _ s: VoiceSession) throws {
        stmt.bind(1, s.id)
        stmt.bind(2, s.startedAt)
        stmt.bind(3, s.durationSec)
        stmt.bind(4, s.audioPath)
        stmt.bind(5, s.asrEngine.rawValue)
        stmt.bind(6, s.asrText)
        stmt.bind(7, s.asrConfidence)
        stmt.bind(8, s.parserEngine?.rawValue)
        stmt.bind(9, s.parserRawJSON)
        stmt.bind(10, s.parsedCount)
        stmt.bind(11, s.confirmedCount)
        stmt.bind(12, s.status.rawValue)
        stmt.bind(13, s.error)
        stmt.bind(14, s.createdAt)
    }

    private static func decode(_ s: PreparedStatement) -> VoiceSession {
        VoiceSession(
            id: s.columnText(0),
            startedAt: s.columnDate(1),
            durationSec: s.columnDouble(2),
            audioPath: s.columnTextOrNil(3),
            asrEngine: ASREngine(rawValue: s.columnText(4)) ?? .speechLocal,
            asrText: s.columnText(5),
            asrConfidence: s.columnDoubleOrNil(6),
            parserEngine: s.columnTextOrNil(7).flatMap { ParserEngine(rawValue: $0) },
            parserRawJSON: s.columnTextOrNil(8),
            parsedCount: s.columnInt(9),
            confirmedCount: s.columnInt(10),
            status: VoiceSessionStatus(rawValue: s.columnText(11)) ?? .recording,
            error: s.columnTextOrNil(12),
            createdAt: s.columnDate(13)
        )
    }
}
