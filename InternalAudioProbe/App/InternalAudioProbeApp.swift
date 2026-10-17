import AudioCore
import AVFoundation
import SwiftUI

@main
struct InternalAudioProbeApp: App {
    @StateObject private var recorder = CaptureController()
    var body: some Scene {
        WindowGroup { RecorderView(recorder: recorder) }
    }
}

