import Foundation
import Darwin

/// Private ownership receipt for an interrupted C-last publication. No user text.
struct PendingVaultWrite: Codable, Sendable {
    var format = "dayisle-pending-publication/v1"
    var bindingID: UUID
    var datasetID: UUID
    var writerID: UUID
    var commitPath: String
    var fileHashes: [String:String]
    var parentHashes: [String]
    var createdAt = Date()
    var generationRoot: String {
        let parts = commitPath.dropFirst("commits/".count).split(separator:"-")
        return parts.count == 3 ? "generations/" + parts[0] + "/" + parts[1] : ""
    }
    func validate() throws {
        let commitPattern = "^commits/e[1-9][0-9]*-g[1-9][0-9]*-[a-f0-9]{64}\\.json$"
        guard format == "dayisle-pending-publication/v1", commitPath.range(of:commitPattern,options:.regularExpression) != nil,
              fileHashes.count <= 1200, parentHashes.count <= 10000, Set(parentHashes).count == parentHashes.count,
              fileHashes[commitPath] != nil, fileHashes[generationRoot + "/generation-manifest.json"] != nil,
              (Array(fileHashes.values) + parentHashes).allSatisfy({ $0.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil }) else { throw LifeError.message("发布恢复凭据无效，原文件保留。") }
        for path in fileHashes.keys where path != commitPath {
            guard path.hasPrefix(generationRoot + "/"), String(path.dropFirst(generationRoot.count + 1)).range(of:"^(snapshot\\.json|generation-manifest\\.json|days/[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json|projections/[a-f0-9]{64}\\.json)$",options:.regularExpression) != nil else { throw LifeError.invalidValue }
        }
    }
}

extension VaultFiles {
    /// Returns true if C already exists. Never deletes a committed generation.
    static func recoverUncommitted(root: URL, receipt: PendingVaultWrite) throws -> Bool {
        try receipt.validate()
        return try coordinated(root,write:true) { base in
            let rawCommit = base.appendingPathComponent(exchange + "/" + receipt.commitPath)
            if FileManager.default.fileExists(atPath:rawCommit.path) {
                let bytes = try read(exchange + "/" + receipt.commitPath,root:base,maximum:65536)
                guard hashBytes(bytes) == receipt.fileHashes[receipt.commitPath] else { throw LifeError.message("恢复位置存在不同提交，未清理任何文件。") }
                return true
            }
            let commitsURL = base.appendingPathComponent(exchange + "/commits")
            var parents: [String] = [], protected: Set<String> = []
            if FileManager.default.fileExists(atPath:commitsURL.path) {
                _ = try path(exchange + "/commits",root:base)
                let names = try FileManager.default.contentsOfDirectory(atPath:commitsURL.path)
                guard names.count <= 10000 else { throw LifeError.invalidValue }
                for name in names {
                    let bytes = try read(exchange + "/commits/" + name,root:base,maximum:65536); parents.append(hashBytes(bytes))
                    guard let c = try JSONSerialization.jsonObject(with:bytes) as? [String:Any], let manifest = c["manifestPath"] as? String, manifest.hasSuffix("/generation-manifest.json") else { throw LifeError.message("恢复时账本异常，未删除任何内容。") }
                    protected.insert(String(manifest.dropLast("/generation-manifest.json".count)))
                }
            }
            guard Set(parents) == Set(receipt.parentHashes), !protected.contains(receipt.generationRoot) else { throw LifeError.message("上次中断后账本已变化，未清理或覆盖同步文件。") }
            var owned: [URL] = [], total = 0
            for relative in receipt.fileHashes.keys.sorted() where relative != receipt.commitPath {
                let raw = base.appendingPathComponent(exchange + "/" + relative)
                guard FileManager.default.fileExists(atPath:raw.path) else { continue }
                let bytes = try read(exchange + "/" + relative,root:base,maximum:16*1024*1024)
                total += bytes.count
                guard total <= 32*1024*1024, hashBytes(bytes) == receipt.fileHashes[relative] else { throw LifeError.message("中断文件已被修改或超过清理预算，原件保留。") }
                owned.append(try path(exchange + "/" + relative,root:base))
            }
            // Inventory all ownership hashes and references before the first removal.
            for url in owned { try FileManager.default.removeItem(at:url) }
            for suffix in ["/days","/projections",""] {
                let directory = base.appendingPathComponent(exchange + "/" + receipt.generationRoot + suffix)
                if FileManager.default.fileExists(atPath:directory.path) {
                    _ = try path(exchange + "/" + receipt.generationRoot + suffix,root:base)
                    let status = directory.withUnsafeFileSystemRepresentation { pointer in pointer.map { Darwin.rmdir($0) } ?? -1 }
                    if status != 0 && errno != ENOTEMPTY && errno != ENOENT { throw LifeError.message("中断文件已处理，但空目录清理失败。") }
                }
            }
            return false
        }
    }
}
