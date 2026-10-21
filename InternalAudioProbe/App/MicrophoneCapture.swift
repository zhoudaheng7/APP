import AudioCore
import AVFoundation

/// Started only after an explicit mixed-mode selection and permission grant.
final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var installed = false
    private var ownsSession = false
    private var previousHapticsPolicy: Bool?
    func start(mixer: AudioMixWriter) throws {
        pause()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        ownsSession = true
        if previousHapticsPolicy == nil { previousHapticsPolicy = session.allowHapticsAndSystemSoundsDuringRecording }
        // Permit start feedback for our own microphone session; failure must not stop audio.
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.unsupportedFormat }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { pcm, when in
            // ScreenCaptureKit PTS and AVAudioEngine hostTime use the system host clock.
            guard when.isHostTimeValid,
                  let sample = try? AudioMixWriter.sample(pcm, at: CMClockMakeHostTimeFromSystemUnits(when.hostTime)) else { return }
            mixer.append(sample, track: .microphone)
        }
        installed = true
        engine.prepare()
        do { try engine.start() }
        catch { pause(); throw error }
    }
    func pause() {
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
    }
    func stop() {
        pause()
        guard ownsSession else { return }
        ownsSession = false
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let previousHapticsPolicy { try? session.setAllowHapticsAndSystemSoundsDuringRecording(previousHapticsPolicy) }
        previousHapticsPolicy = nil
    }
    deinit { stop() }
}
