import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShareImport: ObservableObject {
    @Published var asset: PhotoAsset?
    @Published var failure: String?
    func load(_ context: NSExtensionContext?) {
        guard let items = context?.inputItems as? [NSExtensionItem],
              let provider = items.flatMap({ $0.attachments ?? [] }).first else {
            failure = "请从系统照片或文件选择一个项目后，再分享给一甩。"; return
        }
        let identifiers = provider.registeredTypeIdentifiers
        let type = identifiers.first { id in
            guard let type = UTType(id) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie)
        } ?? identifiers.first { $0 != UTType.fileURL.identifier && UTType($0)?.conforms(to: .data) == true }
        Task {
            do {
                let url: URL = try await withCheckedThrowingContinuation { continuation in
                    if let type = type {
                        provider.loadFileRepresentation(forTypeIdentifier: type) { source, error in
                            do {
                                guard let source = source else { throw error ?? PhotoFailure.invalid }
                                // Provider URLs expire when this callback returns. Copy before resuming.
                                let copy = try PhotoFiles.copyImported(source, name: provider.suggestedName)
                                continuation.resume(returning: copy)
                            } catch { continuation.resume(throwing: error) }
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                            do {
                                guard let source = item as? URL else { throw error ?? PhotoFailure.invalid }
                                let access = source.startAccessingSecurityScopedResource()
                                defer { if access { source.stopAccessingSecurityScopedResource() } }
                                continuation.resume(returning: try PhotoFiles.copyImported(source, name: provider.suggestedName))
                            } catch { continuation.resume(throwing: error) }
                        }
                    } else { continuation.resume(throwing: PhotoFailure.invalid) }
                }
                asset = try await Task.detached(priority: .userInitiated) { try PhotoAsset.prepare(url) }.value
            } catch { failure = error.localizedDescription }
        }
    }
}

final class ShareViewController: UIViewController {
    private let link = PeerLink()
    private let importer = ShareImport()
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareRoot(link: link, importer: importer, finish: { [weak self] in
            self?.link.suspend(); self?.extensionContext?.completeRequest(returningItems: nil)
        })
        let host = UIHostingController(rootView: root.tint(.green))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: 420, height: 760)
        link.activate(); importer.load(extensionContext)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { link.suspend() }
    }
    deinit { link.suspend() }
}

private struct ShareRoot: View {
    @ObservedObject var link: PeerLink
    @ObservedObject var importer: ShareImport
    let finish: () -> Void
    var body: some View {
        Group {
            if let asset = importer.asset { ComposerScreen(link: link, initialAsset: asset, initialSide: .right, finish: finish) }
            else {
                NavigationStack {
                    VStack(spacing: 22) {
                        if let error = importer.failure {
                            Image(systemName: "exclamationmark.circle").font(.largeTitle)
                            Text(error).multilineTextAlignment(.center)
                        } else { ProgressView("正在读取原文件…"); Text("请保持分享窗口打开，直到传输完成。").font(.footnote).foregroundStyle(.secondary) }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemGroupedBackground))
                        .navigationTitle("一甩").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消", action: finish) } }
                }
            }
        }
    }
}
