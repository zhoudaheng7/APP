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
    @State private var showHelp = false
    private var idle: Bool { recorder.phase == .idle && !recorder.libraryWorking && !recorder.externalRecording }

    var body: some View {
        NavigationStack {
            List {
                capturePanel.recorderRow()
                if !recorder.libraryMessage.isEmpty || playback.error != nil {
                    HStack(spacing: 8) {
                        if recorder.libraryWorking { ProgressView().controlSize(.mini) }
                        Text(playback.error ?? recorder.libraryMessage).font(.caption).foregroundStyle(.secondary)
                    }.recorderCard().recorderRow()
                }
                libraryHeading.recorderRow()
                if recorder.sessions.isEmpty {
                    Label("录制后即可试听、导出和管理", systemImage: "waveform")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .recorderCard().recorderRow()
                }
                ForEach(recorder.sessions) { session in
                    RecordingCardView(session: session, playback: playback,
                        check: recorder.checks[session.id], enabled: idle,
                        selecting: selecting, selected: selected.contains(session.id),
                        toggleSelected: {
                            if selected.contains(session.id) { selected.remove(session.id) }
                            else { selected.insert(session.id) }
                        }, inspect: { Task { await recorder.inspect(session) } },
                        merge: { playback.stop(); Task { await recorder.merge(ids: [session.id]) } },
                        delete: { pendingDelete = [session.id]; confirmDelete = true })
                        .recorderRow()
                }
                Text("时长受可用空间与系统状态影响，部分受保护内容无法录制。")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(.vertical, 6).recorderRow()
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .background(RecorderTheme.background)
            .navigationTitle("内录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "选择") { selecting.toggle(); selected.removeAll() }
                        .font(.subheadline).disabled(!idle)
                }
            }
            .refreshable { recorder.refreshSessions() }
            .sheet(isPresented: $showHelp) { helpSheet }
            .confirmationDialog("删除 \(pendingDelete.count) 条录音及其音频文件？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除录音", role: .destructive) {
                    playback.stop(); recorder.delete(ids: pendingDelete)
                    selected.subtract(pendingDelete); pendingDelete.removeAll()
                }
                Button("取消", role: .cancel) { pendingDelete.removeAll() }
            } message: { Text("删除后无法从 App 恢复。已导出的文件不会删除。") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && recorder.phase == .idle { recorder.refreshSessions() }
            }
        }
        .tint(RecorderTheme.accent).preferredColorScheme(.dark)
    }

    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform").foregroundStyle(RecorderTheme.accent)
                Text("只录内部声音").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("AUDIO ONLY").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RecorderTheme.accent.opacity(0.8))
            }
            Text("连续录制 · 不存画面 · 不录麦克风").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Button {
                playback.stop()
                if recorder.phase == .idle { recorder.start() }
                else { Task { await recorder.stop() } }
            } label: {
                Text(recorder.phase == .idle ? "开始内录" : "停止并保存")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .foregroundStyle(RecorderTheme.background)
                    .background(LinearGradient(colors: recorder.phase == .idle
                        ? [RecorderTheme.accent, RecorderTheme.blue] : [.orange, .red],
                        startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled([.starting, .stopping].contains(recorder.phase) || recorder.libraryWorking || recorder.externalRecording)
            if let report = recorder.report {
                HStack {
                    Text("已录 \(RecordingCardView.clock(report.audioSeconds))")
                    Spacer()
                    Text(report.audioSeconds > 5 && report.nonSilentBuffers == 0 ? "暂未检测到声音" : "有声缓冲 \(report.nonSilentBuffers)")
                        .foregroundStyle(report.audioSeconds > 5 && report.nonSilentBuffers == 0 ? Color.orange : .secondary)
                }.font(.system(size: 11, design: .monospaced))
                if let error = report.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                }
            } else {
                Text(recorder.externalRecording ? "控制中心正在录音，请从系统录屏按钮停止。"
                     : recorder.status == "准备好后点开始，再切到课程或其他播放 App。" ? "就绪 · 开始后切到播放 App" : recorder.status)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            HStack {
                Label("控制中心直录", systemImage: "record.circle").font(.system(size: 11, weight: .medium))
                Spacer()
                Button("使用说明") { showHelp = true }.font(.system(size: 11)).accessibilityIdentifier("recording-help")
            }
            Text("长按「录屏」→「内录 · 仅音频」→ 开始广播")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .recorderCard()
        .accessibilityElement(children: .contain).accessibilityIdentifier("capture-panel")
    }

    private var libraryHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("录音记录").font(.system(size: 13, weight: .semibold))
                Text("\(recorder.sessions.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                if selecting {
                    Text("已选 \(selected.count)").font(.caption2).foregroundStyle(.secondary)
                    Button("合并") {
                        playback.stop(); let ids = selected
                        Task { await recorder.merge(ids: ids); selected.removeAll(); selecting = false }
                    }.disabled(selected.count < 2 || !idle)
                    Button(role: .destructive) { pendingDelete = selected; confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }.disabled(selected.isEmpty || !idle).accessibilityLabel("删除所选录音")
                }
            }.font(.caption).buttonStyle(.borderless)
            if selecting { Text("按录音时间合并，原件保留。").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.padding(.top, 10).padding(.bottom, 3)
    }

    private var helpSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("从控制中心开始", systemImage: "record.circle").font(.headline)
                Text("下拉控制中心，长按「录屏」，选择「内录 · 仅音频」，再点「开始广播」。停止时点击系统录屏按钮，之后回到这里试听和导出。")
                Text("也可以直接使用首页的「开始内录」。录音会持续保存，不按分钟切段；程序只保存内部声音。")
                Text(recorder.controlCenterStatus).font(.caption).foregroundStyle(.secondary)
                Text("合并生成新录音并保留原件。删除无法撤销，重要录音请先导出。").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(20).font(.subheadline)
                .background(RecorderTheme.background)
                .navigationTitle("录音使用说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("知道了") { showHelp = false } } }
        }.presentationDetents([.medium, .large])
    }
}

