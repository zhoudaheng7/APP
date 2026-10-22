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
    @State private var title = ""
    @State private var note = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var goalID: UUID?
    @State private var taskID: UUID?
    @State private var isCommitment = false
    @State private var value = ""
    @State private var unit = "次"
    @State private var mood = 3
    @State private var discard = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .task:
                    Section { titleField("例如：读完这一章"); TextField("补充一点想法", text: $note, axis: .vertical).lineLimit(3...5) }
                    if !store.data.goals.isEmpty {
                        Section { Picker("关联方向", selection: $goalID) { Text("暂不关联").tag(UUID?.none); ForEach(store.data.goals.filter { !$0.archived }) { Text($0.title).tag(Optional($0.id)) } } }
                    }
                case .session:
                    Section { titleField("例如：阅读、学习、写作"); taskPicker }
                    Section { Text("这是一段实际投入。结束后可单独核对，任务是否完成由你另行确认。") .foregroundStyle(.secondary) }
                case .plan:
                    Section { titleField("安排什么？"); taskPicker; Toggle("这是已有的日历承诺", isOn: $isCommitment) }
                    Section { DatePicker("开始", selection: $start); DatePicker("结束", selection: $end, in: start...) }
                    Section { Text(isCommitment ? "仅记录已有承诺，不会在系统日历创建事件。" : "私人计划只保存在 LifeOS，不会写入系统日历。") .foregroundStyle(.secondary) }
                case .goal:
                    Section { titleField("例如：保持阅读的习惯"); TextField("为什么这对你重要？", text: $note, axis: .vertical).lineLimit(3...5) }
                    Section("想看到的成果") { TextField("目标数值，例如 12", text: $value).keyboardType(.decimalPad); TextField("单位，例如 本、次、公里", text: $unit); DatePicker("希望完成于", selection: $end, displayedComponents: .date) }
                case .measurement(let goal):
                    Section { Text(goal.title).font(.headline); TextField("当前累计成果（\(goal.unit)）", text: $value).keyboardType(.decimalPad); TextField("这次读数的依据或说明", text: $note, axis: .vertical).lineLimit(3...5) }
                    Section { Text("读数由你明确记录，不从计时、任务或位置自动推算。") .foregroundStyle(.secondary) }
                case .review(let day):
                    Section { Text(day.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary); Picker("今天的感受", selection: $mood) { Text("低落").tag(1); Text("有点累").tag(2); Text("平静").tag(3); Text("不错").tag(4); Text("很充实").tag(5) } }
                    Section("哪些值得记住？") { TextField("今天发生了什么？有哪些小小的进步，或想留给明天的话？", text: $note, axis: .vertical).lineLimit(8...14).accessibilityIdentifier("reviewText") }
                }
            }
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", systemImage: "xmark") { if title.isEmpty && note.isEmpty && value.isEmpty { dismiss() } else { discard = true } } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", systemImage: "checkmark", action: save).disabled(!canSave).accessibilityIdentifier("saveComposer") }
            }
            .confirmationDialog("放弃未保存的内容？", isPresented: $discard, titleVisibility: .visible) { Button("放弃", role: .destructive) { dismiss() }; Button("继续编辑", role: .cancel) {} }
            .onAppear {
                let cal = Calendar.current
                start = cal.date(bySettingHour: cal.component(.hour, from: Date()), minute: 0, second: 0, of: initialDate) ?? initialDate
                end = start.addingTimeInterval(3600)
                if case .goal = kind { end = cal.date(byAdding: .month, value: 3, to: Date()) ?? end }
            }
        }.presentationDetents([.large]).interactiveDismissDisabled(!title.isEmpty || !note.isEmpty || !value.isEmpty)
    }
    func titleField(_ placeholder: String) -> some View { TextField(placeholder, text: $title, axis: .vertical).font(.title3).lineLimit(1...3).focused($titleFocused).accessibilityIdentifier("composerTitle") }
    var taskPicker: some View { Picker("关联任务", selection: $taskID) { Text("独立记录").tag(UUID?.none); ForEach(store.data.tasks.filter { $0.completedAt == nil }) { Text($0.title).tag(Optional($0.id)) } } }
    var number: Double? { Double(value.replacingOccurrences(of: ",", with: ".")) }
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
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool
        switch kind {
        case .task: success = store.addTask(title: clean, note: note, goalID: goalID)
        case .session: success = store.startSession(title: clean, taskID: taskID)
        case .plan: success = store.addPlan(LifePlan(title: clean, taskID: taskID, start: start, end: end, isCommitment: isCommitment))
        case .goal: success = store.addGoal(LifeGoal(title: clean, intention: note, target: number!, unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), due: end))
        case .measurement(let goal): success = store.addMeasurement(LifeMeasurement(goalID: goal.id, value: number!, note: note))
        case .review(let day): success = store.addReview(LifeReview(day: LifeSnapshot.dayKey(day), reflection: note.trimmingCharacters(in: .whitespacesAndNewlines), mood: mood))
        }
        if success { dismiss() }
    }
}
