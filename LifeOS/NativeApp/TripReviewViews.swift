import SwiftUI
import Charts

struct NewTripView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var note = ""
    @State private var initialized = false
    @State private var saved = false
    var body: some View {
        NavigationStack { Form {
            TextField("给这段行程一个名字", text: $title); DatePicker("开始", selection: $start); DatePicker("结束", selection: $end, in: start...); TextField("行程故事", text: $note, axis: .vertical).lineLimit(5...12)
            Text("保存后可逐条选择到访、路线、地点记忆和照片，不自动推断一次旅行。") .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("新建行程").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveTrip(LifeTrip(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end, note: note)) { saved = true; EditorDrafts.remove("new-trip"); dismiss() } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end < start) } }
            .onAppear { if !initialized { initialized = true; if let draft = EditorDrafts.load("new-trip") { title = draft["title"] ?? ""; note = draft["note"] ?? ""; if let value = draft["start"].flatMap(Double.init) { start = Date(timeIntervalSince1970:value) }; if let value = draft["end"].flatMap(Double.init) { end = Date(timeIntervalSince1970:value) } } } }
            .retainingDraft("new-trip", fields: ["title":title,"note":note,"start":String(start.timeIntervalSince1970),"end":String(end.timeIntervalSince1970)], active: initialized && !saved)
        }
    }
}

struct TripDetailView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var draft: LifeTrip?
    @State private var addPhoto = false
    @State private var delete = false
    var body: some View {
        Group {
            if let draft {
                TripEditorContent(trip: Binding(get: { self.draft ?? draft }, set: { self.draft = $0 }), addPhoto: $addPhoto, delete: $delete)
                    .toolbar { Button("保存") { if let draft = self.draft, store.saveTrip(draft) { self.draft = store.data.trips.first { $0.id == tripID }; EditorDrafts.remove(draftKey) } }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.end < draft.start) }
                    .retainingDraft(draftKey, fields: EditorDrafts.fields(draft), active: store.data.trips.first(where: { $0.id == tripID }).map { $0 != draft } ?? false)
                    .confirmationDialog("删除这个行程？", isPresented: $delete, titleVisibility: .visible) { Button("删除行程", role: .destructive) { store.deleteTrip(draft); dismiss() }; Button("取消", role: .cancel) {} } message: { Text("到访、路线、照片和地点记忆保留，仅解除行程关联。") }
            } else { ProgressView() }
        }.navigationTitle("行程记忆").navigationBarTitleDisplayMode(.inline)
            .onAppear { if draft == nil { draft = EditorDrafts.value(draftKey, as: LifeTrip.self) ?? store.data.trips.first { $0.id == tripID } } }
            .sheet(isPresented: $addPhoto) { AddPhotoView(tripID: tripID) }
    }
    var draftKey: String { "trip:" + tripID.uuidString }
}

