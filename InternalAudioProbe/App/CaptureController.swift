import AudioCore
import AVFoundation
import Combine
import ScreenCaptureKit
import SwiftUI

@MainActor
final class CaptureController: NSObject, ObservableObject {
    enum Phase: String { case idle, selecting, starting, recording, stopping }
    @Published var phase: Phase = .idle
    @Published var status = "准备好后点开始，再切到课程或其他播放 App。"
    @Published var report: SessionReport?
    @Published var sessions: [SavedSession] = []
    @Published var inspection = ""
    private var stream: SCStream?
    private var sink: AudioSink?
    private var writer: AudioSegmentWriter?
    private var ownsPicker = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    let root: URL

    override init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        super.init()
        refreshSessions()
    }

    func start() {
        guard phase == .idle else { return }
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else { status = "当前设备无法打开系统采集选择器。"; return }
        guard !picker.isActive else { status = "已有其他屏幕采集正在使用选择器，请先停止。"; return }
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
    }

    private func begin(with filter: SCContentFilter) async {
        guard phase == .selecting else { return }
        phase = .starting
        do {
            let output = try AudioSegmentWriter(root: root)
            writer = output
            output.onUpdate = { [weak self] value in
                Task { @MainActor in self?.report = value }
            }
            output.onFatalError = { [weak self] message in
                Task { @MainActor in await self?.stop(reason: message) }
            }
            let sink = AudioSink(writer: output)
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
            try await capture.startCapture()
            phase = .recording
            status = "正在录内部音，可切换到播放 App。麦克风关闭；画面不保存。"
            releasePicker()
        } catch {
            await stop(reason: "启动失败：\(error.localizedDescription)")
        }
    }

    func stop(reason: String? = nil) async {
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
        status = "正在完成音频分段，请稍候。"
        releasePicker()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FinalizeAudio") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
        if let stream {
            // The system Stop button can stop the stream before its delegate runs.
            try? await stream.stopCapture()
        }
        stream = nil
        sink = nil
        guard let writer else {
            phase = .idle
            status = reason ?? "已取消。"
            endBackgroundTask()
            return
        }
        self.writer = nil
        let completed = await withCheckedContinuation { continuation in
            writer.finish(reason: reason) { value in continuation.resume(returning: value) }
        }
        report = completed
        phase = .idle
        switch completed.state {
        case "no-audio": status = "未收到内部音频。请确认来源正在播放，或换一个 App 验证。"
        case "silent": status = "收到的内部音频持续静音；这次不能算内录成功。"
        case "interrupted": status = "录制中断：\(completed.error ?? "请查看分段状态")"
        default: status = "已保存纯音频。试听后再确认这次录制是否成功。"
        }
        refreshSessions()
        if let session = sessions.first(where: { $0.id == completed.id }) { await inspect(session) }
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func releasePicker() {
        guard ownsPicker else { return }
        ownsPicker = false
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
    }

    func refreshSessions() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        sessions = folders.compactMap { folder in
            guard let report = try? SessionReport.load(from: folder) else { return nil }
            return SavedSession(report: report, folder: folder)
        }.sorted { $0.report.startedAt > $1.report.startedAt }
    }

    func inspect(_ session: SavedSession) async {
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
        // Inspection JSON is metadata only; never includes captured samples or credentials.
        let result: [String: Any] = ["audioTracks": audio, "videoTracks": video, "errors": errors,
                                     "checkedAt": ISO8601DateFormatter().string(from: Date())]
        do {
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: session.folder.appendingPathComponent("inspection.json"), options: .atomic)
        } catch { inspection += " 保存检查记录失败：\(error.localizedDescription)" }
    }
}

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
    var onStopped: (@Sendable (String) -> Void)?
    init(writer: AudioSegmentWriter) { self.writer = writer }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio { writer.append(sampleBuffer) }
        else if type == .screen { writer.discardVideoFrame() }
        // Microphone output is never registered or consumed.
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped?("系统采集已结束：\(error.localizedDescription)")
    }
}

struct SavedSession: Identifiable {
    let report: SessionReport
    let folder: URL
    var id: UUID { report.id }
    var audioFiles: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "m4a" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    var exportFiles: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["m4a", "json"].contains($0.pathExtension) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
