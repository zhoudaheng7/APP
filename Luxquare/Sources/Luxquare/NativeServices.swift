import AVFoundation
import Combine
import CoreLocation
import CryptoKit
import Foundation
import UIKit

struct NativeRecordingDraft: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var duration: TimeInterval
    var interrupted: Bool
    var finished: Bool
    let fileName: String
    let accountScope: String?

    var durationLabel: String {
        let total = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

enum NativeRecorderState: String {
    case idle, requestingPermission, recording, paused, interrupted

    var label: String {
        switch self {
        case .idle: return "准备就绪"
        case .requestingPermission: return "等待麦克风权限"
        case .recording: return "正在录音"
        case .paused: return "已暂停"
        case .interrupted: return "录音被中断"
        }
    }
}

enum NativeCapabilityError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): return message
        }
    }
}

/// One recorder is shared by the native tools and the web bridge. No network is used here.
@MainActor
final class NativeRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    static let shared = NativeRecorder()

    @Published private(set) var state: NativeRecorderState = .idle
    @Published private(set) var recordings: [NativeRecordingDraft] = []
    @Published private(set) var recordingTime: TimeInterval = 0
    @Published private(set) var level: Double = 0
    @Published private(set) var activeDraftID: UUID?
    @Published private(set) var playingDraftID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var informationMessage: String?
    @Published private(set) var currentAccountScope: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var checkpointAt = Date.distantPast
    private var wantsRecording = false
    private var exportingIDs = Set<UUID>()
    private let storageRoot: URL
    private var storageDirectory: URL { directory(for: currentAccountScope) }

    var hasActiveRecording: Bool { recorder != nil }
    var isRecording: Bool { state == .recording }
    var canResume: Bool { recorder != nil && (state == .paused || state == .interrupted) }
    var recordingTimeLabel: String {
        let seconds = max(0, Int(recordingTime))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    override init() {
        storageRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativeRecordings", isDirectory: true)
        super.init()
        do { try prepareStorage() } catch { errorMessage = "无法准备本机录音目录，请检查手机储存空间。" }
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioServicesReset(_:)), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationBackgrounded(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationBecameActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: UIApplication.willTerminateNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// The host supplies its authenticated identity ID. Switching never reassigns existing audio.
    func setAccountScope(_ scope: String?) {
        let nextScope = scope?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (nextScope?.isEmpty == false) ? nextScope : nil
        guard normalized != currentAccountScope else { return }
        let savedActiveRecording = hasActiveRecording
        if hasActiveRecording { _ = stop() }
        stopPlayback()
        currentAccountScope = normalized
        recordingTime = 0
        level = 0
        state = .idle
        errorMessage = nil
        informationMessage = savedActiveRecording ? "身份已切换，刚才的录音保留在原账号的本机草稿中。" : nil
        refresh()
    }

    /// Returns the original identity ID stored in private metadata, or nil for anonymous/unknown files.
    /// The host must compare this with its *current* authenticated identity before uploading.
    func accountScope(for url: URL) -> String? {
        guard url.isFileURL else { return nil }
        let root = storageRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(root), ["caf", "m4a"].contains(resolved.pathExtension) else { return nil }
        let stem = resolved.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix("recording-"), let id = UUID(uuidString: String(stem.dropFirst("recording-".count))) else { return nil }
        let metadata = resolved.deletingPathExtension().appendingPathExtension("json")
        guard let data = try? Data(contentsOf: metadata), let draft = try? JSONDecoder().decode(NativeRecordingDraft.self, from: data), draft.id == id,
              directory(for: draft.accountScope).resolvingSymlinksInPath().standardizedFileURL == resolved.deletingLastPathComponent() else { return nil }
        return draft.accountScope
    }

    func start() async {
        guard state != .requestingPermission, state != .recording else { return }
        guard UIApplication.shared.applicationState == .active else {
            errorMessage = "请在 App 前台点击开始录音。"
            return
        }
        if canResume { resume(); return }
        errorMessage = nil
        informationMessage = nil
        let requestedScope = currentAccountScope
        state = .requestingPermission
        let granted = await AVAudioApplication.requestRecordPermission()
        guard requestedScope == currentAccountScope else {
            state = .idle
            informationMessage = "身份已变化，请在当前账号重新开始录音。"
            return
        }
        guard granted else {
            state = .idle
            errorMessage = "麦克风权限未开启。可在「设置 → Luxquare → 麦克风」中开启后重试。"
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            state = .idle
            informationMessage = "麦克风权限已开启，回到 App 后可点击开始录音。"
            return
        }
        do {
            try prepareStorage()
            try verifyFreeSpace()
            stopPlayback()
            try activateRecordingSession()
            let id = UUID()
            let fileName = "recording-\(id.uuidString.lowercased()).caf"
            let url = storageDirectory.appendingPathComponent(fileName)
            // Linear PCM in CAF preserves the source independently of a later M4A export.
            // No record(forDuration:) call or artificial Feishu duration cap is used.
            let audio = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 24_000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            audio.delegate = self
            audio.isMeteringEnabled = true
            guard audio.prepareToRecord() else { throw NativeCapabilityError.unavailable("录音设备准备失败，请重试。") }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            var excludedURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try excludedURL.setResourceValues(resourceValues)
            guard audio.record() else { throw NativeCapabilityError.unavailable("麦克风未能开始录音，请检查是否正在通话。") }
            recorder = audio
            activeDraftID = id
            wantsRecording = true
            recordingTime = 0
            state = .recording
            let draft = NativeRecordingDraft(id: id, title: Date.now.formatted(date: .abbreviated, time: .shortened) + " 录音", createdAt: .now, duration: 0, interrupted: false, finished: false, fileName: fileName, accountScope: currentAccountScope)
            recordings.insert(draft, at: 0)
            saveMetadata(draft)
            startMeterTimer()
        } catch {
            recorder?.stop()
            recorder = nil
            activeDraftID = nil
            state = .idle
            wantsRecording = false
            deactivateSession()
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        guard let recorder, state == .recording else { return }
        wantsRecording = false
        recorder.pause()
        recordingTime = recorder.currentTime
        state = .paused
        level = 0
        checkpoint()
        deactivateSession()
    }

    func resume() {
        guard let recorder, canResume else { return }
        do {
            try verifyFreeSpace()
            try activateRecordingSession()
            guard recorder.record() else { throw NativeCapabilityError.unavailable("录音暂时无法继续，请先结束通话或保存当前录音。") }
            state = .recording
            wantsRecording = true
            informationMessage = nil
            startMeterTimer()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Finalizes the source on this device. Uploading requires a separate explicit action.
    @discardableResult
    func stop() -> NativeRecordingDraft? {
        guard let recorder else { return nil }
        wantsRecording = false
        recordingTime = recorder.currentTime
        checkpoint(finished: true)
        let result = recordings.first { $0.id == activeDraftID }
        recorder.stop()
        self.recorder = nil
        activeDraftID = nil
        state = .idle
        level = 0
        meterTimer?.invalidate()
        meterTimer = nil
        deactivateSession()
        informationMessage = "录音已保存在本机，可稍后加入录音总结或分享。"
        return result
    }

    func refresh() {
        guard !hasActiveRecording else { return }
        do {
            try prepareStorage()
            let urls = try FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
            var found: [NativeRecordingDraft] = []
            for url in urls where url.pathExtension == "caf" && url.lastPathComponent.hasPrefix("recording-") {
                let metadataURL = url.deletingPathExtension().appendingPathExtension("json")
                var item: NativeRecordingDraft
                if let data = try? Data(contentsOf: metadataURL), let saved = try? JSONDecoder().decode(NativeRecordingDraft.self, from: data), saved.fileName == url.lastPathComponent {
                    guard saved.accountScope == currentAccountScope else { continue }
                    item = saved
                } else {
                    let rawID = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "recording-", with: "")
                    guard let id = UUID(uuidString: rawID) else { continue }
                    let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
                    item = NativeRecordingDraft(id: id, title: "恢复的录音", createdAt: created, duration: 0, interrupted: true, finished: false, fileName: url.lastPathComponent, accountScope: currentAccountScope)
                }
                if let playable = try? AVAudioPlayer(contentsOf: url), playable.duration.isFinite {
                    item.duration = max(item.duration, playable.duration)
                }
                if !item.finished { item.interrupted = true }
                saveMetadata(item)
                found.append(item)
            }
            recordings = found.sorted { $0.createdAt > $1.createdAt }
        } catch { errorMessage = "读取本机录音失败，已有文件未删除。请检查储存空间后重试。" }
    }

    func fileURL(for draft: NativeRecordingDraft) -> URL {
        // Files are admitted through an app-created UUID name, never a remote supplied path.
        directory(for: draft.accountScope).appendingPathComponent("recording-\(draft.id.uuidString.lowercased()).caf")
    }

    func delete(_ draft: NativeRecordingDraft) {
        guard draft.accountScope == currentAccountScope else { errorMessage = "请切换回录音所属账号再操作。"; return }
        guard draft.id != activeDraftID, !exportingIDs.contains(draft.id) else { return }
        if playingDraftID == draft.id { stopPlayback() }
        let sourceURL = fileURL(for: draft)
        do {
            for url in [sourceURL, sourceURL.deletingPathExtension().appendingPathExtension("json"), sourceURL.deletingPathExtension().appendingPathExtension("m4a")] {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            recordings.removeAll { $0.id == draft.id }
        } catch { errorMessage = "未能删除这段本机录音，请重试。" }
    }

    func togglePlayback(_ draft: NativeRecordingDraft) {
        guard draft.accountScope == currentAccountScope else { return }
        guard !hasActiveRecording else { return }
        if playingDraftID == draft.id { stopPlayback(); return }
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: fileURL(for: draft))
            audio.delegate = self
            guard audio.play() else { throw NativeCapabilityError.unavailable("这段录音暂时无法播放，源文件仍保留在本机。") }
            player = audio
            playingDraftID = draft.id
        } catch { errorMessage = error.localizedDescription; deactivateSession() }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingDraftID = nil
        if !hasActiveRecording { deactivateSession() }
    }

    /// A normal M4A is handed to the host; the durable CAF source is kept until the user deletes it.
    func prepareForSharing(_ draft: NativeRecordingDraft) async throws -> URL {
        guard draft.accountScope == currentAccountScope else { throw NativeCapabilityError.unavailable("请切换回录音所属账号再操作。") }
        guard draft.id != activeDraftID else { throw NativeCapabilityError.unavailable("请先保存当前录音。") }
        guard !exportingIDs.contains(draft.id) else { throw NativeCapabilityError.unavailable("这段录音正在准备，请稍候。") }
        let sourceURL = fileURL(for: draft)
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: outputURL.path), let validated = try? AVAudioPlayer(contentsOf: outputURL), validated.duration > 0 { return outputURL }
        exportingIDs.insert(draft.id)
        defer { exportingIDs.remove(draft.id) }
        try verifyFreeSpace()
        if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw NativeCapabilityError.unavailable("音频暂时无法转换，源文件仍保留在本机。") }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed: continuation.resume()
                case .cancelled: continuation.resume(throwing: NativeCapabilityError.unavailable("音频准备已取消，源文件仍保留。"))
                default: continuation.resume(throwing: NativeCapabilityError.unavailable("音频准备失败，源文件仍保留在本机。"))
                }
            }
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: outputURL.path)
        guard draft.accountScope == currentAccountScope else { throw NativeCapabilityError.unavailable("身份已变化，音频仍保留在原账号的本机草稿中。") }
        return outputURL
    }

    private func directory(for scope: String?) -> URL {
        guard let scope else { return storageRoot }
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return storageRoot.appendingPathComponent("accounts", isDirectory: true).appendingPathComponent(digest, isDirectory: true)
    }

    private func prepareStorage() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var directory = storageDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private func verifyFreeSpace() throws {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: storageDirectory.path)
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free >= 30 * 1_024 * 1_024 else { throw NativeCapabilityError.unavailable("手机储存空间不足，请先释放空间。已有录音仍保留。") }
    }

    private func activateRecordingSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateMeter() }
        }
    }

    private func updateMeter() {
        guard let recorder else { return }
        recordingTime = recorder.currentTime
        if state == .recording {
            if !recorder.isRecording {
                state = .interrupted
                level = 0
                checkpoint()
                informationMessage = "录音已中断，可继续或保存已有内容。"
                return
            }
            recorder.updateMeters()
            level = max(0, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 40)))
        }
        if Date.now.timeIntervalSince(checkpointAt) >= 5 {
            checkpoint()
            if state == .recording {
                do { try verifyFreeSpace() }
                catch { _ = stop(); errorMessage = error.localizedDescription }
            }
        }
    }

    private func checkpoint(finished: Bool = false) {
        guard let id = activeDraftID, let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].duration = max(recordings[index].duration, recordingTime)
        recordings[index].finished = finished
        recordings[index].interrupted = recordings[index].interrupted || state == .interrupted
        saveMetadata(recordings[index])
        checkpointAt = .now
    }

    private func saveMetadata(_ draft: NativeRecordingDraft) {
        let url = fileURL(for: draft).deletingPathExtension().appendingPathExtension("json")
        do {
            let data = try JSONEncoder().encode(draft)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        } catch { errorMessage = "录音文件仍保留，但保存录音信息失败。请检查手机储存空间。" }
    }

    nonisolated @objc private func audioInterruption(_ notification: Notification) {
        let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
        let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
        Task { @MainActor [weak self] in self?.handleInterruption(type: type, options: options) }
    }

    private func handleInterruption(type: UInt?, options: UInt) {
        guard let type, let interruption = AVAudioSession.InterruptionType(rawValue: type), recorder != nil else { return }
        if interruption == .began {
            recorder?.pause()
            recordingTime = recorder?.currentTime ?? recordingTime
            state = .interrupted
            level = 0
            checkpoint()
            informationMessage = "系统暂时占用了麦克风，已保留录音。"
        } else if wantsRecording && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
            resume()
        } else {
            informationMessage = "中断已结束，可继续录音或保存。"
        }
    }

    nonisolated @objc private func audioRouteChanged(_ notification: Notification) {
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
        Task { @MainActor [weak self] in
            guard let self, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue, self.state == .recording else { return }
            self.pause()
            self.informationMessage = "耳机或麦克风已断开，录音已暂停。确认输入设备后可继续。"
        }
    }

    nonisolated @objc private func audioServicesReset(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.hasActiveRecording else { return }
            _ = self.stop()
            self.informationMessage = "系统音频服务已重置，已有录音保留在本机。可新建录音继续。"
        }
    }

    nonisolated @objc private func applicationBackgrounded(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.checkpoint() }
    }

    nonisolated @objc private func applicationBecameActive(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.hasActiveRecording { self.updateMeter() } else { self.refresh() }
        }
    }

    nonisolated @objc private func applicationWillTerminate(_ notification: Notification) {
        // iOS does not guarantee this notification on force quit; source/checkpoints stay in Application Support.
        Task { @MainActor [weak self] in _ = self?.stop() }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.recorder?.url == url else { return }
            _ = self.stop()
            if !flag { self.errorMessage = "录音意外结束，已保留本机源文件。请检查后再分享或上传。" }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.recorder?.url == url else { return }
            _ = self.stop()
            self.errorMessage = "录音写入发生异常，已有源文件仍保留。请检查手机空间。"
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stopPlayback() }
    }
}

