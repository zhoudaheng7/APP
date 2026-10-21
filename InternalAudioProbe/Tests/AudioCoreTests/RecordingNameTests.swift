import Foundation
import XCTest
@testable import AudioCore

final class RecordingNameTests: XCTestCase {
    func testFileNameUsesGregorianLocalStartTimeAndFixedDigits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 20, hour: 13, minute: 16, second: 7)))

        XCTAssertEqual(RecordingName.audioFile(startedAt: start, index: 0), "2026-10-20_13-16-07.m4a")
    }

    func testAdditionalPartsKeepStartTimeAndReceiveDistinctNumbers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5)))

        XCTAssertEqual(RecordingName.audioFile(startedAt: start, index: 1), "2026-01-02_03-04-05_02.m4a")
        XCTAssertEqual(RecordingName.audioFile(startedAt: start, index: 2), "2026-01-02_03-04-05_03.m4a")
        XCTAssertEqual(RecordingName.audioFile(startedAt: start, index: 99), "2026-01-02_03-04-05_100.m4a")
    }

    func testLegacyExportCanBeNamedWithoutMovingOrDuplicatingSource() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("recording.m4a")
        let contents = Data([1, 2, 3, 4])
        try contents.write(to: original)
        var report = SessionReport()
        report.segments = [AudioSegment(id: 0, filename: "recording.m4a", duration: 1, state: "complete")]

        let files = RecordingFiles.audioForExport(report: report, folder: folder)
        let shareName = RecordingName.audioFile(startedAt: report.startedAt, index: 0)

        XCTAssertEqual(files, [original])
        XCTAssertNotEqual(shareName, original.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: original), contents)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["recording.m4a"])
    }
}
