import AudioCore
import AVFoundation
import Combine
import CoreMedia
import Foundation
import UIKit
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

enum ProbePhase: String { case idle, selecting, starting, recording, stopping }

/// A library item contains only completed audio files beneath its own probe directory.
struct ProbeRecord: Identifiable {
    let id: UUID
    let date: Date
    let folder: URL
    let systemFiles: [URL]
    let microphoneFiles: [URL]
    let systemStats: ProbeSignalStats
    let microphoneStats: ProbeSignalStats
    let microphoneEnabled: Bool
    let events: [String]
    let isActive: Bool
    let state: String
    let error: String?

    var exportFiles: [URL] { systemFiles + microphoneFiles }
}

private struct ProbeDocument: Codable {
    var schemaVersion = 1
    var id: UUID
    var date: Date
    var endedAt: Date?
    var state = "starting"
    var microphoneEnabled: Bool
    var systemWriterID: UUID
    var microphoneWriterID: UUID
    var systemReport: SessionReport?
    var microphoneReport: SessionReport?
    var systemStats = ProbeSignalStats()
    var microphoneStats = ProbeSignalStats()
    var events: [String]
    var error: String?
    var osVersion: String
    var appVersion: String
    // Signal presence is deliberately not labeled as successful two-sided call recording.
    var contentAcceptance = "unverified"
    var videoSaved = false
    var automaticUpload = false
}

@MainActor
final class ProbeCaptureController: NSObject, ObservableObject {
    @Published private(set) var phase: ProbePhase = .idle
    @Published private(set) var status = "准备好后打开系统选择器；通话双方声音需分别试听确认。"
    @Published private(set) var records: [ProbeRecord] = []
    @Published private(set) var systemStats = ProbeSignalStats()
    @Published private(set) var microphoneStats = ProbeSignalStats()
    @Published private(set) var events: [String] = []

    let root: URL
    private var document: ProbeDocument?
    private var activeFolder: URL?
    private var systemWriter: AudioSegmentWriter?
    private var microphoneWriter: AudioSegmentWriter?
    private var statisticsTask: Task<Void, Never>?
    private var audioActivationTask: Task<String?, Never>?
    private var audioSessionActivated = false
    private var lastStatsPublication = Date.distantPast
    private var lastCheckpoint = Date.distantPast
    private var selectionID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
#if canImport(ScreenCaptureKit)
    private var stream: SCStream?
    private var streamStartTask: Task<Void, Error>?
    private var sink: ProbeSCKSink?
    private var ownsPicker = false
#endif

    override init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CallAudioProbe", isDirectory: true)
        super.init()
        observeSessionEvents()
        refresh()
    }

    deinit {
        statisticsTask?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        guard phase == .idle else { return }
#if canImport(ScreenCaptureKit)
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else {
            status = "当前设备无法打开系统采集选择器。"
            return
        }
        guard !picker.isActive else {
            status = "系统选择器正在使用，请结束原操作后重试。"
            return
        }
        events = []
        document = nil
        phase = .selecting
        status = "请授权全屏采集，并按需要开启系统选择器中的麦克风开关；不保存画面。"
        let selection = UUID()
        selectionID = selection
        Task { [weak self] in
            guard let self else { return }
            await self.publishThrottled(ProbeStatsSnapshot(), selection: selection)
            guard self.phase == .selecting, self.selectionID == selection else { return }
            guard !picker.isActive else {
                self.phase = .idle
                self.status = "系统选择器正在使用，请结束原操作后重试。"
                return
            }
            self.addEvent("present full-display picker; microphone control visible")
            var configuration = SCContentSharingPickerConfiguration()
            configuration.showsMicrophoneControl = true
            picker.defaultConfiguration = configuration
            picker.add(self)
            self.ownsPicker = true
            picker.isActive = true
            picker.present()
        }
#else
        status = "模拟器没有 ScreenCaptureKit 采集入口；请在 iPhone 真机验证。未开始录音。"
#endif
    }

    func stop() async {
        await finishCapture(reason: nil, systemAlreadyStopped: false)
    }

