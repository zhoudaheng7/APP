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
    @State private var original: LifeTask?
    var task: LifeTask? { store.data.tasks.first { $0.id == taskID } }
    var draftKey: String { "task:" + taskID.uuidString }
    var edited: LifeTask? { guard var value = original else { return nil }; value.title = title; value.note = note; value.goalID = goalID; value.dueAt = hasDue ? due : nil; value.priority = priority; return value }
    var draftFields: [String:String] { guard let original, let edited else { return [:] }; return EditorDrafts.fields(RecordDraft(original: original, edited: edited)) }
    var body: some View {
        if let task {
            Form {
                EditorConflictNotice(changed: original.map { $0 != task } ?? false, current: task.title + "\n" + task.note + "\n" + (task.dueAt?.formatted() ?? "无截止时间")) { original = task }
                Section { TextField("任务", text: $title, axis: .vertical); TextField("想法与说明", text: $note, axis: .vertical).lineLimit(3...8) }
                Section { Picker("关联方向", selection: $goalID) { Text("独立任务").tag(UUID?.none); ForEach(store.data.goals) { Text($0.title).tag(Optional($0.id)) } }; Picker("优先级", selection: $priority) { Text("普通").tag(0); Text("值得关注").tag(1); Text("重要").tag(2); Text("优先").tag(3) }; Toggle("设置截止日期", isOn: $hasDue); if hasDue { DatePicker("截止", selection: $due) } }
                Section("接下来") {
                    if task.isOpen {
                        Button("开始实际计时", systemImage: "play.circle") { _ = store.startSession(title: task.title, taskID: task.id) }.disabled(store.runningSession != nil)
                        Button("安排私人计划", systemImage: "calendar.badge.plus") { plan = true }
                        Button("确认任务已完成", systemImage: "checkmark.circle") { store.completeTask(task) }
                    } else { Label(task.completedAt == nil ? "已归档或取消" : "已完成", systemImage: "checkmark.circle"); if task.completedAt != nil { Button("撤销完成，恢复待办") { _ = store.reopenTask(task) } } }
                }
                Section("实际记录") {
                    ForEach(store.data.sessions.filter { $0.taskID == task.id }) { session in NavigationLink { SessionEditor(sessionID: session.id) } label: { VStack(alignment: .leading) { Text(session.title); Text(session.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } } }
                }
                Section {
                    Button(task.archivedAt == nil ? "归档任务" : "恢复到任务列表") {
                        _ = store.commit(kind: "task.archive", id: task.id) { state in if let i = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[i].archivedAt = task.archivedAt == nil ? Date() : nil; state.tasks[i].revision += 1 } }
                    }
                    NavigationLink("查看修订历史") { RecordHistoryView(entityID:task.id,kind:"task") }; Button("删除任务", role: .destructive) { delete = true }
                }
            }.navigationTitle("任务详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存") { if store.editTask(original ?? task, title: title, note: note, goalID: goalID, due: hasDue ? due : nil, priority: priority) { original = self.task; EditorDrafts.remove(draftKey) } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                .onAppear { if !initialized { initialized = true; let saved = EditorDrafts.value(draftKey, as: RecordDraft<LifeTask>.self); original = saved?.original ?? task; let value = saved?.edited ?? task; title = value.title; note = value.note; goalID = value.goalID; hasDue = value.dueAt != nil; due = value.dueAt ?? Date(); priority = value.priority ?? 0; if saved == nil, let draft = EditorDrafts.load(draftKey) { title = draft["title"] ?? title; note = draft["note"] ?? note } } }
                .retainingDraft(draftKey, fields: draftFields, active: initialized && self.task != nil && edited != self.task)
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
            ForEach(tasks) { task in NavigationLink { TaskDetailView(taskID: task.id) } label: { VStack(alignment: .leading) { Text(task.title); if let due = task.dueAt { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } } } }
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
    @State private var deletePlan = false
    @State private var original: LifePlan?
    @State private var timeZone: String? = TimeZone.current.identifier
    @State private var allDay = false
    var plan: LifePlan? { store.data.plans.first { $0.id == planID } }
    var draftKey: String { "plan:" + planID.uuidString }
    var edited: LifePlan? { guard var value = original else { return nil }; value.title = title; value.note = note; value.start = start; value.end = end; value.taskID = taskID; value.timeZone = timeZone ?? value.timeZone; value.allDay = allDay; value.reminderMinutes = reminder < 0 ? nil : reminder; return value }
    var draftFields: [String:String] { guard let original, let edited else { return [:] }; var fields = EditorDrafts.fields(RecordDraft(original: original, edited: edited)); fields["repeatDays"] = String(repeatDays); fields["repeatCount"] = String(repeatCount); return fields }
    var conflicts: [LifePlan] { store.data.plans.filter { $0.id != planID && !$0.cancelled && $0.deletedAt == nil && $0.start < end && $0.end > start } }
    var calendarLink: CalendarLink? { store.data.calendarLinks.first { $0.planID == planID || $0.sourcePlanID == planID } }
    var hasEdits: Bool { guard let plan else { return false }; return edited != plan }
    var body: some View {
        if let plan {
            Form {
                EditorConflictNotice(changed: original.map { $0 != plan } ?? false, current: plan.title + "\n" + plan.start.formatted() + " — " + plan.end.formatted() + "\n" + (plan.note ?? "")) { original = plan }
                Section { TextField("安排", text: $title, axis: .vertical); DatePicker("开始", selection: $start,displayedComponents:allDay ? .date : [.date,.hourAndMinute]); DatePicker(allDay ? "截止日期（不含）" : "结束", selection: $end, in: start...,displayedComponents:allDay ? .date : [.date,.hourAndMinute]); TextField("说明", text: $note, axis: .vertical).lineLimit(3...6); Picker("关联任务", selection: $taskID) { Text("独立安排").tag(UUID?.none); ForEach(store.data.tasks) { Text($0.title).tag(Optional($0.id)) } } }
                Section { AttributionZonePicker(zone:$timeZone); Toggle("全天安排",isOn:$allDay); Text(recordTimeText(start,zone:timeZone)).font(.caption).foregroundStyle(.secondary) }
                if !conflicts.isEmpty { Section("有时间重叠，请核对") { ForEach(conflicts) { Text($0.title + " · " + $0.start.formatted(date: .omitted, time: .shortened)) }; Text("允许保留重叠安排；实际投入统计不会重复累计同一时段。") .font(.caption).foregroundStyle(.secondary) } }
                Section("本地提醒") { Picker("提前提醒", selection: $reminder) { Text("不提醒").tag(-1); Text("准时").tag(0); Text("提前5分钟").tag(5); Text("提前15分钟").tag(15); Text("提前1小时").tag(60) }; Text("保存提醒设置后，在设置页主动启用通知。私人计划不自动创建系统日历事件。") .font(.caption).foregroundStyle(.secondary) }
                Section("重复安排") { Picker("间隔", selection: $repeatDays) { Text("每天").tag(1); Text("每周").tag(7); Text("每两周").tag(14) }; Stepper("新增 \(repeatCount) 次", value: $repeatCount, in: 1...30); Button("预览并创建后续私人计划") { repeatPreview = true }.disabled(hasEdits); if hasEdits { Text("先保存当前修改，再预览重复或创建系统事件。") .font(.caption).foregroundStyle(.secondary) } }
                Section("系统日历") {
                    if let calendarLink { NavigationLink("查看保存回执与核对系统事件") { CalendarLinkManager(link: calendarLink) } }
                    else { Button("在苹果日历编辑器中创建", systemImage: "calendar.badge.plus") { calendarEditor = true }.disabled(hasEdits) }
                    Text("本页保存只更新本机记录。只有你在系统编辑器中保存后才修改苹果日历；取消不写入。已有保存回执时先核对原事件，避免重复创建。") .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button(plan.cancelled ? "恢复这个安排" : "取消这个安排", role: plan.cancelled ? nil : .destructive) { _ = store.commit(kind: "plan.cancel", id: plan.id) { state in if let i = state.plans.firstIndex(where: { $0.id == plan.id }) { state.plans[i].cancelled.toggle(); state.plans[i].revision += 1 } } } }
                Section { NavigationLink("查看修订历史") { RecordHistoryView(entityID:plan.id,kind:"plan") }; Button("删除本机安排", role: .destructive) { deletePlan = true }; Text("不删除或修改苹果日历中的事件。") .font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle(plan.isCommitment ? "日历承诺" : "私人计划").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存") { if store.editPlan(original ?? plan, title: title, start: start, end: end, taskID: taskID, note: note, reminder: reminder < 0 ? nil : reminder,timeZone:timeZone,allDay:allDay) { original = self.plan; EditorDrafts.remove(draftKey) } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start || timeZone == nil) }
                .onAppear { if !initialized { initialized = true; let saved = EditorDrafts.value(draftKey, as: RecordDraft<LifePlan>.self); original = saved?.original ?? plan; let value = saved?.edited ?? plan; title = value.title; note = value.note ?? ""; start = value.start; end = value.end; taskID = value.taskID; reminder = value.reminderMinutes ?? -1; timeZone = value.timeZone; allDay = value.allDay ?? false; if let fields = EditorDrafts.load(draftKey) { repeatDays = fields["repeatDays"].flatMap(Int.init).flatMap { [1,7,14].contains($0) ? $0 : nil } ?? 7; repeatCount = min(30,max(1,fields["repeatCount"].flatMap(Int.init) ?? 3)) } } }
                .environment(\.timeZone,timeZone.flatMap(TimeZone.init(identifier:)) ?? .current)
                .retainingDraft(draftKey, fields: draftFields, active: initialized && self.plan != nil && (hasEdits || repeatDays != 7 || repeatCount != 3))
                .sheet(isPresented: $repeatPreview) { NavigationStack { List { Section("将创建以下私人计划") { ForEach(1...repeatCount, id: \.self) { i in Text(Calendar.current.date(byAdding: .day, value: repeatDays * i, to: start)!.formatted(date: .abbreviated, time: .shortened)) } }; Button("确认创建 \(repeatCount) 次") { if store.repeatPlan(plan, everyDays: repeatDays, count: repeatCount) { repeatPreview = false } } }.navigationTitle("重复安排预览").toolbar { Button("关闭") { repeatPreview = false } } } }
                .sheet(isPresented: $calendarEditor) { CalendarEventEditor(plan: plan) }
                .confirmationDialog("删除这条本机安排？", isPresented: $deletePlan, titleVisibility: .visible) { Button("删除本机记录", role: .destructive) { _ = store.deletePlan(plan) }; Button("取消", role: .cancel) {} } message: { Text("苹果日历中的原事件和实际投入保留。") }
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
    @State private var original: LifeSession?
    @State private var timeZone: String? = TimeZone.current.identifier
    let sessionID: UUID
    var session: LifeSession? { store.data.sessions.first { $0.id == sessionID } }
    var draftKey: String { "actual:" + sessionID.uuidString }
    var draftFields: [String:String] { guard let original else { return [:] }; var edited = original; edited.title = title; edited.note = note; edited.start = start; edited.end = end; edited.confirmed = confirmed; edited.timeZone = timeZone ?? original.timeZone; return EditorDrafts.fields(RecordDraft(original: original, edited: edited)) }
    var body: some View {
        if let session {
            Form {
                EditorConflictNotice(changed: original.map { $0 != session } ?? false, current: session.title + "\n" + session.start.formatted() + " — " + (session.end?.formatted() ?? "计时中") + "\n" + (session.note ?? "")) { original = session }
                Section { TextField("实际活动", text: $title); DatePicker("开始", selection: $start).disabled(session.end == nil && session.restorePending != true); DatePicker("结束", selection: $end, in: start...).disabled(session.end == nil && session.restorePending != true); TextField("说明", text: $note, axis: .vertical).lineLimit(3...8); Toggle("我已核对这段投入", isOn: $confirmed).disabled(session.end == nil && session.restorePending != true) }
                Section { AttributionZonePicker(zone:$timeZone); Text(recordTimeText(start,zone:timeZone)).font(.caption).foregroundStyle(.secondary); NavigationLink("查看修订历史") { RecordHistoryView(entityID:session.id,kind:"actual") } }
                if session.restorePending == true { Section("先核对恢复记录") { Text("备份没有保存结束时间。请填写你确认的结束时间；预填值只方便编辑，不代表实际发生。不需要保留时可以删除，系统不会把恢复时刻自动补成结束。") .font(.subheadline).foregroundStyle(.secondary) } }
                if session.end != nil { Section { NavigationLink("拆分或合并实际记录") { ActualAdjustmentView(original: session) } } }
                Section { Text("修改只影响这段实际记录，不修改任务完成、原计划或成果读数。原记录版本会保留。") .foregroundStyle(.secondary); if session.end == nil && session.restorePending != true { Button("结束当前计时") { store.stopSession() } }; Button("删除这段实际记录", role: .destructive) { delete = true }.disabled(session.end == nil && session.restorePending != true) }
            }.navigationTitle("实际记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存修正") { if store.editSession(original ?? session, title: title, start: start, end: end, note: note, confirmed: confirmed,timeZone:timeZone) { original = self.session; EditorDrafts.remove(draftKey) } }.disabled((session.end == nil && session.restorePending != true) || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start || end > Date().addingTimeInterval(60) || timeZone == nil) }
                .onAppear { if !initialized { initialized = true; let saved = EditorDrafts.value(draftKey, as: RecordDraft<LifeSession>.self); original = saved?.original ?? session; let value = saved?.edited ?? session; title = value.title; note = value.note ?? ""; start = value.start; end = value.end ?? Date(); confirmed = value.confirmed; timeZone = value.timeZone } }
                .environment(\.timeZone,timeZone.flatMap(TimeZone.init(identifier:)) ?? .current)
                .retainingDraft(draftKey, fields: draftFields, active: initialized && self.session != nil && (title != session.title || note != (session.note ?? "") || start != session.start || (session.end != nil && end != session.end) || confirmed != session.confirmed || timeZone != session.timeZone))
                .onChange(of: session.end) { old, new in if old == nil, let new { end = new } }
                .confirmationDialog("删除这段实际记录？", isPresented: $delete, titleVisibility: .visible) { Button("删除", role: .destructive) { store.deleteSession(session) }; Button("取消", role: .cancel) {} }
        } else { ContentUnavailableView("实际记录已删除", systemImage: "clock") }
    }
}

struct ReviewDetailView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var delete = false
    let reviewID: UUID
    @State private var text = ""
    @State private var mood: Int?
    @State private var people = ""
    @State private var initialized = false
    @State private var original: LifeReview?
    var review: LifeReview? { store.data.reviews.first { $0.id == reviewID } }
    var draftKey: String { "review:" + reviewID.uuidString }
    var edited: LifeReview? { guard var value = original else { return nil }; value.reflection = text; value.mood = mood; value.people = aliases(people); return value }
    var draftFields: [String:String] { guard let original, let edited else { return [:] }; return EditorDrafts.fields(RecordDraft(original: original, edited: edited)) }
    var body: some View {
        if let review {
            Form {
                EditorConflictNotice(changed: original.map { $0 != review } ?? false, current: review.reflection + "\n" + (review.people ?? []).joined(separator: "，")) { original = review }
                Section(review.day) { TextField("留给这一天的话", text: $text, axis: .vertical).lineLimit(8...20); Picker("感受", selection: $mood) { Text("不记录").tag(Int?.none); ForEach(1...5, id: \.self) { Text("\($0) / 5").tag(Optional($0)) } }; TextField("人物别名，用逗号分开（可留空）", text: $people) }
                Section { if review.canonical == false { Text("这是旧版保留的附加草稿，不计入正式复盘天数和感受统计。") }; NavigationLink("查看修订历史") { RecordHistoryView(entityID:review.id,kind:"review") }; Button("删除这篇复盘",role:.destructive) { delete = true }; Text("只记录你手写的别名，不读取通讯录，不合并同名人物。") .font(.caption).foregroundStyle(.secondary); LabeledContent("当前版本", value: String(review.revision ?? 1)); Text("修订保留上一版本，不另造同一天的第二份正式复盘。") .font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("这一天").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存修订") { saveRevision(review) } }
                .onAppear { if !initialized { initialized = true; let saved = EditorDrafts.value(draftKey, as: RecordDraft<LifeReview>.self); original = saved?.original ?? review; let value = saved?.edited ?? review; text = value.reflection; mood = value.mood; people = (value.people ?? []).joined(separator: "，"); if saved == nil, let draft = EditorDrafts.load(draftKey) { text = draft["text"] ?? text; people = draft["people"] ?? people; mood = draft["mood"].flatMap(Int.init) } }; mergeReviewAppends() }
                .onReceive(NotificationCenter.default.publisher(for:EditorDrafts.reviewAppended)) { event in if event.object as? String == draftKey { mergeReviewAppends() } }
                .confirmationDialog("删除这篇复盘？",isPresented:$delete,titleVisibility:.visible) { Button("删除复盘",role:.destructive) { if store.commit(kind:"review.delete",id:review.id,{ $0.reviews.removeAll { $0.id == review.id }; $0.tombstone(review.id,kind:"review") }) { dismiss() } }; Button("取消",role:.cancel) {} }
                .retainingDraft(draftKey, fields: draftFields, active: initialized && self.review != nil && (text != review.reflection || mood != review.mood || aliases(people) != (review.people ?? [])))
        }
    }
    func mergeReviewAppends() {
        guard initialized,let original,let edited else { return }
        do { text = try EditorDrafts.consumeReviewAppends(draftKey,baseText:text) { appended in var value = edited; value.reflection = appended; return EditorDrafts.fields(RecordDraft(original:original,edited:value)) } }
        catch { store.error = "快捷指令追加尚未合并，原草稿保留。" }
    }
    func saveRevision(_ review: LifeReview) {
        do { if try !EditorDrafts.pendingReviewAppends(draftKey).isEmpty { mergeReviewAppends(); store.error = "已带入新的快捷指令文字，请核对后再保存。"; return } } catch { store.error = error.localizedDescription; return }
        if store.reviseReview(original ?? review,text:text,mood:mood,people:aliases(people)) { original = self.review; EditorDrafts.remove(draftKey) }
    }
}
