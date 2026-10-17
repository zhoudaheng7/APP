import AVFoundation
import CoreMedia
import Foundation

/// One serial queue owns all mutable writer state. No video writer exists.
public final class AudioSegmentWriter: @unchecked Sendable {
    public let folder: URL
    public let queue = DispatchQueue(label: "com.lightsquare.audio-writer", qos: .userInitiated)
    public var onUpdate: (@Sendable (SessionReport) -> Void)?
    public var onFatalError: (@Sendable (String) -> Void)?
    private let finalizations = DispatchGroup()
    private let segmentLength: Double
    private var report: SessionReport
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var segmentStart: CMTime?
    private var lastTimestamp: CMTime?
    private var segmentEnd: CMTime?
    private var currentIndex: Int?
    private var accepting = true
    private var finishing = false
    private var lastPublication = Date.distantPast

    public init(root: URL, segmentLength: Double = 60) throws {
        self.segmentLength = segmentLength
        let report = SessionReport()
        self.report = report
        folder = root.appendingPathComponent(report.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try persist()
    }

    public func append(_ sample: CMSampleBuffer) {
        queue.async { [self] in
            guard accepting, CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample),
                  let description = CMSampleBufferGetFormatDescription(sample),
                  let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard time.isValid, time.isNumeric else { report.rejectedTimestamps += 1; return }
            if let lastTimestamp, CMTimeCompare(time, lastTimestamp) <= 0 {
                report.rejectedTimestamps += 1
                return
            }
            lastTimestamp = time
            report.audioBuffers += 1
            report.sampleRate = format.mSampleRate
            report.channelCount = format.mChannelsPerFrame
            if let peak = PCMMeter.peak(of: sample) {
                report.meteredBuffers += 1
                report.peak = max(report.peak, peak)
                if peak > 0.0001 { report.nonSilentBuffers += 1 }
            }
            do {
                if let start = segmentStart, CMTimeGetSeconds(time - start) >= segmentLength { closeSegment() }
                // Split on a source format change instead of silently feeding incompatible AAC settings.
                if let input, let hint = input.sourceFormatHint,
                   !CMFormatDescriptionEqual(hint, otherFormatDescription: description) { closeSegment() }
                if writer == nil { try openSegment(description: description, format: format, timestamp: time) }
                guard let writer, let input else { return }
                if writer.status == .failed { throw writer.error ?? AudioError.encodingFailed }
                guard input.isReadyForMoreMediaData else { report.droppedBuffers += 1; publish(); return }
                guard input.append(sample) else { throw writer.error ?? AudioError.encodingFailed }
                let duration = Double(CMSampleBufferGetNumSamples(sample)) / format.mSampleRate
                report.audioSeconds += duration
                segmentEnd = time + CMTime(seconds: duration, preferredTimescale: 1_000_000)
                publish()
            } catch { fail(error) }
        }
    }

    public func discardVideoFrame() {
        queue.async { [self] in
            guard accepting else { return }
            report.videoFramesDiscarded += 1
            // No pixel buffer is retained, encoded, copied, or written to disk.
        }
    }

    public func finish(reason: String? = nil, completion: @escaping @Sendable (SessionReport) -> Void) {
        queue.async { [self] in
            guard !finishing else { return }
            finishing = true
            accepting = false
            if let reason { report.error = reason }
            closeSegment()
            finalizations.notify(queue: queue) { [self] in
                report.endedAt = Date()
                if report.error != nil || report.segments.contains(where: { $0.state == "failed" }) { report.state = "interrupted" }
                else if report.audioBuffers == 0 { report.state = "no-audio" }
                else if report.meteredBuffers > 0 && report.nonSilentBuffers == 0 { report.state = "silent" }
                else { report.state = "finished" }
                do { try persist() } catch { report.error = "保存诊断失败：\(error.localizedDescription)"; report.state = "interrupted" }
                onUpdate?(report)
                completion(report)
            }
        }
    }

    private func openSegment(description: CMFormatDescription, format: AudioStreamBasicDescription, timestamp: CMTime) throws {
        let index = report.segments.count
        let name = String(format: "part-%03d.m4a", index + 1)
        let assetWriter = try AVAssetWriter(outputURL: folder.appendingPathComponent(name), fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.mSampleRate,
            AVNumberOfChannelsKey: min(2, max(1, format.mChannelsPerFrame)),
            AVEncoderBitRateKey: 96_000
        ]
        let assetInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: description)
        assetInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(assetInput) else { throw AudioError.unsupportedFormat }
        assetWriter.add(assetInput)
        guard assetWriter.startWriting() else { throw assetWriter.error ?? AudioError.encodingFailed }
        assetWriter.startSession(atSourceTime: timestamp)
        writer = assetWriter
        input = assetInput
        segmentStart = timestamp
        segmentEnd = timestamp
        currentIndex = index
        report.segments.append(AudioSegment(id: index, filename: name, duration: 0, state: "writing"))
        try persist()
    }

    private func closeSegment() {
        guard let writer, let input, let index = currentIndex else { return }
        if let start = segmentStart, let end = segmentEnd { report.segments[index].duration = max(0, CMTimeGetSeconds(end - start)) }
        self.writer = nil
        self.input = nil
        segmentStart = nil
        segmentEnd = nil
        currentIndex = nil
        guard writer.status == .writing else {
            report.segments[index].state = "failed"
            report.segments[index].error = writer.error?.localizedDescription ?? "编码器未处于可完成状态"
            report.error = report.segments[index].error
            try? persist()
            return
        }
        input.markAsFinished()
        finalizations.enter()
        writer.finishWriting { [self] in
            queue.async { [self] in
                report.segments[index].state = writer.status == .completed ? "complete" : "failed"
                report.segments[index].error = writer.error?.localizedDescription
                if writer.status != .completed { report.error = writer.error?.localizedDescription ?? "音频分段未能完成" }
                do { try persist() } catch { report.error = error.localizedDescription }
                finalizations.leave()
            }
        }
    }

    private func fail(_ error: Error) {
        accepting = false
        report.error = error.localizedDescription
        report.state = "interrupted"
        try? persist()
        onFatalError?(error.localizedDescription)
    }

    private func publish() {
        guard Date().timeIntervalSince(lastPublication) >= 0.5 else { return }
        lastPublication = Date()
        do { try persist() } catch { fail(error); return }
        onUpdate?(report)
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: folder.appendingPathComponent("session.json"), options: .atomic)
    }
}

public enum AudioError: LocalizedError {
    case encodingFailed, unsupportedFormat
    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "音频编码失败，已完成的分段仍保留。"
        case .unsupportedFormat: return "当前内部音频格式无法编码。"
        }
    }
}
