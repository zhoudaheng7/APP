import SwiftUI

extension LifeStore {
    func addClosedSession(_ value: LifeSession) -> Bool {
        guard let end = value.end, end > value.start, end <= Date().addingTimeInterval(60) else { error = "请填写实际发生过的开始与结束时间。"; return false }
        var value = value; value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return commit(kind: "actual.manual", id: value.id) { $0.sessions.append(value) }
    }
    func reopenTask(_ task: LifeTask) -> Bool {
        commit(kind: "task.reopen", id: task.id) { state in
            guard let i = state.tasks.firstIndex(where: { $0.id == task.id }), state.tasks[i].revision == task.revision else { throw LifeError.invalidReference }
            try state.audit(state.tasks[i], id: task.id, kind: "task", revision: task.revision)
            state.tasks[i].completedAt = nil; state.tasks[i].revision += 1
        }
    }
    func splitSession(_ original: LifeSession, at date: Date) -> Bool {
        guard let end = original.end, date > original.start, date < end else { error = "拆分时刻须在原记录之内。"; return false }
        return commit(kind: "actual.split", id: original.id) { state in
            guard let i = state.sessions.firstIndex(where: { $0.id == original.id }), state.sessions[i] == original else { throw LifeError.message("原记录已变化，请重新核对。") }
            var first = original, second = original; first.id = UUID(); second.id = UUID(); first.revision = 1; second.revision = 1
            first.end = date; second.start = date
            state.sessions.remove(at: i); state.tombstone(original.id, kind: "actual"); state.sessions.append(contentsOf: [first,second])
        }
    }
    func mergeSessions(_ first: LifeSession, _ second: LifeSession) -> Bool {
        guard first.id != second.id, let a = first.end, let b = second.end,
              first.taskID == second.taskID, first.placeID == second.placeID, first.tripID == second.tripID, first.timeZone == second.timeZone,
              first.start <= b, second.start <= a else { error = "只能合并关联相同且相接或重叠的记录，不能把空档补成投入。"; return false }
        return commit(kind: "actual.merge", id: first.id) { state in
            guard state.sessions.contains(first), state.sessions.contains(second) else { throw LifeError.message("原记录已变化，请重新核对。") }
            var merged = first; merged.id = UUID(); merged.revision = 1; merged.start = min(first.start,second.start); merged.end = max(a,b)
            merged.confirmed = first.confirmed && second.confirmed
            if first.title != second.title { merged.title = first.title + " / " + second.title }
            merged.note = [first.note,second.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            state.sessions.removeAll { $0.id == first.id || $0.id == second.id }; state.tombstone(first.id, kind: "actual"); state.tombstone(second.id, kind: "actual"); state.sessions.append(merged)
        }
    }
    func deletePlan(_ original: LifePlan) -> Bool {
        commit(kind: "plan.delete", id: original.id) { state in
            guard state.plans.contains(original) else { throw LifeError.message("安排已更新，请重新核对。") }
            state.tombstone(original.id, kind: original.isCommitment ? "commitment":"plan"); state.applyDeletionHistory()
        }
    }
}

struct ManualActualView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LifeSession(title: "", start: Date().addingTimeInterval(-3600), end: Date())
    @State private var initialized = false
    @State private var saved = false
    var body: some View {
        NavigationStack { Form {
            Section {
                TextField("实际做了什么？", text: $draft.title)
                DatePicker("开始", selection: $draft.start, in: ...Date())
                DatePicker("结束", selection: Binding(get: { draft.end ?? Date() }, set: { draft.end = $0 }), in: draft.start...max(draft.start,Date()))
                Picker("关联任务", selection: $draft.taskID) { Text("独立活动").tag(UUID?.none); ForEach(store.data.tasks) { Text($0.title).tag(Optional($0.id)) } }
                TextField("说明或补录依据", text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0 }), axis: .vertical).lineLimit(3...8)
                Toggle("我已核对这段实际投入", isOn: $draft.confirmed)
            }
            Section { Text("只补录你确认发生过的活动，不由路线、照片或日历推断。保存不会完成任务，也不产生任何成果读数。时间按本页显示的时区保存：" + draft.timeZone).font(.caption).foregroundStyle(.secondary) }
        }.environment(\.timeZone, TimeZone(identifier:draft.timeZone) ?? .current)
            .navigationTitle("补录实际投入").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.addClosedSession(draft) { saved = true; EditorDrafts.remove("new-actual"); dismiss() } }.disabled(draft.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.end.map { $0 <= draft.start } != false) }
            }.onAppear { if !initialized { initialized = true; draft = EditorDrafts.value("new-actual", as: LifeSession.self) ?? draft } }
            .retainingDraft("new-actual", fields: EditorDrafts.fields(draft), active: initialized && !saved)
        }
    }
}

struct ActualAdjustmentView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: LifeSession
    @State private var splitAt = Date()
    @State private var otherID: UUID?
    @State private var initialized = false
    var candidates: [LifeSession] { store.data.sessions.filter { $0.id != original.id && $0.end != nil && $0.taskID == original.taskID && $0.timeZone == original.timeZone } }
    var body: some View {
        Form {
            Section("拆成两段实际记录") {
                DatePicker("拆分时刻", selection: $splitAt, in: original.start...(original.end ?? original.start))
                Text("拆分保留原有说明和关联，合计时长不变。原记录保留删除标记，新两段使用新的身份。") .font(.caption).foregroundStyle(.secondary)
                Button("确认拆分为两段") { if store.splitSession(original, at: splitAt) { dismiss() } }.disabled(splitAt <= original.start || splitAt >= (original.end ?? original.start))
            }
            Section("合并相接或重叠的记录") {
                Picker("另一段", selection: $otherID) { Text("请选择").tag(UUID?.none); ForEach(candidates) { Text($0.title + " · " + $0.start.formatted()).tag(Optional($0.id)) } }
                Text("要求任务、地点、行程和时区相同；空档不会被补为投入。两段都已核对，合并记录才保持已核对。") .font(.caption).foregroundStyle(.secondary)
                Button("确认合并这两段") { if let other = candidates.first(where:{ $0.id == otherID }), store.mergeSessions(original,other) { dismiss() } }.disabled(otherID == nil)
            }
        }.navigationTitle("整理实际记录").onAppear { if !initialized { initialized = true; splitAt = original.start.addingTimeInterval((original.end ?? original.start).timeIntervalSince(original.start)/2) } }
    }
}
