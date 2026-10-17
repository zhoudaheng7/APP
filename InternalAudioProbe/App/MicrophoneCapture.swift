import AudioCore
import AVFoundation

/// Started only after an explicit mixed-mode selection and permission grant.
final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var installed = false
    func start(mixer: AudioMixWriter) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
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
        try engine.start()
    }
    func stop() {
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    deinit { stop() }
}
