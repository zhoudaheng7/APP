import AVFoundation
import Foundation

public struct AudioWaveform: Sendable {
    public let peaks: [Float]
    public let duration: Double

    public static func read(_ url: URL, bins: Int = 64) throws -> AudioWaveform {
        let audio = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard audio.length > 0, bins > 0 else { return AudioWaveform(peaks: [], duration: 0) }
        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096)!
        var peaks = Array(repeating: Float.zero, count: bins)
        var offset: AVAudioFramePosition = 0
        while offset < audio.length {
            try audio.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, audio.length - offset)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0..<Int(buffer.frameLength) {
                let bin = min(bins - 1, Int((offset + Int64(frame)) * Int64(bins) / audio.length))
                for channel in 0..<Int(audio.processingFormat.channelCount) {
                    let value = abs(channels[channel][frame])
                    if value.isFinite { peaks[bin] = max(peaks[bin], value) }
                }
            }
            offset += Int64(buffer.frameLength)
        }
        return AudioWaveform(peaks: peaks, duration: Double(audio.length) / audio.processingFormat.sampleRate)
    }
}
