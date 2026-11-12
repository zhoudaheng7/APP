import SwiftUI

struct TaskDetailView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var taskID: UUID
    @State private var title = ""
    @State private var note = ""
    @State private var goalID: UUID?
    @State private var hasDue = false
    @State private var due = Date()
    @State private var priority = 0
    @State private var delete = false
    @State private var plan = false
    @State private var initialized = false
    var task: LifeTask? { store.data.tasks.first { $0.id == taskID } }
    var body: some View {
        if let task {
            Form {
                Section { TextField("任务", text: $title, axis: .vertical); TextField("想法与说明", text: $note, axis: .vertical).lineLimit(3...8) }
                Section { Picker("关联方向", selection: $goalID) { Text("独立任务").tag(UUID?.none); ForEach(store.data.goals) { Text($0.title).tag(Optional($0.id)) } }; Picker("优先级", selection: $priority) { Text("普通").tag(0); Text("值得关注").tag(1); Text("重要").tag(2); Text("优先").tag(3) }; Toggle("设置截止日期", isOn: $hasDue); if hasDue { DatePicker("截止", selection: $due) } }
                Section("接下来") {
                    if task.isOpen {
                        Button("开始实际计时", systemImage: "play.circle") { _ = store.startSession(title: task.title, taskID: task.id) }.disabled(store.runningSession != nil)
                        Button("安排私人计划", systemImage: "calendar.badge.plus") { plan = true }
                        Button("确认任务已完成", systemImage: "checkmark.circle") { store.completeTask(task) }
                    } else { Label(task.completedAt == nil ? "已归档或取消" : "已完成", systemImage: "checkmark.circle") }
                }
                Section("实际记录") {
                    ForEach(store.data.sessions.filter { $0.taskID == task.id }) { session in NavigationLink { SessionEditor(sessionID: session.id) } label: { VStack(alignment: .leading) { Text(session.title); Text(session.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } } }
                }
                Section {
                    Button(task.archivedAt == nil ? "归档任务" : "恢复到任务列表") {
                        _ = store.commit(kind: "task.archive", id: task.id) { state in if let i = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[i].archivedAt = task.archivedAt == nil ? Date() : nil; state.tasks[i].revision += 1 } }
                    }
                    Button("删除任务", role: .destructive) { delete = true }
                }
            }.navigationTitle("任务详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存") { if store.editTask(task, title: title, note: note, goalID: goalID, due: hasDue ? due : nil, priority: priority) { EditorDrafts.remove("task:" + taskID.uuidString) } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                .onAppear { if !initialized { initialized = true; title = task.title; note = task.note; goalID = task.goalID; hasDue = task.dueAt != nil; due = task.dueAt ?? Date(); priority = task.priority ?? 0; if let draft = EditorDrafts.load("task:" + taskID.uuidString) { title = draft["title"] ?? title; note = draft["note"] ?? note } } }
                .onDisappear { if let current = self.task, title != current.title || note != current.note { EditorDrafts.save("task:" + taskID.uuidString, fields: ["title": title, "note": note]) } }
                .confirmationDialog("删除这个任务？", isPresented: $delete, titleVisibility: .visible) { Button("删除任务", role: .destructive) { store.deleteTask(task); dismiss() }; Button("取消", role: .cancel) {} } message: { Text("相关计划和实际记录会保留，并解除与此任务的关联。") }
                .sheet(isPresented: $plan) { ComposerView(kind: .plan, prefilledTitle: task.title, initialTaskID: task.id) }
        } else { ContentUnavailableView("任务已删除", systemImage: "checklist") }
    }
}

