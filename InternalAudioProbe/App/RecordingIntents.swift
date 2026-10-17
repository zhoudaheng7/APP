import AppIntents
import Foundation

enum RecordingChoice: String, AppEnum {
    case internalOnly, withMicrophone
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "录音模式"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .internalOnly: "仅内部音", .withMicrophone: "内部音＋麦克风"
    ]
}

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始声屿内录"
    static var description = IntentDescription("选择仅内部音或加入麦克风，然后确认系统采集授权。")
    static var openAppWhenRun = true
    @Parameter(title: "录音模式", default: .internalOnly) var mode: RecordingChoice
    init() {}
    init(mode: RecordingChoice) { self.mode = mode }
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await CaptureController.shared.prepareStart(microphone: mode == .withMicrophone)
        return .result(dialog: "请在系统选择器中确认开始采集。")
    }
}

struct OpenRecordingMenuIntent: AppIntent {
    static var title: LocalizedStringResource = "声屿快捷菜单"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        CaptureController.shared.showQuickMenu = true
        return .result()
    }
}

struct StartInternalAudioIntent: AppIntent {
    static var title: LocalizedStringResource = "仅内部音"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await CaptureController.shared.prepareStart(microphone: false)
        return .result(dialog: "请确认系统采集授权。麦克风关闭。")
    }
}

struct StartMixedAudioIntent: AppIntent {
    static var title: LocalizedStringResource = "内部音＋麦克风"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await CaptureController.shared.prepareStart(microphone: true)
        return .result(dialog: "请确认系统采集授权。将混合内部音与麦克风。")
    }
}

struct RecordingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenRecordingMenuIntent(), phrases: ["打开\(.applicationName)录音菜单"], shortTitle: "录音菜单", systemImageName: "waveform")
        AppShortcut(intent: StartInternalAudioIntent(), phrases: ["用\(.applicationName)内录"], shortTitle: "仅内部音", systemImageName: "record.circle")
        AppShortcut(intent: StartMixedAudioIntent(), phrases: ["用\(.applicationName)混音录音"], shortTitle: "内部音＋麦克风", systemImageName: "mic")
    }
}
