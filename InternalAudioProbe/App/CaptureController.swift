import AudioCore
import ActivityKit
import AVFoundation
import Combine
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
import SwiftUI

@MainActor
final class CaptureController: NSObject, ObservableObject {
    static let shared = CaptureController()
    enum Phase: String { case idle, selecting, starting, recording, stopping }
    @Published var phase: Phase = .idle
    @Published var status = "就绪"
    @Published var report: SessionReport?
    @Published var sessions: [SavedSession] = []
    @Published var inspection = ""
    @Published var controlCenterStatus = ""
    @Published var checks: [UUID: AudioCheck] = [:]
    @Published var libraryWorking = false
    @Published var libraryMessage = ""
    @Published var externalRecording = false
    @Published var microphoneEnabled = false
    @Published private(set) var microphoneInterrupted = false
    @Published private(set) var controlCenterAvailable = false
    @Published private(set) var controlCenterIssue: String?
    @Published var showQuickMenu = false
    private var writer: AudioSegmentWriter?
    private var mixer: AudioMixWriter?
    private var microphone: MicrophoneCapture?
    private var liveActivity: Activity<RecordingActivityAttributes>?
    private var interruptionObserver: NSObjectProtocol?
#if canImport(ScreenCaptureKit)
    private var stream: SCStream?
    private var sink: AudioSink?
    private var ownsPicker = false
    private var captureAttempt: UUID?
#endif
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let recordingFeedback = RecordingFeedback()
    let root: URL

    override init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        super.init()
        microphoneEnabled = RecordingPaths.microphonePreference
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.handleMicrophoneInterruption(notification)
                }
            }
        refreshSessions()
    }

    func start() {
        Task { do { try await prepareStart(microphone: microphoneEnabled) } catch { status = error.localizedDescription } }
    }

    func prepareStart(microphone enabled: Bool) async throws {
        refreshSessions()
        guard phase == .idle, !libraryWorking, !externalRecording else { throw StartError.busy }
        phase = .starting
        report = nil
        inspection = ""
        microphoneEnabled = enabled
        microphoneInterrupted = false
        RecordingPaths.microphonePreference = enabled
        if enabled {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else { phase = .idle; throw StartError.permission }
        }
#if canImport(ScreenCaptureKit)
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else { phase = .idle; throw StartError.unavailable }
        guard !picker.isActive else { phase = .idle; throw StartError.busy }
        phase = .selecting
        status = "请确认开始录制"
        report = nil
        inspection = ""
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        ownsPicker = true
        picker.isActive = true
        picker.present()
#else
        phase = .idle
        status = "请在 iPhone 上录制"
#endif
    }

#if canImport(ScreenCaptureKit)
    private func begin(with filter: SCContentFilter) async {
        guard phase == .selecting else { return }
        phase = .starting
        let attempt = UUID()
        captureAttempt = attempt
        do {
            let output = try AudioSegmentWriter(root: root, microphoneRequested: microphoneEnabled)
            writer = output
            output.onUpdate = { [weak self, weak output] value in
                Task { @MainActor in
                    guard let self, let output, self.writer === output else { return }
                    self.report = value
                }
            }
            output.onFatalError = { [weak self, weak output] message in
                Task { @MainActor in
                    guard let self, let output, self.writer === output else { return }
                    await self.stop(reason: message)
                }
            }
            let mix = microphoneEnabled ? AudioMixWriter(writer: output) : nil
            mix?.onError = output.onFatalError
            mixer = mix
            let sink = AudioSink(writer: output, mixer: mix)
            self.sink = sink
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            let capture = SCStream(filter: filter, configuration: configuration, delegate: sink)
            sink.onStopped = { [weak self, weak output] error in
                Task { @MainActor in
                    guard let self, let output, self.writer === output else { return }
                    await self.stop(reason: error)
                }
            }
            // Receive screen callbacks only as a discard sink; never construct a video encoder.
            try capture.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.callbackQueue)
            try capture.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.callbackQueue)
            stream = capture
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                liveActivity = try? Activity.request(attributes: RecordingActivityAttributes(
                    sessionID: output.folder.lastPathComponent, startedAt: Date(), microphone: microphoneEnabled),
                    content: ActivityContent(state: .init(message: "录制中"), staleDate: nil), pushType: nil)
            }
            try await capture.startCapture()
            guard phase == .starting, writer === output else { try? await capture.stopCapture(); return }
            if let mix {
                let mic = MicrophoneCapture()
                microphone = mic
                do { try mic.start(mixer: mix) }
                catch { microphoneInterrupted = true }
            }
            guard phase == .starting else { return }
            phase = .recording
            recordingFeedback.started()
            status = microphoneInterrupted ? "录制中 · 麦克风已暂停" : "录制中"
            if liveActivity == nil { status += " · 请从 App 或系统停止" }
            // Keep the picker active for the entire stream, including when backgrounded.
            // Deactivating it here relinquishes management of the ongoing system capture.
        } catch {
            guard captureAttempt == attempt else { return }
            await stop(reason: Self.captureError(error, prefix: "启动失败"))
        }
    }
