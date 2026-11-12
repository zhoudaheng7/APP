import Foundation
import SwiftUI

struct RecordDraft<Value: Codable>: Codable {
    var original: Value
    var edited: Value
}

/// Editor-only drafts are local, protected, and never facts or exchange intents.
@MainActor enum EditorDrafts {
    private static var drafts: [String: [String: String]]?
    private static var readFailure: Error?
    private static var versions: [String:Int] = [:]
    static func version(_ key: String) -> Int { versions[key,default:0] }
    private static func url() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("LifeOS", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("EditorDrafts-v2.json")
    }
    static func load(_ key: String) -> [String: String]? {
        if drafts == nil {
            do {
                let path = try url()
                if FileManager.default.fileExists(atPath: path.path) {
                    let bytes = try Data(contentsOf: path)
                    guard bytes.count <= 2_000_000 else { throw LifeError.message("草稿文件超过容量限制，原件已保留。") }
                    drafts = try JSONDecoder().decode([String: [String: String]].self, from: bytes)
                } else { drafts = [:] }
            } catch { readFailure = error; return nil }
        }
        return drafts?[key]
    }
    static func save(_ key: String, fields: [String: String]) {
        do { try write(key, fields: fields) } catch { LifeStore.shared.error = "草稿未能保存，原文件未被覆盖。" }
    }
    static func value<Value: Decodable>(_ key: String, as type: Value.Type) -> Value? {
        guard let text = load(key)?["record"] else { return nil }
        do { return try JSONDecoder().decode(type, from: Data(text.utf8)) }
        catch { LifeStore.shared.error = "这份编辑草稿无法读取，原件已保留。"; return nil }
    }
    static func fields<Value: Encodable>(_ value: Value) -> [String: String] {
        do { return ["record": String(decoding: try JSONEncoder().encode(value), as: UTF8.self)] }
        catch { LifeStore.shared.error = "编辑草稿无法编码，请先保留本页内容。"; return [:] }
    }
    static func remove(entities: Set<UUID>) {
        _ = load(""); guard readFailure == nil else { return }
        let ids = Set(entities.map { $0.uuidString.lowercased() })
        let candidate = (drafts ?? [:]).filter { key, _ in !key.split(separator: ":").contains { ids.contains($0.lowercased()) } }
        for key in (drafts ?? [:]).keys where candidate[key] == nil { versions[key,default:0] += 1 }
        do { try persist(candidate) } catch { LifeStore.shared.error = "记录已删除，但相关草稿清除失败。" }
    }
    static func write(_ key: String, fields: [String: String]) throws {
        _ = load(key); if let readFailure { throw readFailure }
        var candidate = drafts ?? [:]; candidate[key] = fields; try persist(candidate)
    }
    static func remove(_ key: String) {
        versions[key,default:0] += 1
        _ = load(key); guard readFailure == nil else { return }
        var candidate = drafts ?? [:]; candidate.removeValue(forKey: key)
        do { try persist(candidate) } catch { LifeStore.shared.error = "业务记录已保存，但旧草稿清除失败，请勿重复创建。" }
    }
    private static func persist(_ candidate: [String:[String:String]]) throws {
        if candidate == drafts { return }
        let bytes = try JSONEncoder().encode(candidate)
        guard bytes.count <= 2_000_000 else { throw LifeError.message("草稿超过2MB，未覆盖原文件。") }
        try bytes.write(to: url(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); drafts = candidate
    }
}

private struct RetainedEditorDraft: ViewModifier {
    @Environment(\.scenePhase) private var phase
    let key: String
    let fields: [String: String]
    let active: Bool
    @State private var version: Int?
    var signature: String { fields.keys.sorted().map { $0 + "=" + (fields[$0] ?? "") }.joined(separator: "\u{0}") }
    func save() { if active && !fields.isEmpty && version == EditorDrafts.version(key) { EditorDrafts.save(key, fields: fields) } }
    func body(content: Content) -> some View {
        content.onAppear { version = EditorDrafts.version(key) }.task(id: signature + String(active)) {
            do { try await Task.sleep(for: .milliseconds(450)); if !Task.isCancelled { save() } } catch {}
        }.onDisappear { save() }.onChange(of: phase) { _, new in if new != .active { save() } }
    }
}
extension View {
    func retainingDraft(_ key: String, fields: [String: String], active: Bool = true) -> some View {
        modifier(RetainedEditorDraft(key: key, fields: fields, active: active))
    }
}
struct EditorConflictNotice: View {
    var changed: Bool
    var current: String
    var acknowledge: () -> Void
    var body: some View {
        if changed { Section("记录已更新，请核对") {
            Text("本页保留了你的修改。已保存的记录在别处发生变化，先核对下面内容，再决定是否继续保存本页。")
            Text(current).textSelection(.enabled).foregroundStyle(.secondary)
            Button("我已核对，继续使用本页修改", action: acknowledge)
        } }
    }
}
