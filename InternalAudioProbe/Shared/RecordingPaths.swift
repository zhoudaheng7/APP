import Foundation

enum RecordingPaths {
    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AudioAppGroupIdentifier") as? String
            ?? ""
    }

    private static var hasConfiguredGroup: Bool {
        let value = groupIdentifier
        return value.hasPrefix("group.") && value.count > 6 &&
            !value.contains("$(") && !value.contains("*") &&
            value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    private static var groupSubdirectory: String? {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "AudioAppGroupSubdirectory") else { return "" }
        guard let value = configured as? String, value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"),
              value.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { return nil }
        return value
    }

    static var sharedRoot: URL? {
        guard hasConfiguredGroup, let subdirectory = groupSubdirectory,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        else { return nil }
        let scoped = subdirectory.isEmpty ? container : container.appendingPathComponent(subdirectory, isDirectory: true)
        return scoped.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Call explicitly before recording or when checking storage, never from a view render.
    /// Only the configured, system-authorized group is used; extension-local storage is not shared.
    static func verifySharedAccess() throws -> URL {
        guard hasConfiguredGroup, groupSubdirectory != nil else { throw SharedAccessError.configuration }
        guard let root = sharedRoot else { throw SharedAccessError.authorization }
        let files = FileManager.default
        let probe = root.appendingPathComponent(".access-\(UUID().uuidString)")
        defer { try? files.removeItem(at: probe) }
        do {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            let expected = Data(UUID().uuidString.utf8)
            try expected.write(to: probe, options: .atomic)
            guard try Data(contentsOf: probe) == expected else { throw SharedAccessError.storage }
            try files.removeItem(at: probe)
            return root
        } catch {
            throw SharedAccessError.storage
        }
    }

    enum SharedAccessError: LocalizedError {
        case configuration, authorization, storage

        var errorDescription: String? {
            switch self {
            case .configuration: return "共享配置无效，请重新签名"
            case .authorization: return "签名未启用共享存储"
            case .storage: return "共享存储不可写，请检查空间或签名"
            }
        }
    }

    private static var preferences: UserDefaults {
        // App-only recording can still remember its mode when shared signing is unavailable.
        guard sharedRoot != nil else { return .standard }
        return UserDefaults(suiteName: groupIdentifier) ?? .standard
    }

    private static var microphonePreferenceKey: String {
        guard let subdirectory = groupSubdirectory, !subdirectory.isEmpty else { return "nextRecordingMicrophone" }
        return "\(subdirectory).nextRecordingMicrophone"
    }

    static var microphonePreference: Bool {
        get { preferences.bool(forKey: microphonePreferenceKey) }
        set { preferences.set(newValue, forKey: microphonePreferenceKey) }
    }
}