#if canImport(ScreenCaptureKit)
    private func begin(with filter: SCContentFilter) async {
        guard phase == .selecting else { return }
        guard filter.style == .display else {
            addEvent("picker source rejected; expected display, received \(String(describing: filter.style))")
            releasePicker()
            phase = .idle
            selectionID = nil
            status = "本探针需要全屏采集。请重新开始，并在系统选择器中选择整个屏幕。"
            return
        }
        phase = .starting
        let id = UUID()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            activeFolder = folder
            // Persist a recoverable probe identity before a writer can create any audio files.
            document = ProbeDocument(id: id, date: Date(), microphoneEnabled: filter.isMicrophoneEnabled,
                                     systemWriterID: UUID(), microphoneWriterID: UUID(), events: events,
                                     osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                     appVersion: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))")
            addEvent("picker microphone enabled=\(filter.isMicrophoneEnabled)")
            addEvent("picker capture style=display")
            try saveCheckpoint()
            let system = try AudioSegmentWriter(root: folder.appendingPathComponent("system", isDirectory: true),
                                               captureSource: "sck-system")
            systemWriter = system
            guard let systemID = UUID(uuidString: system.folder.lastPathComponent) else { throw ProbeFailure.unsafePath }
            document?.systemWriterID = systemID
            let microphone = try AudioSegmentWriter(root: folder.appendingPathComponent("microphone", isDirectory: true),
                                                   captureSource: "sck-microphone", microphoneRequested: filter.isMicrophoneEnabled)
            microphoneWriter = microphone
            guard let microphoneID = UUID(uuidString: microphone.folder.lastPathComponent) else { throw ProbeFailure.unsafePath }
            document?.microphoneWriterID = microphoneID
            try saveCheckpoint()
            system.onUpdate = { [weak self] report in
                Task { @MainActor in self?.writerUpdated(report, source: .system, id: id) }
            }
            microphone.onUpdate = { [weak self] report in
                Task { @MainActor in self?.writerUpdated(report, source: .microphone, id: id) }
            }
            system.onFatalError = { [weak self] message in
                Task { @MainActor in await self?.writerFailed(message, source: .system, id: id) }
            }
            microphone.onFatalError = { [weak self] message in
                Task { @MainActor in await self?.writerFailed(message, source: .microphone, id: id) }
            }

            // Follow Apple's iOS sample: failure to activate does not prevent an SCStream attempt.
            if filter.isMicrophoneEnabled {
                let activation = Task.detached(priority: .userInitiated) { () -> String? in
                    do {
                        let session = AVAudioSession.sharedInstance()
                        try session.setCategory(.playAndRecord, mode: .videoRecording,
                                                options: [.mixWithOthers, .allowBluetoothHFP])
                        try session.setActive(true)
                        return nil
                    } catch { return Self.describe(error) }
                }
                audioActivationTask = activation
                let failure = await activation.value
                guard phase == .starting, document?.id == id else { return }
                audioSessionActivated = failure == nil
                audioActivationTask = nil
                addEvent(failure.map { "audio session activation failed; SCK attempt continues: \($0)" }
                         ?? "audio session activation succeeded")
            } else {
                addEvent("audio session activation skipped; picker microphone disabled")
            }

            let output = ProbeSCKSink(systemWriter: system, microphoneWriter: microphone,
                                      microphoneEnabled: filter.isMicrophoneEnabled)
            sink = output
            output.onStopped = { [weak self] reason in
                Task { @MainActor in
                    guard self?.document?.id == id else { return }
                    await self?.finishCapture(reason: reason, systemAlreadyStopped: true)
                }
            }
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            let capture = SCStream(filter: filter, configuration: configuration, delegate: output)
            try capture.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.callbackQueue)
            if filter.isMicrophoneEnabled {
                try capture.addStreamOutput(output, type: .microphone, sampleHandlerQueue: output.callbackQueue)
            }
            try capture.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.callbackQueue)
            stream = capture
            addEvent("SCStream start requested; independent system/microphone writers; no AVAudioEngine")
            let start = Task { try await capture.startCapture() }
            streamStartTask = start
            try await start.value
            guard phase == .starting, document?.id == id else { return }
            streamStartTask = nil
            document?.state = "recording"
            phase = .recording
            status = "采集中。系统音频与麦克风分别保存；尚未确认通话双方声音。"
            addEvent("SCStream started; content acceptance remains unverified")
            releasePicker()
            startStatisticsLoop(id: id, sink: output)
            try saveCheckpoint()
        } catch {
            guard phase == .starting || phase == .recording,
                  document?.id == id || document == nil else { return }
            await finishCapture(reason: "启动失败：\(Self.describe(error))", systemAlreadyStopped: false)
        }
    }

    private func startStatisticsLoop(id: UUID, sink: ProbeSCKSink) {
        statisticsTask?.cancel()
        statisticsTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return }
                let snapshot = await sink.snapshot()
                guard !Task.isCancelled, let self, self.document?.id == id, self.phase == .recording else { return }
                await self.publishThrottled(snapshot)
                if Date().timeIntervalSince(self.lastCheckpoint) >= 2 {
                    do { try self.saveCheckpoint() }
                    catch {
                        await self.finishCapture(reason: "保存探针记录失败：\(Self.describe(error))", systemAlreadyStopped: false)
                        return
                    }
                }
            }
        }
    }

    private func releasePicker() {
        guard ownsPicker else { return }
        ownsPicker = false
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
    }
