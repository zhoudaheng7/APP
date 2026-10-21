import AudioToolbox
import Foundation

/// Best-effort physical feedback; iOS decides whether vibration is allowed in the background.
/// This does not activate an audio session or play an audible system sound.
final class RecordingFeedback: @unchecked Sendable {
    private let lock = NSLock()
    private var recording = false

    func started() { transition(to: true) }
    func stopped() { transition(to: false) }

    private func transition(to next: Bool) {
        lock.lock()
        let changed = recording != next
        recording = next
        lock.unlock()
        guard changed else { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
