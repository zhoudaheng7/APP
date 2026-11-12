import SwiftUI
import MapKit

struct VisitInboxView: View {
    @Environment(LifeStore.self) private var store
    @Environment(LifeLocation.self) private var location
    @State private var scope = "inferred"
    var body: some View {
        List {
            Section("自动到访") {
                Text(location.visitStatus).font(.subheadline)
                Text(location.precise ? "当前为精确定位" : "当前为大致定位，地点匹配可能不准确").font(.caption).foregroundStyle(.secondary)
                if store.visitsEnabled { Button("暂停自动到访", role: .destructive) { location.disableVisits() } }
                else { Button("开启低功耗自动到访") { location.enableVisits() } }
                Text("系统可能在离开后才送达记录，未知到达或离开时间会保留为未知。确认到访也不会自动判断你做了什么。强退、关权限和系统限制期间可能没有记录。") .font(.caption).foregroundStyle(.secondary)
            }
            Section { Picker("到访状态", selection: $scope) { Text("待核对").tag("inferred"); Text("已确认").tag("confirmed"); Text("已排除").tag("rejected") }.pickerStyle(.segmented) }
            Section {
                let visits = store.data.visits.filter { $0.state == scope }.sorted { ($0.arrival ?? $0.departure ?? $0.receivedAt) > ($1.arrival ?? $1.departure ?? $1.receivedAt) }
                if visits.isEmpty { ContentUnavailableView("这里还没有到访", systemImage: "mappin.and.ellipse", description: Text("自动到访的送达由系统决定，也可以继续用手动地图记忆。")) }
                ForEach(visits) { visit in NavigationLink { VisitDetailView(visitID: visit.id) } label: { VisitRow(visit: visit) } }
            }
        }.navigationTitle("到访收件箱")
    }
}

