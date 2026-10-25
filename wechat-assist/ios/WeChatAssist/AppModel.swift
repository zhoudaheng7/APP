import SwiftUI
import UIKit

struct Capture: Decodable {
    var status: String
    var message: String
    var expected_chat: String?
    var last_seen: Double?
}
struct Snapshot: Decodable {
    let revision: Int
    let chat_title: String
    let text: String
    let captured_at: Double
    let source: String
}
struct Reply: Decodable, Identifiable {
    var id: String { label + text }
    let label: String
    let text: String
}
struct Draft: Decodable {
    let revision: Int
    let analysis: String
    let replies: [Reply]
    var created_at: Double?
}
struct ModelInfo: Decodable {
    let configured: Bool
    let auto: Bool
    let name: String
}
struct BridgeState: Decodable {
    var capture: Capture
    var snapshot: Snapshot?
    var draft: Draft?
    var model: ModelInfo
    var generating: Bool?
    static let empty = BridgeState(capture: Capture(status: "offline", message: "等待连接 Windows"),
        model: ModelInfo(configured: false, auto: false, name: "未配置"))
}

@MainActor final class AppModel: ObservableObject {
    @Published var state = BridgeState.empty
    @Published var connected = false
    @Published var hasPairing = false
    @Published var editor = ""
    @Published var question = ""
    @Published var error = ""
    @Published var generating = false
    private var editorRevision = 0
    private var client: BridgeClient?
    private var polling: Task<Void, Never>?

    var stale: Bool {
        guard let snapshot = state.snapshot else { return !editor.isEmpty }
        return editorRevision != 0 && editorRevision != snapshot.revision
    }
    var canGenerate: Bool {
        connected && state.snapshot != nil && state.model.configured && !generating &&
        Date().timeIntervalSince1970 - (state.capture.last_seen ?? 0) <= 120
    }

    init() {
        if let pairing = PairingKeychain.load() { client = BridgeClient(pairing); hasPairing = true }
    }
    func pair(_ text: String) async {
        do {
            let pairing = try Pairing.parse(text)
            let newClient = BridgeClient(pairing)
            let newState: BridgeState = try await newClient.request("/api/state")
            try PairingKeychain.save(pairing)
            stopPolling()
            client = newClient; state = newState; connected = true; hasPairing = true; error = ""
            startPolling()
        } catch { self.error = error.localizedDescription }
    }
    func startPolling() {
        guard polling == nil, client != nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let client = self.client else { return }
                do {
                    let next: BridgeState = try await client.request("/api/state")
                    if Task.isCancelled { return }
                    self.state = next; self.connected = true
                } catch {
                    if Task.isCancelled { return }
                    self.connected = false
                    self.state.capture.status = "offline"
                    self.state.capture.message = "连接中断，显示的是上一次上下文。请检查 Windows 与网络。"
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func stopPolling() { polling?.cancel(); polling = nil }
    func disconnect() {
        stopPolling(); client = nil; PairingKeychain.clear()
        hasPairing = false; connected = false; state = .empty
        // Preserve the user's unsent draft when the connection is removed.
    }
    func choose(_ reply: Reply) {
        editor = reply.text; editorRevision = state.draft?.revision ?? 0
    }
    func generate(_ instruction: String = "") async {
        guard canGenerate, let snapshot = state.snapshot, let client else { return }
        generating = true; error = ""
        defer { generating = false }
        do {
            let draft: Draft = try await client.request("/api/generate", body: ["revision": snapshot.revision, "instruction": instruction])
            state.draft = draft
            // New candidates never overwrite the user's editor.
        } catch { self.error = error.localizedDescription }
    }
    func tune(_ instruction: String) async {
        await generate(instruction + "。我的草稿：" + editor)
    }
    func copy() {
        guard !editor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !stale else { return }
        UIPasteboard.general.string = editor
        error = "已复制，请回到微信核对对象后发送。"
    }
}
