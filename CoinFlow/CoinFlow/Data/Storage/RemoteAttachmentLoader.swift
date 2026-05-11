//  RemoteAttachmentLoader.swift
//  CoinFlow · M11 · 飞书素材按需下载（内存 + 磁盘双层缓存）
//
//  背景：
//  - 同步成功后本地截图被 SyncQueue 主动删除（节省存储；云端 file_token 保留）
//  - 详情页查看 OCR 截图时需要按需从飞书拉
//
//  缓存策略：
//  - L1 内存（NSCache）：进程生命周期，最大 12 张（约 ~9MB），命中即返回
//  - L2 磁盘（<tmp>/feishu_attachment_cache/）：持久到下次系统清理 tmp，
//    用 file_token 做文件名，详情页二次进入秒开
//  - tmp 目录会被 iOS 自动管理（应用生命周期 / 存储压力时清），
//    所以无需自己实现 GC，零再次膨胀风险
//
//  并发：actor 隔离，多次并发请求同一个 file_token 只会发一次网络
//    （inflight 任务去重，参考标准 SwiftNIO loader 模式）

import Foundation
import UIKit

actor RemoteAttachmentLoader {

    static let shared = RemoteAttachmentLoader()

    // MARK: - Memory cache (L1)

    /// NSCache key: file_token；value: UIImage
    /// 设上限 12 张，单图 ~700KB → 约 8.4MB 上限，对详情页足够
    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        return cache
    }()

    // MARK: - Disk cache (L2)

    /// 磁盘缓存根目录：<tmp>/feishu_attachment_cache/
    private var diskRootURL: URL {
        let tmp = FileManager.default.temporaryDirectory
        let dir = tmp.appendingPathComponent("feishu_attachment_cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        }
        return dir
    }

    private func diskFileURL(for fileToken: String) -> URL {
        // file_token 是飞书生成的安全字符串，可直接作为文件名
        diskRootURL.appendingPathComponent("\(fileToken).jpg")
    }

    // MARK: - In-flight dedupe

    /// 同一 file_token 并发请求去重：第二个请求复用第一个的 Task
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    // MARK: - API

    /// 加载远端附件为 UIImage。
    /// 命中顺序：L1 内存 → L2 磁盘 → 网络（飞书 download API）
    /// - Parameter fileToken: 飞书 file_token（来自 record.attachmentRemoteToken）
    /// - Returns: 解码后的 UIImage；网络失败 / 解码失败 返回 nil
    func image(for fileToken: String) async -> UIImage? {
        guard !fileToken.isEmpty else { return nil }

        // L1
        if let cached = memoryCache.object(forKey: fileToken as NSString) {
            return cached
        }

        // 同 token 并发去重
        if let existing = inflight[fileToken] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadCold(fileToken: fileToken)
        }
        inflight[fileToken] = task
        let img = await task.value
        inflight.removeValue(forKey: fileToken)
        return img
    }

    /// L2 磁盘 → 网络
    private func loadCold(fileToken: String) async -> UIImage? {
        let diskURL = diskFileURL(for: fileToken)

        // L2 磁盘
        if FileManager.default.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL),
           let img = UIImage(data: data) {
            memoryCache.setObject(img, forKey: fileToken as NSString)
            return img
        }

        // 网络拉取
        do {
            let data = try await FeishuBitableClient.shared.downloadAttachment(fileToken: fileToken)
            // 写磁盘（失败不致命，下次重新下载即可）
            try? data.write(to: diskURL, options: .atomic)
            guard let img = UIImage(data: data) else {
                NSLog("[CoinFlow] RemoteAttachmentLoader decode fail token=\(fileToken.prefix(12))…")
                return nil
            }
            memoryCache.setObject(img, forKey: fileToken as NSString)
            return img
        } catch {
            NSLog("[CoinFlow] RemoteAttachmentLoader download fail token=\(fileToken.prefix(12))… err=\(error.localizedDescription)")
            return nil
        }
    }

    /// 主动清缓存（飞书表重建 / 用户操作触发）。一般不需要手动调。
    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskRootURL)
    }
}
