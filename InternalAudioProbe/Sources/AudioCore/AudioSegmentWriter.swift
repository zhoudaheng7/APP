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
    // Bound retained PCM even when storage or the encoder cannot keep up. Metadata
    // updates share one coalesced work item, rather than queuing per video frame.
    private let ingress = NSLock()
    private let maximumPendingAudioBuffers = 128
    private let maximumPendingAudioBytes = 4 * 1024 * 1024
    private var pendingAudioBuffers = 0
    private var pendingAudioBytes = 0
    private var ingressClosed = false
    private var countersQueued = false
    private var discardedVideoFrames = 0
    private var microphoneBuffers = 0
    private var failureReported = false

    public init(root: URL, segmentLength: Double = .infinity, captureSource: String? = nil, microphoneRequested: Bool = false) throws {
        self.segmentLength = segmentLength
        var report = SessionReport()
        report.captureSource = captureSource
        report.microphoneRequested = microphoneRequested
        self.report = report
        folder = root.appendingPathComponent(report.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
#if os(iOS)
        // User-initiated captures may continue after the screen locks. New files
        // remain protected, while access stays available after the first unlock.
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: folder.path)
#endif
        try persist()
    }

    public func append(_ sample: CMSampleBuffer) {
        let sampleBytes = max(1, CMSampleBufferGetTotalSampleSize(sample))
        ingress.lock()
        guard !ingressClosed else { ingress.unlock(); return }
        guard pendingAudioBuffers < maximumPendingAudioBuffers,
              sampleBytes <= maximumPendingAudioBytes,
              pendingAudioBytes <= maximumPendingAudioBytes - sampleBytes else {
            ingressClosed = true
            queue.async { [self] in
                report.droppedBuffers += 1
                fail(AudioError.inputOverflow)
            }
            ingress.unlock()
            return
        }
        pendingAudioBuffers += 1
        pendingAudioBytes += sampleBytes
        // Enqueue while holding the ingress lock so finish cannot overtake an
        // already accepted sample from another capture callback queue.
        queue.async { [self] in
            defer {
                ingress.lock()
                pendingAudioBuffers -= 1
                pendingAudioBytes -= sampleBytes
                ingress.unlock()
            }
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
        ingress.unlock()
    }

    public func discardVideoFrame() {
        ingress.lock()
        guard !ingressClosed else { ingress.unlock(); return }
        discardedVideoFrames += 1
        enqueueCountersIfNeeded()
        ingress.unlock()
        // No pixel buffer is retained, encoded, copied, or written to disk.
    }

    public func noteMicrophoneInput() {
        ingress.lock()
        guard !ingressClosed else { ingress.unlock(); return }
        microphoneBuffers += 1
        enqueueCountersIfNeeded()
        ingress.unlock()
    }

    // Caller holds ingress. At most one pending metadata block exists.
    private func enqueueCountersIfNeeded() {
        guard !countersQueued else { return }
        countersQueued = true
        queue.async { [self] in
            ingress.lock()
            let video = discardedVideoFrames, mic = microphoneBuffers
            discardedVideoFrames = 0
            microphoneBuffers = 0
            countersQueued = false
            ingress.unlock()
            guard accepting else { return }
            report.videoFramesDiscarded += video
            if mic > 0 {
                report.microphoneRequested = true
                report.microphoneRecorded = true
                report.microphoneBuffers = (report.microphoneBuffers ?? 0) + mic
            }
        }
    }

    public func finish(reason: String? = nil, completion: @escaping @Sendable (SessionReport) -> Void) {
        ingress.lock()
        ingressClosed = true
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
        ingress.unlock()
    }

    private func openSegment(description: CMFormatDescription, format: AudioStreamBasicDescription, timestamp: CMTime) throws {
        let index = report.segments.count
        let name = RecordingName.audioFile(startedAt: report.startedAt, index: index)
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
        guard !failureReported else { return }
        failureReported = true
        ingress.lock()
        ingressClosed = true
        ingress.unlock()
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
    case encodingFailed, unsupportedFormat, inputOverflow
    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "音频编码失败，已完成的分段仍保留。"
        case .unsupportedFormat: return "当前内部音频格式无法编码。"
        case .inputOverflow: return "音频写入积压，录制已停止；部分输入未保存。"
        }
    }
}
