import Foundation

/// Only files listed by this component, with unchanged content, may be reclaimed.
/// User backups, editor drafts, unknown files and shared exports are never swept.
@MainActor enum PrivateArtifacts {
    struct Entry: Codable { var name: String; var sha256: String; var bytes: Int; var expires: Date }
    private static var leases = Set<String>()
    static func root() throws -> URL {
        let support = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("LifeOS",isDirectory:true)
        let root = support.appendingPathComponent("PrivateExports-v1",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        guard try root.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw LifeError.invalidValue }
        return root
    }
    static func entries(_ root: URL) throws -> [Entry] {
        let index = root.appendingPathComponent("owned-exports.json")
        guard FileManager.default.fileExists(atPath:index.path) else { return [] }
        guard (try index.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey])).isSymbolicLink != true,
              ((try index.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? Int.max) <= 32768 else { throw LifeError.message("导出文件登记无法读取，原件保留。") }
        let list = try JSONDecoder().decode([Entry].self,from:Data(contentsOf:index))
        let allowed = ["Dayisle-private-backup.json","Dayisle-readable.md","Dayisle-story.pdf"]
        guard list.count <= 8,Set(list.map(\.name)).count == list.count,list.allSatisfy({ entry in
            let parts = entry.name.split(separator:"_",maxSplits:1).map(String.init)
            return parts.count == 2 && UUID(uuidString:parts[0]) != nil && allowed.contains(parts[1]) && entry.sha256.count == 64 && entry.bytes >= 0 && entry.bytes <= LifeStore.backupByteLimit && entry.expires.timeIntervalSince1970.isFinite
        }) else { throw LifeError.message("导出所有权登记异常，未清理文件。") }
        return list
    }
    private static func persist(_ list: [Entry],root: URL) throws {
        try JSONEncoder().encode(list).write(to:root.appendingPathComponent("owned-exports.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    static func sweep(now: Date = Date()) throws {
        let directory = try root(); var list = try entries(directory)
        for entry in list where entry.expires <= now && !leases.contains(entry.name) { try remove(entry,root:directory) }
        list.removeAll { $0.expires <= now && !leases.contains($0.name) }
        try persist(list,root:directory)
    }
    static func export(_ bytes: Data,name: String) throws -> URL {
        guard ["Dayisle-private-backup.json","Dayisle-readable.md","Dayisle-story.pdf"].contains(name),bytes.count <= LifeStore.backupByteLimit else { throw LifeError.invalidValue }
        try sweep(); let directory = try root(); var list = try entries(directory)
        let files = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.isDirectoryKey,.isSymbolicLinkKey])
        var total = 0
        guard files.count <= 16 else { throw LifeError.message("私人导出目录需要核对，未覆盖现有文件。") }
        for file in files { let value = try file.resourceValues(forKeys:[.fileSizeKey,.isDirectoryKey,.isSymbolicLinkKey]); guard value.isDirectory != true,value.isSymbolicLink != true else { throw LifeError.invalidValue }; total += value.fileSize ?? 0 }
        guard list.count < 8,total + bytes.count <= 512 * 1024 * 1024 else { throw LifeError.message("私人导出副本达到512MB上限，请先结束已有分享或稍后重试。") }
        let entry = Entry(name:UUID().uuidString + "_" + name,sha256:LifeStore.fingerprint(bytes),bytes:bytes.count,expires:Date().addingTimeInterval(24 * 3600))
        list.append(entry); try persist(list,root:directory)
        let url = directory.appendingPathComponent(entry.name)
        try bytes.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]); leases.insert(entry.name)
        return url
    }
    static func finishExport(_ url: URL) throws {
        let directory = try root()
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { throw LifeError.invalidValue }
        var list = try entries(directory)
        guard let entry = list.first(where: { $0.name == url.lastPathComponent }) else { throw LifeError.invalidValue }
        leases.remove(entry.name); try remove(entry,root:directory); list.removeAll { $0.name == entry.name }; try persist(list,root:directory)
    }
    private static func remove(_ entry: Entry,root: URL) throws {
        let url = root.appendingPathComponent(entry.name)
        guard FileManager.default.fileExists(atPath:url.path) else { return }
        let value = try url.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey,.isRegularFileKey])
        guard value.isSymbolicLink != true,value.isRegularFile == true,value.fileSize == entry.bytes,
              LifeStore.fingerprint(try Data(contentsOf:url)) == entry.sha256 else { throw LifeError.message("导出副本已被修改，未自动删除。") }
        try FileManager.default.removeItem(at:url)
    }
}

@MainActor enum MigrationProtection {
    struct Receipt: Codable { var sha256: String; var bytes: Int; var expires: Date }
    static func preserve(_ bytes: Data,root: URL,now: Date = Date()) throws {
        guard bytes.count < 128 * 1024 * 1024 else { throw LifeError.invalidValue }
        let copy = root.appendingPathComponent("before-v2-migration.json"), receipt = root.appendingPathComponent("before-v2-migration-owner.json")
        let manager = FileManager.default, hash = LifeStore.fingerprint(bytes)
        if manager.fileExists(atPath:receipt.path) {
            let info = try receipt.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey])
            guard info.isSymbolicLink != true,(info.fileSize ?? Int.max) < 2048 else { throw LifeError.invalidValue }
            let record = try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:receipt))
            guard record.sha256 == hash,record.bytes == bytes.count else { throw LifeError.message("迁移保护凭据不属于当前旧数据，原件保留。") }
            if manager.fileExists(atPath:copy.path) {
                let info = try copy.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey])
                guard info.isSymbolicLink != true,info.fileSize == bytes.count,LifeStore.fingerprint(try Data(contentsOf:copy)) == hash else { throw LifeError.message("迁移保护副本已改变，未覆盖原件。") }
            } else { try bytes.write(to:copy,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
            return
        }
        if manager.fileExists(atPath:copy.path) {
            let values = try copy.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey])
            guard values.isSymbolicLink != true,values.fileSize == bytes.count,LifeStore.fingerprint(try Data(contentsOf:copy)) == hash else { throw LifeError.message("已有迁移保护文件与旧数据不同，原件保留并停止迁移。") }
        }
        let record = Receipt(sha256:hash,bytes:bytes.count,expires:now.addingTimeInterval(7 * 86400))
        try JSONEncoder().encode(record).write(to:receipt,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        if !manager.fileExists(atPath:copy.path) { try bytes.write(to:copy,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
    }
    static func sweep(root: URL,now: Date = Date()) throws {
        let copy = root.appendingPathComponent("before-v2-migration.json"),receipt = root.appendingPathComponent("before-v2-migration-owner.json"), manager = FileManager.default
        guard manager.fileExists(atPath:receipt.path) else { return }
        let values = try receipt.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey])
        guard values.isSymbolicLink != true,(values.fileSize ?? Int.max) < 2048 else { throw LifeError.invalidValue }
        let record = try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:receipt))
        guard record.expires <= now else { return }
        guard record.bytes < 128 * 1024 * 1024,record.bytes >= 0,record.sha256.count == 64 else { throw LifeError.invalidValue }
        if manager.fileExists(atPath:copy.path) {
            let info = try copy.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey])
            guard info.isSymbolicLink != true,info.fileSize == record.bytes,LifeStore.fingerprint(try Data(contentsOf:copy)) == record.sha256 else { throw LifeError.message("迁移保护副本已改变，未自动清理。") }
            try manager.removeItem(at:copy)
        }
        try manager.removeItem(at:receipt)
    }
}
