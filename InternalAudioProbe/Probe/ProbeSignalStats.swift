import AVFoundation
import CoreMedia
import Foundation

/// A description of the declared format, not a claim about the source of its sound.
struct ProbePCMFormat: Codable, Sendable, Equatable, CustomStringConvertible {
    let formatID: UInt32
    let flags: UInt32
    let sampleRate: Double
    let channels: UInt32
    let bitsPerChannel: UInt32
    let bytesPerFrame: UInt32
    let interleaved: Bool
    let encoding: String

    var description: String {
        "\(encoding) · \(sampleRate) Hz · \(channels) ch · \(interleaved ? "interleaved" : "planar")"
    }

    fileprivate init(_ asbd: AudioStreamBasicDescription) {
        formatID = asbd.mFormatID
        flags = asbd.mFormatFlags
        // A malformed format must not put NaN/Inf in the JSON report.
        sampleRate = asbd.mSampleRate.isFinite ? asbd.mSampleRate : 0
        channels = asbd.mChannelsPerFrame
        bitsPerChannel = asbd.mBitsPerChannel
        bytesPerFrame = asbd.mBytesPerFrame
        interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            encoding = "float\(asbd.mBitsPerChannel)"
        } else if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 {
            encoding = "int\(asbd.mBitsPerChannel)"
        } else {
            encoding = "unsupported-\(asbd.mBitsPerChannel)bit"
        }
    }
}

/// Statistics only: this value never retains a sample buffer, PCM pointer, or audio copy.
///
/// The owner must call `consume` on one serial callback queue and synchronize any
/// cross-thread value copies. This type deliberately does not dispatch to the main
/// queue. `hasSignal` means finite, nonzero PCM was observed; it cannot establish
/// that either participant, much less both participants, was captured.
struct ProbeSignalStats: Codable, Sendable {
    private(set) var bufferCount = 0
    private(set) var analyzedBufferCount = 0
    private(set) var unsupportedBufferCount = 0
    private(set) var invalidBufferCount = 0
    /// Frames in buffers whose PCM layout was successfully decoded.
    private(set) var frameCount: Int64 = 0
    /// Scalar samples, across all channels, including non-finite float samples.
    private(set) var totalSamples: Int64 = 0
    private(set) var nonZeroSamples: Int64 = 0
    private(set) var invalidSamples: Int64 = 0
    private(set) var peak: Double = 0
    private(set) var rms: Double = 0
    /// Finite presentation timestamps of received, valid sample buffers, in seconds.
    private(set) var firstPTS: Double?
    private(set) var lastPTS: Double?
    private(set) var format: ProbePCMFormat?
    private(set) var formatChanges = 0
    /// Bounded, deduplicated diagnostics. errorCount also counts repeated errors.
    private(set) var errors: [String] = []
    private(set) var errorCount = 0

    // Scaled sum of squares avoids overflow even for very large finite float64 PCM.
    private var squareScale: Double = 0
    private var scaledSumSquares: Double = 0

    var finiteSampleCount: Int64 { totalSamples - invalidSamples }
    var hasDecodedSamples: Bool { finiteSampleCount > 0 }
    var hasSignal: Bool { nonZeroSamples > 0 }
    var nonZeroFraction: Double {
        finiteSampleCount > 0 ? Double(nonZeroSamples) / Double(finiteSampleCount) : 0
    }

    init() {}

    mutating func consume(_ sampleBuffer: CMSampleBuffer) {
        consume(sampleBuffer as CMSampleBuffer?)
    }

    /// The optional overload makes nil callbacks diagnosable without crashing.
    mutating func consume(_ sampleBuffer: CMSampleBuffer?) {
        bufferCount += 1
        guard let sampleBuffer, CMSampleBufferIsValid(sampleBuffer) else {
            invalidBufferCount += 1
            recordError("invalidSampleBuffer")
            return
        }
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if seconds.isFinite {
            if firstPTS == nil { firstPTS = seconds }
            lastPTS = seconds
        } else {
            recordError("invalidPresentationTimestamp")
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            invalidBufferCount += 1
            recordError("sampleDataNotReady")
            return
        }
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            invalidBufferCount += 1
            recordError("missingAudioFormat")
            return
        }

        let nextFormat = ProbePCMFormat(asbd)
        if let format, format != nextFormat { formatChanges += 1 }
        format = nextFormat
        let floating = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let signed = asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        let supportedBits = floating
            ? (asbd.mBitsPerChannel == 32 || asbd.mBitsPerChannel == 64)
            : (signed && (asbd.mBitsPerChannel == 16 || asbd.mBitsPerChannel == 32))
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              supportedBits, !(floating && signed),
              asbd.mSampleRate.isFinite, asbd.mSampleRate > 0,
              asbd.mChannelsPerFrame > 0, asbd.mChannelsPerFrame <= 1_024 else {
            unsupportedBufferCount += 1
            recordError("unsupportedPCMFormat: id=\(asbd.mFormatID), flags=\(asbd.mFormatFlags), bits=\(asbd.mBitsPerChannel)")
            return
        }