struct TaskLibraryView: View {
    @Environment(LifeStore.self) private var store
    @State private var search = ""
    @State private var filter = 0
    var tasks: [LifeTask] { store.data.tasks.filter { task in
        let state = filter == 0 ? task.isOpen : filter == 1 ? task.completedAt != nil && task.archivedAt == nil : task.archivedAt != nil
        return state && (search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.note.localizedCaseInsensitiveContains(search))
    } }
    var body: some View {
        List { Picker("任务范围", selection: $filter) { Text("进行中").tag(0); Text("已完成").tag(1); Text("归档").tag(2) }.pickerStyle(.segmented)
            ForEach(tasks) { task in NavigationLink { TaskDetailView(taskID: task.id) } label: { VStack(alignment: .leading) { Text(task.title); if let due = task.dueAt { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } } }
        }.navigationTitle("全部任务").searchable(text: $search, prompt: "搜索任务和说明")
    }
}

struct PlanEditor: View {
    @Environment(LifeStore.self) private var store
    let planID: UUID
    @State private var title = ""
    @State private var note = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var taskID: UUID?
    @State private var reminder = -1
    @State private var repeatDays = 7
    @State private var repeatCount = 3
    @State private var repeatPreview = false
    @State private var initialized = false
    @State private var calendarEditor = false
    var plan: LifePlan? { store.data.plans.first { $0.id == planID } }
    var conflicts: [LifePlan] { store.data.plans.filter { $0.id != planID && !$0.cancelled && $0.deletedAt == nil && $0.start < end && $0.end > start } }
    var calendarLink: CalendarLink? { store.data.calendarLinks.first { $0.planID == planID || $0.sourcePlanID == planID } }
    var hasEdits: Bool { guard let plan else { return false }; return title != plan.title || start != plan.start || end != plan.end || note != (plan.note ?? "") || taskID != plan.taskID }
    var body: some View {
        if let plan {
            Form {
                Section { TextField("安排", text: $title, axis: .vertical); DatePicker("开始", selection: $start); DatePicker("结束", selection: $end, in: start...); TextField("说明", text: $note, axis: .vertical).lineLimit(3...6); Picker("关联任务", selection: $taskID) { Text("独立安排").tag(UUID?.none); ForEach(store.data.tasks) { Text($0.title).tag(Optional($0.id)) } } }
                if !conflicts.isEmpty { Section("有时间重叠，请核对") { ForEach(conflicts) { Text($0.title + " · " + $0.start.formatted(date: .omitted, time: .shortened)) }; Text("允许保留重叠安排；实际投入统计不会重复累计同一时段。") .font(.caption).foregroundStyle(.secondary) } }
                Section("本地提醒") { Picker("提前提醒", selection: $reminder) { Text("不提醒").tag(-1); Text("准时").tag(0); Text("提前5分钟").tag(5); Text("提前15分钟").tag(15); Text("提前1小时").tag(60) }; Text("保存提醒设置后，在设置页主动启用通知。私人计划不自动创建系统日历事件。") .font(.caption).foregroundStyle(.secondary) }
                Section("重复安排") { Picker("间隔", selection: $repeatDays) { Text("每天").tag(1); Text("每周").tag(7); Text("每两周").tag(14) }; Stepper("新增 \(repeatCount) 次", value: $repeatCount, in: 1...30); Button("预览并创建后续私人计划") { repeatPreview = true }.disabled(hasEdits); if hasEdits { Text("先保存当前修改，再预览重复或创建系统事件。") .font(.caption).foregroundStyle(.secondary) } }
                Section("系统日历") {
                    if let calendarLink { NavigationLink("查看保存回执与核对系统事件") { CalendarLinkManager(link: calendarLink) } }
                    else { Button("在苹果日历编辑器中创建", systemImage: "calendar.badge.plus") { calendarEditor = true }.disabled(hasEdits) }
                    Text("本页保存只更新本机记录。只有你在系统编辑器中保存后才修改苹果日历；取消不写入。已有保存回执时先核对原事件，避免重复创建。") .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button(plan.cancelled ? "恢复这个安排" : "取消这个安排", role: plan.cancelled ? nil : .destructive) { _ = store.commit(kind: "plan.cancel", id: plan.id) { state in if let i = state.plans.firstIndex(where: { $0.id == plan.id }) { state.plans[i].cancelled.toggle(); state.plans[i].revision += 1 } } } }
            }.navigationTitle(plan.isCommitment ? "日历承诺" : "私人计划").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存") { if store.editPlan(plan, title: title, start: start, end: end, taskID: taskID, note: note, reminder: reminder < 0 ? nil : reminder) { Task { await LifeNotifications.shared.reschedule(store.data.plans) } } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start) }
                .onAppear { if !initialized { initialized = true; title = plan.title; note = plan.note ?? ""; start = plan.start; end = plan.end; taskID = plan.taskID; reminder = plan.reminderMinutes ?? -1 } }
                .sheet(isPresented: $repeatPreview) { NavigationStack { List { Section("将创建以下私人计划") { ForEach(1...repeatCount, id: \.self) { i in Text(Calendar.current.date(byAdding: .day, value: repeatDays * i, to: start)!.formatted(date: .abbreviated, time: .shortened)) } }; Button("确认创建 \(repeatCount) 次") { if store.repeatPlan(plan, everyDays: repeatDays, count: repeatCount) { repeatPreview = false } } }.navigationTitle("重复安排预览").toolbar { Button("关闭") { repeatPreview = false } } } }
                .sheet(isPresented: $calendarEditor) { CalendarEventEditor(plan: plan) }
        }
    }
}

struct SessionEditor: View {
    @Environment(LifeStore.self) private var store
    @State private var title = ""
    @State private var note = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var confirmed = false
    @State private var delete = false
    @State private var initialized = false
    let sessionID: UUID
    var session: LifeSession? { store.data.sessions.first { $0.id == sessionID } }
    var body: some View {
        if let session {
            Form {
                Section { TextField("实际活动", text: $title); DatePicker("开始", selection: $start); DatePicker("结束", selection: $end, in: start...); TextField("说明", text: $note, axis: .vertical).lineLimit(3...8); Toggle("我已核对这段投入", isOn: $confirmed) }
                Section { Text("修改只影响这段实际记录，不修改任务完成、原计划或成果读数。原记录版本会保留。") .foregroundStyle(.secondary); if session.end == nil { Button("结束当前计时") { store.stopSession() } }; Button("删除这段实际记录", role: .destructive) { delete = true }.disabled(session.end == nil) }
            }.navigationTitle("实际记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存修正") { _ = store.editSession(session, title: title, start: start, end: end, note: note, confirmed: confirmed) }.disabled(session.end == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start || end > Date().addingTimeInterval(60)) }
                .onAppear { if !initialized { initialized = true; title = session.title; note = session.note ?? ""; start = session.start; end = session.end ?? Date(); confirmed = session.confirmed } }
                .confirmationDialog("删除这段实际记录？", isPresented: $delete, titleVisibility: .visible) { Button("删除", role: .destructive) { store.deleteSession(session) }; Button("取消", role: .cancel) {} }
        } else { ContentUnavailableView("实际记录已删除", systemImage: "clock") }
    }
}

