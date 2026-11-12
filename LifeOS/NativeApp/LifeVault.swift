import Foundation
import Observation

struct ProjectionMapping: Codable { var path: String; var state = "active"; var lastCommitID: String? }
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
        let states = ["open":"待办","completed":"已完成","cancelled":"已取消","archived":"已归档","active":"有效安排","running":"计时中","stopped":"已结束","confirmed":"已核对","inferred":"待核对","rejected":"已排除"]
        fields = labels.keys.sorted().compactMap { key in
            guard let value = row[key] else { return nil }; let text: String
            if value is NSNull { text = "未知/未结束" } else if key == "allDay", let flag = value as? Bool { text = flag ? "是":"否" } else { let raw = String(describing:value); text = states[raw] ?? raw }
            return DisclosurePreviewField(id:labels[key]!,value:text)
        }
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
    private var projectionCandidates: [[String:Any]] = []
    private(set) var projectionIssues: [String] = []
    private(set) var privacyCleanupPending = false
    private var checkpointNeeded = false
    var pendingMappedBlocksCount: Int { let head = verifiedCommit?["commitID"] as? String ?? store.data.disclosure.lastCommitID; return binding?.mappings.values.filter { $0.lastCommitID != head }.count ?? 0 }
    private(set) var incoming: [IncomingReview] = []
    private let store: LifeStore
    private let directory: URL?
    init(store: LifeStore? = nil, directory: URL? = nil) {
        self.store = store ?? .shared
        self.directory = directory
        do {
            let url = try bindingURL()
            if FileManager.default.fileExists(atPath: url.path) {
                let value = try url.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey]); guard value.isSymbolicLink != true,(value.fileSize ?? Int.max) <= 2*1024*1024 else { throw LifeError.invalidValue }
                binding = try JSONDecoder().decode(VaultBinding.self, from: Data(contentsOf: url))
            }
        } catch { message = "已保存的目录授权无法读取，原文件未重置；请重新选择目录。" }
    }
    private func bindingURL() throws -> URL {
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("LifeOS", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root.appendingPathComponent("VaultBinding-v2.json")
    }
    @discardableResult private func persistBinding(_ binding: VaultBinding) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let bytes = try encoder.encode(binding)
        guard bytes.count <= 2*1024*1024 else { throw LifeError.message("目录映射登记超过2MB，原件保留。") }
        try bytes.write(to: bindingURL(), options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication]); self.binding = binding; return bytes
    }
    private func pendingURL(_ binding: VaultBinding) throws -> URL { try bindingURL().deletingLastPathComponent().appendingPathComponent("PendingVaultPublication-" + binding.id.uuidString + ".json") }
    private func pendingWrite(_ binding: VaultBinding) throws -> PendingVaultWrite? {
        let url = try pendingURL(binding); guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        let values = try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 2*1024*1024 else { throw LifeError.invalidValue }
        let receipt = try JSONDecoder().decode(PendingVaultWrite.self,from:Data(contentsOf:url)); try receipt.validate()
        guard receipt.bindingID == binding.id, receipt.datasetID == binding.datasetID, receipt.writerID == binding.writerID else { throw LifeError.message("恢复凭据不属于当前绑定，已保留原件。") }
        return receipt
    }
    private func clearPending(_ binding: VaultBinding) throws {
        let url = try pendingURL(binding); if FileManager.default.fileExists(atPath:url.path) { _ = try pendingWrite(binding); try FileManager.default.removeItem(at:url) }
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
            next.bookmark = bookmark
            let priorBinding = binding
            let writtenBinding = try persistBinding(next)
            if store.commit(kind: "vault.bind", id: next.id, { $0.disclosure = settings; $0.disclosure.enabled = true; $0.disclosure.approvedAt = Date() }) {
                runtime = try WireRuntime(); verifiedCommit = nil; projectionKey = nil; projectionKeys = [:]; projectionCandidates = []; projectionIssues = []; publicationCandidate = nil
                message = "已绑定你选择的目录。尚未向Vault发布任何事实，先预览内容。"
            } else {
                let path = try bindingURL()
                guard try Data(contentsOf:path) == writtenBinding else { throw LifeError.message("绑定保存期间目录凭据已变化，原件保留，请重新核对。") }
                if let priorBinding { try persistBinding(priorBinding) }
                else { try FileManager.default.removeItem(at:path); binding = nil }
                message = store.error ?? "本机数据未保存，原目录绑定已恢复。"
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
            let pending = try pendingWrite(binding)
            if let pending { _ = try await Task.detached { try VaultFiles.recoverUncommitted(root:root,receipt:pending) }.value }
            var disk = try await Task.detached { try VaultFiles.disk(root:root,includeLarge:false) }.value
            let engine = try runtime ?? WireRuntime(); runtime = engine
            if !disk.commits.isEmpty {
                let needed = try engine.call("member-paths",["commits":disk.commits,"files":disk.files,"datasetID":binding.datasetID.wire])
                guard let paths = needed["paths"] as? [String] else { throw LifeError.invalidValue }
                let thin = disk; disk = try await Task.detached { try VaultFiles.loadMembers(root:root,disk:thin,paths:paths) }.value
            }
            guard store.refreshForExternalUse() else { throw LifeError.message("本机数据未能重新核对，未准备发布。") }
            let state = store.data, settings = state.disclosure
            guard settings.enabled, settings.datasetID == binding.datasetID, settings.writerID == binding.writerID else { throw LifeError.message("目录绑定与本机发布身份不一致，请重新绑定。") }
            if disk.commits.isEmpty && settings.lastCommitID != nil { throw LifeError.message("这个目录尚未包含本机已经发布的账本，请等待同步；不要自动另建或覆盖。") }
            if !disk.commits.isEmpty {
                let verified = try engine.call("verify",["commits":disk.commits,"files":disk.files,"datasetID":settings.datasetID.wire])
                guard verified["status"] as? String == "promoted" else { throw LifeError.message("原同步账本校验失败，未覆盖。") }
                if let floor = settings.lastCommitID, !(verified["ancestry"] as? [String] ?? []).contains(floor) { throw LifeError.message("目录尚未包含本机最近的发布记录，已阻止旧同步覆盖。") }
                checkpointNeeded = verified["needsCheckpoint"] as? Bool ?? false; privacyCleanupPending = checkpointNeeded || settings.privacyCleanupPending == true
                verifiedCommit = verified["commit"] as? [String:Any]; projectionKeys = verified["projectionKeys"] as? [String:String] ?? [:]; lastDisk = disk
            }
            if pending != nil { try clearPending(binding) }
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
            if candidate["needsCheckpoint"] as? Bool == true { message += " 撤回会再写一份完全相同、同一时刻的保护检查点，再清理早期正式大代；中断时明确标记待完成。" }
        } catch { message = error.localizedDescription }
    }
    func publish() async {
        guard !busy, let binding, let prepared = publicationCandidate else { message = "先完整预览，再确认发布。"; return }; busy = true; defer { busy = false }
        let initialHead = verifiedCommit?["commitID"] as? String
        do {
            guard store.refreshForExternalUse(), Date().timeIntervalSince(prepared.createdAt) <= 900, try publicFingerprint(binding) == prepared.sourceFingerprint else { publicationCandidate = nil; throw LifeError.message("记录、披露选择或发布设置在预览后变化，或预览超过15分钟。请重新预览；这次没有写入。") }
            guard let engine = runtime else { throw LifeError.invalidValue }
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let needsCheckpoint = prepared.candidate["needsCheckpoint"] as? Bool ?? false
            let needsCleanup = needsCheckpoint || privacyCleanupPending || store.data.disclosure.privacyCleanupPending == true
            try await writeConfirmed(prepared,binding:binding,root:root,engine:engine,cleanupPending:needsCleanup)
            if needsCheckpoint {
                let next = try engine.call("checkpoint",["disk":["datasetID":binding.datasetID.wire,"commits":lastDisk.commits,"files":lastDisk.files]])
                guard let encoded = next["files"] as? [String:String] else { throw LifeError.invalidValue }
                var bytes: [String:Data] = [:]; for (path,base64) in encoded { guard let data = Data(base64Encoded:base64) else { throw LifeError.invalidValue }; bytes[path] = data }
                let checkpoint = PublicationPreview(candidate:next,files:bytes,disk:lastDisk,sourceFingerprint:prepared.sourceFingerprint,createdAt:prepared.createdAt)
                try await writeConfirmed(checkpoint,binding:binding,root:root,engine:engine,cleanupPending:needsCleanup)
            }
            let removed = try await retireLarge(root:root,engine:engine,binding:binding)
            message = "完整授权视图已发布，已移除\(removed)个正式退役文件；永久身份/摘要证明保留。配套插件校验后采用新范围。另有\(pendingMappedBlocksCount)个已登记笔记块待核对更新；外部、手改或离线副本不作抹去承诺。"
            if (try? publicFingerprint(binding)) != prepared.sourceFingerprint { message += " 发布过程中又有修改，后来的选择尚未发布，请重新预览。" }
        } catch {
            if initialHead != (verifiedCommit?["commitID"] as? String) || (try? pendingWrite(binding)) != nil { privacyCleanupPending = true; _ = store.commit(kind:"vault.cleanup-pending",id:binding.datasetID) { $0.disclosure.privacyCleanupPending = true } }
            publicationCandidate = nil; message = error.localizedDescription + " 发布或保护清理未全部完成，请重新读取核对提交状态；不要把失败当作撤回完成。"
        }
    }
    private func writeConfirmed(_ prepared: PublicationPreview, binding: VaultBinding, root: URL, engine: WireRuntime, cleanupPending: Bool) async throws {
        let candidate = prepared.candidate
        guard let commit = candidate["commit"] as? [String:Any], let commitID = commit["commitID"] as? String, let commitPath = candidate["commitPath"] as? String, let manifest = candidate["manifest"] as? [String:Any], let policy = (manifest["capabilities"] as? [String:Any])?["disclosure"] as? [String:Any], let rawGrants = policy["grants"] as? [[String:Any]] else { throw LifeError.invalidValue }
        var grants: [DisclosureGrant] = []
        for row in rawGrants { guard let type = row["entityType"] as? String, let rawID = row["entityID"] as? String, let id = UUID(uuidString:rawID), let text = row["text"] as? Bool else { throw LifeError.invalidValue }; grants.append(DisclosureGrant(entityType:type,entityID:id,text:text)) }
        guard try pendingWrite(binding) == nil else { throw LifeError.message("上次发布尚待恢复，请重新完整预览。") }
        let files = prepared.files, expected = Set(prepared.disk.commits)
        let receipt = PendingVaultWrite(bindingID:binding.id,datasetID:binding.datasetID,writerID:binding.writerID,commitPath:commitPath,fileHashes:files.mapValues(hashBytes),parentHashes:prepared.disk.commits.map { hashBytes(Data(base64Encoded:$0)!) })
        try receipt.validate(); let receiptBytes = try JSONEncoder().encode(receipt)
        guard receiptBytes.count <= 2*1024*1024 else { throw LifeError.invalidValue }
        let recoveryDirectory = try bindingURL().deletingLastPathComponent(), names = try FileManager.default.contentsOfDirectory(atPath:recoveryDirectory.path).filter { $0.hasPrefix("PendingVaultPublication-") && $0.hasSuffix(".json") }
        guard names.count < 16 else { throw LifeError.message("本机已有16份发布恢复凭据，请先核对原绑定，不再堆积。") }
        try receiptBytes.write(to:pendingURL(binding),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        try await Task.detached { try VaultFiles.writePublication(root:root,files:files,commitPath:commitPath,expectedCommits:expected,datasetID:binding.datasetID.wire,commitID:commitID) }.value
        _ = try engine.call("adopt",["commitID":commitID]); verifiedCommit = commit; projectionKey = candidate["projectionKey"] as? String; projectionKeys = candidate["projectionKeys"] as? [String:String] ?? [:]
        checkpointNeeded = candidate["needsCheckpoint"] as? Bool ?? false; privacyCleanupPending = cleanupPending
        var published = prepared.disk; published.commits.append(files[commitPath]!.base64EncodedString()); published.files.merge(files.mapValues { $0.base64EncodedString() }) { _,new in new }
        if let manifestPath = commit["manifestPath"] as? String { let rootPath = String(manifestPath.dropLast("/generation-manifest.json".count)); published.files = published.files.filter { $0.key.hasSuffix("/generation-manifest.json") || $0.key.hasPrefix(rootPath + "/") } }
        lastDisk = published
        guard store.commit(kind:"vault.published",id:binding.datasetID,{ state in state.disclosure.lastCommitID = commitID; state.disclosure.lastSequence = (commit["generation"] as? NSNumber)?.int64Value ?? 0; state.disclosure.lastPublishedGrants = grants; state.disclosure.privacyCleanupPending = cleanupPending }) else { throw LifeError.message("同步代已发布，但本机回执未能保存，请重新读取核对。") }
        publicationCandidate = nil; projectionCandidates = []; projectionIssues = []; try clearPending(binding)
    }
    private func retireLarge(root: URL, engine: WireRuntime, binding: VaultBinding) async throws -> Int {
        guard !checkpointNeeded, let head = verifiedCommit?["commitID"] as? String else { throw LifeError.message("保护检查点尚未完成，不能清除上一大代。") }
        var removed = 0, contentBytes = 0
        for _ in 0..<30 {
            let inventory = try await Task.detached { try VaultFiles.coordinated(root,write:false) { try VaultFiles.inventory(root:$0) } }.value
            let plan = try engine.call("retire-plan",["datasetID":binding.datasetID.wire,"commits":lastDisk.commits,"files":lastDisk.files,"inventory":inventory])
            let count = plan["eligibleCount"] as? Int ?? 0
            if count == 0 {
                if store.data.disclosure.privacyCleanupPending == true { guard store.commit(kind:"vault.cleanup",id:binding.datasetID,{ $0.disclosure.privacyCleanupPending = false }) else { throw LifeError.message("历史文件已处理，但本机清理回执未保存。") } }
                privacyCleanupPending = false; return removed
            }
            guard let entries = plan["entries"] as? [[String:Any]], let keep = plan["keep"] as? [String] else { throw LifeError.invalidValue }
            let paths = entries.compactMap { $0["path"] as? String }
            let bytes = try await Task.detached { try VaultFiles.retirementFiles(root:root,paths:paths) }.value
            let checked = try engine.call("check-retirement",["files":bytes.map { ["path":$0.key,"bytes":$0.value] }])
            guard let rows = checked["files"] as? [[String:String]], !rows.isEmpty else { throw LifeError.message("退役清理未取得进展，原件保留。") }
            let proofs = try rows.map { row -> RetiredFileProof in guard let path = row["path"], let sha = row["sha256"] else { throw LifeError.invalidValue }; return RetiredFileProof(path:path,sha256:sha) }
            contentBytes += checked["contentBytes"] as? Int ?? 0
            guard contentBytes <= 128*1024*1024, removed + proofs.count <= 15000 else { throw LifeError.message("本次退役清理达到128MB/15,000项预算，剩余内容保留。") }
            let commits = Set(lastDisk.commits)
            removed += try await Task.detached { try VaultFiles.removeRetired(root:root,files:proofs,keep:keep,head:head,expectedCommits:commits) }.value
        }
        throw LifeError.message("退役清理达到本次批次上限，剩余内容保留。")
    }
    func cleanupRetired() async {
        guard !busy, let binding, let engine = runtime else { message = "先读取并校验当前同步代。"; return }; busy = true; defer { busy = false }
        do { let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }; let count = try await retireLarge(root:root,engine:engine,binding:binding); message = "已移除\(count)个正式退役文件，当前/回退大代、永久证明和未知文件保留。" }
        catch { privacyCleanupPending = true; _ = store.commit(kind:"vault.cleanup-pending",id:binding.datasetID) { $0.disclosure.privacyCleanupPending = true }; message = error.localizedDescription }
    }
    func setProjection(_ enabled: Bool) {
        guard !busy, var next = binding, next.projectionEnabled != enabled else { return }
        guard next.projectionEpoch < 9_007_199_254_740_991 else { message = "发布配置计数达到上限，原配置保留。"; return }
        next.projectionEnabled = enabled; next.projectionEpoch += 1
        do { try persistBinding(next); projectionCandidates = []; publicationCandidate = nil; message = "笔记派生块设置已更改；重新发布同步代后才生效。" } catch { message = "设置未能保存，原授权不变。" }
    }
    func prepareProjection() async {
        guard !store.data.disclosure.selectionPending else { message = "先发布新的披露选择，再更新受管块。"; return }
        guard !busy, let binding, binding.projectionEnabled, let engine = runtime, let commit = verifiedCommit, let head = commit["commitID"] as? String, !projectionKeys.isEmpty else { message = "请先开启派生块并发布新的完整同步代。"; return }
        busy = true; defer { busy = false }
        projectionCandidates = []; projectionIssues = []
        do {
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            var notes = try await Task.detached { try VaultFiles.noteSnapshot(root: root) }.value
            for day in projectionKeys.keys.sorted() {
                do {
                    var input: [String:Any] = ["head":head,"projectionKey":projectionKeys[day]!,"writerID":store.data.disclosure.writerID.wire,"notes":notes]
                    if let map = binding.mappings[day] { input["mapping"] = ["path":map.path,"state":map.state] }
                    let candidate = try engine.call("project",input)
                    guard let path = candidate["path"] as? String, let bytes = candidate["bytes"] as? String else { throw LifeError.invalidValue }
                    projectionCandidates.append(candidate); notes[path] = bytes
                } catch { projectionIssues.append(day + "：" + error.localizedDescription) }
            }
            message = "已核对\(projectionCandidates.count)个受管块；另有\(projectionIssues.count)个冲突待处理。确认后更新所有已核对块，块外文字保留；有冲突的内容不会被冒称已撤回。"
        } catch { message = error.localizedDescription }
    }
    var projectionReady: Bool { !projectionCandidates.isEmpty }
    func writeProjection() async {
        guard !busy, var binding, !projectionCandidates.isEmpty else { return }
        busy = true; defer { busy = false }
        var written = 0
        do {
            let root = try root(), access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
            let commits = Set(lastDisk.commits)
            for candidate in projectionCandidates {
                guard let path = candidate["path"] as? String, let base64 = candidate["bytes"] as? String, let bytes = Data(base64Encoded:base64), let originalHash = candidate["originalHash"] as? String, let day = candidate["dayKey"] as? String else { throw LifeError.invalidValue }
                try await Task.detached { try VaultFiles.writeNote(root:root,relative:path,bytes:bytes,originalHash:originalHash,ledgerCommits:commits) }.value
                binding.mappings[day] = ProjectionMapping(path:path,lastCommitID:verifiedCommit?["commitID"] as? String); try persistBinding(binding); written += 1
            }
            projectionCandidates = []
            message = projectionIssues.isEmpty ? "所有已登记受管块已更新到当前授权视图，块外文字保留。外部、手改或离线副本不作抹去承诺。":"已更新\(written)个安全受管块；仍有\(projectionIssues.count)个冲突未清理，请逐项处理。"
        } catch { projectionCandidates = Array(projectionCandidates.dropFirst(written)); message = "已更新\(written)个块，其余未完成：" + error.localizedDescription }
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
            let url = try bindingURL(); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            binding = nil; runtime = nil; verifiedCommit = nil; projectionCandidates = []; projectionKeys = [:]; projectionIssues = []; incoming = []; publicationCandidate = nil
            message = "已停止后续发布并忘记目录授权。本机事实保留；Vault中已经披露的文件和插件缓存仍存在，这不是撤回历史披露。"
        } catch { message = "未能清除目录授权，本机已停止后续发布。" }
    }
}