struct TripEditorContent: View {
    @Environment(LifeStore.self) private var store
    @Binding var trip: LifeTrip
    @Binding var addPhoto: Bool
    @Binding var delete: Bool
    var body: some View {
        Form {
            if let current = store.data.trips.first(where: { $0.id == trip.id }) { EditorConflictNotice(changed: current.revision != trip.revision, current: current.title + "\n" + current.note + "\n" + current.start.formatted() + " — " + current.end.formatted()) { trip.revision = current.revision } }
            Section { TextField("行程名称", text: $trip.title); DatePicker("开始", selection: $trip.start); DatePicker("结束", selection: $trip.end, in: trip.start...); TextField("这段路上的故事", text: $trip.note, axis: .vertical).lineLimit(5...15); Toggle("收藏行程", isOn: $trip.favorite) }
            Section("选择关联到访") {
                ForEach(store.data.visits.filter { $0.state == "confirmed" }) { visit in
                    Toggle(isOn: selected(visit.id, path: \.visitIDs)) { VisitRow(visit: visit) }
                    if trip.visitIDs.contains(visit.id) { NavigationLink("核对这次到访") { VisitDetailView(visitID: visit.id) } }
                }
            }
            Section("选择关联路线") {
                ForEach(store.data.routes) { route in
                    Toggle(route.title, isOn: selected(route.id, path: \.routeIDs))
                    if trip.routeIDs.contains(route.id) { NavigationLink("回看这段路线") { RouteDetailView(routeID: route.id) } }
                }
            }
            Section("选择地点记忆") {
                ForEach(store.data.places) { memory in
                    Toggle(memory.title, isOn: selected(memory.id, path: \.memoryIDs))
                    if trip.memoryIDs.contains(memory.id) { NavigationLink("阅读这段记忆") { MemoryDetailView(memoryID: memory.id) } }
                }
            }
            Section("行程照片") { PhotoStrip(photos: store.data.photos.filter { $0.tripID == trip.id && $0.memoryID == nil }); Button("添加一张照片", systemImage: "photo.badge.plus") { addPhoto = true } }
            Section { Text("关联是你手动选择的，不改变原始到访或路线事实。无目标、无任务，也可以独立记录完整行程。") .font(.caption).foregroundStyle(.secondary); Button("删除行程，保留来源记录", role: .destructive) { delete = true } }
        }
    }
    func selected(_ id: UUID, path: WritableKeyPath<LifeTrip,[UUID]>) -> Binding<Bool> {
        Binding(get: { trip[keyPath: path].contains(id) }, set: { enabled in if enabled { if !trip[keyPath: path].contains(id) { trip[keyPath: path].append(id) } } else { trip[keyPath: path].removeAll { $0 == id } } })
    }
}

struct PhotoLibraryView: View {
    @Environment(LifeStore.self) private var store
    @State private var add = false
    var body: some View { List { Section { Text("这里只显示你主动选取的本机副本；备份会包含这些照片。") .font(.caption).foregroundStyle(.secondary) }; PhotoStrip(photos: store.data.photos.sorted { $0.capturedAt > $1.capturedAt }); if store.data.photos.isEmpty { ContentUnavailableView("留下一张普通日子", systemImage: "photo") } }.navigationTitle("照片记忆").toolbar { Button("添加", systemImage: "plus") { add = true } }.sheet(isPresented: $add) { AddPhotoView() } }
}

struct FootprintView: View {
    @Environment(LifeStore.self) private var store
    @AppStorage("dayisle.milestones.enabled") private var milestonesEnabled = true
    var confirmed: [LifeVisit] { store.data.visits.filter { $0.state == "confirmed" } }
    var places: [KnownPlace] { let ids = Set(confirmed.compactMap(\.placeID)); return store.data.knownPlaces.filter { ids.contains($0.id) } }
    var cities: [String] { Array(Set(places.filter { !$0.city.isEmpty }.map { $0.country + " · " + $0.city })).sorted() }
    var countries: [String] { Array(Set(places.map(\.country).filter { !$0.isEmpty })).sorted() }
    var body: some View {
        List {
            Section("已确认的足迹") { LabeledContent("到访", value: String(confirmed.count)); LabeledContent("稳定地点", value: String(places.count)); LabeledContent("城市", value: String(cities.count)); LabeledContent("国家或地区", value: String(countries.count)); LabeledContent("未知地域到访", value: String(confirmed.filter { visit in !places.contains { $0.id == visit.placeID && !$0.city.isEmpty && !$0.country.isEmpty } }.count)) }
            Section("城市 · 用户填写") { ForEach(cities, id: \.self) { Text($0) } }
            Section("国家或地区 · 用户填写") { ForEach(countries, id: \.self) { Text($0) } }
            Section("小小里程碑") {
                Toggle("显示小小里程碑",isOn:$milestonesEnabled)
                if milestonesEnabled {
                milestone("留下第一篇日复盘", done: !store.data.reviews.isEmpty)
                milestone("确认第一段实际投入", done: store.data.sessions.contains { $0.confirmed && $0.end != nil })
                milestone("确认第一次到访", done: !confirmed.isEmpty)
                milestone("手写第一段行程", done: !store.data.trips.isEmpty)
                milestone("记录7天的生活", done: store.data.reviews.filter { $0.canonical != false }.count >= 7)
                }
            }
            Section { Text("这些统计从当前记录重新计算。地点收藏、路线经过、手动记忆和照片都不算已确认到访；不同拼写的城市暂不自动合并。删除或排除到访后，统计与里程碑会相应变化。") .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("自己的足迹")
    }
    func milestone(_ title: String, done: Bool) -> some View { Label(title, systemImage: done ? "checkmark.seal.fill" : "seal").foregroundStyle(done ? Color.teal : Color.secondary) }
}

struct PeriodReviewListView: View {
    @Environment(LifeStore.self) private var store
    @State private var start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!.start
    @State private var end = Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:Date()))!
    @State private var add = false
    var body: some View {
        List {
            Section("回看一个阶段") {
                HStack { Button("本周") { let range = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!; start = range.start; end = range.end }; Spacer(); Button("本月") { let range = Calendar.current.dateInterval(of: .month, for: Date())!; start = range.start; end = range.end } }
                DatePicker("开始", selection: $start, displayedComponents: .date); DatePicker("截止（不含）", selection: $end, in: start..., displayedComponents: .date)
                NavigationLink { PeriodSummaryView(start: Calendar.current.startOfDay(for:start), end: Calendar.current.startOfDay(for:end)) } label: { Label("查看这个阶段", systemImage: "chart.bar.xaxis") }.disabled(Calendar.current.startOfDay(for:end) <= Calendar.current.startOfDay(for:start))
            }
            Section("已写下的回顾") { ForEach(store.data.periodReviews) { review in NavigationLink { PeriodSummaryView(start: review.start, end: review.end, reviewID: review.id) } label: { VStack(alignment: .leading) { Text(review.title).font(.headline); Text(review.reflection).font(.caption).foregroundStyle(.secondary).lineLimit(2) } } } }
        }.navigationTitle("阶段回顾")
    }
}

