import ActivityKit
import AppIntents
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var message: String
    }
    let sessionID: String
    let startedAt: Date
    let microphone: Bool
}

struct StopRecordingIntent: LiveActivityIntent, AudioRecordingIntent {
    static var title: LocalizedStringResource = "停止声屿录音"
    static var description = IntentDescription("结束指定的声屿录音并保存音频。")
    static var openAppWhenRun = false
    @Parameter(title: "录音标识") var sessionID: String
    init() {}
    init(sessionID: String) { self.sessionID = sessionID }
    @MainActor
    func perform() async throws -> some IntentResult {
#if WIDGET_EXTENSION
        // LiveActivityIntent must be dispatched to the host app. Never report a
        // successful stop if the system unexpectedly executes this extension copy.
        throw RecordingIntentError.hostRequired
#else
        try await CaptureController.shared.stopFromActivity(sessionID: sessionID)
#endif
        return .result()
    }
}

private enum RecordingIntentError: LocalizedError {
    case hostRequired
    var errorDescription: String? { "请打开声屿停止录音；当前无法连接主程序。" }
}
