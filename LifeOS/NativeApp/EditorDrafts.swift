import Foundation
import SwiftUI

struct RecordDraft<Value: Codable>: Codable {
    var original: Value
    var edited: Value
}
struct ReviewDraftAppend: Codable, Identifiable { var id = UUID(); var text: String }

/// Editor-only drafts are local, protected, and never facts or exchange intents.
@MainActor enum EditorDrafts {
    static let reviewAppended = Notification.Name("dayisle.review-draft-appended")
    private static var drafts: [String: [String: String]]?
    private static var readFailure: Error?
    private static var versions: [String:Int] = [:]
    static func version(_ key: String) -> Int { if versions[key] == nil { versions[key] = 0 }; return versions[key]! }
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
                    guard bytes.count <= 16 * 1024 * 1024 else { throw LifeError.message("草稿文件超过容量限制，原件已保留。") }
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
    static func decode<Value: Decodable>(_ type: Value.Type,text: String) -> Value? { try? JSONDecoder().decode(type,from:Data(text.utf8)) }
    static func fields<Value: Encodable>(_ value: Value) -> [String: String] {
        do { return ["record": String(decoding: try JSONEncoder().encode(value), as: UTF8.self)] }
        catch { LifeStore.shared.error = "编辑草稿无法编码，请先保留本页内容。"; return [:] }
    }
    static func remove(deleted: [LocalTombstone]) {
        _ = load(""); guard readFailure == nil else { return }
        let prefixes = ["commitment":"plan"]
        let keys = Set(deleted.map { (prefixes[$0.kind] ?? $0.kind) + ":" + $0.id.uuidString.lowercased() })
        let owned = Set((drafts ?? [:]).keys).union(versions.keys).filter { keys.contains($0.lowercased()) }
        let candidate = (drafts ?? [:]).filter { !owned.contains($0.key) }
        // Invalidate even an editor whose debounce has not written its first byte.
        // Context IDs in a new composer are associations, not draft ownership.
        for key in owned { versions[key,default:0] += 1 }
        do { try persist(candidate) } catch { LifeStore.shared.error = "记录已删除，但相关草稿清除失败。" }
    }
    static func write(_ key: String, fields: [String: String]) throws {
        _ = load(key); if let readFailure { throw readFailure }
        var fields = fields
        // A delayed editor save must not discard newly arrived shortcut input.
        if let pending = drafts?[key]?["reviewAppends"] { fields["reviewAppends"] = pending }
        var candidate = drafts ?? [:]; candidate[key] = fields; try persist(candidate)
    }
    static func pendingReviewAppends(_ key: String) throws -> [ReviewDraftAppend] {
        let fields = load(key); if let readFailure { throw readFailure }
        guard let text = fields?["reviewAppends"] else { return [] }
        let items = try JSONDecoder().decode([ReviewDraftAppend].self,from:Data(text.utf8))
        guard items.count <= 100,Set(items.map(\.id)).count == items.count else { throw LifeError.invalidValue }; return items
    }
    static func appendReviewText(_ text: String,day: String,existing: LifeReview?) throws {
        let key = existing.map { "review:" + $0.id.uuidString } ?? "compose:review-" + day
        var fields = load(key) ?? (existing == nil ? load("review-" + day) : nil) ?? [:]
        var pending = try pendingReviewAppends(key)
        guard pending.count < 100 else { throw LifeError.message("这一天的待核对追加达到100条，请先在朝屿核对草稿。") }
        if let existing,fields["record"] == nil,fields["text"] == nil { fields["text"] = existing.reflection; fields["mood"] = existing.mood.map(String.init) ?? ""; fields["people"] = (existing.people ?? []).joined(separator:"，") }
        pending.append(ReviewDraftAppend(text:text)); fields["reviewAppends"] = String(decoding:try JSONEncoder().encode(pending),as:UTF8.self)
        _ = load(key); if let readFailure { throw readFailure }
        var candidate = drafts ?? [:]; candidate[key] = fields; try persist(candidate)
        NotificationCenter.default.post(name:reviewAppended,object:key)
    }
    static func consumeReviewAppends(_ key: String,baseText: String,fields: (String) -> [String:String]) throws -> String {
        let pending = try pendingReviewAppends(key); guard !pending.isEmpty else { return baseText }
        if key.hasPrefix("review:"),let record = load(key)?["record"] { _ = try JSONDecoder().decode(RecordDraft<LifeReview>.self,from:Data(record.utf8)) }
        let text = ([baseText] + pending.map(\.text)).filter { !$0.isEmpty }.joined(separator:"\n")
        var merged = fields(text); merged.removeValue(forKey:"reviewAppends")
        var candidate = drafts ?? [:]; candidate[key] = merged
        // Consumed IDs and the full edited text change in one protected-file write.
        try persist(candidate); versions[key,default:0] += 1; return text
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
        guard bytes.count <= 16 * 1024 * 1024 else { throw LifeError.message("本机未保存草稿超过16MB，未覆盖原文件。请先保存或整理已有照片草稿。") }
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
        content.onAppear { version = EditorDrafts.version(key) }.onChange(of:signature) { _, _ in version = EditorDrafts.version(key) }.task(id: signature + String(active) + String(version ?? -1)) {
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
