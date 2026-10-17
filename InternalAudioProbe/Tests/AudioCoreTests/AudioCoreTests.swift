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
            let decoded = try AVAudioFile(forReading: writer.folder.appendingPathComponent(segment.filename))
            let pcm = AVAudioPCMBuffer(pcmFormat: decoded.processingFormat, frameCapacity: AVAudioFrameCount(decoded.length))!
            try decoded.read(into: pcm)
            XCTAssertGreaterThan(pcm.frameLength, 0)
            let maximum = (0..<Int(pcm.frameLength)).map { abs(pcm.floatChannelData![0][$0]) }.max() ?? 0
            XCTAssertGreaterThan(maximum, 0.01, "The encoded file must contain an audible signal")
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

    func testExportExcludesDiagnosticsAndUnfinishedAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root)
        for index in 0..<4 { writer.append(try sample(index: index, silent: false)) }
        let report = await finish(writer)
        // A stale partial file and the private JSON files must not enter the share sheet.
        try Data([0]).write(to: writer.folder.appendingPathComponent("unfinished.m4a"))
        try Data("{}".utf8).write(to: writer.folder.appendingPathComponent("inspection.json"))
        let files = RecordingFiles.audioForExport(report: report, folder: writer.folder)
        XCTAssertEqual(files.map(\.lastPathComponent), ["recording.m4a"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: writer.folder.path).count, 4)
    }

    func testControlCenterMetadataAndLegacyCompatibility() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root, captureSource: "control-center")
        _ = await finish(writer)
        XCTAssertEqual(try SessionReport.load(from: writer.folder).captureSource, "control-center")
        let path = writer.folder.appendingPathComponent("session.json")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        legacy.removeValue(forKey: "captureSource")
        try JSONSerialization.data(withJSONObject: legacy).write(to: path)
        XCTAssertNil(try SessionReport.load(from: writer.folder).captureSource)
    }

    private func finish(_ writer: AudioSegmentWriter) async -> SessionReport {
        await withCheckedContinuation { continuation in
            writer.finish { continuation.resume(returning: $0) }
        }
    }

    func testContinuousRecordingCrossesMinuteWithoutSplitting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root)
        for index in 0..<3000 {
            writer.append(try sample(index: index, silent: false))
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let report = await finish(writer)
        XCTAssertEqual(report.segments.count, 1, "Continuous recording must not rotate at the 60-second boundary")
        XCTAssertEqual(report.state, "finished")
        XCTAssertGreaterThan(report.audioSeconds, 20)
        if let fixture = ProcessInfo.processInfo.environment["AUDIO_CORE_UI_FIXTURE"] {
            let destination = URL(fileURLWithPath: fixture).appendingPathComponent(report.id.uuidString)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: writer.folder, to: destination)
        }
    }

    func testMergeProducesOneAudibleAudioFileAndKeepsOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var files: [URL] = []
        var ids: [UUID] = []
        for _ in 0..<2 {
            let writer = try AudioSegmentWriter(root: root)
            for index in 0..<20 {
                writer.append(try sample(index: index, silent: false))
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let report = await finish(writer)
            ids.append(report.id)
            files += RecordingFiles.audioForExport(report: report, folder: writer.folder)
        }
        let merged = try await RecordingLibrary.merge(files: files, sourceIDs: ids, root: root)
        let report = try SessionReport.load(from: merged)
        XCTAssertEqual(report.mergedFrom, ids)
        let outputs = RecordingFiles.audioForExport(report: report, folder: merged)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let waveform = try AudioWaveform.read(outputs[0])
        XCTAssertEqual(waveform.peaks.count, 64)
        XCTAssertGreaterThan(waveform.peaks.max() ?? 0, 0.01)
        XCTAssertGreaterThan(waveform.duration, 0.3)
        let video = try await AVURLAsset(url: outputs[0]).loadTracks(withMediaType: .video)
        XCTAssertTrue(video.isEmpty)
    }

    func testDeleteRejectsRootOutsideFolderAndActiveRecording() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("allowed")
        let writer = try AudioSegmentWriter(root: root)
        _ = await finish(writer)
        let outside = try AudioSegmentWriter(root: base.appendingPathComponent("outside"))
        _ = await finish(outside)
        XCTAssertThrowsError(try RecordingLibrary.deleteSession(folder: root, allowedRoots: [root]))
        XCTAssertThrowsError(try RecordingLibrary.deleteSession(folder: outside.folder, allowedRoots: [root]))
        let marker = writer.folder.appendingPathComponent(".active")
        try Data().write(to: marker)
        XCTAssertThrowsError(try RecordingLibrary.deleteSession(folder: writer.folder, allowedRoots: [root]))
        try FileManager.default.removeItem(at: marker)
        try RecordingLibrary.deleteSession(folder: writer.folder, allowedRoots: [root])
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.folder.path))
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
