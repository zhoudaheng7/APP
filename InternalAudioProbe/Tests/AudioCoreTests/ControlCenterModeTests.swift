import AudioCore
import AVFoundation
import XCTest

final class ControlCenterModeTests: XCTestCase {
    func testInternalOnlyPreservesLevelWithoutAppPreference() async throws {
        let (report, values) = try await capture(microphone: .absent)
        XCTAssertEqual(report.microphoneRequested, false)
        XCTAssertFalse(report.microphoneRecorded)
        XCTAssertNil(report.microphoneBuffers)
        XCTAssertGreaterThan(amplitude(values, frequency: 440, range: 9_600..<38_400), 0.32)
        XCTAssertLessThan(amplitude(values, frequency: 880, range: 9_600..<38_400), 0.01)
    }

    func testMutedMicrophonePlaceholdersDoNotClaimExternalAudio() async throws {
        let (report, values) = try await capture(microphone: .muted)
        XCTAssertEqual(report.microphoneRequested, false)
        XCTAssertFalse(report.microphoneRecorded)
        XCTAssertNil(report.microphoneBuffers)
        XCTAssertGreaterThan(amplitude(values, frequency: 440, range: 9_600..<38_400), 0.32)
        XCTAssertLessThan(amplitude(values, frequency: 880, range: 9_600..<38_400), 0.01)
    }

    func testSystemMicrophoneJoinsSameFileAfterInternalAudioStarted() async throws {
        let (report, values) = try await capture(microphone: .joinsAtForty)
        XCTAssertEqual(report.microphoneRequested, true)
        XCTAssertTrue(report.microphoneRecorded)
        XCTAssertEqual(report.microphoneBuffers, 60)
        XCTAssertGreaterThan(amplitude(values, frequency: 440, range: 4_800..<14_400), 0.32)
        XCTAssertLessThan(amplitude(values, frequency: 880, range: 4_800..<14_400), 0.01)
        XCTAssertGreaterThan(amplitude(values, frequency: 440, range: 28_800..<43_200), 0.13)
        XCTAssertGreaterThan(amplitude(values, frequency: 880, range: 28_800..<43_200), 0.13)
    }

    private enum Microphone { case absent, muted, joinsAtForty }

    private func capture(microphone: Microphone) async throws -> (SessionReport, [Float]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // No App preference is supplied. ReplayKit's received sources determine the mix.
        let writer = try AudioSegmentWriter(root: root, captureSource: "control-center")
        let mixer = AudioMixWriter(writer: writer, microphoneFollowsInput: true)
        for block in 0..<100 {
            if microphone == .muted || (microphone == .joinsAtForty && block >= 40) {
                mixer.append(try tone(block, frequency: 880, gain: microphone == .muted ? 0 : 0.4), track: .microphone)
            }
            mixer.append(try tone(block, frequency: 440, gain: 0.4), track: .app)
            try await Task.sleep(for: .milliseconds(3))
        }
        let report = await withCheckedContinuation { continuation in
            mixer.finish { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(report.state, "finished", report.error ?? "")
        XCTAssertEqual(report.captureSource, "control-center")
        XCTAssertEqual(report.segments.count, 1, "Changing the system mic input must not split the recording")
        XCTAssertEqual(report.audioSeconds, 1, accuracy: 0.02)
        XCTAssertEqual(report.droppedBuffers, 0)
        XCTAssertEqual(report.rejectedTimestamps, 0)
        let url = writer.folder.appendingPathComponent(try XCTUnwrap(report.segments.first).filename)
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(video.isEmpty)
        let file = try AVAudioFile(forReading: url)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                               frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: pcm)
        let values = Array(UnsafeBufferPointer(start: pcm.floatChannelData![0], count: Int(pcm.frameLength)))
        XCTAssertGreaterThanOrEqual(values.count, 48_000)
        guard values.count >= 48_000 else { throw AudioError.encodingFailed }
        return (report, values)
    }

    private func tone(_ block: Int, frequency: Double, gain: Float) throws -> CMSampleBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        pcm.frameLength = 480
        for frame in 0..<480 {
            pcm.floatChannelData![0][frame] = Float(sin(Double(block * 480 + frame) * 2 * .pi * frequency / 48_000)) * gain
        }
        return try AudioMixWriter.sample(pcm, at: CMTime(value: 10_000 + Int64(block), timescale: 100))
    }

    private func amplitude(_ values: [Float], frequency: Double, range: Range<Int>) -> Double {
        var real = 0.0, imaginary = 0.0
        for i in range {
            let angle = Double(i) * 2 * .pi * frequency / 48_000
            real += Double(values[i]) * cos(angle)
            imaginary += Double(values[i]) * sin(angle)
        }
        return 2 * sqrt(real * real + imaginary * imaginary) / Double(range.count)
    }
}