struct VisitRow: View {
    @Environment(LifeStore.self) private var store
    let visit: LifeVisit
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.data.knownPlaces.first(where: { $0.id == visit.placeID })?.title ?? "尚未命名的地点").font(.headline)
            Text((visit.arrival.map { recordTimeText($0,zone:visit.timeZoneSource == "user" ? visit.timeZone:nil) } ?? "到达时间未知") + " → " + (visit.departure.map { recordTimeText($0,zone:visit.timeZoneSource == "user" ? visit.timeZone:nil) } ?? "离开时间未知"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct VisitDetailView: View {
    @Environment(LifeStore.self) private var store
    let visitID: UUID
    @State private var placeID: UUID?
    @State private var knownArrival = false
    @State private var knownDeparture = false
    @State private var arrival = Date()
    @State private var departure = Date()
    @State private var note = ""
    @State private var state = "inferred"
    @State private var initialized = false
    @State private var addPlace = false
    @State private var delete = false
    @State private var memoryID: UUID?
    @State private var newMemory: LifePlace?
    @State private var original: LifeVisit?
    @State private var timeZone: String?
    var visit: LifeVisit? { store.data.visits.first { $0.id == visitID } }
    var draftKey: String { "visit:" + visitID.uuidString }
    var hasEdits: Bool { guard let visit else { return false }; return placeID != visit.placeID || knownArrival != (visit.arrival != nil) || knownDeparture != (visit.departure != nil) || (knownArrival && arrival != visit.arrival) || (knownDeparture && departure != visit.departure) || note != visit.note || state != visit.state || timeZone != (visit.timeZoneSource == "user" ? visit.timeZone:nil) }
    var draftFields: [String:String] {
        guard let original else { return [:] }; var edited = original
        edited.placeID = placeID; edited.arrival = knownArrival ? arrival:nil; edited.departure = knownDeparture ? departure:nil; edited.note = note; edited.state = state; edited.timeZoneSource = timeZone == nil ? nil:"user"; if let timeZone { edited.timeZone = timeZone }
        return EditorDrafts.fields(RecordDraft(original:original,edited:edited))
    }
    var body: some View {
        if let visit {
            Form {
                EditorConflictNotice(changed: original.map { $0 != visit } ?? false, current: visit.note + "\n" + (visit.arrival?.formatted() ?? "到达未知") + " → " + (visit.departure?.formatted() ?? "离开未知")) { original = visit }
                Section { Map { Marker("系统送达的大致位置", coordinate: CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)) }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16)); Text("位置误差约 \(Int(visit.accuracy.rounded())) 米 · 来源：苹果低功耗到访").font(.caption).foregroundStyle(.secondary) }
                Section("你的核对") {
                    Picker("地点", selection: $placeID) { Text("仍未知").tag(UUID?.none); ForEach(store.data.knownPlaces) { Text($0.title).tag(Optional($0.id)) } }
                    Button("在这个位置新增稳定地点") { addPlace = true }
                    Toggle("知道到达时间", isOn: $knownArrival); if knownArrival { DatePicker("到达", selection: $arrival) }
                    Toggle("知道离开时间", isOn: $knownDeparture); if knownDeparture { DatePicker("离开", selection: $departure) }
                    AttributionZonePicker(zone:$timeZone)
                    Text("系统到访回调不提供所在地时区。未知时以当前时区显示，你可以核对后填写；不会把收到回调时的时区当作所在地证明。") .font(.caption).foregroundStyle(.secondary)
                    Picker("结论", selection: $state) { Text("待核对").tag("inferred"); Text("我确认到访").tag("confirmed"); Text("排除这次记录").tag("rejected") }
                    TextField("补充说明", text: $note, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Button("确认保存核对结果") { if store.reviseVisit(original ?? visit, placeID: placeID, arrival: knownArrival ? arrival : nil, departure: knownDeparture ? departure : nil, note: note, state: state, timeZone:timeZone) { original = self.visit; EditorDrafts.remove(draftKey) } }
                    if let date = visit.arrival ?? visit.departure { NavigationLink("在这一天的时间线回看") { TodayView(day: date) } }
                    if visit.state == "confirmed" {
                        Button("从这次到访写一段记忆") {
                            if let saved = store.data.places.first(where: { $0.visitID == visit.id }) { memoryID = saved.id; return }
                            guard let occurred = visit.arrival ?? visit.departure else { store.error = "先核对一个已知时间，再创建记忆。"; return }
                            var memory = LifePlace(title: store.data.knownPlaces.first(where: { $0.id == visit.placeID })?.title ?? "一次到访", note: "", latitude: visit.latitude, longitude: visit.longitude, occurredAt: occurred, knownPlaceID: visit.placeID, visitID: visit.id)
                            memory.timeZone = visit.timeZoneSource == "user" ? visit.timeZone:nil
                            newMemory = memory
                        }
                    }
                    Button("删除这次到访", role: .destructive) { delete = true }
                    Text("修订保留原版本。核对后的内容不会被晚到的自动回调覆盖；删除会留下本机删除标记，避免旧备份或晚到回调恢复它。") .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("核对到访").navigationBarTitleDisplayMode(.inline)
                .environment(\.timeZone,timeZone.flatMap(TimeZone.init(identifier:)) ?? .current)
                .onAppear { if !initialized { initialized = true; let draft = EditorDrafts.value(draftKey,as:RecordDraft<LifeVisit>.self); original = draft?.original ?? visit; let value = draft?.edited ?? visit; placeID = value.placeID; knownArrival = value.arrival != nil; knownDeparture = value.departure != nil; arrival = value.arrival ?? value.receivedAt; departure = value.departure ?? value.receivedAt; note = value.note; state = value.state; timeZone = value.timeZoneSource == "user" ? value.timeZone:nil } }
                .retainingDraft(draftKey,fields:draftFields,active:initialized && self.visit != nil && hasEdits)
                .sheet(isPresented: $addPlace) { NavigationStack { KnownPlaceEditor(place: KnownPlace(title: "", latitude: visit.latitude, longitude: visit.longitude)) { placeID = $0 } } }
                .sheet(item: $newMemory) { NewMemoryView(seed: $0, contextKey: "new-memory:" + visit.id.uuidString) }
                .navigationDestination(item: $memoryID) { MemoryDetailView(memoryID: $0) }
                .confirmationDialog("删除这次到访？", isPresented: $delete, titleVisibility: .visible) { Button("删除", role: .destructive) { store.deleteVisit(visit) }; Button("取消", role: .cancel) {} }
        } else { ContentUnavailableView("到访已删除", systemImage: "mappin.slash") }
    }
}

struct KnownPlaceLibrary: View {
    @Environment(LifeStore.self) private var store
    @State private var search = ""
    var body: some View {
        List {
            Section { Text("稳定地点代表你命名的地方；只有已确认到访才参与足迹统计。城市与国家由你核对填写，未填写保持未知。") .font(.caption).foregroundStyle(.secondary) }
            ForEach(store.data.knownPlaces.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { place in
                NavigationLink { KnownPlaceEditor(place: place) } label: { HStack { Image(systemName: place.favorite ? "star.fill" : "mappin.circle").foregroundStyle(.teal); VStack(alignment: .leading) { Text(place.title); Text([place.city,place.country].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) } } }
            }
        }.navigationTitle("我的地点").searchable(text: $search)
    }
}

struct KnownPlaceEditor: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var place: KnownPlace
    var saved: ((UUID) -> Void)? = nil
    @State private var delete = false
    @State private var composer: ComposerKind?
    @State private var initialized = false
    @State private var savedDraft = false
    @State private var retainedKey: String?
    var exists: Bool { store.data.knownPlaces.contains { $0.id == place.id } }
    var body: some View {
        Form {
            Section { TextField("地点名称", text: $place.title); TextField("城市（由你核对，可留空）", text: $place.city); TextField("国家或地区（由你核对，可留空）", text: $place.country); Toggle("收藏", isOn: $place.favorite); Toggle("敏感地点", isOn: $place.isSensitive); LabeledContent("地域来源", value: "用户填写，未做自动行政区判断") }
            if let current = store.data.knownPlaces.first(where: { $0.id == place.id }) { EditorConflictNotice(changed: current.revision != place.revision, current: current.title + "\n" + current.city + " · " + current.country) { place.revision = current.revision } }
            Section { Map { Marker(place.title, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) }.frame(height: 230); Slider(value: $place.radius, in: 50...1000, step: 50) { Text("参考范围") }; Text("参考范围 \(Int(place.radius)) 米，仅辅助你核对，不自动合并到访。") .font(.caption).foregroundStyle(.secondary) }
            if exists { Section("已确认到访") { ForEach(store.data.visits.filter { $0.placeID == place.id && $0.state == "confirmed" }) { visit in NavigationLink { VisitDetailView(visitID: visit.id) } label: { VisitRow(visit: visit) } } }; Button("删除地点名称，保留原始到访", role: .destructive) { delete = true } }
            if exists { Section("下次再去") { Button("预览一件想做的事", systemImage: "checkmark.circle") { composer = .task }; Button("预览一个私人计划", systemImage: "calendar.badge.plus") { composer = .plan }; Text("打开后仍需你填写并保存；关闭草稿不会创建任务、计划、日历或到访。") .font(.caption).foregroundStyle(.secondary) } }
        }.navigationTitle(exists ? "地点详情" : "命名这个地方").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("保存") { if store.saveKnownPlace(place) { savedDraft = true; EditorDrafts.remove(draftKey); saved?(place.id); dismiss() } }.disabled(place.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            .onAppear { if !initialized { initialized = true; retainedKey = draftKey; place = EditorDrafts.value(draftKey, as: KnownPlace.self) ?? place } }
            .retainingDraft(draftKey, fields: EditorDrafts.fields(place), active: initialized && !savedDraft)
            .confirmationDialog("删除这个稳定地点？", isPresented: $delete, titleVisibility: .visible) { Button("删除", role: .destructive) { store.deleteKnownPlace(place); dismiss() }; Button("取消", role: .cancel) {} } message: { Text("到访与文字记忆保留，并解除地点关联；地域统计会重新计算。") }
            .sheet(item: $composer) { ComposerView(kind: $0, prefilledTitle: "下次再去：" + place.title, initialPlaceID: place.id) }
    }
    var draftKey: String { retainedKey ?? (exists ? "known-place:" + place.id.uuidString : "new-known-place:" + LifeStore.fingerprint(Data((String(place.latitude) + ":" + String(place.longitude)).utf8))) }
}

struct MapHistoryView: View {
    @Environment(LifeStore.self) private var store
    @State private var day = Date()
    @State private var allDays = false
    var visits: [LifeVisit] { store.data.visits.filter { $0.state == "confirmed" && (allDays || ($0.arrival ?? $0.departure).map { overlapsDay($0, $0.addingTimeInterval(1), day: day) } == true) } }
    var memories: [LifePlace] { store.data.places.filter { allDays || Calendar.current.isDate($0.occurredAt, inSameDayAs: day) } }
    var routes: [LifeRoute] { store.data.routes.filter { allDays || overlapsDay($0.start, $0.end ?? Date(), day: day) } }
    var body: some View {
        List {
            Section { Toggle("所有日期", isOn: $allDays); if !allDays { DatePicker("回看日期", selection: $day, displayedComponents: .date) } }
            Section { Map {
                ForEach(visits) { visit in Marker(store.data.knownPlaces.first(where: { $0.id == visit.placeID })?.title ?? "已确认到访", coordinate: CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)).tint(.orange) }
                ForEach(memories) { memory in Marker(memory.title, systemImage: "sparkles", coordinate: CLLocationCoordinate2D(latitude: memory.latitude, longitude: memory.longitude)).tint(.teal) }
            }.frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 20)) }
            Section("到访") { ForEach(visits) { visit in NavigationLink { VisitDetailView(visitID: visit.id) } label: { VisitRow(visit: visit) } } }
            Section("记忆") { ForEach(memories) { memory in NavigationLink(memory.title) { MemoryDetailView(memoryID: memory.id) } } }
            Section("路线") { ForEach(routes) { route in NavigationLink(route.title) { RouteDetailView(routeID: route.id) } } }
        }.navigationTitle("时间里的地图")
    }
}
