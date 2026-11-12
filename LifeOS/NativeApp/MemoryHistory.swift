import SwiftUI

struct MemoryHistoryView: View {
    @Environment(LifeStore.self) private var store
    @State private var mode = "往年今日"
    @State private var day = Date()
    @State private var year = Calendar.current.component(.year,from:Date())
    @State private var search = ""
    @AppStorage("dayisle.history.excludeCommute") private var excludeCommute = false
    var years: [Int] {
        let values = store.data.reviews.compactMap { Int($0.day.prefix(4)) } + store.data.places.compactMap { memory in memory.timeZone.flatMap(TimeZone.init(identifier:)).map { Int(LifeSnapshot.dayKey(memory.occurredAt,zone:$0).prefix(4))! } }
        return Array(Set(values + [year,Calendar.current.component(.year,from:Date())])).sorted(by:>)
    }
    func match(_ key: String) -> Bool {
        if mode == "年度" { return key.hasPrefix(String(year) + "-") }
        let selected = LifeSnapshot.dayKey(day)
        return key.suffix(5) == selected.suffix(5) && key.prefix(4) < selected.prefix(4)
    }
    func searchMatch(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }
    func recordMatch(_ date: Date,zone: String?) -> Bool { guard let zone,let timeZone = TimeZone(identifier:zone) else { return false }; return match(LifeSnapshot.dayKey(date,zone:timeZone)) }
    var body: some View {
        List {
            Section {
                Picker("回看范围",selection:$mode) { Text("往年今日").tag("往年今日"); Text("年度").tag("年度") }.pickerStyle(.segmented)
                if mode == "年度" { Picker("年份",selection:$year) { ForEach(years,id:\.self) { Text(String($0)).tag($0) } } }
                else { DatePicker("对应月日",selection:$day,displayedComponents:.date) }
                Toggle("隐藏标记为通勤的路线",isOn:$excludeCommute)
            }
            Section("日复盘") { ForEach(store.data.reviews.filter { match($0.day) && searchMatch($0.reflection + " " + ($0.people ?? []).joined(separator:" ")) }.sorted { $0.day > $1.day }) { r in NavigationLink(r.day + (r.canonical == false ? " · 附加草稿" : "")) { ReviewDetailView(reviewID:r.id) } } }
            Section("生活记忆") { ForEach(store.data.places.filter { recordMatch($0.occurredAt,zone:$0.timeZone) && searchMatch($0.title + " " + $0.note + " " + ($0.people ?? []).joined(separator:" ")) }) { m in NavigationLink(m.title) { MemoryDetailView(memoryID:m.id) } } }
            Section("行程") { ForEach(store.data.trips.filter { recordMatch($0.start,zone:$0.timeZone) && searchMatch($0.title + " " + $0.note) }) { t in NavigationLink(t.title) { TripDetailView(tripID:t.id) } } }
            Section("路线") { ForEach(store.data.routes.filter { recordMatch($0.start,zone:$0.timeZone) && (!excludeCommute || $0.purpose != "通勤") && searchMatch($0.title + " " + ($0.note ?? "")) }) { r in NavigationLink(r.title) { RouteDetailView(routeID:r.id) } } }
            Section("归属时区未知的旧记录") {
                ForEach(store.data.places.filter { $0.timeZone == nil && searchMatch($0.title + " " + $0.note) }) { m in NavigationLink(m.title + " · 时间归属待核对") { MemoryDetailView(memoryID:m.id) } }
                Text("归属时区未知时不强行归入年份或往年今日。2月29日只与同月同日匹配，不移到2月28日。通勤仅按你手动填写的用途隐藏，不删除来源，也不改变投入。") .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("往日与年度").searchable(text:$search,prompt:"文字、人物别名或地点")
    }
}