        let channels = Int(asbd.mChannelsPerFrame)
        let sampleBytes = Int(asbd.mBitsPerChannel / 8)
        let planar = !nextFormat.interleaved
        let expectedBytesPerFrame = sampleBytes * (planar ? 1 : channels)
        // Packed 16/32-bit integers and 32/64-bit floats only. Padded/high-aligned
        // or fractional-bit formats need another decoder, never a "silent" result.
        guard Int(asbd.mBytesPerFrame) == expectedBytesPerFrame else {
            unsupportedBufferCount += 1
            recordError("unsupportedPCMStride: \(asbd.mBytesPerFrame)")
            return
        }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else {
            invalidBufferCount += 1
            recordError("emptyPCMBuffer")
            return
        }
        let (requiredBytes, byteOverflow) = frames.multipliedReportingOverflow(by: expectedBytesPerFrame)
        let (scalarCount, sampleOverflow) = Int64(frames).multipliedReportingOverflow(by: Int64(channels))
        guard !byteOverflow, !sampleOverflow,
              frameCount <= Int64.max - Int64(frames),
              totalSamples <= Int64.max - scalarCount else {
            invalidBufferCount += 1
            recordError("sampleCountOverflow")
            return
        }

        let expectedBuffers = planar ? channels : 1
        let list = AudioBufferList.allocate(maximumBuffers: expectedBuffers)
        defer { list.unsafeMutablePointer.deallocate() }
        var retainedBlock: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list.unsafeMutablePointer,
            bufferListSize: MemoryLayout<AudioBufferList>.size + (expectedBuffers - 1) * MemoryLayout<AudioBuffer>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlock
        )
        defer { withExtendedLifetime(retainedBlock) {} }
        guard status == noErr else {
            invalidBufferCount += 1
            recordError("audioBufferListError: \(status)")
            return
        }
        // Check the returned count before using the list's collection iterator.
        guard Int(list.unsafeMutablePointer.pointee.mNumberBuffers) == expectedBuffers else {
            invalidBufferCount += 1
            recordError("unexpectedAudioBufferCount")
            return
        }
        for buffer in list {
            guard buffer.mNumberChannels == (planar ? 1 : asbd.mChannelsPerFrame),
                  buffer.mData != nil, Int(buffer.mDataByteSize) >= requiredBytes else {
                invalidBufferCount += 1
                recordError("invalidPCMLayoutOrLength")
                return
            }
        }

        let bigEndian = asbd.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
        var badSamples: Int64 = 0
        for buffer in list {
            guard let data = buffer.mData else { continue } // Already validated above.
            let bytes = UnsafeRawBufferPointer(start: data, count: requiredBytes)
            let samplesInBuffer = frames * (planar ? 1 : channels)
            for index in 0..<samplesInBuffer {
                let value = Self.decode(bytes, at: index * sampleBytes,
                                        bytes: sampleBytes, floating: floating, bigEndian: bigEndian)
                guard value.isFinite else {
                    badSamples += 1
                    continue
                }
                let magnitude = abs(value)
                peak = max(peak, magnitude)
                if magnitude != 0 {
                    nonZeroSamples += 1
                    if squareScale < magnitude {
                        let ratio = squareScale / magnitude
                        scaledSumSquares = 1 + scaledSumSquares * ratio * ratio
                        squareScale = magnitude
                    } else {
                        let ratio = magnitude / squareScale
                        scaledSumSquares += ratio * ratio
                    }
                }
            }
        }
        analyzedBufferCount += 1
        frameCount += Int64(frames)
        totalSamples += scalarCount
        invalidSamples += badSamples
        if badSamples > 0 {
            invalidBufferCount += 1
            recordError("nonFinitePCMSamples")
        }
        if finiteSampleCount > 0, squareScale > 0 {
            rms = squareScale * min(1, sqrt(scaledSumSquares / Double(finiteSampleCount)))
        }
    }

    /// Convenience alias; it has the same serial-queue requirement as consume.
    mutating func append(_ sampleBuffer: CMSampleBuffer) { consume(sampleBuffer) }

    private mutating func recordError(_ message: String) {
        errorCount += 1
        if errors.count < 16, !errors.contains(message) { errors.append(message) }
    }

    private static func decode(_ storage: UnsafeRawBufferPointer, at offset: Int,
                               bytes: Int, floating: Bool, bigEndian: Bool) -> Double {
        // Byte assembly is alignment-independent and honors the ASBD byte order.
        var word: UInt64 = 0
        for index in 0..<bytes {
            let shift = (bigEndian ? bytes - index - 1 : index) * 8
            word |= UInt64(storage[offset + index]) << shift
        }
        if floating {
            return bytes == 4 ? Double(Float(bitPattern: UInt32(word))) : Double(bitPattern: word)
        }
        return bytes == 2
            ? Double(Int16(bitPattern: UInt16(word))) / 32_768
            : Double(Int32(bitPattern: UInt32(word))) / 2_147_483_648
    }
}
