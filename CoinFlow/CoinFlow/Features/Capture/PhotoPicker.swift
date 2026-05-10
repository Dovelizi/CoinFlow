//  PhotoPicker.swift
//  CoinFlow · M4 / M7-Fix20 重构
//
//  手动选图入口（M7-Fix20 新流程）：
//  - PhotosUI PhotosPicker 选 1 张图
//  - 仅加载图片到 sourceImage（不在此跑 OCR）
//  - 由下游 CaptureConfirmView 自行串行 OCR → LLM 并维护进度态
//
//  设计变更（M7-Fix20）：原本本协调器调用 OCRRouter.route 拿到 RouteResult 再触发 sheet，
//  导致 picker 卡顿（OCR 耗时被前置）。新流程：选图即弹 sheet 显示骨架屏，
//  OCR/LLM 在 sheet 内异步执行，符合「上传后一直展示骨架屏提示内容解析中」的需求。

import SwiftUI
import PhotosUI

@MainActor
final class PhotoCaptureCoordinator: ObservableObject {

    @Published var pickerItem: PhotosPickerItem?
    @Published var isProcessing: Bool = false
    @Published var error: String?
    /// 当前用户选中的原图（用于 CaptureConfirmView 顶部缩略 + 全屏预览）
    /// 上传后立即赋值，由调用方监听此字段触发 sheet 弹出
    @Published var sourceImage: UIImage?
    /// 每次 handle 生成一个唯一的 captureId，作为下游 sheet 的稳定 Identity
    /// 保证每次上传都当作全新流程，不复用任何 sheet / State / .task
    @Published var captureId: UUID = UUID()

    func handle(item: PhotosPickerItem?) async {
        guard let item else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                error = "图片加载失败"
                return
            }
            // M7-Fix25：批量触发一次 UI 刷新
            //   @Published 赋值会异步触发 objectWillChange，两个 @Published 连续赋值 →
            //   会产生两轮 SwiftUI diff：第一轮新 captureId + 旧 nil sourceImage（不弹 sheet），
            //   第二轮新 captureId + 新 sourceImage（弹 sheet）。期间如果外层视图树有重算，
            //   可能出现 sheet 内部 `.task` 启动一次后因视图 identity 变化被 cancel。
            //   用 objectWillChange.send() 手动先通知 → 后续赋值合并到同一轮 diff。
            let newId = UUID()
            objectWillChange.send()
            captureId = newId
            sourceImage = image
        } catch {
            self.error = "图片处理失败：\(error.localizedDescription)"
        }
    }

    /// 直接处理一张 UIImage（相机拍照路径不走 PhotosPickerItem）
    func handle(image: UIImage) async {
        let newId = UUID()
        objectWillChange.send()
        captureId = newId
        sourceImage = image
    }

    /// 重新拍 / 重新选：保留 sourceImage 之外的状态全部清空
    func retake() {
        pickerItem = nil
        error = nil
        // sourceImage 保留，便于"重新拍"前回看上一张
    }

    func reset() {
        pickerItem = nil
        error = nil
        sourceImage = nil
    }
}
