import AudioCore
import AVFoundation
import CoreMedia
import XCTest

final class AudioCoreTests: XCTestCase {
    func testEncodedSegmentsContainAudioAndNoVideo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root, segmentLength: 0.25)
        for index in 0..<48 {
            writer.append(try sample(index: index, silent: false))
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let report = await finish(writer)
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertEqual(report.audioBuffers, 48)
        XCTAssertGreaterThan(report.nonSilentBuffers, 0)
        XCTAssertGreaterThan(report.audioSeconds, 0.1)
        XCTAssertGreaterThanOrEqual(report.segments.count, 2)
        XCTAssertTrue(report.segments.allSatisfy { $0.state == "complete" })
        for segment in report.segments {
            let asset = AVURLAsset(url: writer.folder.appendingPathComponent(segment.filename))
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let video = try await asset.loadTracks(withMediaType: .video)
            XCTAssertEqual(audio.count, 1)
            XCTAssertEqual(video.count, 0)
            let duration = try await asset.load(.duration)
            XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0)
        }
        let files = try FileManager.default.contentsOfDirectory(at: writer.folder, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.allSatisfy { ["m4a", "json"].contains($0.pathExtension) })
        XCTAssertFalse(report.microphoneRecorded)
        XCTAssertFalse(report.videoSaved)
    }

    func testSilenceAndDuplicateTimestampAreReported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root)
        writer.append(try sample(index: 0, silent: true))
        writer.append(try sample(index: 0, silent: true))
        writer.append(try sample(index: 1, silent: true))
        let report = await finish(writer)
        XCTAssertEqual(report.rejectedTimestamps, 1)
        XCTAssertEqual(report.audioBuffers, 2)
        XCTAssertEqual(report.nonSilentBuffers, 0)
        XCTAssertEqual(report.state, "silent")
    }

    func testNoAudioDoesNotProduceAnEmptyM4A() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root)
        let report = await finish(writer)
        XCTAssertEqual(report.state, "no-audio")
        XCTAssertTrue(report.segments.isEmpty)
    }

    private func finish(_ writer: AudioSegmentWriter) async -> SessionReport {
        await withCheckedContinuation { continuation in
            writer.finish { continuation.resume(returning: $0) }
        }
    }

    private func sample(index: Int, silent: Bool) throws -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let frames: AVAudioFrameCount = 1024
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        pcm.frameLength = frames
        for frame in 0..<Int(frames) {
            pcm.floatChannelData![0][frame] = silent ? 0 : Float(sin(Double(index * Int(frames) + frame) * 2 * .pi * 440 / 48_000)) * 0.25
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(value: Int64(index) * Int64(frames), timescale: 48_000),
                                        decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        let created = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                          makeDataReadyCallback: nil, refcon: nil,
                                          formatDescription: format.formatDescription,
                                          sampleCount: Int(frames), sampleTimingEntryCount: 1,
                                          sampleTimingArray: &timing, sampleSizeEntryCount: 0,
                                          sampleSizeArray: nil, sampleBufferOut: &buffer)
        XCTAssertEqual(created, noErr)
        let sample = try XCTUnwrap(buffer)
        let copied = CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
                                                                  blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                  flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                                  bufferList: pcm.audioBufferList)
        XCTAssertEqual(copied, noErr)
        XCTAssertEqual(CMSampleBufferSetDataReady(sample), noErr)
        return sample
    }
}
