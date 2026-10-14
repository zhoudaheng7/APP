import SwiftUI
import ReplayKit

struct BroadcastPicker: UIViewRepresentable {
    static var extensionID: String? {
        guard let folder = Bundle.main.builtInPlugInsURL,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for file in files where file.pathExtension == "appex" {
            guard let bundle = Bundle(url: file),
                  let configuration = bundle.infoDictionary?["NSExtension"] as? [String: Any],
                  configuration["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload" else { continue }
            return bundle.bundleIdentifier
        }
        return nil
    }
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        // Re-signers may rewrite bundle IDs. Read the installed extension's actual ID.
        picker.preferredExtension = Self.extensionID
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
