import AudioCore
import SwiftUI

struct AudioTrackView: View {
    let file: URL
    @ObservedObject var playback: PlaybackController
    let enabled: Bool
    var showFilename = false
    @State private var waveform: AudioWaveform?
    @State private var loadError: String?
    private var active: Bool { playback.currentURL == file }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Button { playback.toggle(file) } label: {
                    Image(systemName: active && playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(RecorderTheme.accent.opacity(active ? 0.22 : 0.12), in: Circle())
                }
                .foregroundStyle(RecorderTheme.accent)
                .disabled(!enabled)
                .accessibilityLabel(active && playback.isPlaying ? "暂停" : "播放")
                Text(active ? (playback.isPlaying ? "正在播放" : playback.finished ? "播放结束" : "已暂停") : "试听")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let waveform {
                NativeAudioTimeline(file: file, waveform: waveform, playback: playback,
                                    enabled: enabled, showFilename: showFilename)
                    .frame(height: 64)
            } else {
                HStack(spacing: 6) {
                    if loadError == nil { ProgressView().controlSize(.mini) }
                    Text(loadError == nil ? "读取音轨…" : "音轨读取失败")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }.frame(height: 64).accessibilityLabel(loadError ?? "正在读取音轨")
            }
        }
        .task(id: file) {
            do {
                let value = try await WaveformCache.shared.load(file)
                guard !Task.isCancelled else { return }
                waveform = value
            } catch { if !Task.isCancelled { loadError = error.localizedDescription } }
        }
    }
}

/// Small, bounded cache. Decode on one utility task at a time, away from scrolling/rendering.
private actor WaveformCache {
    static let shared = WaveformCache()
    private var values: [URL: AudioWaveform] = [:]
    private var order: [URL] = []
    private var pending: [URL: Task<AudioWaveform, Error>] = [:]
    private var tail: Task<Void, Never>?

    func load(_ file: URL) async throws -> AudioWaveform {
        if let value = values[file] { return value }
        if let task = pending[file] { return try await task.value }
        let previous = tail
        let task = Task.detached(priority: .utility) {
            await previous?.value
            return try AudioWaveform.read(file)
        }
        pending[file] = task
        tail = Task { _ = try? await task.value }
        do {
            let value = try await task.value
            pending[file] = nil
            values[file] = value
            order.append(file)
            if order.count > 24 { values.removeValue(forKey: order.removeFirst()) }
            return value
        } catch { pending[file] = nil; throw error }
    }
}
