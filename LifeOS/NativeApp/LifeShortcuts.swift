import AppIntents
import Foundation

struct CaptureTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "记下一件任务"
    static var description = IntentDescription("在朝屿本机任务中保存，不创建日历事件。")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "任务内容") var title: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LifeStore.shared
        guard store.ready, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, store.addTask(title: title, note: "由你通过快捷指令记录", goalID: nil) else { throw LifeError.message(store.error ?? "没有保存，请打开朝屿检查。") }
        return .result(dialog: "已在朝屿记下这件任务。")
    }
}

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "开始一段投入"
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "这段时间投入什么") var activity: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LifeStore.shared
        guard store.startSession(title: activity) else { throw LifeError.message(store.error ?? "请先检查朝屿中的当前计时。") }
        return .result(dialog: "已开始计时，结束后还需要核对实际投入。")
    }
}

struct EndFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "结束当前投入"
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LifeStore.shared
        guard store.ready, store.runningSession != nil else { return .result(dialog: "当前没有正在计时的投入。") }
        store.stopSession()
        guard store.runningSession == nil else { throw LifeError.message("未能保存结束时间，请打开朝屿检查。") }
        return .result(dialog: "已结束计时。请在朝屿中核对记录；任务状态没有自动改变。")
    }
}

struct CaptureReviewDraftIntent: AppIntent {
    static var title: LocalizedStringResource = "记下今天的复盘草稿"
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "想记住的话") var reflection: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LifeError.invalidValue }
        let today = LifeSnapshot.dayKey(Date())
        let existing = LifeStore.shared.data.reviews.first { $0.day == today && $0.timeZone == TimeZone.current.identifier }
        let key = existing.map { "review:" + $0.id.uuidString } ?? "review-" + today
        var draft = EditorDrafts.load(key) ?? [:]
        let field = existing == nil ? "note" : "text"
        draft[field] = [draft[field] ?? existing?.reflection, reflection].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        if draft["mood"] == nil { draft["mood"] = existing?.mood.map(String.init) ?? "" }
        try EditorDrafts.write(key, fields: draft)
        return .result(dialog: "已保留今天的复盘草稿，请在朝屿打开并确认保存。")
    }
}

// These four discoverable actions are available in the Shortcuts action library.
// Automatic Siri phrases require NLU trained for the final signed bundle identity;
// the cloud product intentionally uses a generic identity, so it must not ship
// a stale generic-bundle NLU model after local signing.
