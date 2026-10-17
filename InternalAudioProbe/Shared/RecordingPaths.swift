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

    static var microphonePreference: Bool {
        get { UserDefaults(suiteName: groupIdentifier)?.bool(forKey: "nextRecordingMicrophone") ?? false }
        set { UserDefaults(suiteName: groupIdentifier)?.set(newValue, forKey: "nextRecordingMicrophone") }
    }
}
