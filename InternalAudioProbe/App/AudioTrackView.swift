import AudioCore
import SwiftUI

struct AudioTrackView: View {
    let file: URL
    @ObservedObject var playback: PlaybackController
    let enabled: Bool
    @State private var waveform: AudioWaveform?
    @State private var loadError: String?
    private var active: Bool { playback.currentURL == file }
    private var duration: Double { active ? playback.duration : waveform?.duration ?? 0 }
    private var time: Double { active ? playback.currentTime : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { playback.toggle(file) } label: {
                    Image(systemName: active && playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                }.disabled(!enabled).accessibilityLabel(active && playback.isPlaying ? "暂停" : "播放")
                VStack(alignment: .leading, spacing: 3) {
                    Text(active ? (playback.isPlaying ? "正在播放" : playback.finished ? "播放结束" : "已暂停") : "点击播放试听")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(active && playback.isPlaying ? Color.accentColor : .primary)
                    Text("\(file.lastPathComponent) · \(sizeLabel)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("audio-file-size")
                }
                Spacer()
                Text("\(clock(time)) / \(clock(duration))").font(.caption.monospacedDigit())
            }
            if let waveform {
                WaveformBars(peaks: waveform.peaks, progress: duration > 0 ? time / duration : 0, active: active)
                    .frame(height: 56)
                    .accessibilityLabel("音频波形，已播放 \(Int(time)) 秒，共 \(Int(duration)) 秒")
            } else if let loadError {
                Text("波形读取失败：\(loadError)").font(.caption).foregroundStyle(.orange)
            } else {
                HStack { ProgressView(); Text("正在读取音轨波形…").font(.caption) }.frame(height: 56)
            }
            Slider(value: Binding(get: { min(time, max(0, duration)) }, set: { playback.seek(file, to: $0) }),
                   in: 0...max(0.01, duration))
                .disabled(!enabled || duration <= 0)
                .accessibilityLabel("播放进度，可拖动定位")
        }
        .padding(12)
        .background(active ? Color.accentColor.opacity(0.07) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .task(id: file) {
            do {
                waveform = try await Task.detached(priority: .utility) { try AudioWaveform.read(file) }.value
            } catch { loadError = error.localizedDescription }
        }
    }

    private func clock(_ value: Double) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private var sizeLabel: String {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct WaveformBars: View {
    let peaks: [Float]
    let progress: Double
    let active: Bool
    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let maximum = max(peaks.max() ?? 0, 0.0001)
            let step = size.width / Double(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let height = max(2, Double(sqrt(max(0, peak) / maximum)) * (size.height - 4))
                let bar = CGRect(x: Double(index) * step, y: (size.height - height) / 2, width: max(1, step - 2), height: height)
                let filled = active && Double(index) / Double(peaks.count) < progress
                context.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(filled ? .accentColor : .secondary.opacity(0.4)))
            }
            if active {
                let x = min(size.width - 1, max(1, progress * size.width))
                var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 0)); cursor.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(cursor, with: .color(.accentColor), lineWidth: 2)
            }
        }
    }
}
