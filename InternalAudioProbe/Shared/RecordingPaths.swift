import Foundation

enum RecordingPaths {
    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AudioAppGroupIdentifier") as? String
            ?? "group.com.lightsquare.internalaudioprobe"
    }

    static var sharedRoot: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("Recordings", isDirectory: true)
    }
}