struct NativeLocationFix: Equatable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let measuredAt: Date
}

@MainActor
final class NativeLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: NativeLocationFix?
    @Published private(set) var isRequesting = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var timeoutTask: Task<Void, Never>?
    private var completion: ((NativeLocationFix) -> Void)?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.delegate = self
    }

    func request(completion: ((NativeLocationFix) -> Void)? = nil) {
        guard !isRequesting else { return }
        guard UIApplication.shared.applicationState == .active else { errorMessage = "请在 App 前台获取位置。"; return }
        errorMessage = nil
        self.completion = completion
        isRequesting = true
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.isRequesting else { return }
            self.fail("定位超时，请到信号更好的位置后重试。")
        }
        continueAfterAuthorization()
    }

    func cancel() {
        manager.stopUpdatingLocation()
        timeoutTask?.cancel()
        timeoutTask = nil
        isRequesting = false
        completion = nil
    }

    private func continueAfterAuthorization() {
        guard isRequesting else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .restricted, .denied: fail("定位权限未开启。可在「设置 → Luxquare → 位置」中允许使用 App 期间访问。")
        @unknown default: fail("暂时无法使用定位，请稍后重试。")
        }
    }

    private func fail(_ message: String) {
        cancel()
        errorMessage = message
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.continueAfterAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.filter({ $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 30 }).last else { return }
        let fix = NativeLocationFix(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude, accuracy: latest.horizontalAccuracy, measuredAt: latest.timestamp)
        Task { @MainActor [weak self] in
            guard let self, self.isRequesting else { return }
            let callback = self.completion
            self.location = fix
            self.cancel()
            callback?(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self, self.isRequesting else { return }
            self.fail(denied ? "定位权限已关闭，请在系统设置中开启。" : "暂时无法取得位置，请检查系统定位与信号后重试。")
        }
    }
}
