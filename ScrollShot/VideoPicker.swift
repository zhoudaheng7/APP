import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct VideoPicker: UIViewControllerRepresentable {
    let selected: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        init(parent: VideoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider else { return }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error { DispatchQueue.main.async { self.parent.selected(.failure(error)) }; return }
                guard let url else {
                    DispatchQueue.main.async { self.parent.selected(.failure(ScrollShotError.message("读取录屏失败。"))) }
                    return
                }
                do {
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (url.pathExtension.isEmpty ? "mov" : url.pathExtension))
                    try FileManager.default.copyItem(at: url, to: copy)
                    DispatchQueue.main.async { self.parent.selected(.success(copy)) }
                } catch { DispatchQueue.main.async { self.parent.selected(.failure(error)) } }
            }
        }
    }
}
