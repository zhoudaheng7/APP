import Foundation

public enum RecordingFiles {
    /// Only complete M4A segments can be shared; diagnostics and partial files stay private.
    public static func audioForExport(report: SessionReport, folder: URL) -> [URL] {
        report.segments.filter { segment in
            segment.state == "complete" &&
            (segment.filename as NSString).pathExtension.lowercased() == "m4a" &&
            (segment.filename as NSString).lastPathComponent == segment.filename &&
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(segment.filename).path)
        }.sorted { $0.id < $1.id }.map { folder.appendingPathComponent($0.filename) }
    }
}