#endif

    private func finishCapture(reason: String?, systemAlreadyStopped: Bool) async {
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
        selectionID = nil
        status = "正在完成两路音频并保存探针记录…"
        statisticsTask?.cancel()
        statisticsTask = nil
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FinishCallAudioProbe")
#if canImport(ScreenCaptureKit)
        releasePicker()
#endif
        // A stop during the asynchronous audio activation must also wait for its eventual result.
        if let activation = audioActivationTask {
            audioSessionActivated = await activation.value == nil
            audioActivationTask = nil
        }
        var finalReason = reason
        addEvent(systemAlreadyStopped ? "SCStream stopped by system" : "app stop requested")
#if canImport(ScreenCaptureKit)
        let capture = stream
        stream = nil
        var startSucceeded = true
        // Keep this session in .stopping until any pending start resolves. Otherwise an old
        // capture could start after its writer was finalized or after a new probe began.
        if let start = streamStartTask {
            do { try await start.value }
            catch {
                startSucceeded = false
                addEvent("SCStream start completed with error: \(Self.describe(error))")
                if finalReason == nil { finalReason = "系统采集启动失败：\(Self.describe(error))" }
            }
            streamStartTask = nil
        }
        if let capture, !systemAlreadyStopped, startSucceeded {
            do { try await capture.stopCapture() }
            catch {
                addEvent("SCStream stop returned error: \(Self.describe(error))")
                if finalReason == nil { finalReason = "结束系统采集时出错：\(Self.describe(error))" }
            }
        }
        if let output = sink {
            let final = await output.seal()
            await publishThrottled(final)
        } else {
            await publishThrottled(ProbeStatsSnapshot())
        }
        sink = nil
#endif
        let system = systemWriter
        let microphone = microphoneWriter
        systemWriter = nil
        microphoneWriter = nil
        let writerReason = finalReason
        // Writer queues drain all previously enqueued audio before finalizing the last M4A.
        if let system {
            let report = await finishWriter(system, reason: writerReason)
            document?.systemReport = report
        }
        if let microphone {
            let report = await finishWriter(microphone, reason: writerReason)
            document?.microphoneReport = report
        }
        // finishWriting and session.json writes can fail after the last append callback.
        let failures = [("系统音频", document?.systemReport), ("麦克风", document?.microphoneReport)].compactMap { name, report -> String? in
            guard let report, report.state == "interrupted" || report.error != nil else { return nil }
            if let writerReason, report.error == writerReason { return nil }
            return "\(name)：\(report.error ?? "音频未正常完成")"
        }
        if !failures.isEmpty {
            finalReason = ([finalReason].compactMap { $0 } + failures).joined(separator: "；")
        }
        if audioSessionActivated {
            do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            catch { addEvent("audio session deactivation failed: \(Self.describe(error))") }
            audioSessionActivated = false
        }
        if document != nil {
            document?.endedAt = Date()
            document?.error = finalReason
            document?.state = finalReason == nil ? "finished" : "interrupted"
            addEvent("writers finalized; no automatic claim of two-sided call success")
            do { try persistDocument() }
            catch { finalReason = "保存探针记录失败：\(Self.describe(error))" }
        }
        if let folder = activeFolder { try? FileManager.default.removeItem(at: folder.appendingPathComponent(".active")) }
        activeFolder = nil
        phase = .idle
        status = finalReason.map { "采集已结束：\($0) 已完成音频仍可试听。" }
            ?? (document == nil ? "已取消，未开始录音。" : "采集已结束，已完成的音频已保留。请分别试听；静音或仅本方声音不算双向通话成功。")
        refresh()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func finishWriter(_ writer: AudioSegmentWriter, reason: String?) async -> SessionReport {
        await withCheckedContinuation { continuation in
            writer.finish(reason: reason) { report in continuation.resume(returning: report) }
        }
    }

    private enum Source { case system, microphone }

    private func writerUpdated(_ report: SessionReport, source: Source, id: UUID) {
        guard document?.id == id, activeFolder != nil else { return }
        switch source {
        case .system: document?.systemReport = report
        case .microphone: document?.microphoneReport = report
        }
    }

    private func writerFailed(_ message: String, source: Source, id: UUID) async {
        guard document?.id == id else { return }
        await finishCapture(reason: "\(source == .system ? "系统音频" : "麦克风")编码失败：\(message)", systemAlreadyStopped: false)
    }

    private func observeSessionEvents() {
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
                let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? UInt.max
                let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                Task { @MainActor in
                    guard let self, self.activeFolder != nil else { return }
                    // This notification describes AVAudioSession, not an SCStream terminal event.
                    self.addEvent("AVAudioSession interruption type=\(type), options=\(options); SCK not stopped")
                }
            })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] notification in
                let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
                Task { @MainActor in
                    guard let self, self.activeFolder != nil else { return }
                    let route = AVAudioSession.sharedInstance().currentRoute
                    // Port types only: no Bluetooth names, UIDs, contact or call identifiers.
                    let inputs = route.inputs.map { $0.portType.rawValue }.joined(separator: ",")
                    let outputs = route.outputs.map { $0.portType.rawValue }.joined(separator: ",")
                    self.addEvent("audio route reason=\(reason), input=\(inputs), output=\(outputs)")
                }
            })
    }

    private func addEvent(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        events.append("\(timestamp) \(text)")
        // Bound metadata if a device repeatedly emits route/interruption notifications.
        if events.count > 200 { events.removeFirst(events.count - 200) }
        document?.events = events
    }

    private func publish(_ snapshot: ProbeStatsSnapshot) {
        lastStatsPublication = Date()
        systemStats = snapshot.system
        microphoneStats = snapshot.microphone
        document?.systemStats = snapshot.system
        document?.microphoneStats = snapshot.microphone
    }

    private func publishThrottled(_ snapshot: ProbeStatsSnapshot, selection: UUID? = nil) async {
        while Date().timeIntervalSince(lastStatsPublication) < 0.5 {
            if let selection, selectionID != selection { return }
            let remaining = 0.5 - Date().timeIntervalSince(lastStatsPublication)
            do { try await Task.sleep(nanoseconds: UInt64(max(0, remaining) * 1_000_000_000)) }
            catch { return }
        }
        if let selection, selectionID != selection { return }
        publish(snapshot)
    }

    private func persistDocument() throws {
        guard let document, let folder = activeFolder else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: folder.appendingPathComponent("probe.json"), options: .atomic)
    }

    private func saveCheckpoint() throws {
        try persistDocument()
        if let folder = activeFolder {
            try Data().write(to: folder.appendingPathComponent(".active"), options: .atomic)
        }
        lastCheckpoint = Date()
    }

    func refresh() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        records = folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  let checked = try? validatedFolder(folder, id: id) else { return nil }
            let live = activeFolder?.standardizedFileURL == folder.standardizedFileURL || Self.hasFreshMarker(folder)
            guard let report = try? loadDocument(checked) else {
                let date = (try? checked.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return ProbeRecord(id: id, date: date, folder: checked, systemFiles: [], microphoneFiles: [],
                    systemStats: ProbeSignalStats(), microphoneStats: ProbeSignalStats(), microphoneEnabled: false,
                    events: [], isActive: live, state: "unreadable", error: "探针记录不完整或无法读取；未导出未确认的文件。")
            }
            let system = (try? SessionReport.load(from: checked.appendingPathComponent("system", isDirectory: true)
                .appendingPathComponent(report.systemWriterID.uuidString, isDirectory: true))) ?? report.systemReport
            let microphone = (try? SessionReport.load(from: checked.appendingPathComponent("microphone", isDirectory: true)
                .appendingPathComponent(report.microphoneWriterID.uuidString, isDirectory: true))) ?? report.microphoneReport
            return ProbeRecord(id: report.id, date: report.date, folder: checked,
                systemFiles: completedFiles(report: system, source: "system", folder: checked),
                microphoneFiles: completedFiles(report: microphone, source: "microphone", folder: checked),
                systemStats: report.systemStats, microphoneStats: report.microphoneStats,
                microphoneEnabled: report.microphoneEnabled, events: report.events, isActive: live,
                state: !live && report.endedAt == nil ? "unfinished" : report.state,
                error: report.error)
        }.sorted { $0.date > $1.date }
    }

    /// Removes the whole UUID folder, including both writers and all diagnostic metadata.
    func delete(_ record: ProbeRecord) throws {
        guard phase == .idle else { throw ProbeFailure.activeRecording }
        let folder = try validatedFolder(record.folder, id: record.id)
        guard activeFolder?.resolvingSymlinksInPath().standardizedFileURL != folder,
              !Self.hasFreshMarker(folder) else { throw ProbeFailure.activeRecording }
        // A failed first write can leave a UUID folder without readable probe.json. It is still
        // deletable inside this dedicated root, but never used as an export source.
        if let report = try? loadDocument(folder), report.id != record.id { throw ProbeFailure.unsafePath }
        try FileManager.default.removeItem(at: folder)
        if document?.id == record.id, activeFolder == nil {
            document = nil
            events = []
        }
        refresh()
    }

    private func loadDocument(_ folder: URL) throws -> ProbeDocument {
        guard let id = UUID(uuidString: folder.lastPathComponent) else { throw ProbeFailure.unsafePath }
        let folder = try validatedFolder(folder, id: id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ProbeDocument.self, from: Data(contentsOf: folder.appendingPathComponent("probe.json")))
        guard report.id == id else { throw ProbeFailure.unsafePath }
        return report
    }

    private func validatedFolder(_ folder: URL, id: UUID) throws -> URL {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              UUID(uuidString: resolved.lastPathComponent) == id,
              resolved.deletingLastPathComponent().path == resolvedRoot.path else { throw ProbeFailure.unsafePath }
        return resolved
    }

    private func completedFiles(report: SessionReport?, source: String, folder: URL) -> [URL] {
        guard let report, source == "system" || source == "microphone" else { return [] }
        let sourceRoot = folder.appendingPathComponent(source, isDirectory: true)
        let writerFolder = sourceRoot.appendingPathComponent(report.id.uuidString, isDirectory: true)
        // Even a malformed local JSON file cannot turn export into an arbitrary file read.
        guard (try? sourceRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              (try? writerFolder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return [] }
        let resolvedWriter = writerFolder.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedWriter.deletingLastPathComponent().path == sourceRoot.standardizedFileURL.resolvingSymlinksInPath().path else { return [] }
        return RecordingFiles.audioForExport(report: report, folder: writerFolder).filter { file in
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true &&
                file.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path == resolvedWriter.path
        }
    }

    private static func hasFreshMarker(_ folder: URL) -> Bool {
        guard let modified = try? folder.appendingPathComponent(".active")
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
        return Date().timeIntervalSince(modified) < 10
    }

    nonisolated private static func describe(_ error: Error) -> String {
        let value = error as NSError
        // Do not serialize userInfo, which may contain paths or unrelated source metadata.
        return "\(value.domain) / \(value.code): \(value.localizedDescription)"
    }
}

