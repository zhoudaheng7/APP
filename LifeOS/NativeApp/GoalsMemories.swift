import SwiftUI

struct GoalsView: View { var body: some View { ObjectiveListView() } }
struct GoalDetailView: View { let goal: LifeGoal; var body: some View { ObjectiveDetailView(objectiveID: goal.id) } }

struct MemoriesView: View {
    @Environment(LifeStore.self) private var store
    @State private var search = ""
    @State private var composer: ComposerKind?
    @State private var newTrip = false
    @State private var favorites = false
    @State private var addPhoto = false
    var reviews: [LifeReview] { store.data.reviews.filter { search.isEmpty || $0.reflection.localizedCaseInsensitiveContains(search) || $0.day.contains(search) }.sorted { $0.day > $1.day } }
    var body: some View {
        List {
            Section {
                NavigationLink { StoryListView() } label: { Label("制作自己的故事与PDF",systemImage:"book.pages") }
                NavigationLink { MemoryHistoryView() } label: { Label("往日与年度回看",systemImage:"calendar.badge.clock") }
                VStack(alignment: .leading, spacing: 8) {
                    Text("生活不只是一张清单。") .font(.title2.bold())
                    Text("去过的地方、认真投入的时间，\n还有那些想记住的普通日子。") .foregroundStyle(.secondary)
                    HStack(spacing: 25) { Label("\(store.data.reviews.filter { $0.canonical != false }.count) 天复盘", systemImage: "book.closed"); Label("\(store.data.places.count) 处记忆", systemImage: "mappin.and.ellipse") }.font(.caption).foregroundStyle(.teal)
                }.padding(.vertical, 12)
            }.listRowBackground(Color.teal.opacity(0.07))
            Section {
                NavigationLink { PeriodReviewListView() } label: { Label("周、月与阶段回顾", systemImage: "chart.bar.xaxis") }
                NavigationLink { FootprintView() } label: { Label("足迹与小小里程碑", systemImage: "globe.asia.australia") }
                NavigationLink { PhotoLibraryView() } label: { Label("照片记忆", systemImage: "photo.on.rectangle.angled") }
                Toggle("只看收藏的地点记忆与行程", isOn: $favorites)
            }
            Section("手写行程") {
                ForEach(store.data.trips.filter { (!favorites || $0.favorite) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search)) }) { trip in NavigationLink { TripDetailView(tripID: trip.id) } label: { VStack(alignment: .leading) { Label(trip.title, systemImage: trip.favorite ? "star.fill" : "suitcase"); Text(trip.start.formatted(date: .abbreviated, time: .omitted) + " – " + trip.end.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) } } }
                Button("新建一段行程", systemImage: "plus") { newTrip = true }
            }
            Section("地点故事") {
                ForEach(store.data.places.filter { (!favorites || $0.favorite == true) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search) || ($0.people ?? []).contains(where: { $0.localizedCaseInsensitiveContains(search) })) }) { memory in NavigationLink { MemoryDetailView(memoryID: memory.id) } label: { VStack(alignment: .leading, spacing: 5) { Label(memory.title, systemImage: memory.favorite == true ? "star.fill" : "mappin.and.ellipse"); Text(memory.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) } } }
            }
            Section("日子的片段") {
                if reviews.isEmpty { ContentUnavailableView("值得记住的，就写下来", systemImage: "sparkles", description: Text("不必完成目标，也可以记录生活。")) }
                ForEach(reviews) { review in
                    NavigationLink { ReviewDetailView(reviewID: review.id) } label: {
                        VStack(alignment: .leading, spacing: 7) { Text(review.day + (review.canonical == false ? " · 保留的附加草稿" : "")).font(.headline); Text(review.reflection).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }.padding(.vertical, 5)
                    }
                }
            }
            Section("走过的路") {
                ForEach(store.data.routes) { route in
                    NavigationLink { RouteDetailView(routeID: route.id) } label: { VStack(alignment: .leading, spacing: 5) { Label(route.title, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"); Text(route.start.formatted(date: .abbreviated, time: .shortened) + (route.end == nil ? " · 记录中" : " · " + minutesText(route.end!.timeIntervalSince(route.start)))).font(.caption).foregroundStyle(.secondary) } }
                }
                if store.data.routes.isEmpty { Text("在地图页，主动开始一段短路线。") .foregroundStyle(.secondary) }
            }
            Section("已经完成") {
                ForEach(store.data.tasks.filter { $0.completedAt != nil }.prefix(30)) { task in NavigationLink { TaskDetailView(taskID: task.id) } label: { Label(task.title, systemImage: "checkmark.circle.fill").foregroundStyle(.teal) } }
                if !store.data.tasks.contains(where: { $0.completedAt != nil }) { Text("每一件完成的小事，都值得被看见。") .foregroundStyle(.secondary) }
            }
        }.navigationTitle("记忆").searchable(text: $search, prompt: "寻找某一天、某一句话")
            .toolbar { Menu { Button("写今日复盘", systemImage: "square.and.pencil") { composer = .review(Date()) }; Button("新建行程", systemImage: "suitcase") { newTrip = true }; Button("添加一张照片", systemImage: "photo.badge.plus") { addPhoto = true } } label: { Image(systemName: "plus") }.accessibilityLabel("新建记忆") }
            .sheet(item: $composer) { ComposerView(kind: $0) }
            .sheet(isPresented: $newTrip) { NewTripView() }
            .sheet(isPresented: $addPhoto) { AddPhotoView() }
    }
}
