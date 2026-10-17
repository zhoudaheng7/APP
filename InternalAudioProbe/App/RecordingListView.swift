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
                Menu {
                    Button("仅内部音") { recorder.microphoneEnabled = false; RecordingPaths.microphonePreference = false }
                    Button("内部音＋麦克风") { recorder.microphoneEnabled = true; RecordingPaths.microphonePreference = true }
                    Button("快捷指令与通话说明") { showHelp = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(recorder.microphoneEnabled ? "内部音＋麦克风" : "仅内部声音")
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                }.disabled(!idle).accessibilityIdentifier("recording-mode")
                Spacer()
                Text("AUDIO ONLY").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RecorderTheme.accent.opacity(0.8))
            }
            Text(recorder.microphoneEnabled ? "连续录制 · 不存画面 · 两路混成一个文件" : "连续录制 · 不存画面 · 麦克风关闭")
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
                Button { recorder.showQuickMenu = true } label: { Label("快捷录音", systemImage: "record.circle") }
                    .font(.system(size: 11, weight: .medium)).accessibilityIdentifier("quick-recording-menu")
                Spacer()
                Button("使用说明") { showHelp = true }.font(.system(size: 11)).accessibilityIdentifier("recording-help")
            }
            Text("长按灵动岛 → 停止并保存 · 支持快捷指令入口")
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
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                Label("从控制中心开始", systemImage: "record.circle").font(.headline)
                Text("下拉控制中心，长按「录屏」，选择「声屿 · 仅音频」，再点「开始广播」。停止时点击系统录屏按钮，之后回到这里试听和导出。")
                Text("App 或快捷指令开始的录音：录前选择仅内部音或内部音＋麦克风，通过系统授权后开录。长按灵动岛展开，再点「停止并保存」；关闭实时活动时需从 App 或系统停止。")
                Text("快捷指令中搜索「声屿」，可用「录音菜单」「仅内部音」「内部音＋麦克风」。组合菜单：第一层通话说明／内部录音，内部录音再选两种模式。系统采集确认不能跳过。")
                Text("控制中心独立开录沿用 App 最近选择的麦克风模式。混音还需先在系统录屏面板开启麦克风；未收到麦克风样本不会记成混音成功。独立广播不能保证创建声屿灵动岛，请从系统录屏停止。")
                NavigationLink("通话录音方案说明") {
                    ScrollView { callInfoContent }.navigationTitle("通话录音").navigationBarTitleDisplayMode(.inline)
                }
                Text(recorder.controlCenterStatus).font(.caption).foregroundStyle(.secondary)
                Text("合并生成新录音并保留原件。删除无法撤销，重要录音请先导出。").font(.caption).foregroundStyle(.secondary)
            }.padding(20).font(.subheadline) }
                .background(RecorderTheme.background)
                .navigationTitle("录音使用说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("知道了") { showHelp = false } } }
        }.presentationDetents([.medium, .large])
    }

    private var callInfoContent: some View {
                VStack(alignment: .leading, spacing: 16) {
                    Text("通话采集尚未接通").font(.title3.bold())
                    Text("此版本不能用声屿直接开始或停止系统电话、微信或 WhatsApp 的双向通话录音。快捷指令不会增加通话音频权限，打开麦克风也不等于录到通话双方。")
                    Text("找到的 AirBeep 只调整系统通话录音提示音；TrollRecorder 需要 TrollStore 或越狱环境。它们暂不能拼成当前企业签名包可用的双向通话录音。")
                    Link("查看 AirBeep 源码", destination: URL(string: "https://github.com/LinkPass888/AirBeep")!)
                    Link("查看 TrollRecorder 源码", destination: URL(string: "https://github.com/Lessica/TrollRecorder")!)
                    Text("系统电话录音请使用电话 App 自身提供的功能，录音由系统管理；声屿灵动岛不能控制它。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
    }

    private var quickMenuSheet: some View {
        NavigationStack {
            List {
                NavigationLink("通话录音（方案说明）") {
                    ScrollView { callInfoContent }.navigationTitle("通话录音").navigationBarTitleDisplayMode(.inline)
                }
                NavigationLink("内部录音") {
                    List {
                        Button("仅内部音") { startFromMenu(microphone: false) }
                        Button("内部音＋麦克风") { startFromMenu(microphone: true) }
                    }.navigationTitle("内部录音").navigationBarTitleDisplayMode(.inline)
                }
            }.navigationTitle("选择录音").navigationBarTitleDisplayMode(.inline)
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
                Text("未收到麦克风声音，请检查系统麦克风开关。")
                    .font(.system(size: 10)).foregroundStyle(.orange)
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
