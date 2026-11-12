import SwiftUI

enum RevisionContent {
    static func decode<T: Decodable & Identifiable>(_ type: T.Type,_ data: Data,expectedID: UUID? = nil) throws -> T where T.ID == UUID {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; let value = try decoder.decode(type,from:data)
        guard expectedID == nil || value.id == expectedID else { throw LifeError.invalidValue }; return value
    }
    static func text(_ value: LifeAmendment) throws -> String {
        switch value.kind {
        case "task": let r = try decode(LifeTask.self,value.previous); return r.title + "\n" + r.note + "\n" + (r.completedAt == nil ? "未完成" : "已完成")
        case "plan","commitment": let r = try decode(LifePlan.self,value.previous); return r.title + "\n" + recordTimeText(r.start,zone:r.timeZone) + " 至 " + recordTimeText(r.end,zone:r.timeZone) + "\n" + (r.note ?? "")
        case "actual": let r = try decode(LifeSession.self,value.previous); return r.title + "\n" + recordTimeText(r.start,zone:r.timeZone) + " 至 " + (r.end.map { recordTimeText($0,zone:r.timeZone) } ?? "未结束") + "\n" + (r.note ?? "") + (r.confirmed ? "\n已核对" : "\n未核对")
        case "review": let r = try decode(LifeReview.self,value.previous); return r.day + "\n" + r.reflection + "\n" + (r.people ?? []).joined(separator:"、")
        case "period-review": let r = try decode(PeriodReview.self,value.previous); return r.title + "\n" + r.reflection + "\n下一步：" + r.nextStep
        case "goal": let r = try decode(LifeGoal.self,value.previous); return r.title + "\n" + r.intention + "\n" + (r.assessment ?? "")
        case "kr": let r = try decode(LifeKeyResult.self,value.previous); return r.title + "\n基线\(r.baseline) → 目标\(r.target) \(r.unit) · 权重\(r.weight)"
        case "memory": let r = try decode(LifePlace.self,value.previous); return r.title + "\n" + r.note + "\n" + recordTimeText(r.occurredAt,zone:r.timeZone)
        case "trip": let r = try decode(LifeTrip.self,value.previous); return r.title + "\n" + r.note
        case "known-place": let r = try decode(KnownPlace.self,value.previous); return r.title + "\n" + r.city + " · " + r.country
        case "photo": let r = try decode(LifePhoto.self,value.previous); return r.caption + "\n" + r.capturedAt.formatted()
        default: return "这份历史只供保留，当前版本不提供恢复。"
        }
    }
}

