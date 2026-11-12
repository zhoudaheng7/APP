import SwiftUI

enum ComposerKind: Identifiable {
    case task, plan, session, goal, measurement(LifeGoal), review(Date)
    var id: String {
        switch self { case .task: return "task"; case .plan: return "plan"; case .session: return "session"; case .goal: return "goal"; case .measurement(let g): return g.id.uuidString; case .review(let d): return "review-" + LifeSnapshot.dayKey(d) }
    }
    var title: String {
        switch self { case .task: return "一件想完成的事"; case .plan: return "为重要的事留时间"; case .session: return "这段时间，投入什么？"; case .goal: return "给生活一个方向"; case .measurement: return "记录成果读数"; case .review: return "给这一天写几句话" }
    }
}

struct ComposerView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: ComposerKind
    var initialDate = Date()
    var initialGoalID: UUID?
    var prefilledTitle = ""
    var initialTaskID: UUID?
    var initialPlaceID: UUID?
    @State private var title = ""
    @State private var note = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var goalID: UUID?
    @State private var taskID: UUID?
    @State private var isCommitment = false
    @State private var value = ""
    @State private var unit = "次"
    @State private var mood: Int?
    @State private var saved = false
    @State private var placeID: UUID?
    @State private var initialized = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .task:
                    Section { titleField("例如：读完这一章"); TextField("补充一点想法", text: $note, axis: .vertical).lineLimit(3...5) }
                    placePicker
                    if !store.data.goals.isEmpty {
                        Section { Picker("关联方向", selection: $goalID) { Text("暂不关联").tag(UUID?.none); ForEach(store.data.goals.filter { !$0.archived }) { Text($0.title).tag(Optional($0.id)) } } }
                    }
                case .session:
                    Section { titleField("例如：阅读、学习、写作"); taskPicker }
                    Section { Text("这是一段实际投入。结束后可单独核对，任务是否完成由你另行确认。") .foregroundStyle(.secondary) }
                case .plan:
                    Section { titleField("安排什么？"); taskPicker; Toggle("这是已有的日历承诺", isOn: $isCommitment) }
                    placePicker
                    Section { DatePicker("开始", selection: $start); DatePicker("结束", selection: $end, in: start...) }
                    Section { Text(isCommitment ? "仅记录已有承诺，不会在系统日历创建事件。" : "私人计划只保存在朝屿，不会写入系统日历。") .foregroundStyle(.secondary) }
                case .goal:
                    Section { titleField("例如：保持阅读的习惯"); TextField("为什么这对你重要？", text: $note, axis: .vertical).lineLimit(3...5) }
                    Section("想看到的成果") { TextField("目标数值，例如 12", text: $value).keyboardType(.decimalPad); TextField("单位，例如 本、次、公里", text: $unit); DatePicker("希望完成于", selection: $end, displayedComponents: .date) }
                case .measurement(let goal):
                    Section { Text(goal.title).font(.headline); TextField("当前累计成果（\(goal.unit)）", text: $value).keyboardType(.decimalPad); TextField("这次读数的依据或说明", text: $note, axis: .vertical).lineLimit(3...5) }
                    Section { Text("读数由你明确记录，不从计时、任务或位置自动推算。") .foregroundStyle(.secondary) }
                case .review(let day):
                    Section { Text(day.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary); Picker("今天的感受", selection: $mood) { Text("不记录").tag(Int?.none); Text("低落").tag(Optional(1)); Text("有点累").tag(Optional(2)); Text("平静").tag(Optional(3)); Text("不错").tag(Optional(4)); Text("很充实").tag(Optional(5)) } }
                    Section("哪些值得记住？") { TextField("今天发生了什么？有哪些小小的进步，或想留给明天的话？", text: $note, axis: .vertical).lineLimit(8...14).accessibilityIdentifier("reviewText") }
                }
            }
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", systemImage: "checkmark", action: save).disabled(!canSave).accessibilityIdentifier("saveComposer") }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                let cal = Calendar.current
                start = cal.date(bySettingHour: cal.component(.hour, from: Date()), minute: 0, second: 0, of: initialDate) ?? initialDate
                end = start.addingTimeInterval(3600)
                if case .goal = kind { end = cal.date(byAdding: .month, value: 3, to: Date()) ?? end }
                goalID = initialGoalID; taskID = initialTaskID; placeID = initialPlaceID; title = prefilledTitle
                if let draft = EditorDrafts.load(draftKey) ?? EditorDrafts.load(legacyDraftKey) {
                    title = draft["title"] ?? title; note = draft["note"] ?? ""; value = draft["value"] ?? ""; unit = draft["unit"] ?? "次"
                    goalID = draft["goalID"].flatMap(UUID.init(uuidString:)) ?? initialGoalID; taskID = draft["taskID"].flatMap(UUID.init(uuidString:)) ?? initialTaskID
                    if let value = draft["placeID"] { placeID = UUID(uuidString: value) }
                    if let number = draft["start"].flatMap(Double.init) { start = Date(timeIntervalSince1970: number) }
                    if let number = draft["end"].flatMap(Double.init) { end = Date(timeIntervalSince1970: number) }
                    mood = draft["mood"].flatMap(Int.init); isCommitment = draft["commitment"] == "true"
                }
                mergeReviewAppends()
            }
            .onReceive(NotificationCenter.default.publisher(for:EditorDrafts.reviewAppended)) { event in if event.object as? String == draftKey { mergeReviewAppends() } }
            .retainingDraft(draftKey, fields: fields(note:note), active: initialized && !saved && (!title.isEmpty || !note.isEmpty || !value.isEmpty))
        }.presentationDetents([.large])
    }
    func titleField(_ placeholder: String) -> some View { TextField(placeholder, text: $title, axis: .vertical).font(.title3).lineLimit(1...3).focused($titleFocused).accessibilityIdentifier("composerTitle") }
    var legacyDraftKey: String { kind.id + (initialGoalID.map { ":" + $0.uuidString } ?? "") + (initialTaskID.map { ":" + $0.uuidString } ?? "") + (initialPlaceID.map { ":" + $0.uuidString } ?? "") + (prefilledTitle.isEmpty ? "" : ":" + LifeStore.fingerprint(Data(prefilledTitle.utf8))) }
    var draftKey: String { "compose:" + legacyDraftKey }
    func fields(note: String) -> [String:String] { ["title":title,"note":note,"value":value,"unit":unit,"start":String(start.timeIntervalSince1970),"end":String(end.timeIntervalSince1970),"goalID":goalID?.uuidString ?? "","taskID":taskID?.uuidString ?? "","placeID":placeID?.uuidString ?? "","mood":mood.map(String.init) ?? "","commitment":String(isCommitment)] }
    func mergeReviewAppends() {
        guard initialized,case .review = kind else { return }
        do { note = try EditorDrafts.consumeReviewAppends(draftKey,baseText:note) { fields(note:$0) } } catch { store.error = "快捷指令追加尚未合并，原草稿保留。" }
    }
    var placePicker: some View { Section { Picker("关联地点", selection: $placeID) { Text("不关联地点").tag(UUID?.none); ForEach(store.data.knownPlaces) { Text($0.title).tag(Optional($0.id)) } }; Text("这是未来打算，不会被算作到过这里。") .font(.caption).foregroundStyle(.secondary) } }
    var taskPicker: some View { Picker("关联任务", selection: $taskID) { Text("独立记录").tag(UUID?.none); ForEach(store.data.tasks.filter(\.isOpen)) { Text($0.title).tag(Optional($0.id)) } } }
    var number: Double? { decimalValue(value) }
    var canSave: Bool {
        switch kind {
        case .review: return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .measurement: return number.map { $0.isFinite && $0 >= 0 } ?? false
        case .goal: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (number.map { $0.isFinite && $0 > 0 } ?? false) && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .plan: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end > start
        default: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    func save() {
        guard canSave else { return }
        if case .review = kind {
            do { if try !EditorDrafts.pendingReviewAppends(draftKey).isEmpty { mergeReviewAppends(); store.error = "已带入新的快捷指令文字，请核对后再保存。"; return } } catch { store.error = error.localizedDescription; return }
        }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool
        switch kind {
        case .task: success = store.addTask(title: clean, note: note, goalID: goalID, placeID: placeID)
        case .session: success = store.startSession(title: clean, taskID: taskID)
        case .plan:
            var plan = LifePlan(title: clean, taskID: taskID, start: start, end: end, isCommitment: isCommitment); plan.placeID = placeID
            success = store.addPlan(plan)
        case .goal: success = store.addGoal(LifeGoal(title: clean, intention: note, target: number!, unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), due: end))
        case .measurement(let goal): success = store.addMeasurement(LifeMeasurement(goalID: goal.id, value: number!, note: note))
        case .review(let day): success = store.addReview(LifeReview(day: LifeSnapshot.dayKey(day), reflection: note.trimmingCharacters(in: .whitespacesAndNewlines), mood: mood))
        }
        if success { saved = true; EditorDrafts.remove(draftKey); EditorDrafts.remove(legacyDraftKey); dismiss() }
    }
}
