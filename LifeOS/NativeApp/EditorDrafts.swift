import Foundation

/// Editor-only drafts are local, protected, and never facts or exchange intents.
@MainActor enum EditorDrafts {
    private static var drafts: [String: [String: String]]?
    private static var readFailure: Error?
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
    static func write(_ key: String, fields: [String: String]) throws {
        _ = load(key); if let readFailure { throw readFailure }
        var candidate = drafts ?? [:]; candidate[key] = fields; try persist(candidate)
    }
    static func remove(_ key: String) {
        _ = load(key); guard readFailure == nil else { return }
        var candidate = drafts ?? [:]; candidate.removeValue(forKey: key)
        do { try persist(candidate) } catch { LifeStore.shared.error = "业务记录已保存，但旧草稿清除失败，请勿重复创建。" }
    }
    private static func persist(_ candidate: [String:[String:String]]) throws {
        let bytes = try JSONEncoder().encode(candidate)
        guard bytes.count <= 2_000_000 else { throw LifeError.message("草稿超过2MB，未覆盖原文件。") }
        try bytes.write(to: url(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); drafts = candidate
    }
}
