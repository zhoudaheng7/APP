import Foundation
import AVFoundation
import UIKit

final class SoundFeedback {
    static let shared = SoundFeedback()
    private var player: AVAudioPlayer?
    private init() {}
    @discardableResult func play(sending: Bool, pack: SoundPack? = nil) -> String? {
        let defaults = UserDefaults.standard
        let selected = pack ?? SoundPack(rawValue: defaults.string(forKey: sending ? "flick.sound.send" : "flick.sound.receive") ?? "swish") ?? .swish
        guard let resource = selected.resource(sending: sending) else { player?.stop(); return nil }
        let level = defaults.object(forKey: "flick.sound.volume") as? Double ?? 0.45
        guard level > 0 else { player?.stop(); return nil }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else { return "音效资源未找到。" }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.volume = Float(min(1, max(0, level))); audio.prepareToPlay()
            player?.stop(); player = audio
            guard audio.play() else { return "声音暂时无法播放，请稍后重试。" }
            return nil
        } catch { return "音效播放失败：\(error.localizedDescription)" }
    }
    func stop() { player?.stop() }
}
enum FlickFeedback {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "flick.haptics") as? Bool ?? true }
    static func selection() { if enabled { UISelectionFeedbackGenerator().selectionChanged() } }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) { if enabled { UIImpactFeedbackGenerator(style: style).impactOccurred() } }
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) { if enabled { UINotificationFeedbackGenerator().notificationOccurred(type) } }
}
