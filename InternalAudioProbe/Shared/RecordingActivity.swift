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
#if !WIDGET_EXTENSION
        try await CaptureController.shared.stopFromActivity(sessionID: sessionID)
#endif
        return .result()
    }
}
