import AVFoundation
import CoreMedia
import XCTest
@testable import ProbeStats

final class ProbeSignalStatsTests: XCTestCase {
    private let channels: [[Double]] = [[0, 0.25, -0.5, 0.75], [-1, 0, 0.5, -0.25]]

    func testAllSupportedTypesAndLayoutsCountBothChannels() throws {
        for kind in [Kind.float32, .float64, .int16, .int32] {
            for planar in [false, true] {
                var stats = ProbeSignalStats()
                stats.consume(try makeSample(kind: kind, planar: planar, values: channels))
                XCTAssertEqual(stats.bufferCount, 1, "\(kind), planar=\(planar)")
                XCTAssertEqual(stats.analyzedBufferCount, 1)
                XCTAssertEqual(stats.frameCount, 4)
                XCTAssertEqual(stats.totalSamples, 8)
                XCTAssertEqual(stats.nonZeroSamples, 6)
                XCTAssertEqual(stats.peak, 1, accuracy: 1e-12)
                XCTAssertEqual(stats.rms, sqrt(2.1875 / 8), accuracy: 1e-12)
                XCTAssertTrue(stats.errors.isEmpty)
                XCTAssertTrue(stats.hasSignal)
                XCTAssertEqual(stats.format?.interleaved, !planar)
            }
        }
    }

    func testDeclaredBigEndianIsHonoredForAllSupportedTypes() throws {
        for kind in [Kind.float32, .float64, .int16, .int32] {
            for planar in [false, true] {
                var stats = ProbeSignalStats()
                stats.consume(try makeSample(kind: kind, planar: planar, bigEndian: true, values: channels))
                XCTAssertEqual(stats.nonZeroSamples, 6, "\(kind), planar=\(planar)")
                XCTAssertEqual(stats.peak, 1, accuracy: 1e-12)
                XCTAssertEqual(stats.rms, sqrt(2.1875 / 8), accuracy: 1e-12)
                XCTAssertTrue(stats.errors.isEmpty)
            }
        }
    }

    func testSilenceIsDistinctFromMissingAndUnsupportedPCM() throws {
        var silent = ProbeSignalStats()
        silent.consume(try makeSample(kind: .float32, values: [[0, 0, 0]]))
        XCTAssertTrue(silent.hasDecodedSamples)
        XCTAssertFalse(silent.hasSignal)
        XCTAssertEqual(silent.totalSamples, 3)
        XCTAssertEqual(silent.rms, 0)

        var unsupported = ProbeSignalStats()
        unsupported.consume(try makeSample(kind: .int8, values: [[0, 0, 0]]))
        XCTAssertFalse(unsupported.hasDecodedSamples)
        XCTAssertEqual(unsupported.unsupportedBufferCount, 1)
        XCTAssertEqual(unsupported.analyzedBufferCount, 0)
        XCTAssertEqual(unsupported.totalSamples, 0)
        XCTAssertTrue(unsupported.errors.contains { $0.hasPrefix("unsupportedPCMFormat") })

        let empty = ProbeSignalStats()
        XCTAssertEqual(empty.bufferCount, 0)
        XCTAssertFalse(empty.hasDecodedSamples)
    }

    func testNilAndInvalidBuffersAreDiagnosed() throws {
        var stats = ProbeSignalStats()
        stats.consume(nil)
        let invalid = try makeSample(kind: .int16, values: [[0.5]])
        CMSampleBufferInvalidate(invalid)
        stats.consume(invalid)
        XCTAssertEqual(stats.bufferCount, 2)
        XCTAssertEqual(stats.invalidBufferCount, 2)
        XCTAssertEqual(stats.errorCount, 2)
        XCTAssertEqual(stats.errors, ["invalidSampleBuffer"])
        XCTAssertEqual(stats.totalSamples, 0)
    }

    func testTimestampsFormatChangesAndJSONRoundTrip() throws {
        var stats = ProbeSignalStats()
        stats.consume(try makeSample(kind: .float32, values: [[0.5, 0]], pts: 2.25))
        stats.consume(try makeSample(kind: .int16, planar: true, values: [[-0.5, 0.5]], pts: 3))
        XCTAssertEqual(stats.firstPTS, 2.25)
        XCTAssertEqual(stats.lastPTS, 3)
        XCTAssertEqual(stats.formatChanges, 1)
        let data = try JSONEncoder().encode(stats)
        var decoded = try JSONDecoder().decode(ProbeSignalStats.self, from: data)
        decoded.consume(try makeSample(kind: .int16, planar: true, values: [[0.5]], pts: 4))
        XCTAssertEqual(decoded.bufferCount, 3)
        XCTAssertEqual(decoded.totalSamples, 5)
        XCTAssertEqual(decoded.nonZeroSamples, 4)
        XCTAssertEqual(decoded.rms, sqrt(1.0 / 5), accuracy: 1e-12)
    }

