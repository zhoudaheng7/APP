import Foundation

struct RetiredFileProof: Sendable { var path: String; var sha256: String }

extension VaultFiles {
    private static func memberPathAllowed(_ relative: String) -> Bool {
        relative.range(of:"^generations/e[1-9][0-9]*/g[1-9][0-9]*/(snapshot\\.json|days/[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json|projections/[a-f0-9]{64}\\.json)$",options:.regularExpression) != nil
    }
    static func loadMembers(root: URL, disk: VaultDisk, paths: [String]) throws -> VaultDisk {
        guard paths.count <= 1200, Set(paths).count == paths.count, paths.allSatisfy(memberPathAllowed) else { throw LifeError.invalidValue }
        return try coordinated(root,write:false) { base in
            guard try commitSet(root:base) == Set(disk.commits) else { throw LifeError.message("读取期间同步账本变化，请重试。") }
            var loaded = disk
            for relative in paths {
                let maximum = relative.hasSuffix("/snapshot.json") ? 16*1024*1024 : 1024*1024
                let bytes = try read(exchange + "/" + relative,root:base,maximum:maximum); loaded.totalBytes += bytes.count
                guard loaded.totalBytes <= budget else { throw LifeError.message("当前同步代及永久证据超过32MB，未采用。") }
                loaded.files[relative] = bytes.base64EncodedString()
            }
            return loaded
        }
    }
    static func commitSet(root: URL) throws -> Set<String> {
        let url = try path(exchange + "/commits",root:root)
        if !FileManager.default.fileExists(atPath:url.path) { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath:url.path)
        guard names.count <= 10000 else { throw LifeError.invalidValue }
        var result: Set<String> = []
        for name in names {
            guard name.range(of:"^e[1-9][0-9]*-g[1-9][0-9]*-[a-f0-9]{64}\\.json$",options:.regularExpression) != nil else { throw LifeError.message("账本有未知文件，已停止。") }
            result.insert(try read(exchange + "/commits/" + name,root:root,maximum:65536).base64EncodedString())
        }
        return result
    }
    /// Bounded namespace inventory; unknown files count toward budget and are never deleted.
    static func inventory(root: URL, reservedBytes: Int = 0) throws -> [String] {
        guard (0...128*1024*1024).contains(reservedBytes) else { throw LifeError.invalidValue }
        let folder = try path(exchange,root:root)
        guard FileManager.default.fileExists(atPath:folder.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]) else { throw LifeError.invalidValue }
        var files: [String] = [], total = reservedBytes, count = 0
        for case let url as URL in enumerator {
            count += 1; guard count <= 15000 else { throw LifeError.message("交换根超过15,000个文件/目录，未继续写入。") }
            guard url.path.hasPrefix(folder.path + "/") else { throw LifeError.invalidValue }
            let relative = String(url.path.dropFirst(folder.path.count + 1)); _ = try path(exchange + "/" + relative,root:root)
            let values = try url.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard values.isSymbolicLink != true else { throw LifeError.invalidValue }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, let size = values.fileSize, (0...128*1024*1024).contains(size), total <= 128*1024*1024-size else { throw LifeError.message("交换根超过128MB或含未知类型，原文件保留。") }
            total += size; files.append(relative)
        }
        return files
    }
    static func retirementFiles(root: URL, paths: [String]) throws -> [String:String] {
        guard paths.count <= 512, paths.allSatisfy(memberPathAllowed) else { throw LifeError.invalidValue }
        return try coordinated(root,write:false) { base in
            var files: [String:String] = [:], total = 0
            for relative in paths {
                let bytes = try read(exchange + "/" + relative,root:base,maximum:16*1024*1024)
                if total + bytes.count > 32*1024*1024 { break }
                total += bytes.count; files[relative] = bytes.base64EncodedString()
            }
            return files
        }
    }
    static func removeRetired(root: URL, files: [RetiredFileProof], keep: [String], head: String, expectedCommits: Set<String>) throws -> Int {
        guard files.count <= 512, Set(files.map(\.path)).count == files.count, files.allSatisfy({ memberPathAllowed($0.path) && $0.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil }) else { throw LifeError.invalidValue }
        return try coordinated(root,write:true) { base in
            guard try commitSet(root:base) == expectedCommits else { throw LifeError.message("清理前账本变化，未删除。") }
            let exchangeURL = try path(exchange,root:base), names = try FileManager.default.contentsOfDirectory(atPath:exchangeURL.path)
            guard !names.contains(where:{ ["pins",".pins","pins.json","retention-pins.json"].contains($0.lowercased()) }) else { throw LifeError.message("存在保留标记，已跳过退役清理。") }
            var records: [String:[String:Any]] = [:]
            for encoded in expectedCommits { guard let bytes = Data(base64Encoded:encoded), let value = try JSONSerialization.jsonObject(with:bytes) as? [String:Any], let id = value["commitID"] as? String else { throw LifeError.invalidValue }; records[id] = value }
            guard let current = records[head], let currentPath = current["manifestPath"] as? String else { throw LifeError.invalidValue }
            var protected = [String(currentPath.dropLast("/generation-manifest.json".count))]
            if let previous = current["previousCommitID"] as? String { guard let previousPath = records[previous]?["manifestPath"] as? String else { throw LifeError.invalidValue }; protected.append(String(previousPath.dropLast("/generation-manifest.json".count))) }
            guard Set(protected) == Set(keep) else { throw LifeError.message("当前/回退保护范围不一致，未清理。") }
            var owned: [URL] = [], total = 0
            for proof in files {
                guard !protected.contains(where:{ proof.path.hasPrefix($0 + "/") }) else { throw LifeError.message("不能删除当前或上一大代。") }
                let url = try path(exchange + "/" + proof.path,root:base)
                guard FileManager.default.fileExists(atPath:url.path) else { continue }
                let bytes = try read(exchange + "/" + proof.path,root:base,maximum:16*1024*1024); total += bytes.count
                guard total <= 32*1024*1024, hashBytes(bytes) == proof.sha256 else { throw LifeError.message("退役文件已变化或超过本次预算，未删除。") }
                owned.append(url)
            }
            for url in owned { try FileManager.default.removeItem(at:url) }
            return owned.count
        }
    }
}
