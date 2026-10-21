import AVFoundation
import CoreMedia
import Foundation

/// Two independent PCM sources, one timestamp domain and one AAC writer.
/// The per-track AVAudioConverter/channel-map approach is adapted from
/// HaishinKit AudioMixerTrack (BSD-3-Clause); see Design/OPEN-SOURCE.md.
public final class AudioMixWriter: @unchecked Sendable {
    public enum Track: Int { case app, microphone }
    private struct Packet {
        let start: Int64
        let samples: [[Float]]
        var end: Int64 { start + Int64(samples[0].count) }
    }
    private let queue = DispatchQueue(label: "com.lightsquare.audio-mix", qos: .userInitiated)
    private let writer: AudioSegmentWriter
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var converters: [Int: AVAudioConverter] = [:]
    private var packets: [[Packet]] = [[], []]
    private var cursor: Int64?
    private var end: Int64 = 0
    private var finished = false
    private var failed = false
    private var failureMessage: String?
    private var lastSourceTime: [Int: Int64] = [:]
    private let gate = NSLock()
    private var pending = 0
    private var ingressClosed = false
    public var onError: (@Sendable (String) -> Void)?

    public init(writer: AudioSegmentWriter) { self.writer = writer }

    public func append(_ sample: CMSampleBuffer, track: Track) {
        gate.lock()
        guard !ingressClosed else { gate.unlock(); return }
        guard pending < 32 else {
            ingressClosed = true
            queue.async { self.fail("混音处理积压，录制已停止；部分输入未保存。") }
            gate.unlock()
            return
        }
        pending += 1
        queue.async { [self] in
            defer { gate.lock(); pending -= 1; gate.unlock() }
            guard !finished, !failed else { return }
            do {
                guard CMSampleBufferDataIsReady(sample),
                      let description = CMSampleBufferGetFormatDescription(sample),
                      let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description) as AVAudioFormat? else { throw AudioError.unsupportedFormat }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                guard time.isNumeric else { throw AudioError.unsupportedFormat }
                let start = CMTimeConvertScale(time, timescale: 48_000, method: .roundHalfAwayFromZero).value
                if let previous = lastSourceTime[track.rawValue], start <= previous { return }
                lastSourceTime[track.rawValue] = start
                let frames = CMSampleBufferGetNumSamples(sample)
                guard frames > 0, frames <= 96_000,
                      let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frames)) else { throw AudioError.unsupportedFormat }
                input.frameLength = AVAudioFrameCount(frames)
                guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList) == noErr else { throw AudioError.unsupportedFormat }
                var converter = converters[track.rawValue]
                if converter?.inputFormat != sourceFormat {
                    converter = AVAudioConverter(from: sourceFormat, to: format)
                    converter?.channelMap = sourceFormat.channelCount == 1 ? [0, 0] : [0, 1]
                    converter?.primeMethod = .none
                    converters[track.rawValue] = converter
                }
                guard let converter, let output = AVAudioPCMBuffer(pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(ceil(Double(frames) * 48_000 / sourceFormat.sampleRate)) + 32) else { throw AudioError.unsupportedFormat }
                var supplied = false
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return input
                }
                if status == .error { throw error ?? AudioError.encodingFailed as NSError }
                guard output.frameLength > 0, let channels = output.floatChannelData else { return }
                let values = (0..<2).map { Array(UnsafeBufferPointer(start: channels[$0], count: Int(output.frameLength))) }
                let packet = Packet(start: start, samples: values)
                // A source may resume after silence or deliver late buffers. Old
                // packets cannot change already written audio and must not pile up.
                if let cursor, packet.end <= cursor { return }
                if cursor == nil { cursor = start }
                packets[track.rawValue].append(packet)
                packets[track.rawValue].sort { $0.start < $1.start }
                end = max(end, packet.end)
                if track == .microphone { writer.noteMicrophoneInput() }
                // 150 ms reorder window lets either source arrive first; bounded by input time.
                try flush(until: end - 7_200)
            } catch { fail(error.localizedDescription) }
        }
        gate.unlock()
    }

    public func finish(reason: String? = nil, completion: @escaping @Sendable (SessionReport) -> Void) {
        gate.lock()
        ingressClosed = true
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            do { try flush(until: end) } catch { fail(error.localizedDescription) }
            packets = [[], []]
            writer.finish(reason: reason ?? failureMessage, completion: completion)
        }
        gate.unlock()
    }

    private func flush(until limit: Int64) throws {
        guard var position = cursor else { return }
        while position < limit {
            for track in 0..<2 { packets[track].removeAll { $0.end <= position } }
            // A suspension must not allocate/fill an unbounded gap.
            if let first = packets.flatMap({ $0 }).map(\.start).min(), first - position > 96_000 { position = first }
            let count = Int(min(480, limit - position))
            if count <= 0 { break }
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            pcm.frameLength = AVAudioFrameCount(count)
            let channels = pcm.floatChannelData!
            for channel in 0..<2 { channels[channel].initialize(repeating: 0, count: count) }
            for track in 0..<2 {
                for packet in packets[track] where packet.start < position + Int64(count) && packet.end > position {
                    let lower = max(position, packet.start), upper = min(position + Int64(count), packet.end)
                    for frame in lower..<upper {
                        for channel in 0..<2 {
                            // Headroom for correlated sources, no wraparound or sample clipping.
                            channels[channel][Int(frame - position)] += packet.samples[channel][Int(frame - packet.start)] * 0.5
                        }
                    }
                }
            }
            for channel in 0..<2 { for frame in 0..<count { channels[channel][frame] = min(1, max(-1, channels[channel][frame])) } }
            writer.append(try Self.sample(pcm, at: CMTime(value: position, timescale: 48_000)))
            position += Int64(count)
            for track in 0..<2 { packets[track].removeAll { $0.end <= position } }
        }
        cursor = position
    }

    public static func sample(_ pcm: AVAudioPCMBuffer, at time: CMTime) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(pcm.format.sampleRate)),
            presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: pcm.format.formatDescription,
            sampleCount: Int(pcm.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result) == noErr,
            let result, CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            bufferList: pcm.audioBufferList) == noErr, CMSampleBufferSetDataReady(result) == noErr else { throw AudioError.unsupportedFormat }
        return result
    }

    private func fail(_ message: String) {
        guard !failed else { return }
        failed = true
        failureMessage = message
        gate.lock()
        ingressClosed = true
        gate.unlock()
        onError?(message)
    }
}
