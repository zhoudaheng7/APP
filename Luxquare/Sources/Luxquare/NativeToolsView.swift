import SwiftUI
import UIKit

@MainActor
struct NativeToolsView: View {
    @StateObject private var recorder = NativeRecorder.shared
    @StateObject private var locationService = NativeLocationService()
    @State private var pendingDelete: NativeRecordingDraft?
    @State private var sharingFile: NativeShareFile?
    @State private var preparingID: UUID?
    @State private var actionError: String?
    @State private var locationNotice: String?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var onRecordingReady: (URL) -> Void
    var onLocationReady: (Double, Double, Double) -> Void

    init(onRecordingReady: @escaping (URL) -> Void = { _ in }, onLocationReady: @escaping (Double, Double, Double) -> Void = { _, _, _ in }) {
        self.onRecordingReady = onRecordingReady
        self.onLocationReady = onLocationReady
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                recordingPanel
                if !recorder.recordings.isEmpty { recordingLibrary }
                locationPanel
                Text("录音先保存在本机。选择「加入录音总结」后再交给工作台处理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(background)
        .accessibilityIdentifier("native.tools.screen")
        .navigationTitle("随身工具")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharingFile) { file in
            NativeAudioShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("删除这段本机录音？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            if let draft = pendingDelete {
                Button("删除本机录音", role: .destructive) { recorder.delete(draft); pendingDelete = nil }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("服务器上已保存的内容不受影响。")
        }
        .alert("暂时无法完成", isPresented: Binding(get: { displayedError != nil }, set: { if !$0 { clearErrors() } })) {
            if displayedError?.contains("权限") == true {
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    clearErrors()
                }
            }
            Button("知道了", role: .cancel) { clearErrors() }
        } message: {
            Text(displayedError ?? "请稍后重试。")
        }
        .onAppear { recorder.refresh() }
    }

    private var displayedError: String? { actionError ?? recorder.errorMessage ?? locationService.errorMessage }

    private func clearErrors() {
        actionError = nil
        recorder.errorMessage = nil
        locationService.errorMessage = nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("把灵感留住")
                .font(.largeTitle.weight(.bold))
            Text("原生录音与定位，随工作自由切换。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private var recordingPanel: some View {
        VStack(spacing: 20) {
            HStack {
                Label("录音", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(recorder.isRecording ? Color.red : Color.secondary).frame(width: 6, height: 6)
                    Text(recorder.state.label).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Text(recorder.recordingTimeLabel)
                    .font(.system(size: 42, weight: .light, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .accessibilityLabel("录音时长 \(recorder.recordingTimeLabel)")
                NativeAudioMeter(level: recorder.level, isRecording: recorder.isRecording)
                    .frame(height: 36)
                    .accessibilityLabel(recorder.isRecording ? "正在接收麦克风声音" : "麦克风未在录音")
            }
            NativeGlassGroup {
                HStack(spacing: 12) {
                    if recorder.hasActiveRecording {
                        Button {
                            if recorder.isRecording { recorder.pause() } else { recorder.resume() }
                        } label: {
                            Label(recorder.isRecording ? "暂停" : "继续", systemImage: recorder.isRecording ? "pause.fill" : "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .modifier(NativeToolButtonStyle(prominent: false))
                        Button { _ = recorder.stop() } label: {
                            Label("保存录音", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .modifier(NativeToolButtonStyle(prominent: true))
                    } else {
                        Button { Task { await recorder.start() } } label: {
                            Label(recorder.state == .requestingPermission ? "等待授权" : "开始录音", systemImage: "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .modifier(NativeToolButtonStyle(prominent: true))
                        .disabled(recorder.state == .requestingPermission)
                    }
                }
                .controlSize(.large)
            }
            if let message = recorder.informationMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("支持锁屏继续录音，结束后保留在本机。")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var recordingLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本机录音").font(.headline)
                Text("\(recorder.recordings.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if recorder.playingDraftID != nil {
                    Button("停止播放") { recorder.stopPlayback() }.font(.caption)
                }
            }
            ForEach(recorder.recordings) { draft in
                recordingRow(draft)
            }
        }
    }

    private func recordingRow(_ draft: NativeRecordingDraft) -> some View {
        let isActive = recorder.activeDraftID == draft.id
        let isPreparing = preparingID == draft.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { recorder.togglePlayback(draft) } label: {
                    Image(systemName: recorder.playingDraftID == draft.id ? "stop.fill" : "play.fill")
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(recorder.hasActiveRecording || isPreparing)
                .accessibilityLabel(recorder.playingDraftID == draft.id ? "停止播放" : "播放录音")
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title).font(.subheadline.weight(.medium)).lineLimit(2)
                    HStack(spacing: 7) {
                        Text(isActive ? recorder.recordingTimeLabel : draft.durationLabel)
                        if isActive { Text("录制中") }
                        else if !draft.finished { Text("中断后保留") }
                        else { Text("已保存") }
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("分享音频", systemImage: "square.and.arrow.up") { prepare(draft, share: true) }
                    Button("删除本机录音", systemImage: "trash", role: .destructive) { pendingDelete = draft }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .disabled(isActive || isPreparing)
                .accessibilityLabel("录音操作")
            }
            if !isActive {
                Button { prepare(draft, share: false) } label: {
                    HStack(spacing: 8) {
                        if isPreparing { ProgressView().controlSize(.small) }
                        Label(isPreparing ? "正在准备音频" : "加入录音总结", systemImage: "arrow.up.doc")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(preparingID != nil || recorder.hasActiveRecording)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var locationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("当前位置", systemImage: "location")
                    .font(.headline)
                Spacer()
                if locationService.isRequesting { ProgressView().controlSize(.small) }
            }
            if let fix = locationService.location {
                Text(String(format: "%.5f, %.5f · 精度约 %.0f 米", fix.latitude, fix.longitude, fix.accuracy))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("只在你点击时获取一次，不持续追踪。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button {
                locationNotice = nil
                locationService.request { fix in
                    onLocationReady(fix.latitude, fix.longitude, fix.accuracy)
                    locationNotice = "位置已取得，可用于当前工作台操作。"
                }
            } label: {
                Label(locationService.isRequesting ? "正在定位" : "获取一次位置", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .modifier(NativeToolButtonStyle(prominent: false))
            .disabled(locationService.isRequesting)
            if let locationNotice { Text(locationNotice).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(20)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func prepare(_ draft: NativeRecordingDraft, share: Bool) {
        guard preparingID == nil else { return }
        preparingID = draft.id
        Task { @MainActor in
            defer { preparingID = nil }
            do {
                let url = try await recorder.prepareForSharing(draft)
                if share { sharingFile = NativeShareFile(url: url) }
                else { onRecordingReady(url) }
            } catch { actionError = error.localizedDescription }
        }
    }

    private var background: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if !reduceTransparency {
                LinearGradient(colors: [Color.indigo.opacity(0.09), .clear, Color.cyan.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
    }
}

private struct NativeAudioMeter: View {
    let level: Double
    let isRecording: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<29, id: \.self) { index in
                let distance = abs(Double(index) - 14) / 14
                let response = (1 - distance * 0.65) * level
                Capsule()
                    .fill(isRecording ? Color.accentColor.opacity(0.55 + 0.45 * (1 - distance)) : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: 4 + 30 * response)
            }
        }
        .animation(.easeOut(duration: 0.18), value: level)
    }
}

private struct NativeToolButtonStyle: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

private struct NativeGlassGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) { content }
        } else {
            content
        }
    }
}

private struct NativeShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct NativeAudioShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
