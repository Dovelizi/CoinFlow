//  ScreenshotStore.swift
//  CoinFlow · M9-Fix4 · OCR 截图归档
//
//  把 OCR 截图保存到 App Caches 目录（同步成功后系统可清理）。
//  - 路径：<Caches>/screenshots/{record_id}.jpg
//  - 格式：JPEG 压缩 0.8（平衡质量与大小，飞书附件单文件 30MB 上限基本不会触发）
//  - Caches 目录策略（Q2=Y）：iOS 在磁盘紧张时可能清理，因此同步成功前不要删本地副本

import Foundation
import UIKit

enum ScreenshotStoreError: Error, LocalizedError {
    case encodeFailed
    case writeFailed(underlying: Error)
    case readFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:           return "截图编码 JPEG 失败"
        case .writeFailed(let e):     return "截图写入失败：\(e.localizedDescription)"
        case .readFailed(let e):      return "截图读取失败：\(e.localizedDescription)"
        }
    }
}

enum ScreenshotStore {

    /// 截图根目录：<Caches>/screenshots/
    static var rootURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory,
                                              in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("screenshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        }
        return dir
    }

    /// 给定 record_id 的目标文件路径
    static func fileURL(for recordId: String) -> URL {
        rootURL.appendingPathComponent("\(recordId).jpg")
    }

    /// 保存 UIImage 到 Caches，返回绝对路径字符串。
    /// - Parameter image: OCR 用到的原图（CaptureConfirmView 持有）
    /// - Parameter recordId: 关联的 record id（用作文件名）
    /// - Returns: 绝对路径（写入 Record.attachmentLocalPath）
    @discardableResult
    static func save(image: UIImage, recordId: String) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw ScreenshotStoreError.encodeFailed
        }
        let url = fileURL(for: recordId)
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            throw ScreenshotStoreError.writeFailed(underlying: error)
        }
    }

    /// 读取截图字节（用于上传飞书）。返回 nil 表示文件不存在/已被系统清理。
    static func read(path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 删除截图（同步成功后调，主动腾空间）
    static func delete(path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
    }

    /// 检查文件是否还在
    static func exists(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
