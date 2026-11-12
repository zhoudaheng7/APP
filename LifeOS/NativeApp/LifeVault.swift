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
struct DisclosurePreviewField: Identifiable { let id: String; let value: String }
struct DisclosurePreviewRecord: Identifiable {
    let id: String
    let kind: String
    let title: String
    let reflection: String?
    let fields: [DisclosurePreviewField]
    init(_ row: [String:Any]) {
        let type = row["entityType"] as? String ?? ""
        kind = ["Task":"任务","DraftPlan":"私人计划","CalendarCommitment":"日历承诺","ActualSession":"实际投入","DailyReview":"日复盘"][type] ?? type
        id = type + ":" + (row["entityID"] as? String ?? "")
        title = row["title"] as? String ?? row["dayKey"] as? String ?? "不披露标题"
        reflection = row["reflection"] as? String
        let labels = ["lifecycleStatus":"状态","runState":"计时状态","factState":"核对状态","plannedStart":"开始（UTC）","plannedEnd":"结束（UTC）","start":"开始（UTC）","end":"结束（UTC）","actualStart":"实际开始（UTC）","actualEnd":"实际结束（UTC）","dayKey":"归属日期","attributionTimeZone":"归属时区","calendarTimeZone":"日历时区","localStartDate":"全天开始日期","localEndDateExclusive":"全天截止（不含）","allDay":"全天","taskID":"已选择任务的同步身份"]
        fields = labels.keys.sorted().compactMap { key in guard let value = row[key] else { return nil }; return DisclosurePreviewField(id:labels[key]!,value:value is NSNull ? "未知/未结束":String(describing:value)) }
    }
}
private struct PublicationPreview {
    var candidate: [String:Any]
    var files: [String:Data]
    var disk: VaultDisk
    var sourceFingerprint: String
    var createdAt: Date
}