#endif

    func stop(reason: String? = nil) async {
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
#if canImport(ScreenCaptureKit)
        captureAttempt = nil
#endif
        status = "正在保存…"
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FinalizeAudio") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
#if canImport(ScreenCaptureKit)
        if let stream {
            // The system Stop button can stop the stream before its delegate runs.
            try? await stream.stopCapture()
        }
        stream = nil
        if let sink {
            await withCheckedContinuation { continuation in
                sink.callbackQueue.async { continuation.resume() }
            }
        }
        sink = nil
        // Match the system capture lifetime: stop/drain the stream before removing its picker.
        releasePicker()
#endif
        microphone?.stop()
        microphone = nil
        guard let writer else {
            recordingFeedback.stopped()
            phase = .idle
            status = reason ?? "已取消。"
            endBackgroundTask()
            return
        }
        self.writer = nil
        let mix = mixer
        mixer = nil
        let completed = await withCheckedContinuation { continuation in
            let completion: @Sendable (SessionReport) -> Void = { value in continuation.resume(returning: value) }
            if let mix { mix.finish(reason: reason, completion: completion) }
            else { writer.finish(reason: reason, completion: completion) }
        }
        recordingFeedback.stopped()
        if let liveActivity {
            let message = completed.segments.contains(where: { $0.state == "complete" }) ? "已保存" : "录音需检查"
            await liveActivity.end(ActivityContent(state: .init(message: message), staleDate: nil), dismissalPolicy: .immediate)
            self.liveActivity = nil
        }
        report = completed
        phase = .idle
        microphoneInterrupted = false
        switch completed.state {
        case "no-audio": status = "未收到声音，请检查音源"
        case "silent": status = "录音为静音，请检查音源"
        case "interrupted": status = "录制中断：\(completed.error ?? "请检查录音")"
        default: status = "已保存"
        }
        if completed.microphoneRequested == true && !completed.microphoneRecorded { status += " · 未收到麦克风声音" }
        refreshSessions()
        if let session = sessions.first(where: { $0.id == completed.id }) { await inspect(session) }
        endBackgroundTask()
    }

    func stopFromActivity(sessionID: String) async throws {
        guard writer?.folder.lastPathComponent == sessionID, [.starting, .recording].contains(phase) else {
            // Dismiss an obsolete activity after system termination; do not stop another session.
            for activity in Activity<RecordingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            throw StartError.noActiveRecording
        }
        await stop()
    }

    enum StartError: LocalizedError {
        case busy, permission, unavailable, noActiveRecording
        var errorDescription: String? {
            switch self {
            case .busy: return "请先结束当前操作"
            case .permission: return "请在设置中允许麦克风访问，或选择仅内部音"
            case .unavailable: return "无法开启录制"
            case .noActiveRecording: return "录音已结束，请返回查看"
            }
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func handleMicrophoneInterruption(_ notification: Notification) {
        guard microphoneEnabled, phase == .recording, let mixer,
              let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            microphone?.pause()
            microphoneInterrupted = true
            status = "录制中 · 麦克风已暂停"
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            guard AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) else { return }
            do {
                try microphone?.start(mixer: mixer)
                microphoneInterrupted = microphone == nil
                status = microphoneInterrupted ? "录制中 · 麦克风已暂停" : "录制中"
            } catch {
                microphoneInterrupted = true
                status = "录制中 · 麦克风已暂停"
            }
        @unknown default: break
        }
    }

    private static func captureError(_ error: Error, prefix: String) -> String {
        let value = error as NSError
        return "\(prefix)：\(value.localizedDescription) [\(value.domain):\(value.code)]"
    }

#if canImport(ScreenCaptureKit)
    private func releasePicker() {
        guard ownsPicker else { return }
        ownsPicker = false
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
    }
