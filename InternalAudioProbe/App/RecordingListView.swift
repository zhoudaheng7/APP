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
                    Label("暂无录音", systemImage: "waveform")
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
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .background(RecorderTheme.background)
            .navigationTitle("声屿").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "选择") { selecting.toggle(); selected.removeAll() }
                        .font(.subheadline).disabled(!idle)
                }
            }
            .refreshable { recorder.refreshSessions() }
            .sheet(isPresented: $showHelp) { helpSheet }
            .sheet(isPresented: $recorder.showQuickMenu) { quickMenuSheet }
            .confirmationDialog("删除 \(pendingDelete.count) 条录音？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除录音", role: .destructive) {
                    playback.stop(); recorder.delete(ids: pendingDelete)
                    selected.subtract(pendingDelete); pendingDelete.removeAll()
                }
                Button("取消", role: .cancel) { pendingDelete.removeAll() }
            } message: { Text("删除后无法恢复。已导出文件保留。") }
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
                Menu {
                    Button("仅内部音") { recorder.microphoneEnabled = false; RecordingPaths.microphonePreference = false }
                    Button("内部音＋麦克风") { recorder.microphoneEnabled = true; RecordingPaths.microphonePreference = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(recorder.microphoneEnabled ? "内部音＋麦克风" : "仅内部音")
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                }.disabled(!idle).accessibilityIdentifier("recording-mode")
                Spacer()
                Text("纯音频").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(RecorderTheme.accent.opacity(0.8))
            }
            Text(recorder.microphoneEnabled ? "内部音与麦克风混为一份" : "麦克风关闭")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
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
                    Text(report.audioSeconds > 5 && report.nonSilentBuffers == 0 ? "未检测到声音" : report.nonSilentBuffers > 0 ? "已检测到声音" : "等待声音")
                        .foregroundStyle(report.audioSeconds > 5 && report.nonSilentBuffers == 0 ? Color.orange : .secondary)
                }.font(.system(size: 11, design: .monospaced))
                if let error = report.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                } else if recorder.phase == .idle && ["no-audio", "silent"].contains(report.state) {
                    Text(recorder.status).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                }
            } else {
                Text(recorder.externalRecording ? "控制中心录音中 · 从系统停止" : recorder.status)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            HStack {
                Button { recorder.showQuickMenu = true } label: { Label("快捷录音", systemImage: "record.circle") }
                    .font(.system(size: 11, weight: .medium)).accessibilityIdentifier("quick-recording-menu")
                Spacer()
                Button("帮助") { showHelp = true }.font(.system(size: 11)).accessibilityIdentifier("recording-help")
            }
        }
        .recorderCard()
        // Multiple automatic Buttons inside one List row otherwise activate together.
        .buttonStyle(.borderless)
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
            if selecting { Text("按时间合并，保留原件。").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.padding(.top, 10).padding(.bottom, 3)
    }

    private var helpSheet: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 14) {
                Text("开始：选择模式，点「开始内录」，确认系统授权后切到播放 App。")
                Text("停止：长按灵动岛点「停止并保存」，或回到 App 停止。")
                Text("控制中心：长按「录屏」，选择「声屿 · 仅音频」开始，从系统录屏按钮停止。")
                Text("控制中心混音需开启麦克风。")
                Text("快捷指令：搜索「声屿」，选择录音菜单或任一模式。")
                Text("合并保留原件；删除无法撤销。").font(.caption).foregroundStyle(.secondary)
            }.padding(20).font(.subheadline) }
                .background(RecorderTheme.background)
                .navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showHelp = false } } }
        }.presentationDetents([.medium, .large])
    }

    private var quickMenuSheet: some View {
        NavigationStack {
            List {
                Button("仅内部音") { startFromMenu(microphone: false) }
                Button("内部音＋麦克风") { startFromMenu(microphone: true) }
            }.navigationTitle("选择模式").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { recorder.showQuickMenu = false } } }
        }.tint(RecorderTheme.accent).preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
    }

    private func startFromMenu(microphone: Bool) {
        recorder.showQuickMenu = false
        playback.stop()
        Task { @MainActor in
            // Let the menu sheet dismiss before presenting the system picker/permission alert.
            try? await Task.sleep(for: .milliseconds(350))
            do { try await recorder.prepareStart(microphone: microphone) }
            catch { recorder.status = error.localizedDescription }
        }
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
        session.report.captureSource == "merged" ? "合并录音" : session.report.microphoneRecorded ? "混音录音" : session.report.captureSource == "control-center" ? "控制中心" : "内部录音"
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
            if session.report.microphoneRequested == true && !session.report.microphoneRecorded && !session.isActive {
                Text("未收到麦克风声音，请检查麦克风开关。")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button(check?.checking == true ? "检查中…" : "检查音轨", action: inspect)
                    .disabled(check?.checking == true || session.isActive)
                    .frame(minHeight: 44)
                if let check {
                    if check.checking { ProgressView().controlSize(.mini) }
                    else {
                        Text(check.message)
                            .foregroundStyle(check.passed ? RecorderTheme.accent : .orange)
                            .lineLimit(1)
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