    func testNonFiniteFloatSamplesDoNotBecomeSilenceOrBreakJSON() throws {
        var stats = ProbeSignalStats()
        stats.consume(try makeSample(kind: .float64, values: [[.nan, .infinity, -.infinity, 0.5]]))
        XCTAssertEqual(stats.totalSamples, 4)
        XCTAssertEqual(stats.invalidSamples, 3)
        XCTAssertEqual(stats.finiteSampleCount, 1)
        XCTAssertEqual(stats.nonZeroSamples, 1)
        XCTAssertEqual(stats.rms, 0.5)
        XCTAssertEqual(stats.invalidBufferCount, 1)
        XCTAssertTrue(stats.errors.contains("nonFinitePCMSamples"))
        XCTAssertNoThrow(try JSONEncoder().encode(stats))

        var onlyInvalid = ProbeSignalStats()
        onlyInvalid.consume(try makeSample(kind: .float32, values: [[.nan, .infinity]]))
        XCTAssertFalse(onlyInvalid.hasDecodedSamples)
        XCTAssertEqual(onlyInvalid.invalidSamples, 2)
    }

    func testLargeFloat64RMSDoesNotOverflow() throws {
        let value = Double.greatestFiniteMagnitude / 2
        var stats = ProbeSignalStats()
        stats.consume(try makeSample(kind: .float64, values: [[value, -value]]))
        XCTAssertTrue(stats.rms.isFinite)
        XCTAssertEqual(stats.rms, value)
        XCTAssertNoThrow(try JSONEncoder().encode(stats))
    }

    private enum Kind: CaseIterable {
        case float32, float64, int8, int16, int32
        var bits: UInt32 {
            switch self {
            case .float32, .int32: return 32
            case .float64: return 64
            case .int8: return 8
            case .int16: return 16
            }
        }
        var floating: Bool { self == .float32 || self == .float64 }
    }

    /// Only generates deterministic synthetic PCM; no microphone, device or files.
    private func makeSample(kind: Kind, planar: Bool = false, bigEndian: Bool = false,
                            values: [[Double]], pts: Double = 1) throws -> CMSampleBuffer {
        let channelCount = values.count
        let frames = try XCTUnwrap(values.first?.count)
        XCTAssertTrue(values.allSatisfy { $0.count == frames })
        let scalarBytes = Int(kind.bits / 8)
        let bytesPerFrame = scalarBytes * (planar ? 1 : channelCount)
        var flags = kAudioFormatFlagIsPacked
        flags |= kind.floating ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger
        if planar { flags |= kAudioFormatFlagIsNonInterleaved }
        if bigEndian { flags |= kAudioFormatFlagIsBigEndian }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
            mBytesPerPacket: UInt32(bytesPerFrame), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame), mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: kind.bits, mReserved: 0)
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description), noErr)
        let formatDescription = try XCTUnwrap(description)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                       presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 48_000),
                                       decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer), noErr)
        let sample = try XCTUnwrap(sampleBuffer)
        let list = AudioBufferList.allocate(maximumBuffers: planar ? channelCount : 1)
        defer { list.unsafeMutablePointer.deallocate() }
        var allocations: [UnsafeMutableRawPointer] = []
        defer { allocations.forEach { $0.deallocate() } }
        for bufferIndex in 0..<list.count {
            var payload: [UInt8] = []
            let scalars = planar ? values[bufferIndex] : (0..<frames).flatMap { frame in values.map { $0[frame] } }
            for scalar in scalars {
                let word: UInt64
                switch kind {
                case .float32: word = UInt64(Float(scalar).bitPattern)
                case .float64: word = scalar.bitPattern
                case .int8: word = UInt64(UInt8(bitPattern: Int8(scalar * 128)))
                case .int16: word = UInt64(UInt16(bitPattern: Int16(scalar * 32_768)))
                case .int32: word = UInt64(UInt32(bitPattern: Int32(scalar * 2_147_483_648)))
                }
                for index in 0..<scalarBytes {
                    let shift = (bigEndian ? scalarBytes - index - 1 : index) * 8
                    payload.append(UInt8(truncatingIfNeeded: word >> shift))
                }
            }
            let pointer = UnsafeMutableRawPointer.allocate(byteCount: payload.count, alignment: 16)
            payload.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: payload.count) }
            allocations.append(pointer)
            list[bufferIndex] = AudioBuffer(mNumberChannels: UInt32(planar ? 1 : channelCount),
                                            mDataByteSize: UInt32(payload.count), mData: pointer)
        }
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            bufferList: list.unsafeMutablePointer), noErr)
        XCTAssertEqual(CMSampleBufferSetDataReady(sample), noErr)
        return sample
    }
}