extension LifeStore {
    func restoreRevision(_ prior: LifeAmendment,expectedFingerprint: String) -> Bool {
        commit(kind:prior.kind + ".undo",id:prior.entityID) { state in
            guard try NewStoryView.fingerprint(state) == expectedFingerprint,state.amendments.contains(where:{ $0.id == prior.id }) else { throw LifeError.message("当前记录已变化，请重新核对修订历史。") }
            let id = prior.entityID
            switch prior.kind {
            case "task":
                guard let i = state.tasks.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(LifeTask.self,prior.previous,expectedID:id); try state.audit(state.tasks[i],id:id,kind:"task",revision:state.tasks[i].revision); r.revision = state.tasks[i].revision + 1; state.tasks[i] = r
            case "plan","commitment":
                guard let i = state.plans.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(LifePlan.self,prior.previous,expectedID:id); try state.audit(state.plans[i],id:id,kind:prior.kind,revision:state.plans[i].revision); r.revision = state.plans[i].revision + 1; state.plans[i] = r
            case "actual":
                guard let i = state.sessions.firstIndex(where:{ $0.id == id }),state.sessions[i].end != nil else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(LifeSession.self,prior.previous,expectedID:id); guard r.end != nil else { throw LifeError.message("不能通过恢复历史重新开启计时，请手动核对。") }; try state.audit(state.sessions[i],id:id,kind:"actual",revision:state.sessions[i].revision); r.revision = state.sessions[i].revision + 1; state.sessions[i] = r
            case "review":
                guard let i = state.reviews.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(LifeReview.self,prior.previous,expectedID:id); try state.audit(state.reviews[i],id:id,kind:"review",revision:state.reviews[i].revision ?? 1); r.revision = (state.reviews[i].revision ?? 1) + 1; state.reviews[i] = r
            case "period-review":
                guard let i = state.periodReviews.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(PeriodReview.self,prior.previous,expectedID:id); try state.audit(state.periodReviews[i],id:id,kind:"period-review",revision:state.periodReviews[i].revision); r.revision = state.periodReviews[i].revision + 1; state.periodReviews[i] = r
            case "goal":
                guard let i = state.goals.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(LifeGoal.self,prior.previous,expectedID:id); try state.audit(state.goals[i],id:id,kind:"goal",revision:state.goals[i].revision ?? 1); r.revision = (state.goals[i].revision ?? 1) + 1; state.goals[i] = r
            case "kr":
                guard let i = state.keyResults.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(LifeKeyResult.self,prior.previous,expectedID:id); try state.audit(state.keyResults[i],id:id,kind:"kr",revision:state.keyResults[i].revision); r.revision = state.keyResults[i].revision + 1; state.keyResults[i] = r
            case "memory":
                guard let i = state.places.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                let r = try RevisionContent.decode(LifePlace.self,prior.previous,expectedID:id); try state.audit(state.places[i],id:id,kind:"memory",revision:prior.priorRevision + 1); state.places[i] = r
            case "trip":
                guard let i = state.trips.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(LifeTrip.self,prior.previous,expectedID:id); try state.audit(state.trips[i],id:id,kind:"trip",revision:state.trips[i].revision); r.revision = state.trips[i].revision + 1; state.trips[i] = r
            case "known-place":
                guard let i = state.knownPlaces.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                var r = try RevisionContent.decode(KnownPlace.self,prior.previous,expectedID:id); try state.audit(state.knownPlaces[i],id:id,kind:"known-place",revision:state.knownPlaces[i].revision); r.revision = state.knownPlaces[i].revision + 1; state.knownPlaces[i] = r
            case "photo":
                guard let i = state.photos.firstIndex(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                let r = try RevisionContent.decode(LifePhoto.self,prior.previous,expectedID:id); guard r.sha256 == state.photos[i].sha256 else { throw LifeError.invalidReference }; try state.audit(state.photos[i],id:id,kind:"photo",revision:prior.priorRevision + 1); state.photos[i] = r
            default: throw LifeError.message("此类历史暂不支持恢复。")
            }
        }
    }
}

struct RecordHistoryView: View {
    @Environment(LifeStore.self) private var store
    let entityID: UUID
    let kind: String
    @State private var fingerprint = ""
    @State private var restore: LifeAmendment?
    var history: [LifeAmendment] { store.data.amendments.filter { $0.entityID == entityID && $0.kind == kind }.sorted { $0.at > $1.at } }
    var body: some View {
        List {
            Section { Text("历史仅包含已经保存的旧版本。恢复会产生新修订，且只改这条记录；原计划、系统日历与其他记录不会被自动改写。已删除的记录不能从这里复活。") .font(.caption).foregroundStyle(.secondary)
                Button("重新核对当前版本") { refresh() }
            }
            ForEach(history) { entry in Section("修订\(entry.priorRevision) · " + entry.at.formatted()) { Text((try? RevisionContent.text(entry)) ?? "这份历史无法读取，原件保留。").textSelection(.enabled); Button("恢复此版本的内容") { restore = entry }.disabled(fingerprint.isEmpty) } }
            if history.isEmpty { ContentUnavailableView("还没有保存修订",systemImage:"clock.arrow.circlepath") }
        }.navigationTitle("修订历史").onAppear { refresh() }
            .confirmationDialog("恢复选中的历史内容？",isPresented:Binding(get:{ restore != nil },set:{ if !$0 { restore = nil } }),titleVisibility:.visible) { Button("恢复并保存为新修订") { if let restore,store.restoreRevision(restore,expectedFingerprint:fingerprint) { refresh() }; restore = nil }; Button("取消",role:.cancel) {} } message: { Text("仅在你核对后记录没有变化时保存，关联或数据校验不通过则保留当前记录。") }
    }
    func refresh() { fingerprint = (try? NewStoryView.fingerprint(store.data)) ?? "" }
}
