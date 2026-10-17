import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackController: NSObject, ObservableObject {
    @Published var currentURL: URL?
    @Published var isPlaying = false
    // Read by the visible UIKit timeline; never publish a frame tick to the recording list.
    var currentTime: Double { finished ? duration : player?.currentTime ?? 0 }
    @Published var duration: Double = 0
    @Published var finished = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var resumeAfterScrub = false
    private(set) var seekCommitCount = 0

    func toggle(_ url: URL) {
        do {
            try prepare(url)
            guard let player else { return }
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                if finished { player.currentTime = 0 }
                guard player.play() else { throw PlaybackFailure.cannotPlay }
                isPlaying = true
                finished = false
            }
            error = nil
        } catch { self.error = "播放失败：\(error.localizedDescription)" }
    }

    func seek(_ url: URL, to seconds: Double) {
        do {
            try prepare(url)
            player?.currentTime = min(max(0, seconds), duration)
            finished = false
            seekCommitCount += 1
            if resumeAfterScrub { isPlaying = player?.play() == true }
            resumeAfterScrub = false
        } catch { self.error = "定位失败：\(error.localizedDescription)" }
    }

    func beginScrubbing(_ url: URL) {
        resumeAfterScrub = currentURL == url && isPlaying
        if resumeAfterScrub { player?.pause() }
    }

    func cancelScrubbing() {
        if resumeAfterScrub { isPlaying = player?.play() == true }
        resumeAfterScrub = false
    }

    func synchronizePlaybackState() {
        guard !resumeAfterScrub, let player, isPlaying != player.isPlaying else { return }
        // An interruption can pause AVAudioPlayer without its finish delegate firing.
        isPlaying = player.isPlaying
    }

    func stop() {
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
        duration = 0
        finished = false
        resumeAfterScrub = false
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

}

extension PlaybackController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.isPlaying = false
            self.finished = true
            if !flag { self.error = "播放未正常完成，请检查音频文件。" }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "音频解码失败"
        Task { @MainActor in
            guard self.player === player else { return }
            self.isPlaying = false; self.error = message
        }
    }
}

private enum PlaybackFailure: LocalizedError {
    case cannotPlay
    var errorDescription: String? { "系统无法播放此音频文件。" }
}
