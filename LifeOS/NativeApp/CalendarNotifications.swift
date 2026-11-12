import SwiftUI
import EventKit
import EventKitUI
import UserNotifications
import Observation

@MainActor @Observable final class LifeCalendar {
    let eventStore = EKEventStore()
    var events: [EKEvent] = []
    var message = ""
    var loading = false
    func readEvents(on day: Date) async {
        loading = true; defer { loading = false }
        do {
            var allowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess
            if !allowed { allowed = try await eventStore.requestFullAccessToEvents() }
            guard allowed else { message = "未取得读取权限。你仍可使用私人计划，或通过系统编辑器单独创建事件。"; return }
            let start = Calendar.current.startOfDay(for: day)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
            message = events.isEmpty ? "这一天未读取到事件。" : "选择事件后才会保存为朝屿中的承诺。"
        } catch { message = "读取失败，未修改系统日历。" }
    }
}

extension LifeStore {
    @discardableResult func recordCalendarSave(plan: LifePlan, eventIdentifier: String, calendarIdentifier: String, linkID: UUID? = nil) -> Bool {
        let existing = data.calendarLinks.first { (linkID != nil && $0.id == linkID) || (!eventIdentifier.isEmpty && $0.eventIdentifier == eventIdentifier) || ($0.sourcePlanID == plan.id && $0.status == "saved-unresolved") }
        let commitmentID = existing?.planID ?? (plan.isCommitment ? plan.id : UUID())
        return commit(kind: "calendar.user-saved", id: commitmentID) { state in
            if !state.plans.contains(where: { $0.id == commitmentID }) {
                var commitment = LifePlan(id: commitmentID, title: plan.title, taskID: plan.taskID, start: plan.start, end: plan.end, timeZone: plan.timeZone, isCommitment: true)
                commitment.note = plan.note; commitment.allDay = plan.allDay; state.plans.append(commitment)
            } else if let i = state.plans.firstIndex(where: { $0.id == commitmentID }) {
                try state.audit(state.plans[i], id: commitmentID, kind: "plan", revision: state.plans[i].revision)
                state.plans[i].title = plan.title; state.plans[i].start = plan.start; state.plans[i].end = plan.end; state.plans[i].allDay = plan.allDay
                state.plans[i].note = plan.note; state.plans[i].timeZone = plan.timeZone; state.plans[i].cancelled = false; state.plans[i].revision += 1
            }
            if let existing, let i = state.calendarLinks.firstIndex(where: { $0.id == existing.id }) {
                state.calendarLinks[i].eventIdentifier = eventIdentifier; state.calendarLinks[i].calendarIdentifier = calendarIdentifier; state.calendarLinks[i].status = eventIdentifier.isEmpty ? "saved-unresolved" : "saved"; state.calendarLinks[i].observedAt = Date()
            } else {
                state.calendarLinks.append(CalendarLink(planID: commitmentID, eventIdentifier: eventIdentifier, calendarIdentifier: calendarIdentifier, status: eventIdentifier.isEmpty ? "saved-unresolved" : "created", sourcePlanID: plan.id))
            }
        }
    }
    func importCalendarEvent(title: String, start: Date, end: Date, identifier: String, calendarIdentifier: String, zone: String, allDay: Bool) -> Bool {
        guard !identifier.isEmpty else { error = "系统事件缺少稳定标识，未导入。"; return false }
        if data.calendarLinks.contains(where: { $0.eventIdentifier == identifier }) { return true }
        var plan = LifePlan(title: title, start: start, end: end, timeZone: zone, isCommitment: true); plan.allDay = allDay
        return commit(kind: "calendar.import", id: plan.id) { state in
            state.plans.append(plan)
            state.calendarLinks.append(CalendarLink(planID: plan.id, eventIdentifier: identifier, calendarIdentifier: calendarIdentifier, status: "imported"))
        }
    }
}