struct ReviewDetailView: View {
    @Environment(LifeStore.self) private var store
    let reviewID: UUID
    @State private var text = ""
    @State private var mood: Int?
    @State private var people = ""
    @State private var initialized = false
    var review: LifeReview? { store.data.reviews.first { $0.id == reviewID } }
    var body: some View {
        if let review {
            Form {
                Section(review.day) { TextField("留给这一天的话", text: $text, axis: .vertical).lineLimit(8...20); Picker("感受", selection: $mood) { Text("不记录").tag(Int?.none); ForEach(1...5, id: \.self) { Text("\($0) / 5").tag(Optional($0)) } }; TextField("人物别名，用逗号分开（可留空）", text: $people) }
                Section { Text("只记录你手写的别名，不读取通讯录，不合并同名人物。") .font(.caption).foregroundStyle(.secondary); LabeledContent("当前版本", value: String(review.revision ?? 1)); Text("修订保留上一版本，不另造同一天的第二份正式复盘。") .font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("这一天").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存修订") { if store.reviseReview(review, text: text, mood: mood, people: people.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespaces) }) { EditorDrafts.remove("review:" + reviewID.uuidString) } } }
                .onAppear { if !initialized { initialized = true; text = review.reflection; mood = review.mood; people = (review.people ?? []).joined(separator: "，"); if let draft = EditorDrafts.load("review:" + reviewID.uuidString) { text = draft["text"] ?? text; people = draft["people"] ?? people; mood = draft["mood"].flatMap(Int.init) } } }
                .onDisappear { if text != self.review?.reflection || mood != self.review?.mood { EditorDrafts.save("review:" + reviewID.uuidString, fields: ["text": text, "people": people, "mood": mood.map(String.init) ?? ""]) } }
        }
    }
}
