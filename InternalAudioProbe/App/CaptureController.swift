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
    @Published var status = "准备好后点开始，再切到课程或其他播放 App。"
    @Published var report: SessionReport?
    @Published var sessions: [SavedSession] = []
    @Published var inspection = ""
    @Published var controlCenterStatus = ""
    @Published var checks: [UUID: AudioCheck] = [:]
    @Published var libraryWorking = false
    @Published var libraryMessage = ""
    @Published var externalRecording = false
    @Published var microphoneEnabled = false
    @Published var showQuickMenu = false
    @Published var showCallInfo = false
    private var writer: AudioSegmentWriter?
    private var mixer: AudioMixWriter?
    private var microphone: MicrophoneCapture?
    private var liveActivity: Activity<RecordingActivityAttributes>?
    private var interruptionObserver: NSObjectProtocol?
#if canImport(ScreenCaptureKit)
    private var stream: SCStream?
    private var sink: AudioSink?
    private var ownsPicker = false
#endif
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    let root: URL

    override init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in
                    guard let self, self.microphoneEnabled, self.phase == .recording else { return }
                    await self.stop(reason: "麦克风被通话或系统中断，已保存收到的音频。")
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
        microphoneEnabled = enabled
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
        status = "请在系统选择器中允许采集；本程序不保存画面。"
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
        status = "模拟器不支持系统内录；请在 iPhone 真机录音。这里可验证录音库与播放界面。"
#endif
    }

#if canImport(ScreenCaptureKit)
    private func begin(with filter: SCContentFilter) async {
        guard phase == .selecting else { return }
        phase = .starting
        do {
            let output = try AudioSegmentWriter(root: root, microphoneRequested: microphoneEnabled)
            writer = output
            output.onUpdate = { [weak self] value in
                Task { @MainActor in self?.report = value }
            }
            output.onFatalError = { [weak self] message in
                Task { @MainActor in await self?.stop(reason: message) }
            }
            let mix = microphoneEnabled ? AudioMixWriter(writer: output) : nil
            mix?.onError = output.onFatalError
            mixer = mix
            let sink = AudioSink(writer: output, mixer: mix)
            self.sink = sink
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            let capture = SCStream(filter: filter, configuration: configuration, delegate: sink)
            sink.onStopped = { [weak self] error in
                Task { @MainActor in await self?.stop(reason: error) }
            }
            // Receive screen callbacks only as a discard sink; never construct a video encoder.
            try capture.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.callbackQueue)
            try capture.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.callbackQueue)
            stream = capture
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                liveActivity = try Activity.request(attributes: RecordingActivityAttributes(
                    sessionID: output.folder.lastPathComponent, startedAt: Date(), microphone: microphoneEnabled),
                    content: ActivityContent(state: .init(message: "正在录制 · 长按灵动岛可停止"), staleDate: nil), pushType: nil)
            }
            try await capture.startCapture()
            if let mix {
                let mic = MicrophoneCapture()
                microphone = mic
                try mic.start(mixer: mix)
            }
            guard phase == .starting else { return }
            phase = .recording
            status = microphoneEnabled ? "正在录内部音＋麦克风；画面不保存。" : "正在录内部音；麦克风关闭，画面不保存。"
            if liveActivity == nil { status += " 灵动岛状态未启用，请从 App 或系统停止。" }
            releasePicker()
        } catch {
            await stop(reason: "启动失败：\(error.localizedDescription)")
        }
    }
#endif

    func stop(reason: String? = nil) async {
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
        status = "正在完成音频分段，请稍候。"
#if canImport(ScreenCaptureKit)
        releasePicker()
#endif
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
#endif
        microphone?.stop()
        microphone = nil
        guard let writer else {
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
        if let liveActivity {
            await liveActivity.end(ActivityContent(state: .init(message: "已停止并保存"), staleDate: nil), dismissalPolicy: .immediate)
            self.liveActivity = nil
        }
        report = completed
        phase = .idle
        switch completed.state {
        case "no-audio": status = "未收到内部音频。请确认来源正在播放，或换一个 App 验证。"
        case "silent": status = "收到的内部音频持续静音；这次不能算内录成功。"
        case "interrupted": status = "录制中断：\(completed.error ?? "请查看分段状态")"
        default: status = "已保存纯音频。试听后再确认这次录制是否成功。"
        }
        if completed.microphoneRequested == true && !completed.microphoneRecorded { status += " 注意：未收到麦克风音频。" }
        refreshSessions()
        if let session = sessions.first(where: { $0.id == completed.id }) { await inspect(session) }
        endBackgroundTask()
    }

    func stopFromActivity(sessionID: String) async throws {
        guard writer?.folder.lastPathComponent == sessionID, phase == .recording else {
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
            case .busy: return "已有录音或其他操作进行中，请先停止。"
            case .permission: return "麦克风权限未开启。请在设置中允许声屿访问麦克风，或选择仅内部音。"
            case .unavailable: return "当前设备无法打开系统采集选择器。"
            case .noActiveRecording: return "这条录音已停止或系统已结束采集，请打开声屿检查保存结果。"
            }
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
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
        if let sharedRoot = RecordingPaths.sharedRoot {
            roots.append(sharedRoot)
            controlCenterStatus = "停止控制中心录音后，回到这里即可试听和导出。"
        } else {
            controlCenterStatus = "控制中心入口需要企业签名保留扩展和共享容器权限。若启动提示共享容器错误，请联系签名服务；App 内开始内录仍可使用。"
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
        checks[session.id] = AudioCheck(checking: true, passed: false, message: "正在读取音频文件并检查轨道…")
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
        else if audio == 0 { message = "未发现可检查的音轨。" }
        else if video > 0 { message = "异常：文件含 \(video) 条视频轨，验证未通过。" }
        else { message = "文件轨道检查：\(audio) 条音轨，0 条视频轨。仍需试听确认内容。" }
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
            libraryMessage = "请选择至少两份完整音频；正在录制的记录请先停止。"
            return
        }
        libraryWorking = true
        libraryMessage = "正在合并音频，原记录会保留…"
        defer { libraryWorking = false }
        do {
            _ = try await RecordingLibrary.merge(files: chosen.flatMap(\.audioFiles), sourceIDs: chosen.map(\.id), root: root)
            refreshSessions()
            libraryMessage = "已生成一条合并录音，原记录仍保留。"
        } catch { libraryMessage = "合并失败：\(error.localizedDescription)" }
    }

    func delete(ids: Set<UUID>) {
        guard phase == .idle, !libraryWorking else { return }
        let chosen = sessions.filter { ids.contains($0.id) }
        var roots = [root]
        if let shared = RecordingPaths.sharedRoot { roots.append(shared) }
        var deleted = 0
        var failures: [String] = []
        for session in chosen {
            do {
                try RecordingLibrary.deleteSession(folder: session.folder, allowedRoots: roots)
                deleted += 1
                checks.removeValue(forKey: session.id)
            } catch { failures.append(error.localizedDescription) }
        }
        refreshSessions()
        libraryMessage = failures.isEmpty ? "已删除 \(deleted) 条录音。" : "已删除 \(deleted) 条；\(failures.joined(separator: "；"))"
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
        Task { @MainActor in await self.begin(with: filter) }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            guard self.phase == .selecting else { return }
            self.releasePicker()
            self.phase = .idle
            self.status = "已取消系统授权，未开始录制。"
        }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in await self.stop(reason: "系统选择器失败：\(error.localizedDescription)") }
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
            onStopped?("系统采集已结束：\(error.localizedDescription)")
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
