import SwiftUI
import AVFoundation

@main
struct CallAudioProbeApp: App {
    var body: some Scene { WindowGroup { ProbeHomeView().preferredColorScheme(.dark) } }
}

@MainActor
private struct ProbeHomeView: View {
    @StateObject private var capture = ProbeCaptureController()
    @StateObject private var playback = ProbePlayback()
    @State private var deleteTarget: ProbeRecord?
    @State private var message = ""
    private let accent = Color(red: 0.24, green: 0.86, blue: 0.78)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("独立实验 · 尚未验证通话双方", systemImage: "waveform.path")
                            .font(.headline).foregroundStyle(accent)
                        Text("分别保存内部音与麦克风两路音频。计时、文件大小或本方有声，都不表示录到了通话对方。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(capture.status).font(.subheadline)
                        HStack {
                            Button {
                                playback.stop()
                                capture.start()
                            } label: {
                                Text("开始采集实验").frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent).tint(accent)
                            .disabled(capture.phase != .idle)
                            if capture.phase != .idle {
                                Button("停止并保存", role: .destructive) {
                                    Task { await capture.stop() }
                                }.buttonStyle(.bordered).disabled(capture.phase == .stopping)
                            }
                        }
                    }.padding(.vertical, 5)
                }
                Section("实际收到的样本") {
                    signal("内部音", capture.systemStats)
                    signal("麦克风", capture.microphoneStats)
                }
                Section {
                    DisclosureGroup("如何验证 Phone／微信通话") {
                        Text("1. 在系统采集面板选择整个屏幕，并打开麦克风。画面直接丢弃，不写入文件。")
                        Text("2. 分别测试先采集后接通、先接通后采集。用耳机，让双方轮流说不同短句，再从系统采集标记或本页停止。")
                        Text("3. 分别试听内部音轨与麦克风轨。内部音轨必须能听见对方，才有进一步集成依据。外放串音或仅本方声音不能通过。")
                        Text("本实验使用独立应用标识，可与声屿并存。它没有快捷开录或自定义灵动岛；先核对真实通话采集能力。")
                    }.font(.subheadline)
                    if !capture.events.isEmpty {
                        DisclosureGroup("本次系统事件（\(capture.events.count)）") {
                            ForEach(Array(capture.events.enumerated()), id: \.offset) { _, event in
                                Text(event).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
                if !message.isEmpty { Section { Text(message).foregroundStyle(.orange) } }
                if !playback.status.isEmpty { Section { Text(playback.status).font(.footnote) } }
                Section("实验记录 · \(capture.records.count)") {
                    if capture.records.isEmpty { Text("还没有实验录音").foregroundStyle(.secondary) }
                    ForEach(capture.records) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(record.date, format: .dateTime.month().day().hour().minute()).font(.subheadline.bold())
                                Spacer()
                                Text(record.isActive ? "采集中" : "待试听核对").font(.caption).foregroundStyle(.secondary)
                                Button(role: .destructive) { deleteTarget = record } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless).disabled(record.isActive || capture.phase != .idle)
                            }
                            trackFiles("内部音", files: record.systemFiles)
                            trackFiles("麦克风", files: record.microphoneFiles)
                            if record.systemFiles.isEmpty && record.microphoneFiles.isEmpty {
                                Text("没有已完成的音频文件").font(.caption).foregroundStyle(.secondary)
                            }
                            DisclosureGroup("样本与事件详情") {
                                signal("内部音", record.systemStats)
                                signal("麦克风", record.microphoneStats)
                                Text(record.microphoneEnabled ? "系统选择器麦克风：开启" : "系统选择器麦克风：关闭")
                                Text("状态：\(record.state)")
                                if let error = record.error { Text(error).foregroundStyle(.orange) }
                                ForEach(Array(record.events.enumerated()), id: \.offset) { _, event in Text(event) }
                            }.font(.caption)
                        }.padding(.vertical, 5)
                    }
                }
            }
            .listStyle(.insetGrouped).tint(accent)
            .navigationTitle("通话采集实验")
            .toolbar { Button("刷新") { capture.refresh() }.disabled(capture.phase != .idle) }
            .alert("删除这次实验及全部附属文件？", isPresented: Binding(
                get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("取消", role: .cancel) { deleteTarget = nil }
                Button("删除", role: .destructive) {
                    guard let record = deleteTarget else { return }
                    playback.stop()
                    do { try capture.delete(record); message = "" }
                    catch { message = error.localizedDescription }
                    deleteTarget = nil
                }
            } message: { Text("音频、样本统计和诊断 JSON 会一起删除。") }
        }
    }

    private func signal(_ name: String, _ stats: ProbeSignalStats) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.subheadline.bold())
                Spacer()
                Text(stats.bufferCount == 0 ? "未收到样本" : !stats.hasDecodedSamples ? "无可分析 PCM" : stats.nonZeroSamples == 0 ? "收到静音样本" : "有非零样本 · 待试听")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("缓冲 \(stats.bufferCount) · 帧 \(stats.frameCount) · 非零样本 \(stats.nonZeroSamples)/\(stats.totalSamples)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(String(format: "峰值 %.5f · RMS %.5f", stats.peak, stats.rms))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let format = stats.format { Text(format.description).font(.caption).foregroundStyle(.secondary) }
            if !stats.errors.isEmpty { Text(stats.errors.joined(separator: "；")).font(.caption).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder
    private func trackFiles(_ name: String, files: [URL]) -> some View {
        ForEach(Array(files.enumerated()), id: \.element) { index, file in
            HStack(spacing: 10) {
                Button { playback.toggle(file) } label: {
                    Image(systemName: playback.playingURL == file ? "pause.circle.fill" : "play.circle.fill").font(.title2)
                }.buttonStyle(.borderless).disabled(capture.phase != .idle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(files.count > 1 ? "\(name) \(index + 1)" : name).font(.subheadline)
                    Text(fileSize(file)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if playback.currentURL == file { Text(playback.timeText).font(.caption.monospacedDigit()) }
                ShareLink(item: file) { Label("导出", systemImage: "square.and.arrow.up").font(.subheadline) }
                    .buttonStyle(.borderless).disabled(capture.phase != .idle)
            }
        }
    }

    private func fileSize(_ file: URL) -> String {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

@MainActor
private final class ProbePlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingURL: URL?
    @Published var currentURL: URL?
    @Published var status = ""
    @Published var timeText = ""
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var ownsAudioSession = false

    func toggle(_ url: URL) {
        if currentURL == url, let player {
            if player.isPlaying { player.pause(); playingURL = nil; timer?.invalidate(); status = "试听已暂停" }
            else { if player.currentTime >= player.duration { player.currentTime = 0 }; play(player, url) }
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            ownsAudioSession = true
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            player = newPlayer
            currentURL = url
            play(newPlayer, url)
        } catch { status = "试听失败：\(error.localizedDescription)" }
    }
    private func play(_ player: AVAudioPlayer, _ url: URL) {
        guard player.play() else { status = "无法开始试听"; return }
        playingURL = url
        status = "正在试听 · 仍需辨认是否包含对方声音"
        updateTime()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTime() }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        playingURL = nil; currentURL = nil; timeText = ""; status = ""
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }
    private func updateTime() {
        guard let player else { return }
        func clock(_ t: Double) -> String { let s = max(0, Int(t)); return String(format: "%d:%02d", s / 60, s % 60) }
        timeText = "\(clock(player.currentTime)) / \(clock(player.duration))"
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.timer?.invalidate(); self.timer = nil; self.playingURL = nil
            self.status = flag ? "试听结束，请核对两条音轨" : "试听中断"; self.updateTime()
        }
    }
}