private struct RecordingCardView: View {
    let session: SavedSession
    @ObservedObject var playback: PlaybackController
    let check: AudioCheck?
    let enabled: Bool
    let selecting: Bool
    let selected: Bool
    let toggleSelected: () -> Void
    let inspect: () -> Void
    let merge: () -> Void
    let delete: () -> Void
    @State private var showCheckDetail = false
    private var usable: Bool { enabled && !session.isActive }
    private var title: String {
        session.report.captureSource == "merged" ? "合并录音" : session.report.captureSource == "control-center" ? "控制中心" : "内部录音"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if selecting {
                    Button(action: toggleSelected) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3)
                    }.disabled(!usable).accessibilityLabel("选择这条录音")
                }
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(session.report.startedAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: session.isActive ? "record.circle.fill" : session.report.state == "finished" ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(session.isActive ? .red : .secondary)
                    .accessibilityLabel(session.isActive ? "录制中" : session.report.state == "finished" ? "已保存" : "需检查")
            }
            ForEach(session.audioFiles, id: \.self) { file in
                AudioTrackView(file: file, playback: playback, enabled: usable, showFilename: session.audioFiles.count > 1)
            }
            if session.audioFiles.isEmpty {
                Text(session.isActive ? "录制中，停止后可试听" : "暂无完整音频")
                    .font(.caption2).foregroundStyle(.secondary).frame(height: 28)
            }
            HStack(spacing: 8) {
                Button(check?.checking == true ? "检查中…" : "检查音轨", action: inspect)
                    .disabled(check?.checking == true || session.isActive)
                    .frame(minHeight: 44)
                if let check {
                    if check.checking { ProgressView().controlSize(.mini) }
                    else {
                        Text(check.passed ? "纯音频 ✓" : "检查详情")
                            .foregroundStyle(check.passed ? RecorderTheme.accent : .orange)
                            .accessibilityLabel(check.message)
                            .onTapGesture { showCheckDetail = true }
                    }
                }
                Spacer(minLength: 0)
                if session.audioFiles.count > 1 {
                    Button(action: merge) { Image(systemName: "arrow.triangle.merge") }
                        .frame(width: 44, height: 44).disabled(!usable).accessibilityLabel("合并为一个音频文件")
                }
                ShareLink(items: session.exportFiles) { Image(systemName: "square.and.arrow.up") }
                    .frame(width: 44, height: 44).disabled(session.exportFiles.isEmpty || session.isActive).accessibilityLabel("导出音频")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .frame(width: 44, height: 44).disabled(!usable).accessibilityLabel("删除这条录音")
            }
            .font(.system(size: 11, weight: .medium)).buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
        .recorderCard(padding: 10)
        .accessibilityElement(children: .contain).accessibilityIdentifier("recording-card")
        .alert("音轨检查", isPresented: $showCheckDetail) { Button("关闭", role: .cancel) {} }
            message: { Text(check?.message ?? "尚未检查") }
    }

    static func clock(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
