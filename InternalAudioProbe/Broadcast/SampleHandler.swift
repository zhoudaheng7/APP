import AudioCore
import Foundation
import ReplayKit

/// Runs independently of the containing app, including starts from Control Center.
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private var writer: AudioSegmentWriter?
    private var activityTimer: DispatchSourceTimer?
    private var activeMarker: URL?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let root = RecordingPaths.sharedRoot else {
            finishBroadcastWithError(NSError(domain: "InternalAudioProbe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "企业签名未启用录音共享容器。请为主 App 和广播扩展配置相同的 App Group 后重新签名。App 内的开始内录仍可使用。"
            ]))
            return
        }
        do {
            let output = try AudioSegmentWriter(root: root, captureSource: "control-center")
            output.onFatalError = { [weak self] message in
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.finishBroadcastWithError(NSError(domain: "InternalAudioProbe", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: message]))
                }
            }
            writer = output
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
        case .audioApp: writer?.append(sampleBuffer)
        case .video: writer?.discardVideoFrame()
        case .audioMic: break // Ignore microphone samples even if the system toggle was turned on.
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
        output.finish { _ in completed.signal() }
        _ = completed.wait(timeout: .now() + 8)
    }
}
