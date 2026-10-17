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

struct RecorderView: View {
    @ObservedObject var recorder: CaptureController
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVAudioPlayer?
    @State private var playbackError: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("只保存内部声音", systemImage: "waveform")
                        .font(.title2.bold())
                    Text("默认关闭麦克风，画面不保存。系统仍可能显示屏幕采集提示。")
                        .foregroundStyle(.secondary)
                    Button {
                        player?.stop()
                        player = nil
                        if recorder.phase == .idle { recorder.start() }
                        else { Task { await recorder.stop() } }
                    } label: {
                        Label(recorder.phase == .idle ? "开始内录" : "停止并保存",
                              systemImage: recorder.phase == .idle ? "record.circle" : "stop.circle.fill")
                            .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.phase == .idle ? .blue : .red)
                    .disabled([.starting, .stopping].contains(recorder.phase))
                    Text(recorder.status).font(.callout)
                }
                if let report = recorder.report {
                    Section("本次采集") {
                        LabeledContent("已写入音频", value: String(format: "%.1f 秒", report.audioSeconds))
                        LabeledContent("非静音缓冲", value: "\(report.nonSilentBuffers) / \(report.audioBuffers)")
                        LabeledContent("已丢弃画面帧", value: "\(report.videoFramesDiscarded)")
                        LabeledContent("视频写入", value: "0 帧")
                        LabeledContent("编码来不及处理", value: "\(report.droppedBuffers) 个缓冲")
                        if report.audioSeconds > 5 && report.nonSilentBuffers == 0 {
                            Text("目前没有检测到声音。来源可能没有播放、处于静音或不允许采集。")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if !recorder.inspection.isEmpty {
                    Section("文件检查") { Text(recorder.inspection).font(.callout) }
                }
                if let playbackError { Section { Text(playbackError).foregroundStyle(.red) } }
                Section("录音记录 · 每分钟一段") {
                    if recorder.sessions.isEmpty { Text("结束录制后，这里会显示音频文件。").foregroundStyle(.secondary) }
                    ForEach(recorder.sessions) { session in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(session.report.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text("\(session.audioFiles.count) 段 · \(Int(session.report.audioSeconds)) 秒 · \(stateLabel(session.report.state))")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(session.audioFiles, id: \.self) { file in
                                HStack {
                                    Text(file.lastPathComponent).font(.caption.monospaced())
                                    Spacer()
                                    Button("试听") { play(file) }.disabled(recorder.phase != .idle)
                                }
                            }
                            HStack {
                                Button("检查音轨") { Task { await recorder.inspect(session) } }
                                Spacer()
                                ShareLink(items: session.exportFiles) { Label("导出", systemImage: "square.and.arrow.up") }
                            }.font(.callout)
                        }.padding(.vertical, 6).buttonStyle(.borderless)
                    }
                }
                Section("验证方法") {
                    Text("1. 点开始，在苹果系统界面允许采集。\n2. 切到课程或视频 App，播放一段能听清的内容。\n3. 回到这里停止，检查音轨并试听。\n4. 分别验证扬声器、耳机、切换 App 和长时间录制。")
                        .font(.callout)
                    Text("部分 App、受保护内容和通话声音可能无法捕获。切换到后台不等于锁屏录制，锁屏行为也需单独验证。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("内录验证")
            .onChange(of: scenePhase) { _, value in
                if value == .active && recorder.phase == .idle { recorder.refreshSessions() }
            }
        }
    }

    private func play(_ file: URL) {
        do {
            let next = try AVAudioPlayer(contentsOf: file)
            guard next.prepareToPlay(), next.play() else { throw PlaybackError.cannotPlay }
            player = next
            playbackError = nil
        } catch { playbackError = "试听失败：\(error.localizedDescription)" }
    }
    private func stateLabel(_ state: String) -> String {
        switch state {
        case "finished": return "已完成"
        case "silent": return "持续静音"
        case "no-audio": return "未收到音频"
        case "interrupted": return "中断，检查已保存分段"
        default: return "未正常结束，检查可恢复分段"
        }
    }
}

private enum PlaybackError: LocalizedError {
    case cannotPlay
    var errorDescription: String? { "系统无法播放此音频文件。" }
}
