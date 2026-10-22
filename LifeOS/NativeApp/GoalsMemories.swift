import SwiftUI

struct GoalsView: View {
    @Environment(LifeStore.self) private var store
    @State private var composer: ComposerKind?
    var body: some View {
        List {
            Section { VStack(alignment: .leading, spacing: 8) { Text("把注意力，留给真正想成为的自己。") .font(.title2.bold()); Text("方向连接日常，成果由你亲自确认。") .foregroundStyle(.secondary) }.padding(.vertical, 12) }.listRowBackground(Color.teal.opacity(0.07))
            if store.data.goals.isEmpty { ContentUnavailableView("你想朝哪里走？", systemImage: "scope", description: Text("从一个有意义、看得见成果的方向开始。")) }
            ForEach(store.data.goals.filter { !$0.archived }) { goal in
                NavigationLink { GoalDetailView(goal: goal) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(goal.title).font(.headline); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.teal) }
                        if !goal.intention.isEmpty { Text(goal.intention).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        let measurement = store.data.measurements.filter { $0.goalID == goal.id }.max { $0.recordedAt < $1.recordedAt }
                        let value = measurement?.value ?? 0
                        ProgressView(value: min(value, goal.target), total: goal.target).tint(.teal)
                        HStack { Text("\(value.formatted()) / \(goal.target.formatted()) \(goal.unit)"); Spacer(); Text(goal.due.formatted(.dateTime.month().day())) }.font(.caption).foregroundStyle(.secondary)
                        if measurement == nil { Text("尚未记录成果读数").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
            }
            Section { Button { composer = .goal } label: { Label("添加一个方向", systemImage: "plus") } }
        }.navigationTitle("方向")
            .toolbar { Button { composer = .goal } label: { Image(systemName: "plus") }.accessibilityLabel("添加方向") }
            .sheet(item: $composer) { ComposerView(kind: $0) }
    }
}

struct GoalDetailView: View {
    @Environment(LifeStore.self) private var store
    let goal: LifeGoal
    @State private var composer: ComposerKind?
    var body: some View {
        List {
            Section { Text(goal.title).font(.title2.bold()); if !goal.intention.isEmpty { Text(goal.intention) }; LabeledContent("希望完成", value: goal.due.formatted(date: .abbreviated, time: .omitted)); LabeledContent("目标", value: "\(goal.target.formatted()) \(goal.unit)") }
            Section("成果读数") {
                Button { composer = .measurement(goal) } label: { Label("记录当前成果", systemImage: "plus.circle") }
                ForEach(store.data.measurements.filter { $0.goalID == goal.id }.sorted { $0.recordedAt > $1.recordedAt }) { m in
                    VStack(alignment: .leading, spacing: 5) { Text("\(m.value.formatted()) \(goal.unit)").font(.headline); if !m.note.isEmpty { Text(m.note) }; Text(m.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("关联的日常") {
                let tasks = store.data.tasks.filter { $0.goalID == goal.id }
                if tasks.isEmpty { Text("添加任务时，可以把它关联到这个方向。") .foregroundStyle(.secondary) }
                ForEach(tasks) { task in Label(task.title, systemImage: task.completedAt == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(task.completedAt == nil ? Color.primary : Color.teal) }
            }
        }.navigationTitle("方向详情").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $composer) { ComposerView(kind: $0) }
    }
}

struct MemoriesView: View {
    @Environment(LifeStore.self) private var store
    @State private var search = ""
    @State private var composer: ComposerKind?
    var reviews: [LifeReview] { store.data.reviews.filter { search.isEmpty || $0.reflection.localizedCaseInsensitiveContains(search) || $0.day.contains(search) }.sorted { $0.day > $1.day } }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("生活不只是一张清单。") .font(.title2.bold())
                    Text("去过的地方、认真投入的时间，\n还有那些想记住的普通日子。") .foregroundStyle(.secondary)
                    HStack(spacing: 25) { Label("\(store.data.reviews.count) 天复盘", systemImage: "book.closed"); Label("\(store.data.places.count) 处记忆", systemImage: "mappin.and.ellipse") }.font(.caption).foregroundStyle(.teal)
                }.padding(.vertical, 12)
            }.listRowBackground(Color.teal.opacity(0.07))
            Section("日子的片段") {
                if reviews.isEmpty { ContentUnavailableView("值得记住的，就写下来", systemImage: "sparkles", description: Text("不必完成目标，也可以记录生活。")) }
                ForEach(reviews) { review in
                    NavigationLink { List { Section(review.day) { Text(review.reflection).textSelection(.enabled); Label("感受 \(review.mood) / 5", systemImage: "heart") .foregroundStyle(.secondary) } }.navigationTitle("这一天").navigationBarTitleDisplayMode(.inline) } label: {
                        VStack(alignment: .leading, spacing: 7) { Text(review.day).font(.headline); Text(review.reflection).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }.padding(.vertical, 5)
                    }
                }
            }
            Section("走过的路") {
                ForEach(store.data.routes) { route in
                    NavigationLink { RouteDetailView(routeID: route.id) } label: { VStack(alignment: .leading, spacing: 5) { Label(route.title, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"); Text(route.start.formatted(date: .abbreviated, time: .shortened) + (route.end == nil ? " · 记录中" : " · " + minutesText(route.end!.timeIntervalSince(route.start)))).font(.caption).foregroundStyle(.secondary) } }
                }
                if store.data.routes.isEmpty { Text("在地图页，主动开始一段前台路线。") .foregroundStyle(.secondary) }
            }
            Section("已经完成") {
                ForEach(store.data.tasks.filter { $0.completedAt != nil }.prefix(30)) { task in Label(task.title, systemImage: "checkmark.circle.fill").foregroundStyle(.teal) }
                if !store.data.tasks.contains(where: { $0.completedAt != nil }) { Text("每一件完成的小事，都值得被看见。") .foregroundStyle(.secondary) }
            }
        }.navigationTitle("记忆").searchable(text: $search, prompt: "寻找某一天、某一句话")
            .toolbar { Button { composer = .review(Date()) } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("写今日复盘") }
            .sheet(item: $composer) { ComposerView(kind: $0) }
    }
}