private struct ProbeStatsSnapshot: Sendable {
    var system = ProbeSignalStats()
    var microphone = ProbeSignalStats()
}

enum ProbeFailure: LocalizedError {
    case unsafePath, activeRecording
    var errorDescription: String? {
        switch self {
        case .unsafePath: return "探针目录校验失败，未删除任何内容。"
        case .activeRecording: return "这条探针仍在采集，请先停止。"
        }
    }
}

#if canImport(ScreenCaptureKit)
extension ProbeCaptureController: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await self.begin(with: filter) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            guard self.phase == .selecting else { return }
            self.releasePicker()
            self.phase = .idle
            self.addEvent("picker canceled; no capture started")
            self.status = "已取消系统授权，未开始录音。"
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        let message = Self.describe(error)
        Task { @MainActor in await self.finishCapture(reason: "系统选择器失败：\(message)", systemAlreadyStopped: false) }
    }
}

/// The serial callback queue owns both accumulators. It never creates an AVAudioEngine.
private final class ProbeSCKSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let callbackQueue = DispatchQueue(label: "com.lightsquare.call-probe-callbacks", qos: .userInitiated)
    var onStopped: (@Sendable (String?) -> Void)?
    private let systemWriter: AudioSegmentWriter
    private let microphoneWriter: AudioSegmentWriter
    private let microphoneEnabled: Bool
    private var stats = ProbeStatsSnapshot()
    private var accepting = true

    init(systemWriter: AudioSegmentWriter, microphoneWriter: AudioSegmentWriter, microphoneEnabled: Bool) {
        self.systemWriter = systemWriter
        self.microphoneWriter = microphoneWriter
        self.microphoneEnabled = microphoneEnabled
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard accepting else { return }
        switch type {
        case .audio:
            stats.system.consume(sampleBuffer)
            systemWriter.append(sampleBuffer)
        case .microphone:
            guard microphoneEnabled else { return }
            stats.microphone.consume(sampleBuffer)
            microphoneWriter.noteMicrophoneInput()
            microphoneWriter.append(sampleBuffer)
        case .screen:
            // No pixel buffer is read, retained, copied, encoded or written.
            systemWriter.discardVideoFrame()
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let value = error as NSError
        let userStopped = value.domain == SCStreamError.errorDomain && value.code == SCStreamError.Code.userStopped.rawValue
        onStopped?(userStopped ? nil : "\(value.domain) / \(value.code): \(value.localizedDescription)")
    }

    func snapshot() async -> ProbeStatsSnapshot {
        await withCheckedContinuation { continuation in
            callbackQueue.async { continuation.resume(returning: self.stats) }
        }
    }

    func seal() async -> ProbeStatsSnapshot {
        await withCheckedContinuation { continuation in
            callbackQueue.async {
                self.accepting = false
                continuation.resume(returning: self.stats)
            }
        }
    }
}
#endif
