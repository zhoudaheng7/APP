import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackController: NSObject, ObservableObject {
    @Published var currentURL: URL?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var finished = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ url: URL) {
        do {
            try prepare(url)
            guard let player else { return }
            if isPlaying {
                player.pause()
                isPlaying = false
                timer?.invalidate()
            } else {
                if finished { player.currentTime = 0; currentTime = 0 }
                guard player.play() else { throw PlaybackFailure.cannotPlay }
                isPlaying = true
                finished = false
                startTimer()
            }
            error = nil
        } catch { self.error = "播放失败：\(error.localizedDescription)" }
    }

    func seek(_ url: URL, to seconds: Double) {
        do {
            try prepare(url)
            player?.currentTime = min(max(0, seconds), duration)
            currentTime = player?.currentTime ?? 0
            finished = false
        } catch { self.error = "定位失败：\(error.localizedDescription)" }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        finished = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func prepare(_ url: URL) throws {
        if currentURL == url, player != nil { return }
        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try AVAudioSession.sharedInstance().setActive(true)
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.delegate = self
        guard audio.prepareToPlay() else { throw PlaybackFailure.cannotPlay }
        player = audio
        currentURL = url
        duration = audio.duration
    }

    private func startTimer() {
        timer?.invalidate()
        let next = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.isPlaying = player.isPlaying
            }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
}

extension PlaybackController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.timer?.invalidate()
            self.isPlaying = false
            self.finished = true
            self.currentTime = self.duration
            if !flag { self.error = "播放未正常完成，请检查音频文件。" }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "音频解码失败"
        Task { @MainActor in
            guard self.player === player else { return }
            self.isPlaying = false; self.timer?.invalidate(); self.error = message
        }
    }
}

private enum PlaybackFailure: LocalizedError {
    case cannotPlay
    var errorDescription: String? { "系统无法播放此音频文件。" }
}
