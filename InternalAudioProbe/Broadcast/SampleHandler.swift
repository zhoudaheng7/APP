import AudioCore
import Foundation
import ReplayKit

/// Runs independently of the containing app, including starts from Control Center.
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private var writer: AudioSegmentWriter?
    private var mixer: AudioMixWriter?
    private var activityTimer: DispatchSourceTimer?
    private var activeMarker: URL?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        do {
            let root = try RecordingPaths.verifySharedAccess()
            let useMic = RecordingPaths.microphonePreference
            let output = try AudioSegmentWriter(root: root, captureSource: "control-center", microphoneRequested: useMic)
            output.onFatalError = { [weak self] message in
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.finishBroadcastWithError(NSError(domain: "InternalAudioProbe", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: message]))
                }
            }
            writer = output
            if useMic {
                let mix = AudioMixWriter(writer: output)
                mix.onError = output.onFatalError
                mixer = mix
            }
            let marker = output.folder.appendingPathComponent(".active")
            try Data().write(to: marker)
            activeMarker = marker
            let heartbeat = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            heartbeat.schedule(deadline: .now(), repeating: 2)
            heartbeat.setEventHandler {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: marker.path)
            }
            heartbeat.resume()
            activityTimer = heartbeat
        } catch {
            finishBroadcastWithError(error)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .audioApp:
            if let mixer { mixer.append(sampleBuffer, track: .app) }
            else { writer?.append(sampleBuffer) }
        case .video: writer?.discardVideoFrame()
        case .audioMic: mixer?.append(sampleBuffer, track: .microphone)
        @unknown default: break
        }
    }

    override func broadcastFinished() {
        activityTimer?.cancel()
        activityTimer = nil
        defer {
            if let activeMarker { try? FileManager.default.removeItem(at: activeMarker) }
            activeMarker = nil
        }
        guard let output = writer else { return }
        writer = nil
        // ReplayKit can tear down the extension after this callback returns. Finish on the
        // independent writer queue, with a bounded wait; finalized earlier parts stay safe.
        let completed = DispatchSemaphore(value: 0)
        if let mixer { mixer.finish { _ in completed.signal() } }
        else { output.finish { _ in completed.signal() } }
        mixer = nil
        _ = completed.wait(timeout: .now() + 8)
    }
}