@MainActor @Observable final class LifeVault {
    static let shared = LifeVault()
    private(set) var binding: VaultBinding?
    private var runtime: WireRuntime?
    private(set) var busy = false
    var message = ""
    private(set) var preview = ""
    private(set) var previewRecords: [DisclosurePreviewRecord] = []
    private(set) var previewDate: Date?
    private var publicationCandidate: PublicationPreview?
    private(set) var verifiedCommit: [String:Any]?
    private(set) var projectionKey: String?
    private var projectionKeys: [String:String] = [:]
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
    var publicationReady: Bool { publicationCandidate != nil }
    private func publicFingerprint(_ binding: VaultBinding) throws -> String {
        let state = store.data
        let fields: [String:Any] = ["datasetID":state.disclosure.datasetID.wire,"writerID":state.disclosure.writerID.wire,"bindingID":binding.id.wire,"bookmark":hashBytes(binding.bookmark),"projectionEnabled":binding.projectionEnabled,"projectionEpoch":binding.projectionEpoch,"projectionDays":binding.mappings.keys.sorted(),"grants":(state.disclosure.grants ?? []).map(\.wireValue),"entities":state.disclosedWireEntities(),"deleted":state.wireTombstones()]
        return hashBytes(try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys]))
    }
    func makePreview() async {
        guard !busy, let binding else { return }; busy = true; publicationCandidate = nil; previewRecords = []; defer { busy = false }
        do {
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let disk = try await Task.detached { try VaultFiles.disk(root:root) }.value
            guard store.refreshForExternalUse() else { throw LifeError.message("本机数据未能重新核对，未准备发布。") }
            let state = store.data, settings = state.disclosure
            guard settings.enabled, settings.datasetID == binding.datasetID, settings.writerID == binding.writerID else { throw LifeError.message("目录绑定与本机发布身份不一致，请重新绑定。") }
            let engine = try runtime ?? WireRuntime(); runtime = engine
            if disk.commits.isEmpty && settings.lastCommitID != nil { throw LifeError.message("这个目录尚未包含本机已经发布的账本，请等待同步；不要自动另建或覆盖。") }
            if !disk.commits.isEmpty {
                let verified = try engine.call("verify",["commits":disk.commits,"files":disk.files,"datasetID":settings.datasetID.wire])
                guard verified["status"] as? String == "promoted" else { throw LifeError.message("原同步账本校验失败，未覆盖。") }
                if let floor = settings.lastCommitID, !(verified["ancestry"] as? [String] ?? []).contains(floor) { throw LifeError.message("目录尚未包含本机最近的发布记录，已阻止旧同步覆盖。") }
            }
            let selectedIDs = Set((settings.grants ?? []).filter { $0.entityType == "ActualSession" }.map(\.entityID))
            guard !state.sessions.contains(where:{ selectedIDs.contains($0.id) && $0.restorePending == true && $0.end == nil }) else { throw LifeError.message("先核对已选实际记录中恢复的未结束计时，再披露它。") }
            let now = Date(), start = Calendar.current.date(byAdding:.day,value:-30,to:now)!, end = Calendar.current.date(byAdding:.day,value:3,to:now)!
            let seed: [String:Any] = ["datasetID":settings.datasetID.wire,"writerID":settings.writerID.wire,"bindingID":binding.id.wire,"today":LifeSnapshot.dayKey(now),"startDay":LifeSnapshot.dayKey(start),"endDay":LifeSnapshot.dayKey(end),"now":wireInstant(now),"projectionEnabled":binding.projectionEnabled,"projectionEpoch":binding.projectionEpoch,"projectionDays":binding.mappings.keys.sorted(),"entities":state.disclosedWireEntities(),"deleted":state.wireTombstones(),"disclosure":["grants":(settings.grants ?? []).map(\.wireValue)],"disk":["commits":disk.commits,"files":disk.files,"datasetID":settings.datasetID.wire]]
            let candidate = try engine.call("build",seed)
            guard let encoded = candidate["files"] as? [String:String], let snapshot = candidate["snapshot"] as? [String:Any], let manifest = candidate["manifest"] as? [String:Any], let rows = snapshot["entities"] as? [[String:Any]] else { throw LifeError.invalidValue }
            var files: [String:Data] = [:]
            for (path,base64) in encoded { guard let bytes = Data(base64Encoded:base64) else { throw LifeError.invalidValue }; files[path] = bytes }
            let policy = (manifest["capabilities"] as? [String:Any])?["disclosure"] as? [String:Any] ?? [:]
            preview = String(decoding:try JSONSerialization.data(withJSONObject:["snapshot":snapshot,"disclosure":policy],options:[.prettyPrinted,.sortedKeys]),as:UTF8.self)
            previewRecords = rows.map(DisclosurePreviewRecord.init); previewDate = now
            publicationCandidate = PublicationPreview(candidate:candidate,files:files,disk:disk,sourceFingerprint:try publicFingerprint(binding),createdAt:now)
            let withdrawn = (policy["stamps"] as? [[String:Any]] ?? []).filter { $0["state"] as? String == "withdrawn" }.count
            message = "已准备完整预览：\(rows.count)条当前授权记录，本次撤回\(withdrawn)条。同步身份与摘要历史保留以防旧内容重现；本机原记录保留。确认前尚未写入Vault。"
        } catch { message = error.localizedDescription }
    }
    func publish() async {
        guard !busy, let binding, let prepared = publicationCandidate else { message = "先完整预览，再确认发布。"; return }; busy = true; defer { busy = false }
        do {
            guard store.refreshForExternalUse(), Date().timeIntervalSince(prepared.createdAt) <= 900, try publicFingerprint(binding) == prepared.sourceFingerprint else { publicationCandidate = nil; throw LifeError.message("记录、披露选择或发布设置在预览后变化，或预览超过15分钟。请重新预览；这次没有写入。") }
            let candidate = prepared.candidate, settings = store.data.disclosure
            guard let engine = runtime, let commit = candidate["commit"] as? [String:Any], let commitID = commit["commitID"] as? String, let commitPath = candidate["commitPath"] as? String else { throw LifeError.invalidValue }
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let files = prepared.files, expected = Set(prepared.disk.commits)
            try await Task.detached { try VaultFiles.writePublication(root:root,files:files,commitPath:commitPath,expectedCommits:expected,datasetID:settings.datasetID.wire,commitID:commitID) }.value
            _ = try engine.call("adopt",["commitID":commitID]); verifiedCommit = commit; projectionKey = candidate["projectionKey"] as? String; projectionKeys = candidate["projectionKeys"] as? [String:String] ?? [:]
            var published = prepared.disk; published.commits.append(files[commitPath]!.base64EncodedString()); published.files.merge(files.mapValues { $0.base64EncodedString() }) { _,new in new }; lastDisk = published
            if store.commit(kind: "vault.published", id: settings.datasetID, { $0.disclosure.lastCommitID = commitID; $0.disclosure.lastSequence = (commit["generation"] as? NSNumber)?.int64Value ?? 0; $0.disclosure.lastPublishedGrants = settings.grants ?? [] }) {
                message = "预览的完整授权视图已发布。配套插件校验后替换当前视图；受管笔记块须另行核对并更新，外部/离线副本不会被自动抹去。"
                if (try? publicFingerprint(binding)) != prepared.sourceFingerprint { message += " 发布过程中又有修改，后来的选择尚未发布，请重新预览。" }
            } else { message = "同步代已发布，但本机发布回执保存失败；请先重新读取，不要更换数据集。" }
            publicationCandidate = nil; projectionCandidate = nil
        } catch { message = error.localizedDescription + " 若文件提供方曾中断，请重新读取核对提交状态；不要把失败当作撤回完成。" }
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
