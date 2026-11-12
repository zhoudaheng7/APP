import SwiftUI

struct TodayView: View {
    @Environment(LifeStore.self) private var store
    @State private var day = Date()
    @State private var composer: ComposerKind?
    @State private var settings = false
    init(day: Date = Date()) { _day = State(initialValue: day) }
    var openTasks: [LifeTask] { store.data.tasks.filter(\.isOpen).sorted { ($0.priority ?? 0) > ($1.priority ?? 0) } }
    var sessions: [LifeSession] { store.data.sessions.filter { overlapsDay($0.start, $0.end ?? Date(), day: day, zone: TimeZone(identifier: $0.timeZone) ?? .current) }.sorted { $0.start < $1.start } }
    var plans: [LifePlan] { store.data.plans.filter { !$0.cancelled && overlapsDay($0.start, $0.end, day: day, zone: TimeZone(identifier: $0.timeZone) ?? .current) }.sorted { $0.start < $1.start } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(day.formatted(.dateTime.month(.wide).day().weekday(.wide))).font(.subheadline).foregroundStyle(.secondary)
                            Text(Calendar.current.isDateInToday(day) ? "把今天，过成自己喜欢的样子。" : "这一天，留下了什么？")
                                .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.orange.gradient).accessibilityHidden(true)
                    }
                    HStack(spacing: 24) {
                        metric("已完成", "\(store.data.tasks.filter { $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }.count)")
                        metric("已确认投入", minutesText(store.data.unionActualSeconds(from: Calendar.current.startOfDay(for: day), to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day))!)))
                    }
                    DatePicker("选择回看日期", selection: $day, displayedComponents: .date)
                    HStack {
                        Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("前一天")
                        Spacer()
                        Button("回到今天") { day = Date() }
                        Spacer()
                        Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("后一天")
                    }.font(.subheadline)
                }.padding(.vertical, 8)
            }.listRowBackground(Color.teal.opacity(0.07))

            if let active = store.runningSession {
                Section("正在投入") {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(active.title, systemImage: "waveform.path").font(.headline)
                        if active.restorePending == true {
                            Text("备份里的未结束记录，需要核对结束时间。") .foregroundStyle(.secondary)
                            NavigationLink("核对恢复记录") { SessionEditor(sessionID: active.id) }
                        } else {
                            Text(active.start, style: .timer).font(.system(.largeTitle, design: .rounded).monospacedDigit()).accessibilityIdentifier("activeTimer")
                            PrimaryAction(title: "结束这一段", symbol: "stop.fill") { store.stopSession() }
                        }
                        Text("结束计时后核对实际投入，任务完成另行确认。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            } else {
                Section {
                    PrimaryAction(title: "开始一段专注", symbol: "play.fill") { composer = .session }
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }

            Section {
                if openTasks.isEmpty {
                    ContentUnavailableView("给今天一个小目标", systemImage: "checkmark.circle", description: Text("先写下一件值得完成的事。"))
                } else {
                    ForEach(openTasks) { task in
                        HStack(alignment: .top, spacing: 12) {
                            Button { store.completeTask(task) } label: { Image(systemName: "circle").font(.title2) }
                                .buttonStyle(.plain).foregroundStyle(.teal).accessibilityLabel("完成\(task.title)")
                            NavigationLink { TaskDetailView(taskID: task.id) } label: { VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).font(.body.weight(.medium))
                                if !task.note.isEmpty { Text(task.note).font(.caption).foregroundStyle(.secondary) }
                                if let goal = store.data.goals.first(where: { $0.id == task.goalID }) { Label(goal.title, systemImage: "scope").font(.caption).foregroundStyle(.teal) }
                            } }
                            Spacer()
                            Button { _ = store.startSession(title: task.title, taskID: task.id) } label: { Image(systemName: "play.circle") }
                                .buttonStyle(.borderless).disabled(store.runningSession != nil).accessibilityLabel("为\(task.title)开始计时")
                        }.padding(.vertical, 5)
                    }
                }
                Button { composer = .task } label: { Label("添加任务", systemImage: "plus") }.accessibilityIdentifier("addTask")
                NavigationLink("查看全部任务") { TaskLibraryView() }
            } header: { Text("想完成的事") }

            Section("计划与承诺") {
                if plans.isEmpty { Text("留白也可以是一种安排。") .foregroundStyle(.secondary) }
                ForEach(plans) { plan in
                    NavigationLink { PlanEditor(planID: plan.id) } label: { HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(plan.isCommitment ? Color.orange : Color.teal).frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title).font(.headline)
                            Text("\(plan.start.formatted(date: .omitted, time: .shortened)) – \(plan.end.formatted(date: Calendar.current.isDate(plan.start, inSameDayAs: plan.end) ? .omitted : .abbreviated, time: .shortened))").font(.subheadline).foregroundStyle(.secondary)
                            Text(plan.isCommitment ? "日历承诺 · 仅本机记录" : "私人计划").font(.caption).foregroundStyle(plan.isCommitment ? .orange : .teal)
                        }
                    }.padding(.vertical, 4) }
                }
            }

            Section("实际发生") {
                if sessions.isEmpty { Text("开始计时，留下真实投入。") .foregroundStyle(.secondary) }
                ForEach(sessions) { session in
                    NavigationLink { SessionEditor(sessionID: session.id) } label: { VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(session.title).font(.headline); Spacer(); Text(session.restorePending == true && session.end == nil ? "结束时间未知" : minutesText(clippedSeconds(session.start, session.end ?? Date(), day: day, zone: TimeZone(identifier: session.timeZone) ?? .current))).font(.subheadline.monospacedDigit()) }
                        HStack {
                            Label(session.confirmed ? "已核对" : session.end == nil ? "计时中" : "待核对", systemImage: session.confirmed ? "checkmark.seal" : "clock")
                                .font(.caption).foregroundStyle(session.confirmed ? Color.teal : Color.secondary)
                            Spacer()
                            if session.end != nil && !session.confirmed { Button("确认实际投入") { store.confirmSession(session) }.font(.caption).buttonStyle(.borderless) }
                        }
                    }.padding(.vertical, 5) }
                }
            }

            Section("到访与生活记忆") {
                ForEach(store.data.visits.filter { visit in
                    guard visit.state != "rejected", let date = visit.arrival ?? visit.departure else { return false }
                    let stop = visit.arrival != nil ? visit.departure ?? date.addingTimeInterval(1) : date.addingTimeInterval(1)
                    return overlapsDay(date, stop, day: day, zone: TimeZone(identifier: visit.timeZone) ?? .current)
                }) { visit in NavigationLink { VisitDetailView(visitID: visit.id) } label: { VStack(alignment: .leading, spacing: 4) { VisitRow(visit: visit); Text(visit.state == "confirmed" ? "你已确认到访":"自动候选 · 尚未核对").font(.caption).foregroundStyle(.secondary) } } }
                ForEach(store.data.places.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: day) }) { memory in NavigationLink(memory.title) { MemoryDetailView(memoryID: memory.id) } }
                ForEach(store.data.routes.filter { overlapsDay($0.start, $0.end ?? Date(), day: day) }) { route in NavigationLink(route.title) { RouteDetailView(routeID: route.id) } }
                Text("到访、记忆与路线各守原来的身份，不转成已完成任务或成果。") .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if let review = store.data.reviews.first(where: { $0.day == LifeSnapshot.dayKey(day) && $0.canonical != false }) {
                    Label("今天的复盘已留下", systemImage: "sparkles").foregroundStyle(.teal)
                    Text(review.reflection)
                    NavigationLink("查看与修订") { ReviewDetailView(reviewID: review.id) }
                } else {
                    Button { composer = .review(day) } label: { Label("给这一天写几句话", systemImage: "square.and.pencil") }
                }
            } header: { Text("日落以后") }
        }
        .navigationTitle("今天")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("设置与更新") }
            ToolbarItem(placement: .topBarTrailing) {
                Menu { Button("任务", systemImage: "checkmark.circle") { composer = .task }; Button("私人计划", systemImage: "calendar.badge.plus") { composer = .plan }; Button("生活记录", systemImage: "square.and.pencil") { composer = .review(day) } } label: { Image(systemName: "plus") }.accessibilityLabel("新建")
            }
        }
        .sheet(item: $composer) { ComposerView(kind: $0) }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
    }
    func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.title3.bold()); Text(title).font(.caption).foregroundStyle(.secondary) } }
    func shiftDay(_ amount: Int) { day = Calendar.current.date(byAdding: .day, value: amount, to: day) ?? day }
}

