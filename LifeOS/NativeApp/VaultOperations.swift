import Foundation

struct VaultRequestFile: Sendable {
    var clientID: String
    var operationID: String
    var bytes: String
}
struct IncomingReview: Identifiable {
    var id: UUID
    var clientID: UUID
    var bytes: String
    var day: String
    var reflection: String
    var zone: String
    var validation: String
}
extension VaultFiles {
    static func requests(root: URL) throws -> [VaultRequestFile] {
        try coordinated(root, write: false) { base in
            let intents = try path(exchange + "/intents", root: base)
            if !FileManager.default.fileExists(atPath: intents.path) { return [] }
            var output: [VaultRequestFile] = []
            let clients = try FileManager.default.contentsOfDirectory(atPath: intents.path)
            guard clients.count <= 100 else { throw LifeError.message("请求来源过多，停止扫描。") }
            for client in clients {
                guard let id = UUID(uuidString: client), id.uuidString.lowercased() == client else { throw LifeError.message("请求目录身份无效。") }
                let folder = try path(exchange + "/intents/" + client, root: base)
                let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                for name in names {
                    guard output.count < 200 else { throw LifeError.message("一次最多核对200个请求，请先处理已有请求。") }
                    let op = String(name.dropLast(5))
                    guard name.hasSuffix(".json"), let id = UUID(uuidString: op), id.uuidString.lowercased() == op else { throw LifeError.message("请求文件名无效。") }
                    let bytes = try read(exchange + "/intents/" + client + "/" + name, root: base, maximum: 100000)
                    output.append(VaultRequestFile(clientID: client, operationID: op, bytes: bytes.base64EncodedString()))
                }
            }
            return output
        }
    }
    static func writeReceipts(root: URL, records: [VaultOperation]) throws {
        try coordinated(root, write: true) { base in
            for record in records { try immutableWrite(record.receipt, relative: exchange + "/receipts/" + record.id.uuidString.lowercased() + "/1.json", root: base) }
        }
    }
    static func installPlugin(root: URL, files: [String:Data], previous: [String:String]) throws -> [String:String] {
        try coordinated(root, write: true) { base in
            let prefix = ".obsidian/plugins/dayisle-panel/"
            for (name,_) in files {
                let url = try path(prefix + name, root: base, createParents: true)
                if FileManager.default.fileExists(atPath: url.path) {
                    let old = try Data(contentsOf: url), oldHash = hashBytes(old)
                    guard old == files[name] || previous[name] == oldHash else { throw LifeError.message("发现不是本App登记的插件文件或用户修改，未覆盖。") }
                }
            }
            var hashes: [String:String] = [:]
            for name in files.keys.sorted(by: { $0 == "manifest.json" ? false : $1 == "manifest.json" ? true : $0 < $1 }) {
                let url = try path(prefix + name, root: base, createParents: true); let content = files[name]!
                if !FileManager.default.fileExists(atPath: url.path) || (try Data(contentsOf: url)) != content { try content.write(to: url, options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }; hashes[name] = hashBytes(content)
            }
            // Enabling community plugins remains an explicit Obsidian user action.
            return hashes
        }
    }
}

extension LifeStore {
    func recordVaultResult(_ operation: VaultOperation, review: LifeReview?) -> Bool {
        if let previous = data.vaultOperations.first(where: { $0.id == operation.id }) {
            guard previous.payloadHash == operation.payloadHash, previous.clientID == operation.clientID else { error = "同一请求身份出现不同内容，已阻断，原结果保留。"; return false }; return true
        }
        return commit(kind: "vault.operation", id: operation.id) { state in
            guard (operation.status == "accepted") == (review != nil) else { throw LifeError.invalidValue }
            if var review {
                guard !state.reviews.contains(where: { $0.day == review.day && $0.canonical != false }), review.id == operation.finalEntityID else { throw LifeError.message("这一天已有正式复盘，本请求不能覆盖。") }
                review.sourceOperationID = operation.id; state.reviews.insert(review, at: 0)
            }
            state.vaultOperations.append(operation)
        }
    }
}
