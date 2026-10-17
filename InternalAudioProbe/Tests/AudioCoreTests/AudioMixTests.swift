import AudioCore
import AVFoundation
import XCTest

final class AudioMixTests: XCTestCase {
    func testResampledStereoMixContainsBothTonesAndAlignedDelay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root, microphoneRequested: true)
        let mixer = AudioMixWriter(writer: writer)
        for block in 0..<400 {
            // Opposite delivery order, unequal sample rates and channel counts.
            if block >= 20 && block % 2 == 0 { mixer.append(try tone(block, rate: 48_000, channels: 2, frequency: 880), track: .microphone) }
            mixer.append(try tone(block, rate: 44_100, channels: 1, frequency: 440), track: .app)
            if block >= 20 && block % 2 != 0 { mixer.append(try tone(block, rate: 48_000, channels: 2, frequency: 880), track: .microphone) }
            try await Task.sleep(for: .milliseconds(3))
        }
        let report = await withCheckedContinuation { continuation in mixer.finish { continuation.resume(returning: $0) } }
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertEqual(report.segments.count, 1)
        XCTAssertTrue(report.microphoneRecorded)
        XCTAssertEqual(report.microphoneBuffers, 380)
        XCTAssertEqual(report.rejectedTimestamps, 0)
        XCTAssertEqual(report.droppedBuffers, 0)
        let url = writer.folder.appendingPathComponent("recording.m4a")
        let file = try AVAudioFile(forReading: url)
        let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: pcm)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        XCTAssertEqual(Double(pcm.frameLength) / 48_000, 4, accuracy: 0.05)
        let values = Array(UnsafeBufferPointer(start: pcm.floatChannelData![0], count: Int(pcm.frameLength)))
        XCTAssertGreaterThan(amplitude(values, frequency: 440, range: 24_000..<72_000), 0.07)
        XCTAssertGreaterThan(amplitude(values, frequency: 880, range: 24_000..<72_000), 0.07)
        XCTAssertLessThan(amplitude(values, frequency: 880, range: 1_000..<6_000), 0.02, "Mic starts at 0.2 s; it must not be shifted to time zero")
        let video = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        XCTAssertTrue(video.isEmpty)
    }

    func testMicContinuesWithoutAppSamplesAndFinishDrainsTail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root, microphoneRequested: true)
        let mixer = AudioMixWriter(writer: writer)
        for block in 0..<100 {
            mixer.append(try tone(block, rate: 48_000, channels: 1, frequency: 880), track: .microphone)
            try await Task.sleep(for: .milliseconds(2))
        }
        let report = await withCheckedContinuation { c in mixer.finish { c.resume(returning: $0) } }
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertEqual(report.audioSeconds, 1, accuracy: 0.02)
        XCTAssertTrue(report.microphoneRecorded)
        XCTAssertEqual(report.microphoneRequested, true)
        XCTAssertEqual(report.segments.count, 1)
        XCTAssertFalse(report.videoSaved)
    }

    func testMissingMicrophoneNeverClaimsItWasRecorded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try AudioSegmentWriter(root: root, microphoneRequested: true)
        let mixer = AudioMixWriter(writer: writer)
        for block in 0..<50 {
            mixer.append(try tone(block, rate: 48_000, channels: 1, frequency: 440), track: .app)
            try await Task.sleep(for: .milliseconds(2))
        }
        let report = await withCheckedContinuation { c in mixer.finish { c.resume(returning: $0) } }
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertFalse(report.microphoneRecorded)
        XCTAssertNil(report.microphoneBuffers)
        XCTAssertEqual(report.microphoneRequested, true)
    }

    private func tone(_ block: Int, rate: Double, channels: AVAudioChannelCount, frequency: Double) throws -> CMSampleBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let frames = Int(rate / 100)
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        pcm.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(channels) { for frame in 0..<frames {
            pcm.floatChannelData![channel][frame] = Float(sin(Double(block * frames + frame) * 2 * .pi * frequency / rate)) * 0.25
        } }
        return try AudioMixWriter.sample(pcm, at: CMTime(value: 10_000 + Int64(block), timescale: 100))
    }

    private func amplitude(_ samples: [Float], frequency: Double, range: Range<Int>) -> Double {
        var real = 0.0, imaginary = 0.0
        for i in range {
            let angle = Double(i) * 2 * .pi * frequency / 48_000
            real += Double(samples[i]) * cos(angle); imaginary += Double(samples[i]) * sin(angle)
        }
        return 2 * sqrt(real * real + imaginary * imaginary) / Double(range.count)
    }
}
