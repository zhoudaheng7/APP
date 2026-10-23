import AppIntents
import Foundation

struct StartReceivingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始接收"
    static var description = IntentDescription("打开一甩的接收页，自动寻找之前确认过的设备。")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            UserDefaults.standard.set(true, forKey: "flick.startReceiving")
            NotificationCenter.default.post(name: Notification.Name("FlickStartReceiving"), object: nil)
        }
        return .result()
    }
}
struct FlickShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartReceivingIntent(), phrases: ["用\(.applicationName)接收文件", "打开\(.applicationName)接收"], shortTitle: "开始接收", systemImageName: "square.and.arrow.down")
    }
}
