import Foundation
import CryptoKit

struct VaultDisk: Sendable {
    var commits: [String] = []
    var files: [String:String] = [:]
    var headHint: String?
    var totalBytes = 0
}
enum VaultFiles {
    static let exchange = "LifeOSExchange"
    static let budget = 32 * 1024 * 1024
    static func path(_ relative: String, root: URL, createParents: Bool = false) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") && !$0.contains("\\") && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) && !$0.hasSuffix(".") && !$0.hasSuffix(" ") }) else { throw LifeError.message("目录边界检查失败。") }
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey,.isDirectoryKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw LifeError.message("所选目录不是可用的普通文件夹。") }
        var current = root
        for (index,part) in parts.enumerated() {
            let siblings = try FileManager.default.contentsOfDirectory(atPath: current.path)
            if let alias = siblings.first(where: { $0.caseInsensitiveCompare(part) == .orderedSame }), alias != part { throw LifeError.message("目录存在大小写冲突，未写入。") }
            current.appendPathComponent(part)
            if FileManager.default.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey,.isAliasFileKey,.isDirectoryKey,.isRegularFileKey,.linkCountKey])
                guard values.isSymbolicLink != true, values.isAliasFile != true, values.linkCount.map({ $0 <= 1 || values.isDirectory == true }) ?? true else { throw LifeError.message("目录含链接或别名，已停止访问。") }
                if index < parts.count - 1 && values.isDirectory != true { throw LifeError.message("目录路径被文件占用。") }
                if index == parts.count - 1 && values.isDirectory != true && values.isRegularFile != true { throw LifeError.invalidValue }
            } else if index < parts.count - 1 {
                guard createParents else { throw LifeError.message("交换目录尚不存在，请先发布。") }
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
        return current
    }
    static func coordinated<T>(_ root: URL, write: Bool, _ body: (URL) throws -> T) throws -> T {
        var failure: NSError?, result: Result<T,Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if write { coordinator.coordinate(writingItemAt: root, options: .forMerging, error: &failure) { result = Result { try body($0) } } }
        else { coordinator.coordinate(readingItemAt: root, options: .withoutChanges, error: &failure) { result = Result { try body($0) } } }
        if let failure { throw failure }; guard let result else { throw LifeError.message("文件提供方没有完成本次协调。") }; return try result.get()
    }
    static func read(_ relative: String, root: URL, maximum: Int = budget) throws -> Data {
        let url = try path(relative, root: root)
        let values = try url.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey])
        guard values.isRegularFile == true, let count = values.fileSize, count <= maximum else { throw LifeError.message("交换文件缺失或超过容量限制。") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= maximum else { throw LifeError.invalidValue }; return bytes
    }
    static func immutableWrite(_ bytes: Data, relative: String, root: URL) throws {
        let url = try path(relative, root: root, createParents: true)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == bytes else { throw LifeError.message("不可变同步文件已存在且内容不同，未覆盖。") }; return
        }
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func disk(root: URL) throws -> VaultDisk {
        try coordinated(root, write: false) { base in
            var disk = VaultDisk()
            let exchangeURL = try path(exchange, root: base)
            if !FileManager.default.fileExists(atPath: exchangeURL.path) { return disk }
            let commitsURL = try path(exchange + "/commits", root: base)
            guard FileManager.default.fileExists(atPath: commitsURL.path) else { return disk }
            let names = try FileManager.default.contentsOfDirectory(atPath: commitsURL.path)
            guard names.count <= 10000 else { throw LifeError.message("永久账本达到本版容量上限。") }
            let expression = try NSRegularExpression(pattern: "^e[1-9][0-9]*-g[1-9][0-9]*-[a-f0-9]{64}\\.json$")
            for name in names.sorted() {
                guard expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil else { throw LifeError.message("账本中有未知文件，未采用。") }
                let bytes = try read(exchange + "/commits/" + name, root: base, maximum: 65536)
                disk.commits.append(bytes.base64EncodedString()); disk.totalBytes += bytes.count
                // Only read fixed manifests named by a strictly shaped commit filename.
                let fields = name.split(separator: "-")
                let manifest = "generations/" + fields[0] + "/" + fields[1] + "/generation-manifest.json"
                let m = try read(exchange + "/" + manifest, root: base, maximum: 1024 * 1024)
                disk.files[manifest] = m.base64EncodedString(); disk.totalBytes += m.count
            }
            // Contents of the newest directory are not authoritative. Include all
            // retained big generations; the strict ledger decides the unique head.
            let generations = try path(exchange + "/generations", root: base)
            if let enumerator = FileManager.default.enumerator(at: generations, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey,.isRegularFileKey], options: []) {
                var count = 0
                for case let url as URL in enumerator {
                    count += 1; guard count <= 15000 else { throw LifeError.message("交换目录文件过多。") }
                    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey,.isDirectoryKey])
                    guard values.isSymbolicLink != true else { throw LifeError.message("交换目录含符号链接。") }
                    if values.isDirectory == true { continue }
                    let prefix = generations.path + "/"; guard url.path.hasPrefix(prefix) else { throw LifeError.invalidValue }
                    let rel = "generations/" + String(url.path.dropFirst(prefix.count))
                    if disk.files[rel] == nil { let bytes = try read(exchange + "/" + rel, root: base); disk.files[rel] = bytes.base64EncodedString(); disk.totalBytes += bytes.count }
                    guard disk.totalBytes <= budget else { throw LifeError.message("同步目录超过32MB，请保留当前/上一代及永久账本后再发布。") }
                }
            }
            let hintURL = try path(exchange + "/current.json", root: base)
            if FileManager.default.fileExists(atPath: hintURL.path), let object = try? JSONSerialization.jsonObject(with: read(exchange + "/current.json", root: base, maximum: 65536)) as? [String:Any] { disk.headHint = object["commitID"] as? String }
            return disk
        }
    }
    static func writePublication(root: URL, files: [String:Data], commitPath: String, expectedCommits: Set<String>, datasetID: String, commitID: String) throws {
        try coordinated(root, write: true) { base in
            // Serialize publishers under the selected directory. Check ledger bytes
            // again just before COMMITTED; a changed parent is a visible failure.
            let commitsURL = try path(exchange + "/commits", root: base, createParents: true)
            if !FileManager.default.fileExists(atPath: commitsURL.path) { try FileManager.default.createDirectory(at: commitsURL, withIntermediateDirectories: false) }
            let current = try Set(FileManager.default.contentsOfDirectory(atPath: commitsURL.path).map { try read(exchange + "/commits/" + $0, root: base, maximum: 65536).base64EncodedString() })
            guard current == expectedCommits else { throw LifeError.message("同步账本在准备期间变化，请重新读取，未发布提交记录。") }
            for relative in files.keys.sorted() where relative != commitPath { try immutableWrite(files[relative]!, relative: exchange + "/" + relative, root: base) }
            guard let record = files[commitPath] else { throw LifeError.invalidValue }
            try immutableWrite(record, relative: exchange + "/" + commitPath, root: base)
            let hint = try JSONSerialization.data(withJSONObject: ["datasetID":datasetID,"commitID":commitID], options: [.sortedKeys])
            try hint.write(to: path(exchange + "/current.json", root: base), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    static func noteSnapshot(root: URL) throws -> [String:String] {
        try coordinated(root, write: false) { base in
            let notes = try path("Dayisle", root: base); if !FileManager.default.fileExists(atPath: notes.path) { return [:] }
            var output: [String:String] = [:], total = 0
            guard let enumerator = FileManager.default.enumerator(at: notes, includingPropertiesForKeys: [.isSymbolicLinkKey,.isDirectoryKey], options: []) else { throw LifeError.invalidValue }
            var count = 0
            for case let url as URL in enumerator {
                count += 1; guard count <= 2000 else { throw LifeError.message("派生笔记目录过大，未写入。") }
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey,.isDirectoryKey]); guard values.isSymbolicLink != true else { throw LifeError.message("派生笔记目录含链接。") }; if values.isDirectory == true { continue }
                guard url.path.hasPrefix(base.path + "/") else { throw LifeError.invalidValue }
                let rel = String(url.path.dropFirst(base.path.count + 1))
                if url.pathExtension.lowercased() == "md" { let bytes = try read(rel, root: base, maximum: 2 * 1024 * 1024); total += bytes.count; guard total <= 8 * 1024 * 1024 else { throw LifeError.message("派生笔记扫描超过8MB，未写入。") }; output[rel] = bytes.base64EncodedString() }
            }
            return output
        }
    }
    static func writeNote(root: URL, relative: String, bytes: Data, originalHash: String, ledgerCommits: Set<String>) throws {
        try coordinated(root, write: true) { base in
            guard relative.hasPrefix("Dayisle/") else { throw LifeError.invalidValue }
            let commits = try path(exchange + "/commits", root: base)
            let latest = try Set(FileManager.default.contentsOfDirectory(atPath: commits.path).map { try read(exchange + "/commits/" + $0, root: base, maximum: 65536).base64EncodedString() })
            guard latest == ledgerCommits else { throw LifeError.message("同步代已变化，笔记未修改，请重新预览。") }
            let url = try path(relative, root: base, createParents: true)
            let old = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : Data()
            guard hashBytes(old) == originalHash else { throw LifeError.message("笔记在预览后变化，未覆盖，请重新核对。") }
            if old != bytes { try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        }
    }
}

// File I/O workers must not access an actor-isolated store just to hash bytes.
func hashBytes(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