struct PeriodSummaryView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let start: Date
    let end: Date
    var reviewID: UUID? = nil
    @State private var title = ""
    @State private var reflection = ""
    @State private var next = ""
    @State private var currentID: UUID?
    @State private var initialized = false
    @State private var createTask = false
    @State private var original: PeriodReview?
    @State private var delete = false
    var draftFields: [String:String] {
        var fields = ["title":title,"reflection":reflection,"next":next]
        if let original { fields["original"] = EditorDrafts.fields(original)["record"] }
        return fields
    }
    var daily: [LifeReview] { store.data.reviews.filter { $0.canonical != false && $0.day >= LifeSnapshot.dayKey(start) && $0.day < LifeSnapshot.dayKey(end) } }
    var plans: [LifePlan] { store.data.plans.filter { !$0.cancelled && $0.start < end && $0.end > start } }
    var body: some View {
        Form {
            if let currentID,let current = store.data.periodReviews.first(where:{ $0.id == currentID }) { EditorConflictNotice(changed:current.revision != original?.revision,current:current.title + "\n" + current.reflection + "\n" + current.nextStep) { original = current } }
            Section(start.formatted(date: .abbreviated, time: .omitted) + " – " + end.formatted(date: .abbreviated, time: .omitted)) {
                LabeledContent("已确认实际投入（重叠合并）", value: minutesText(store.data.unionActualSeconds(from: start, to: end)))
                LabeledContent("私人计划", value: String(plans.filter { !$0.isCommitment }.count)); LabeledContent("日历承诺", value: String(plans.filter(\.isCommitment).count))
                LabeledContent("完成任务", value: String(store.data.tasks.filter { $0.completedAt.map { $0 >= start && $0 < end } == true }.count))
                LabeledContent("地点记忆", value: String(store.data.places.filter { $0.occurredAt >= start && $0.occurredAt < end }.count))
            }
            Section("方向与成果") { ForEach(store.data.goals.filter { !$0.archived }) { goal in NavigationLink { ObjectiveDetailView(objectiveID: goal.id) } label: { VStack(alignment: .leading) { Text(goal.title); Text("当前成果进度：" + (store.data.objectiveProgress(goal.id).map { Int($0 * 100).formatted() + "%" } ?? "尚未完整测量")).font(.caption).foregroundStyle(.secondary) } } }; Text("这里显示当前成果读数，不将投入或任务数转换为成果，也不冒充阶段末的历史快照。") .font(.caption).foregroundStyle(.secondary) }
            Section("这些天的感受") {
                if daily.compactMap(\.mood).isEmpty { Text("没有记录感受，保持未知。") .foregroundStyle(.secondary) }
                else { Chart(daily.filter { $0.mood != nil }) { review in PointMark(x: .value("日期", review.day), y: .value("感受", review.mood!)) }.chartYScale(domain: 1...5).frame(height: 160) }
                ForEach(daily) { review in NavigationLink(review.day) { ReviewDetailView(reviewID: review.id) } }
            }
            Section("写给这个阶段") { TextField("回顾名称", text: $title); TextField("有哪些值得记住和调整的事？", text: $reflection, axis: .vertical).lineLimit(6...18); TextField("下一步想尝试什么？", text: $next, axis: .vertical).lineLimit(3...8) }
            Section { Button("保存阶段回顾") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Button("把下一步带入新任务", systemImage: "arrow.turn.up.right") { createTask = true }.disabled(next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Text("只有在新任务页面点击保存才创建任务；不会自动改计划、实际投入或成果。") .font(.caption).foregroundStyle(.secondary) }
            if let currentID { Section { NavigationLink("查看修订历史") { RecordHistoryView(entityID:currentID,kind:"period-review") }; Button("删除阶段回顾",role:.destructive) { delete = true } } }
        }.navigationTitle("回看与调整").navigationBarTitleDisplayMode(.inline)
            .onAppear { if !initialized { initialized = true; let saved = store.data.periodReviews.first { $0.id == reviewID }; currentID = saved?.id; original = saved; title = saved?.title ?? "我的阶段回顾"; reflection = saved?.reflection ?? ""; next = saved?.nextStep ?? ""; if let draft = EditorDrafts.load(draftKey) { title = draft["title"] ?? title; reflection = draft["reflection"] ?? reflection; next = draft["next"] ?? next; if let text = draft["original"],let captured = EditorDrafts.decode(PeriodReview.self,text:text) { original = captured; currentID = captured.id } } } }
            .retainingDraft(draftKey,fields:draftFields,active:initialized && (original == nil || title != original?.title || reflection != original?.reflection || next != original?.nextStep))
            .confirmationDialog("删除这份阶段回顾？",isPresented:$delete,titleVisibility:.visible) { Button("删除回顾",role:.destructive) { if let currentID,store.commit(kind:"period-review.delete",id:currentID,{ $0.periodReviews.removeAll { $0.id == currentID }; $0.tombstone(currentID,kind:"period-review") }) { dismiss() } }; Button("取消",role:.cancel) {} } message: { Text("来源日复盘、任务与实际投入保留。") }
            .sheet(isPresented: $createTask) { ComposerView(kind: .task, prefilledTitle: next) }
    }
    var draftKey: String { reviewID.map { "period-review:" + $0.uuidString } ?? "period:" + String(start.timeIntervalSince1970) + ":" + String(end.timeIntervalSince1970) }
    func save() {
        if let id = currentID, let original {
            if store.commit(kind: "period-review.edit", id: id, { state in guard let i = state.periodReviews.firstIndex(where: { $0.id == id }),state.periodReviews[i].revision == original.revision else { throw LifeError.message("阶段回顾已更新，请核对后保存。") }; try state.audit(original, id: id, kind: "period-review", revision: original.revision); state.periodReviews[i].title = title; state.periodReviews[i].reflection = reflection; state.periodReviews[i].nextStep = next; state.periodReviews[i].revision += 1 }) { self.original = store.data.periodReviews.first { $0.id == id }; EditorDrafts.remove(draftKey) }
        } else {
            let review = PeriodReview(title: title, start: start, end: end, reflection: reflection, nextStep: next)
            if store.addPeriodReview(review) { currentID = review.id; original = review; EditorDrafts.remove(draftKey) }
        }
    }
}