struct PlansView: View {
    @Environment(LifeStore.self) private var store
    @State private var date = Date()
    @State private var add = false
    @State private var calendar = false
    @State private var includeCancelled = false
    var plans: [LifePlan] { store.data.plans.filter { (includeCancelled || !$0.cancelled) && $0.deletedAt == nil && overlapsDay($0.start, $0.end, day: date, zone: TimeZone(identifier: $0.timeZone) ?? .current) }.sorted { $0.start < $1.start } }
    var body: some View {
        List {
            Section { DatePicker("选择日期", selection: $date, displayedComponents: .date).datePickerStyle(.graphical); Toggle("显示已取消安排", isOn: $includeCancelled); Button("读取与导入苹果日历", systemImage: "calendar.badge.clock") { calendar = true } }
            Section("这一天的安排") {
                if plans.isEmpty { ContentUnavailableView("时间，留给重要的事", systemImage: "calendar", description: Text("私人计划与已有承诺分开记录。")) }
                ForEach(plans) { plan in
                    NavigationLink { PlanEditor(planID: plan.id) } label: { VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(plan.title).font(.headline); Spacer(); Image(systemName: plan.isCommitment ? "calendar.badge.clock" : "rectangle.dashed") .foregroundStyle(plan.isCommitment ? .orange : .teal) }
                        Text(plan.start.formatted(date: .omitted, time: .shortened) + " – " + plan.end.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        Text(plan.isCommitment ? "本机承诺记录" : "私人计划 · 不写系统日历").font(.caption).foregroundStyle(.secondary)
                        if plan.cancelled { Text("已取消").foregroundStyle(.secondary) }
                    }.padding(.vertical, 5) }
                        .swipeActions { Button("取消", role: .destructive) { store.cancelPlan(plan) } }
                }
            }
        }.navigationTitle("计划")
            .toolbar { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加计划") }
            .sheet(isPresented: $add) { ComposerView(kind: .plan, initialDate: date) }
            .sheet(isPresented: $calendar) { CalendarImportView() }
    }
}