struct CalendarEventEditor: UIViewControllerRepresentable {
    @Environment(LifeStore.self) private var life
    @Environment(\.dismiss) private var dismiss
    let plan: LifePlan
    var existingEvent: EKEvent? = nil
    var existingStore: EKEventStore? = nil
    var linkID: UUID? = nil
    func makeCoordinator() -> Coordinator { Coordinator(life: life, plan: plan, events: existingStore ?? EKEventStore(), linkID: linkID, dismiss: { dismiss() }) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController(); controller.eventStore = context.coordinator.events
        let event = existingEvent ?? EKEvent(eventStore: context.coordinator.events)
        if existingEvent == nil { event.title = plan.title; event.startDate = plan.start; event.endDate = plan.end; event.notes = plan.note; event.timeZone = TimeZone(identifier: plan.timeZone); event.isAllDay = plan.allDay ?? false }
        controller.event = event; controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, EKEventEditViewDelegate {
        let events: EKEventStore; let life: LifeStore; let plan: LifePlan; let dismiss: () -> Void; let linkID: UUID?
        init(life: LifeStore, plan: LifePlan, events: EKEventStore, linkID: UUID?, dismiss: @escaping () -> Void) { self.life = life; self.plan = plan; self.events = events; self.linkID = linkID; self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            if action == .saved, let event = controller.event {
                var saved = plan; saved.title = event.title ?? plan.title; saved.start = event.startDate; saved.end = event.endDate; saved.allDay = event.isAllDay; saved.note = event.notes; saved.timeZone = event.timeZone?.identifier ?? plan.timeZone
                if !life.recordCalendarSave(plan: saved, eventIdentifier: event.eventIdentifier ?? "", calendarIdentifier: event.calendar?.calendarIdentifier ?? "", linkID: linkID) { life.error = "系统事件已经保存，但本机映射未能落盘。请先在系统日历核对，不要重复创建。" }
            } else if action == .deleted, let linkID {
                _ = life.commit(kind: "calendar.user-deleted", id: plan.id) { state in
                    if let i = state.calendarLinks.firstIndex(where: { $0.id == linkID }) { state.calendarLinks[i].status = "deleted-system"; state.calendarLinks[i].observedAt = Date() }
                    if let i = state.plans.firstIndex(where: { $0.id == plan.id }) { state.plans[i].cancelled = true; state.plans[i].revision += 1 }
                }
            }
            dismiss()
        }
    }
}

struct CalendarLinkManager: View {
    @Environment(LifeStore.self) private var life
    let link: CalendarLink
    @State private var events = EKEventStore()
    @State private var selected: EKEvent?
    @State private var message = ""
    @State private var reading = false
    @State private var editing = false
    var body: some View {
        List {
            Section("本机保存回执") { LabeledContent("状态", value: link.status); LabeledContent("上次核对", value: link.observedAt.formatted(date: .abbreviated, time: .shortened)); Text("本机承诺与系统事件分开保存。此页只在你主动读取后核对，不宣称持续自动同步。") .font(.caption).foregroundStyle(.secondary) }
            Section {
                Button("授权并核对原系统事件") { Task { await read() } }.disabled(reading || link.eventIdentifier.isEmpty)
                if reading { ProgressView() }; if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                if let selected { Text(selected.title ?? "未命名事件"); Text(selected.startDate.formatted(date: .abbreviated, time: .shortened)); Button("将系统当前值更新到本机承诺") { if let plan = life.data.plans.first(where: { $0.id == link.planID }) { var value = plan; value.title = selected.title ?? plan.title; value.start = selected.startDate; value.end = selected.endDate; value.note = selected.notes; value.allDay = selected.isAllDay; value.timeZone = selected.timeZone?.identifier ?? plan.timeZone; _ = life.recordCalendarSave(plan: value, eventIdentifier: selected.eventIdentifier ?? "", calendarIdentifier: selected.calendar.calendarIdentifier, linkID: link.id) } }; Button("打开系统编辑器修改这个事件") { editing = true } }
                if link.eventIdentifier.isEmpty { Text("系统编辑器已报告保存，但没有可用事件标识。请到苹果日历核对；这里不会重试创建，以免重复。") .font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle("核对系统日历").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { if let selected, let plan = life.data.plans.first(where: { $0.id == link.planID }) { CalendarEventEditor(plan: plan, existingEvent: selected, existingStore: events, linkID: link.id) } }
    }
    func read() async {
        reading = true; defer { reading = false }
        do {
            let allowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? true : try await events.requestFullAccessToEvents()
            guard allowed else { message = "未获读取许可；原回执和私人计划已保留。"; return }
            selected = events.event(withIdentifier: link.eventIdentifier)
            message = selected == nil ? "当前找不到原事件。它可能已删除、移动或所属日历不可用；未自动重建或删除本机记录。" : "已读取原事件，是否更新或修改由你选择。"
        } catch { message = "读取失败，未修改任何事件。" }
    }
}

struct CalendarImportView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var service = LifeCalendar()
    @State private var day = Date()
    var body: some View {
        NavigationStack { List {
            Section { DatePicker("读取日期", selection: $day, displayedComponents: .date); Button("授权并读取这一天的日历") { Task { await service.readEvents(on: day) } }.disabled(service.loading); if service.loading { ProgressView() }; if !service.message.isEmpty { Text(service.message).font(.caption).foregroundStyle(.secondary) } }
            ForEach(Array(service.events.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title ?? "未命名事件").font(.headline)
                    Text(event.startDate.formatted(date: .abbreviated, time: .shortened) + " – " + event.endDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if store.data.calendarLinks.contains(where: { $0.eventIdentifier == event.eventIdentifier }) { Label("已记录为承诺", systemImage: "checkmark.circle").font(.caption) }
                    else { Button("记为本机日历承诺") { _ = store.importCalendarEvent(title: event.title ?? "未命名事件", start: event.startDate, end: event.endDate, identifier: event.eventIdentifier ?? "", calendarIdentifier: event.calendar.calendarIdentifier, zone: event.timeZone?.identifier ?? TimeZone.current.identifier, allDay: event.isAllDay) } }
                }.padding(.vertical, 4)
            }
            Section { Text("读取与导入不会修改系统事件，也不会创建实际投入或完成任务。系统事件后续变化需重新核对，本机承诺不冒充持续实时同步。") .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("苹果日历").navigationBarTitleDisplayMode(.inline).toolbar { Button("完成") { dismiss() } } }
    }
}

@MainActor @Observable final class LifeNotifications {
    static let shared = LifeNotifications()
    var message = ""
    func authorize(plans: [LifePlan]) async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if granted { await reschedule(plans); message = "本地提醒已启用，按每个计划的提醒设置安排。" }
            else { message = "通知未获允许，计划已保留；可以在 iPhone 设置中修改。" }
        } catch { message = "无法启用通知，计划未受影响。" }
    }
    func reschedule(_ plans: [LifePlan]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let previous = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: previous.filter { $0.identifier.hasPrefix("dayisle.plan.") }.map(\.identifier))
        let candidates = plans.filter { !$0.cancelled && $0.deletedAt == nil && $0.reminderMinutes != nil && $0.start.addingTimeInterval(-Double($0.reminderMinutes!) * 60) > Date() }.sorted { $0.start < $1.start }.prefix(60)
        for plan in candidates {
            let content = UNMutableNotificationContent(); content.title = "朝屿 · 计划提醒"; content.body = "你有一个安排即将开始，打开朝屿查看。"; content.sound = .default
            // Lock-screen content deliberately excludes the title and location.
            let interval = max(1, plan.start.addingTimeInterval(-Double(plan.reminderMinutes!) * 60).timeIntervalSinceNow)
            let request = UNNotificationRequest(identifier: "dayisle.plan." + plan.id.uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            do { try await center.add(request) } catch { message = "部分提醒未能安排，计划已保留。" }
        }
    }
}