#endif

    func refreshSessions() {
        var roots = [root]
        do {
            let sharedRoot = try RecordingPaths.verifySharedAccess()
            roots.append(sharedRoot)
            controlCenterAvailable = true
            controlCenterIssue = nil
            controlCenterStatus = "停止后可试听和导出"
        } catch {
            controlCenterAvailable = false
            controlCenterIssue = error.localizedDescription
            controlCenterStatus = "控制中心暂不可用"
        }
        let folders = roots.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        sessions = folders.compactMap { folder in
            guard let report = try? SessionReport.load(from: folder) else { return nil }
            return SavedSession(report: report, folder: folder)
        }.sorted { $0.report.startedAt > $1.report.startedAt }
        externalRecording = sessions.contains { $0.isActive }
    }

    func inspect(_ session: SavedSession) async {
        guard checks[session.id]?.checking != true else { return }
        checks[session.id] = AudioCheck(checking: true, passed: false, message: "检查中…")
        var audio = 0, video = 0
        var errors: [String] = []
        for url in session.audioFiles {
            do {
                let asset = AVURLAsset(url: url)
                audio += try await asset.loadTracks(withMediaType: .audio).count
                video += try await asset.loadTracks(withMediaType: .video).count
            } catch { errors.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        let message: String
        if !errors.isEmpty { message = "文件检查失败：" + errors.joined(separator: "；") }
        else if audio == 0 { message = "未发现音轨" }
        else if video > 0 { message = "含 \(video) 条视频轨" }
        else { message = "\(audio)音轨 · 无视频" }
        inspection = message
        checks[session.id] = AudioCheck(checking: false, passed: errors.isEmpty && audio > 0 && video == 0, message: message)
        // Inspection JSON is metadata only; never includes captured samples or credentials.
        let result: [String: Any] = ["audioTracks": audio, "videoTracks": video, "errors": errors,
                                     "checkedAt": ISO8601DateFormatter().string(from: Date())]
        do {
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: session.folder.appendingPathComponent("inspection.json"), options: .atomic)
        } catch { inspection += " 保存检查记录失败：\(error.localizedDescription)" }
    }

    func merge(ids: Set<UUID>) async {
        guard phase == .idle, !libraryWorking else { return }
        let chosen = sessions.filter { ids.contains($0.id) }.sorted { $0.report.startedAt < $1.report.startedAt }
        guard !chosen.isEmpty, chosen.allSatisfy({ !$0.isActive && !$0.audioFiles.isEmpty }),
              chosen.flatMap(\.audioFiles).count > 1 else {
            libraryMessage = "请选择至少两份完整音频"
            return
        }
        libraryWorking = true
        libraryMessage = "正在合并…"
        defer { libraryWorking = false }
        do {
            _ = try await RecordingLibrary.merge(files: chosen.flatMap(\.audioFiles), sourceIDs: chosen.map(\.id), root: root)
            refreshSessions()
            libraryMessage = "已合并，原件保留"
        } catch { libraryMessage = "合并失败：\(error.localizedDescription)" }
    }

    func delete(ids: Set<UUID>) {
        guard phase == .idle, !libraryWorking else { return }
        let chosen = sessions.filter { ids.contains($0.id) }
        var roots = [root]
        if let shared = RecordingPaths.sharedRoot { roots.append(shared) }
        var failures: [String] = []
        for session in chosen {
            do {
                try RecordingLibrary.deleteSession(folder: session.folder, allowedRoots: roots)
                checks.removeValue(forKey: session.id)
            } catch { failures.append(error.localizedDescription) }
        }
        refreshSessions()
        libraryMessage = failures.isEmpty ? "" : "部分录音删除失败：\(failures.joined(separator: "；"))"
    }
}

struct AudioCheck {
    let checking: Bool
    let passed: Bool
    let message: String
}

#if canImport(ScreenCaptureKit)
extension CaptureController: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        // iOS has no SCStream.updateContentFilter API. This app presents the picker
        // only before recording; callbacks for an existing stream must not restart it.
        guard stream == nil else { return }
        Task { @MainActor in
            await self.begin(with: filter)
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            guard self.phase == .selecting else { return }
            self.releasePicker()
            self.phase = .idle
            self.status = "已取消"
        }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in await self.stop(reason: Self.captureError(error, prefix: "无法开启录制")) }
    }
}

private final class AudioSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let callbackQueue = DispatchQueue(label: "com.lightsquare.capture-callbacks", qos: .userInitiated)
    let writer: AudioSegmentWriter
    let mixer: AudioMixWriter?
    var onStopped: (@Sendable (String?) -> Void)?
    init(writer: AudioSegmentWriter, mixer: AudioMixWriter?) { self.writer = writer; self.mixer = mixer }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            if let mixer { mixer.append(sampleBuffer, track: .app) }
            else { writer.append(sampleBuffer) }
        }
        else if type == .screen { writer.discardVideoFrame() }
        // Microphone output is never registered or consumed.
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let systemError = error as NSError
        if systemError.domain == SCStreamError.errorDomain && systemError.code == SCStreamError.Code.userStopped.rawValue {
            onStopped?(nil)
        } else {
            onStopped?("系统采集已结束：\(systemError.localizedDescription) [\(systemError.domain):\(systemError.code)]")
        }
    }
}
#endif

struct SavedSession: Identifiable {
    let report: SessionReport
    let folder: URL
    var id: UUID { report.id }
    let isActive: Bool
    let audioFiles: [URL]
    let audioBytes: Int64
    init(report: SessionReport, folder: URL) {
        self.report = report
        self.folder = folder
        isActive = RecordingLibrary.isActive(folder: folder)
        let files = RecordingFiles.audioForExport(report: report, folder: folder)
        audioFiles = files
        audioBytes = files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    var exportFiles: [URL] {
        audioFiles
    }
}
