import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

final class PreparationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); let value = cancelled; lock.unlock(); if value { throw CancellationError() } }
}

struct SelectionItem: Identifiable {
    let id = UUID()
    var title: String
    var progress = 0.0
    var phase = "等待准备"
    var asset: PhotoAsset?
    var failure: String?
}

@MainActor final class MediaSelection: ObservableObject {
    @Published var items: [SelectionItem] = []
    @Published private(set) var busy = false
    private var token = PreparationToken()
    private var providerProgress: Progress?
    private var progressObserver: NSKeyValueObservation?
    var assets: [PhotoAsset] { items.compactMap(\.asset) }
    var canSend: Bool { !busy && !assets.isEmpty }
    func cancel() {
        token.cancel(); providerProgress?.cancel(); progressObserver = nil; busy = false
        for index in items.indices where items[index].asset == nil && items[index].failure == nil {
            items[index].failure = "读取已取消，已准备的项目仍可发送。"
        }
    }
    func removeFailed() { items.removeAll { $0.failure != nil } }
    func load(_ providers: [NSItemProvider]) {
        cancel(); token = PreparationToken()
        guard providers.count <= 50 else {
            var item = SelectionItem(title: "一次最多选择 50 个项目")
            item.failure = "请减少本次选择数量后重试。"
            items = [item]; return
        }
        items = providers.enumerated().map { SelectionItem(title: $0.element.suggestedName ?? "第 \($0.offset + 1) 个项目") }
        let currentToken = token; let ids = items.map(\.id); busy = !providers.isEmpty
        Task {
            for (index, provider) in providers.enumerated() {
                do {
                    try currentToken.check()
                    update(ids[index], progress: 0, phase: "从相册读取原文件…")
                    let url = try await read(provider, id: ids[index], token: currentToken)
                    try currentToken.check()
                    update(ids[index], progress: 0.5, phase: "正在准备原文件…")
                    let id = ids[index]
                    let asset = try await Task.detached(priority: .userInitiated) {
                        try PhotoAsset.prepare(url, token: currentToken, progress: { value in
                            Task { @MainActor [weak self] in self?.update(id, progress: 0.5 + 0.5 * value, phase: "正在准备原文件…") }
                        })
                    }.value
                    try currentToken.check()
                    if let position = items.firstIndex(where: { $0.id == id }) {
                        items[position].asset = asset; items[position].title = asset.title; items[position].progress = 1; items[position].phase = "按住即可甩送"
                    }
                } catch {
                    if error is CancellationError { break }
                    if let position = items.firstIndex(where: { $0.id == ids[index] }) { items[position].failure = error.localizedDescription; items[position].phase = "读取失败，可移除后发送其余项目" }
                }
            }
            if token === currentToken { busy = false; providerProgress = nil; progressObserver = nil }
        }
    }
    func loadFiles(_ urls: [URL]) {
        let providers = urls.map { url -> NSItemProvider in
            let provider = NSItemProvider(); provider.suggestedName = url.lastPathComponent
            provider.registerFileRepresentation(forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all) { completion in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                // Keep the scoped URL alive until our reader has copied it in the callback.
                completion(url, false, nil); return nil
            }
            return provider
        }
        load(providers)
    }
    private func update(_ id: UUID, progress: Double, phase: String) {
        guard busy, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progress = max(items[index].progress, min(1, progress)); items[index].phase = phase
    }
    private func read(_ provider: NSItemProvider, id: UUID, token: PreparationToken) async throws -> URL {
        let identifiers = provider.registeredTypeIdentifiers
        // Movies can advertise an image thumbnail too. Always request the movie first.
        let type = identifiers.first { UTType($0)?.conforms(to: .movie) == true }
            ?? identifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? identifiers.first { $0 != UTType.fileURL.identifier && UTType($0)?.conforms(to: .data) == true }
        return try await withCheckedThrowingContinuation { continuation in
            let finish: (URL?, Error?) -> Void = { [weak self] source, error in
                do {
                    try token.check()
                    guard let source = source else { throw error ?? PhotoFailure.invalid }
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    // Item-provider URLs expire at callback return; copy synchronously here.
                    var name = provider.suggestedName ?? source.lastPathComponent
                    if let type = type, UTType(type)?.conforms(to: .movie) == true,
                       UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension)?.conforms(to: .movie) != true {
                        name = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + "." + (UTType(type)?.preferredFilenameExtension ?? "mov")
                    }
                    let copy = try PhotoFiles.copyImported(source, name: name, token: token) { value in
                        Task { @MainActor in self?.update(id, progress: value * 0.5, phase: "从相册读取原文件…") }
                    }
                    continuation.resume(returning: copy)
                } catch { continuation.resume(throwing: error) }
            }
            if let type = type {
                providerProgress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in finish(url, error) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                providerProgress = nil
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in finish(value as? URL, error) }
            } else { continuation.resume(throwing: PhotoFailure.invalid); return }
            progressObserver = providerProgress?.observe(\.fractionCompleted, options: [.new]) { [weak self] value, _ in
                Task { @MainActor in self?.update(id, progress: min(0.49, value.fractionCompleted * 0.49), phase: "正在读取，可随时取消…") }
            }
        }
    }
}

struct OriginalMediaPicker: UIViewControllerRepresentable {
    let selected: ([NSItemProvider]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.images, .videos]); config.selectionLimit = 50
        config.selection = .ordered; config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let selected: ([NSItemProvider]) -> Void
        init(selected: @escaping ([NSItemProvider]) -> Void) { self.selected = selected }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { selected(results.map(\.itemProvider)) }
    }
}
