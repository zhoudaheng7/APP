import AudioCore
import SwiftUI

struct RecorderView: View {
    @ObservedObject var recorder: CaptureController
    @StateObject private var playback = PlaybackController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var pendingDelete: Set<UUID> = []
    @State private var confirmDelete = false
    private var idle: Bool { recorder.phase == .idle && !recorder.libraryWorking && !recorder.externalRecording }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("只保存内部声音", systemImage: "waveform").font(.title2.bold())
                    Text("持续录制，不按分钟切段。麦克风关闭，画面不保存。")
                        .foregroundStyle(.secondary)
                    Button {
                        playback.stop()
                        if recorder.phase == .idle { recorder.start() }
                        else { Task { await recorder.stop() } }
                    } label: {
                        Label(recorder.phase == .idle ? "开始内录" : "停止并保存",
                              systemImage: recorder.phase == .idle ? "record.circle" : "stop.circle.fill")
                            .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.phase == .idle ? .blue : .red)
                    .disabled([.starting, .stopping].contains(recorder.phase) || recorder.libraryWorking || recorder.externalRecording)
                    Text(recorder.status).font(.callout)
                }
                if let report = recorder.report {
                    Section("本次采集") {
                        LabeledContent("已写入音频", value: durationLabel(report.audioSeconds))
                        LabeledContent("收到有声数据", value: "\(report.nonSilentBuffers) / \(report.audioBuffers)")
                        if report.audioSeconds > 5 && report.nonSilentBuffers == 0 {
                            Text("目前未检测到声音，请确认来源正在播放且允许采集。")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Section("从控制中心直接开录") {
                    if recorder.externalRecording {
                        Label("控制中心录音进行中，请先从系统录屏按钮停止。", systemImage: "record.circle.fill")
                            .foregroundStyle(.red)
                    }
                    Text("下拉控制中心 → 长按「录屏」→ 选择「内录 · 仅音频」→ 开始广播。")
                        .font(.callout)
                    Text(recorder.controlCenterStatus).font(.caption).foregroundStyle(.secondary)
                }
                if !recorder.libraryMessage.isEmpty || playback.error != nil {
                    Section {
                        if recorder.libraryWorking { ProgressView() }
                        if !recorder.libraryMessage.isEmpty { Text(recorder.libraryMessage).font(.callout) }
                        if let error = playback.error { Text(error).font(.callout).foregroundStyle(.red) }
                    }
                }
                if selecting {
                    Section {
                        HStack {
                            Text("已选 \(selected.count) 条").font(.subheadline)
                            Spacer()
                            Button("合并所选") {
                                playback.stop()
                                let ids = selected
                                Task { await recorder.merge(ids: ids); selected.removeAll(); selecting = false }
                            }.disabled(selected.count < 2 || !idle)
                            Button(role: .destructive) { pendingDelete = selected; confirmDelete = true } label: {
                                Image(systemName: "trash")
                            }.disabled(selected.isEmpty || !idle)
                        }.buttonStyle(.borderless)
                        Text("合并按录音开始时间排序，生成一条新录音，原记录保留。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("录音记录") {
                    if recorder.sessions.isEmpty {
                        Text("录制结束后，这里会显示音轨、播放进度和导出入口。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(recorder.sessions) { session in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                if selecting {
                                    Button {
                                        if selected.contains(session.id) { selected.remove(session.id) }
                                        else { selected.insert(session.id) }
                                    } label: {
                                        Image(systemName: selected.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                    }.disabled(session.isActive || !idle)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.report.captureSource == "merged" ? "合并录音" : session.report.captureSource == "control-center" ? "控制中心录音" : "内部录音")
                                        .font(.headline)
                                    Text(session.report.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(session.isActive ? "录制中" : stateLabel(session.report.state))
                                    .font(.caption).foregroundStyle(session.isActive ? .red : .secondary)
                            }
                            ForEach(session.audioFiles, id: \.self) { file in
                                AudioTrackView(file: file, playback: playback, enabled: idle && !session.isActive)
                            }
                            if session.audioFiles.count > 1 {
                                Button("合并为一个音频文件") {
                                    playback.stop()
                                    Task { await recorder.merge(ids: [session.id]) }
                                }.disabled(!idle || session.isActive)
                            }
                            if let check = recorder.checks[session.id] {
                                HStack(alignment: .top, spacing: 8) {
                                    if check.checking { ProgressView() }
                                    else { Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") }
                                    Text(check.message).font(.caption)
                                }
                                .foregroundStyle(check.checking ? Color.secondary : check.passed ? .green : .orange)
                            }
                            HStack {
                                Button(recorder.checks[session.id]?.checking == true ? "检查中…" : "检查音轨") {
                                    Task { await recorder.inspect(session) }
                                }.disabled(recorder.checks[session.id]?.checking == true || session.isActive)
                                Spacer()
                                ShareLink(items: session.exportFiles) {
                                    Label("导出音频", systemImage: "square.and.arrow.up")
                                }.disabled(session.exportFiles.isEmpty || session.isActive)
                                Button(role: .destructive) {
                                    pendingDelete = [session.id]
                                    confirmDelete = true
                                } label: { Image(systemName: "trash") }
                                    .disabled(!idle || session.isActive)
                                    .accessibilityLabel("删除这条录音")
                            }.font(.callout)
                        }.padding(.vertical, 8).buttonStyle(.borderless)
                    }
                }
                Section {
                    Text("录音长度取决于可用空间、系统运行及播放来源，停止或系统中断时结束。部分课程、受保护内容和通话声音可能无法捕获。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("内录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "选择") { selecting.toggle(); selected.removeAll() }
                        .disabled(!idle)
                }
            }
            .refreshable { recorder.refreshSessions() }
            .confirmationDialog("删除 \(pendingDelete.count) 条录音及其音频文件？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除录音", role: .destructive) {
                    playback.stop()
                    recorder.delete(ids: pendingDelete)
                    selected.subtract(pendingDelete)
                    pendingDelete.removeAll()
                }
                Button("取消", role: .cancel) { pendingDelete.removeAll() }
            } message: {
                Text("删除后无法从 App 恢复。已经导出到其他位置的文件不会删除。")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && recorder.phase == .idle { recorder.refreshSessions() }
            }
        }
    }

    private func durationLabel(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    private func stateLabel(_ state: String) -> String {
        switch state {
        case "finished": return "已保存"
        case "silent": return "持续静音"
        case "no-audio": return "未收到音频"
        case "interrupted": return "已中断"
        default: return "未正常结束"
        }
    }
}
