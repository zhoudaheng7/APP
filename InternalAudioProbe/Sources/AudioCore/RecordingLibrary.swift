import AVFoundation
import Foundation

public enum RecordingLibrary {
    public static func merge(files: [URL], sourceIDs: [UUID], root: URL) async throws -> URL {
        guard !files.isEmpty else { throw LibraryError.noAudio }
        let composition = AVMutableComposition()
        guard let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw LibraryError.noAudio
        }
        var cursor = CMTime.zero
        for file in files {
            let asset = AVURLAsset(url: file)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw LibraryError.noAudio }
            let range = try await track.load(.timeRange)
            guard range.duration.isNumeric, CMTimeGetSeconds(range.duration) > 0 else { throw LibraryError.noAudio }
            try destination.insertTimeRange(range, of: track, at: cursor)
            cursor = cursor + range.duration
        }
        var report = SessionReport()
        report.captureSource = "merged"
        report.mergedFrom = sourceIDs
        let folder = root.appendingPathComponent(report.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Only this freshly created destination is removed on failure; source records stay intact.
        do {
            let audioURL = folder.appendingPathComponent("recording.m4a")
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw LibraryError.exportFailed }
            try await export.export(to: audioURL, as: .m4a)
            let result = AVURLAsset(url: audioURL)
            let audio = try await result.loadTracks(withMediaType: .audio)
            let video = try await result.loadTracks(withMediaType: .video)
            guard audio.count == 1, video.isEmpty else { throw LibraryError.exportFailed }
            report.audioSeconds = CMTimeGetSeconds(try await result.load(.duration))
            report.state = "finished"
            report.endedAt = Date()
            report.segments = [AudioSegment(id: 0, filename: "recording.m4a", duration: report.audioSeconds, state: "complete")]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: folder.appendingPathComponent("session.json"), options: .atomic)
            return folder
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    public static func deleteSession(folder: URL, allowedRoots: [URL]) throws {
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        let allowed = allowedRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        guard UUID(uuidString: resolved.lastPathComponent) != nil,
              allowed.contains(where: { $0.path == resolved.deletingLastPathComponent().path }) else { throw LibraryError.unsafePath }
        let report = try SessionReport.load(from: resolved)
        guard report.id.uuidString.lowercased() == resolved.lastPathComponent.lowercased() else { throw LibraryError.unsafePath }
        if isActive(folder: resolved) { throw LibraryError.stillRecording }
        try FileManager.default.removeItem(at: resolved)
    }

    public static func isActive(folder: URL) -> Bool {
        let marker = folder.appendingPathComponent(".active")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: marker.path),
              let modified = attributes[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < 10
    }
}

public enum LibraryError: LocalizedError {
    case noAudio, exportFailed, unsafePath, stillRecording
    public var errorDescription: String? {
        switch self {
        case .noAudio: return "所选记录没有可合并的完整音频。"
        case .exportFailed: return "合并音频失败，原录音均已保留。"
        case .unsafePath: return "录音目录校验失败，未删除任何内容。"
        case .stillRecording: return "这条录音仍在录制，请先停止。"
        }
    }
}
