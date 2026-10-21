import AudioCore
import AVFoundation
import CoreMedia
import XCTest

final class LongRecordingTests: XCTestCase {
    func testFiveMinuteAACIsOneFileWithAudibleBeginningMiddleAndEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root)
        // Encode five minutes of actual PCM, rather than advancing a fake clock.
        // Small, drained batches keep the accelerated producer within real-time
        // encoder capacity without retaining five minutes of PCM in memory.
        for block in 0..<3000 {
            let frequency: Double = block < 1000 ? 440 : block < 2000 ? 660 : 880
            writer.append(try tone(startFrame: Int64(block * 4800), frames: 4800, frequency: frequency))
            if block % 4 == 3 {
                await drain(writer)
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let report = await finish(writer)
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertEqual(report.segments.count, 1)
        XCTAssertEqual(report.audioBuffers, 3000)
        XCTAssertEqual(report.audioSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(report.droppedBuffers, 0)
        XCTAssertEqual(report.rejectedTimestamps, 0)
        let segment = try XCTUnwrap(report.segments.first)
        XCTAssertEqual(segment.state, "complete")
        XCTAssertEqual(segment.duration, 300, accuracy: 0.001)
        let url = writer.folder.appendingPathComponent(segment.filename)
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertTrue(videoTracks.isEmpty)
        XCTAssertEqual(CMTimeGetSeconds(duration), 300, accuracy: 0.1)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        for (second, frequency) in [(1.0, 440.0), (150.0, 660.0), (298.0, 880.0)] {
            file.framePosition = AVAudioFramePosition(second * file.processingFormat.sampleRate)
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4800))
            try file.read(into: pcm)
            XCTAssertEqual(pcm.frameLength, 4800)
            XCTAssertGreaterThan(amplitude(pcm, frequency: frequency), 0.1,
                                 "AAC must contain the expected tone at \(second) seconds")
        }
        XCTAssertEqual(RecordingFiles.audioForExport(report: report, folder: writer.folder).count, 1)
        XCTAssertFalse(report.videoSaved)
    }

    func testWriterBacklogIsBoundedAndReportsOverflowOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root)
        let sample = try tone(startFrame: 0, frames: 1024, frequency: 440)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        writer.queue.async { entered.signal(); release.wait() }
        guard entered.wait(timeout: .now() + 3) == .success else {
            release.signal()
            return XCTFail("Writer queue did not start")
        }
        let failed = expectation(description: "One clear overflow failure")
        failed.assertForOverFulfill = true
        writer.onFatalError = { message in
            XCTAssertTrue(message.contains("积压"))
            XCTAssertTrue(message.contains("未保存"))
            failed.fulfill()
        }
        // The blocked queue makes this independent of machine speed. Only 128
        // samples and one failure block may enter; the remaining 10,000 calls
        // must not retain PCM or enqueue one failure callback per call.
        for _ in 0..<10_128 { writer.append(sample) }
        for _ in 0..<10_000 { writer.discardVideoFrame() }
        release.signal()
        let report = await finish(writer)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(report.state, "interrupted")
        XCTAssertEqual(report.audioBuffers + report.rejectedTimestamps, 128)
        XCTAssertEqual(report.droppedBuffers, 1)
        XCTAssertTrue(report.error?.contains("积压") == true)
        // A rejected input cannot be reported as an ordinary successful capture.
        XCTAssertNotEqual(report.state, "finished")
    }

    func testMixerResumesAfterTwentySecondInputGapWithoutFillingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root, microphoneRequested: true)
        let mixer = AudioMixWriter(writer: writer)
        let failed = expectation(description: "No gap failure")
        failed.isInverted = true
        mixer.onError = { _ in failed.fulfill() }
        // Only one source is active in each window. Both sources then stop for
        // 20 seconds and resume using their original host-clock timestamps.
        for block in 0..<100 {
            mixer.append(try tone(startFrame: 4_800_000 + Int64(block * 480), frames: 480, frequency: 440), track: .app)
            try await Task.sleep(for: .milliseconds(2))
        }
        for block in 0..<100 {
            mixer.append(try tone(startFrame: 5_808_000 + Int64(block * 480), frames: 480, frequency: 880), track: .microphone)
            try await Task.sleep(for: .milliseconds(2))
        }
        // A late packet entirely before the cursor must be discarded, rather
        // than poisoning subsequent timestamps or being kept indefinitely.
        mixer.append(try tone(startFrame: 4_848_000, frames: 480, frequency: 440), track: .app)
        for block in 0..<30 {
            let start = 5_856_000 + Int64(block * 480)
            mixer.append(try tone(startFrame: start, frames: 480, frequency: 440), track: .app)
            mixer.append(try tone(startFrame: start, frames: 480, frequency: 880), track: .microphone)
            try await Task.sleep(for: .milliseconds(3))
        }
        let report = await withCheckedContinuation { c in mixer.finish { c.resume(returning: $0) } }
        await fulfillment(of: [failed], timeout: 0.1)
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertEqual(report.segments.count, 1)
        XCTAssertEqual(report.droppedBuffers, 0)
        XCTAssertTrue(report.microphoneRecorded)
        XCTAssertLessThan(report.audioSeconds, 3,
                          "A missing 20-second input interval must not produce 20 seconds of allocated zero PCM")
        XCTAssertGreaterThan(report.audioSeconds, 2.25)
        let url = writer.folder.appendingPathComponent(try XCTUnwrap(report.segments.first).filename)
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertTrue(video.isEmpty)
        let file = try AVAudioFile(forReading: url)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4800))
        try file.read(into: pcm)
        XCTAssertGreaterThan(amplitude(pcm, frequency: 440), 0.07)
        file.framePosition = max(0, file.length - 4800)
        try file.read(into: pcm)
        XCTAssertGreaterThan(amplitude(pcm, frequency: 440), 0.07)
        XCTAssertGreaterThan(amplitude(pcm, frequency: 880), 0.07)
    }

    func testMicrophoneReturnsAfterTwentySecondsWhileInternalAudioContinues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root, microphoneRequested: true)
        let mixer = AudioMixWriter(writer: writer)
        for block in 0..<2300 {
            let start = 4_800_000 + Int64(block * 480)
            mixer.append(try tone(startFrame: start, frames: 480, frequency: 440), track: .app)
            // Mic is present for the first second, absent for 20 seconds, and
            // comes back for the last two seconds without ending the session.
            if block < 100 || block >= 2100 {
                mixer.append(try tone(startFrame: start, frames: 480, frequency: 880), track: .microphone)
            }
            try await Task.sleep(for: .milliseconds(3))
        }
        let report = await withCheckedContinuation { c in mixer.finish { c.resume(returning: $0) } }
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertEqual(report.segments.count, 1)
        XCTAssertEqual(report.audioSeconds, 23, accuracy: 0.03)
        XCTAssertEqual(report.droppedBuffers, 0)
        XCTAssertEqual(report.microphoneBuffers, 300)
        let file = try AVAudioFile(forReading: writer.folder.appendingPathComponent(try XCTUnwrap(report.segments.first).filename))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4800))
        file.framePosition = AVAudioFramePosition(10 * file.processingFormat.sampleRate)
        try file.read(into: pcm)
        XCTAssertGreaterThan(amplitude(pcm, frequency: 440), 0.07)
        XCTAssertLessThan(amplitude(pcm, frequency: 880), 0.02)
        file.framePosition = AVAudioFramePosition(22 * file.processingFormat.sampleRate)
        try file.read(into: pcm)
        XCTAssertGreaterThan(amplitude(pcm, frequency: 440), 0.07)
        XCTAssertGreaterThan(amplitude(pcm, frequency: 880), 0.07)
    }

    private func tone(startFrame: Int64, frames: Int, frequency: Double) throws -> CMSampleBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            pcm.floatChannelData![0][frame] = Float(sin(Double(startFrame + Int64(frame)) * 2 * .pi * frequency / 48_000)) * 0.25
        }
        return try AudioMixWriter.sample(pcm, at: CMTime(value: startFrame, timescale: 48_000))
    }

    private func amplitude(_ pcm: AVAudioPCMBuffer, frequency: Double) -> Double {
        guard pcm.frameLength > 0, let samples = pcm.floatChannelData?[0] else { return 0 }
        var real = 0.0, imaginary = 0.0
        for frame in 0..<Int(pcm.frameLength) {
            let angle = Double(frame) * 2 * .pi * frequency / pcm.format.sampleRate
            real += Double(samples[frame]) * cos(angle)
            imaginary += Double(samples[frame]) * sin(angle)
        }
        return 2 * sqrt(real * real + imaginary * imaginary) / Double(pcm.frameLength)
    }

    private func drain(_ writer: AudioSegmentWriter) async {
        await withCheckedContinuation { c in writer.queue.async { c.resume() } }
    }

    private func finish(_ writer: AudioSegmentWriter) async -> SessionReport {
        await withCheckedContinuation { c in writer.finish { c.resume(returning: $0) } }
    }
}
