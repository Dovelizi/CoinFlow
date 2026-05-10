//  CameraPicker.swift
//  CoinFlow · 拍照记账入口
//
//  用 UIImagePickerController(sourceType: .camera) 包装为 SwiftUI sheet 可用的
//  UIViewControllerRepresentable。拍完照把 UIImage 通过 onPicked 回调向上传递，
//  调用方将其喂给 PhotoCaptureCoordinator.handle(image:) 复用现有识别流程。

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    /// 拍照完成或取消后回调；nil 表示用户取消
    let onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // 如设备不支持相机（模拟器）降级为相册，避免闪退
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // no-op
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage?) -> Void
        init(onPicked: @escaping (UIImage?) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true) { [onPicked] in
                onPicked(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [onPicked] in
                onPicked(nil)
            }
        }
    }
}
