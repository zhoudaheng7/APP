import Foundation
import Observation

struct ProjectionMapping: Codable { var path: String; var state = "active" }
struct VaultBinding: Codable {
    var bookmark: Data
    var datasetID: UUID
    var writerID: UUID
    var id = UUID()
    var projectionEpoch = 1
    var projectionEnabled = false
    var mappings: [String:ProjectionMapping] = [:]
    var pluginHashes: [String:String] = [:]
}

@MainActor @Observable final class LifeVault {
    static let shared = LifeVault()
    private(set) var binding: VaultBinding?
    private var runtime: WireRuntime?
    private(set) var busy = false
    var message = ""
    private(set) var preview = ""
    private(set) var verifiedCommit: [String:Any]?
    private(set) var projectionKey: String?
    private var lastDisk = VaultDisk()
    private var projectionCandidate: [String:Any]?
    private(set) var incoming: [IncomingReview] = []
    private let store: LifeStore
    init(store: LifeStore? = nil) {
        self.store = store ?? .shared
        do {
            let url = try Self.bindingURL()
            if FileManager.default.fileExists(atPath: url.path) { binding = try JSONDecoder().decode(VaultBinding.self, from: Data(contentsOf: url)) }
        } catch { message = "已保存的目录授权无法读取，原文件未重置；请重新选择目录。" }
    }
    private static func bindingURL() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("LifeOS", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root.appendingPathComponent("VaultBinding-v2.json")
    }
    private func persistBinding(_ binding: VaultBinding) throws {
        try JSONEncoder().encode(binding).write(to: Self.bindingURL(), options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication]); self.binding = binding
    }
    private func root() throws -> URL {
        guard let binding else { throw LifeError.message("请先在文件选择器中主动选择Vault目录。") }
        var stale = false
        let url = try URL(resolvingBookmarkData: binding.bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { throw LifeError.message("目录授权已过期，请重新选择原Vault目录。") }; return url
    }
    func bind(_ url: URL, newDataset: Bool = false) {
        guard !busy else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try VaultFiles.path("LifeOSExchange", root: url)
            if !newDataset, let existing = try? root(), existing.standardizedFileURL != url.standardizedFileURL { throw LifeError.message("已有绑定。若更换空目录，请明确选择建立新数据集，不能悄悄接管另一目录。") }
            if newDataset {
                let commits = url.appendingPathComponent("LifeOSExchange/commits", isDirectory: true)
                guard !FileManager.default.fileExists(atPath: commits.path) else { throw LifeError.message("新数据集只能绑定新的空交换目录，旧账本未改动。") }
            }
            let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            var settings = store.data.disclosure
            if newDataset { settings = DisclosureSettings() }
            var next = (!newDataset ? binding : nil) ?? VaultBinding(bookmark: bookmark, datasetID: settings.datasetID, writerID: settings.writerID)
            next.bookmark = bookmark; try persistBinding(next)
            if store.commit(kind: "vault.bind", id: next.id, { $0.disclosure = settings; $0.disclosure.enabled = true; $0.disclosure.approvedAt = Date() }) {
                runtime = try WireRuntime(); verifiedCommit = nil; projectionKey = nil; projectionCandidate = nil
                message = "已绑定你选择的目录。尚未向Vault发布任何事实，先预览内容。"
            }
        } catch { message = error.localizedDescription }
    }
    func makePreview() {
        preview = store.data.dailyProjectionBody(day: Date())
        message = "将发布任务、私人计划、日历承诺、实际投入与正式日复盘的全部当前记录；日段覆盖最近30天和未来2天。仅包含标题、时间、状态与复盘正文，不包含地点、路线、照片、人物、目标私密说明或密码。"
    }
    func publish() async {
        guard !busy, let binding else { return }; busy = true; defer { busy = false }
        do {
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let disk = try await Task.detached { try VaultFiles.disk(root: root) }.value
            let engine = try runtime ?? WireRuntime(); runtime = engine
            let settings = store.data.disclosure
            guard settings.enabled, settings.datasetID == binding.datasetID, settings.writerID == binding.writerID else { throw LifeError.message("目录绑定与本机发布身份不一致，请重新绑定，未发布。") }
            if disk.commits.isEmpty && settings.lastCommitID != nil { throw LifeError.message("原账本在这个目录不可见。请恢复同步完整性；若确定使用新的空目录，须明确建立新数据集。") }
            if !disk.commits.isEmpty {
                let verified = try engine.call("verify", ["commits":disk.commits,"files":disk.files,"datasetID":settings.datasetID.wire])
                guard verified["status"] as? String == "promoted" else { throw LifeError.message("原同步账本校验失败，未覆盖。") }
            }
            let now = Date(); let start = Calendar.current.date(byAdding: .day, value: -30, to: now)!, end = Calendar.current.date(byAdding: .day, value: 3, to: now)!
            let state = store.data
            guard !state.sessions.contains(where: { $0.restorePending == true && $0.end == nil }) else { throw LifeError.message("先核对从备份恢复的未结束记录，再发布Obsidian同步，避免把未知时间作为连续计时。") }
            let seed: [String:Any] = ["datasetID":settings.datasetID.wire,"writerID":settings.writerID.wire,"bindingID":binding.id.wire,"today":LifeSnapshot.dayKey(now),"startDay":LifeSnapshot.dayKey(start),"endDay":LifeSnapshot.dayKey(end),"now":wireInstant(now),"projectionEnabled":binding.projectionEnabled,"projectionEpoch":binding.projectionEpoch,"body":state.dailyProjectionBody(day: now),"entities":state.wireEntities(),"deleted":state.wireTombstones(),"disk":["commits":disk.commits,"files":disk.files,"datasetID":settings.datasetID.wire]]
            let candidate = try engine.call("build", seed)
            guard let encoded = candidate["files"] as? [String:String], let commit = candidate["commit"] as? [String:Any], let commitID = commit["commitID"] as? String, let commitPath = candidate["commitPath"] as? String else { throw LifeError.invalidValue }
            var files: [String:Data] = [:]
            for (path,base64) in encoded { guard let bytes = Data(base64Encoded: base64) else { throw LifeError.invalidValue }; files[path] = bytes }
            let expected = Set(disk.commits)
            try await Task.detached { try VaultFiles.writePublication(root: root, files: files, commitPath: commitPath, expectedCommits: expected, datasetID: settings.datasetID.wire, commitID: commitID) }.value
            _ = try engine.call("adopt", ["commitID":commitID]); verifiedCommit = commit; projectionKey = candidate["projectionKey"] as? String
            var published = disk; published.commits.append(encoded[commitPath]!); published.files.merge(encoded) { _,new in new }; lastDisk = published
            if store.commit(kind: "vault.published", id: settings.datasetID, { $0.disclosure.lastCommitID = commitID; $0.disclosure.lastSequence = (commit["generation"] as? NSNumber)?.int64Value ?? 0 }) {
                message = "完整同步代已发布。插件须在文件同步完成后校验再显示；尚未改动任何笔记正文。"
            } else { message = "同步代已发布，但本机发布回执保存失败；请先重新读取，不要更换数据集。" }
            projectionCandidate = nil
        } catch { message = error.localizedDescription }
    }
    func setProjection(_ enabled: Bool) {
        guard !busy, var next = binding, next.projectionEnabled != enabled else { return }
        guard next.projectionEpoch < 9_007_199_254_740_991 else { message = "发布配置计数达到上限，原配置保留。"; return }
        next.projectionEnabled = enabled; next.projectionEpoch += 1
        do { try persistBinding(next); projectionCandidate = nil; message = "笔记派生块设置已更改；重新发布同步代后才生效。" } catch { message = "设置未能保存，原授权不变。" }
    }
    func prepareProjection() async {
        guard !busy, let binding, binding.projectionEnabled, let engine = runtime, let commit = verifiedCommit, let head = commit["commitID"] as? String, let projectionKey else { message = "请先开启派生块并发布新的完整同步代。"; return }
        busy = true; defer { busy = false }
        do {
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let notes = try await Task.detached { try VaultFiles.noteSnapshot(root: root) }.value
            var input: [String:Any] = ["head":head,"projectionKey":projectionKey,"writerID":store.data.disclosure.writerID.wire,"notes":notes]
            let today = LifeSnapshot.dayKey(Date()); if let map = binding.mappings[today] { input["mapping"] = ["path":map.path,"state":map.state] }
            let candidate = try engine.call("project", input); projectionCandidate = candidate
            message = "已核对派生块和笔记原文。点击确认写入后只更新Dayisle目录中的受管块，块外文字保留。"
        } catch { projectionCandidate = nil; message = error.localizedDescription }
    }
    var projectionReady: Bool { projectionCandidate != nil }
    func writeProjection() async {
        guard !busy, var binding, let candidate = projectionCandidate, let path = candidate["path"] as? String, let base64 = candidate["bytes"] as? String, let bytes = Data(base64Encoded: base64), let originalHash = candidate["originalHash"] as? String, let day = candidate["dayKey"] as? String else { return }
        busy = true; defer { busy = false }
        do {
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let commits = Set(lastDisk.commits)
            try await Task.detached { try VaultFiles.writeNote(root: root, relative: path, bytes: bytes, originalHash: originalHash, ledgerCommits: commits) }.value
            binding.mappings[day] = ProjectionMapping(path: path); try persistBinding(binding); projectionCandidate = nil; message = "派生块已写入。用户正文保留；修改块内文字后，下一次更新会先报告冲突。"
        } catch { message = error.localizedDescription }
    }
    func scanRequests() async {
        guard !busy, binding != nil else { return }; busy = true; defer { busy = false }
        do {
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let files = try await Task.detached { try VaultFiles.requests(root: root) }.value
            let engine = try runtime ?? WireRuntime(); runtime = engine
            var candidates: [IncomingReview] = [], invalid = 0
            for file in files {
                do {
                    let result = try engine.call("parse-intent", ["bytes":file.bytes,"context":["datasetID":store.data.disclosure.datasetID.wire,"now":wireInstant(Date())]])
                    guard let intent = result["intent"] as? [String:Any], let payload = intent["payload"] as? [String:Any],
                          let opText = intent["operationID"] as? String, opText == file.operationID, let op = UUID(uuidString: opText),
                          let clientText = intent["clientInstanceID"] as? String, clientText == file.clientID, let client = UUID(uuidString: clientText),
                          let day = payload["dayKey"] as? String, let reflection = payload["reflection"] as? String, let zone = payload["attributionTimeZone"] as? String else { throw LifeError.invalidValue }
                    if store.data.vaultOperations.contains(where: { $0.id == op }) { continue }
                    let validation = (result["validation"] as? [String:Any])?["state"] as? String ?? "rejected"
                    candidates.append(IncomingReview(id: op, clientID: client, bytes: file.bytes, day: day, reflection: reflection, zone: zone, validation: validation))
                } catch { invalid += 1 }
            }
            incoming = candidates.sorted { $0.day < $1.day }; message = "读取到\(candidates.count)个待核对请求，\(invalid)个无效请求已隔离。读取不会建立正式复盘；请核对来源、日期和正文再逐条确认。"
        } catch { message = error.localizedDescription }
    }
    func process(_ request: IncomingReview, accept: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let engine = try runtime ?? WireRuntime(); runtime = engine
            let existing = store.data.vaultOperations.first { $0.id == request.id }
            let hasReview = store.data.reviews.contains { $0.day == request.day && $0.canonical != false }
            var context: [String:Any] = ["datasetID":store.data.disclosure.datasetID.wire,"now":wireInstant(Date()),"hasCanonicalReview":hasReview]
            if let existing { context["knownPayloadHash"] = existing.payloadHash }
            let parsed = try engine.call("parse-intent", ["bytes":request.bytes,"context":context])
            guard let intent = parsed["intent"] as? [String:Any], let hash = intent["payloadHash"] as? String, let validation = parsed["validation"] as? [String:Any] else { throw LifeError.invalidValue }
            if let existing {
                guard existing.payloadHash == hash && existing.clientID == request.clientID else { throw LifeError.message("请求身份出现内容冲突，原结果保留。") }
            } else {
                let valid = validation["state"] as? String == "valid"
                let status = validation["state"] as? String == "expired" ? "expired" : accept && valid ? "accepted":"rejected"
                let review = status == "accepted" ? LifeReview(day: request.day, timeZone: request.zone, reflection: request.reflection, mood: nil) : nil
                var result: [String:Any] = ["now":wireInstant(Date()),"state":status]
                if let review { result["entityID"] = review.id.wire }
                else { result["errorCode"] = valid ? "user_declined" : validation["code"] as? String ?? "invalid_request"; result["reason"] = valid ? "用户核对后未采用此草稿。":"请求已过期、已有正式复盘或校验未通过，未覆盖本机记录。" }
                let receipt = try engine.call("receipt", ["intent":intent,"result":result])
                let bytes = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                let record = VaultOperation(id: request.id, datasetID: store.data.disclosure.datasetID, clientID: request.clientID, payloadHash: hash, status: status, receipt: bytes, finalEntityID: review?.id)
                guard store.recordVaultResult(record, review: review) else { throw LifeError.message(store.error ?? "本机结果未保存，未写回执。") }
            }
            try await flushReceipts(); incoming.removeAll { $0.id == request.id }
            message = "核对结果与本机事实已在同一事务保存，回执已写入。接受的复盘需再发布完整同步代后才进入插件事实面板。"
        } catch { message = error.localizedDescription }
    }
    private func flushReceipts() async throws {
        let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
        let records = store.data.vaultOperations.filter { $0.datasetID == store.data.disclosure.datasetID }
        try await Task.detached { try VaultFiles.writeReceipts(root: root, records: records) }.value
    }
    func resendReceipts() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await flushReceipts(); message = "已保存结果的回执已幂等重发，没有重复建立复盘。" } catch { message = "本机结果保留，回执暂未写入；目录可用后可再次重发。" }
    }
    func installPlugin() async {
        guard !busy, var binding else { return }; busy = true; defer { busy = false }
        do {
            guard let code = Bundle.main.url(forResource: "DayislePlugin", withExtension: "js"), let manifest = Bundle.main.url(forResource: "DayislePlugin-manifest", withExtension: "json") else { throw LifeError.message("内置插件包不可用。") }
            let files = ["main.js":try Data(contentsOf: code),"manifest.json":try Data(contentsOf: manifest)]
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let previous = binding.pluginHashes
            let hashes = try await Task.detached { try VaultFiles.installPlugin(root: root, files: files, previous: previous) }.value
            binding.pluginHashes = hashes; try persistBinding(binding); message = "插件文件已写入此Vault。请在Obsidian的第三方插件列表启用“朝屿 Dayisle”；已启用时重新载入插件。未替你打开受限模式。"
        } catch { message = error.localizedDescription }
    }
    func unbind() {
        guard !busy else { return }
        do {
            guard store.commit(kind: "vault.unbind", id: store.data.disclosure.datasetID, { $0.disclosure.enabled = false }) else { return }
            let url = try Self.bindingURL(); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            binding = nil; runtime = nil; verifiedCommit = nil; projectionCandidate = nil; incoming = []
            message = "已停止后续发布并忘记目录授权。本机事实保留；Vault中已经披露的文件和插件缓存仍存在，这不是撤回历史披露。"
        } catch { message = "未能清除目录授权，本机已停止后续发布。" }
    }
}
