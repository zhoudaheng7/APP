import XCTest
import CoreGraphics
@testable import ScrollShot

final class MatcherTests: XCTestCase {
    private func page(width: Int = 64, height: Int = 600) -> [UInt8] {
        var seed: UInt32 = 17
        return (0..<(width * height)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 24)
        }
    }
    private func frame(_ data: [UInt8], y: Int, width: Int = 64, height: Int = 180) -> GrayFrame {
        GrayFrame(width: width, height: height, pixels: Array(data[(y * width)..<((y + height) * width)]))
    }
    private func image(_ frame: GrayFrame) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(frame.pixels) as CFData))
        return try XCTUnwrap(CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
            bitsPerPixel: 8, bytesPerRow: frame.width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    func testKnownPositiveNegativeAndStationaryShifts() {
        let data = page(), first = frame(data, y: 150)
        for displacement in [0, 1, 14, 49, -35] {
            let result = VerticalMatcher.match(first, frame(data, y: 150 + displacement))
            XCTAssertTrue(result.valid)
            XCTAssertEqual(result.shift, displacement)
        }
    }
    func testCompressionNoiseDoesNotChangeDisplacement() {
        let data = page(), a = frame(data, y: 100), b = frame(data, y: 130)
        let noisy = b.pixels.enumerated().map { index, value in UInt8(clamping: Int(value) + index % 7 - 3) }
        let result = VerticalMatcher.match(a, GrayFrame(width: b.width, height: b.height, pixels: noisy))
        XCTAssertTrue(result.valid); XCTAssertEqual(result.shift, 30)
    }
    func testBlankAndUnrelatedPagesAreNotStitched() {
        let blank = GrayFrame(width: 64, height: 180, pixels: [UInt8](repeating: 255, count: 64 * 180))
        XCTAssertFalse(VerticalMatcher.match(blank, blank).valid)
        let data = page()
        XCTAssertFalse(VerticalMatcher.match(frame(data, y: 30), frame(data, y: 350)).valid)
    }
    func testPixelRowOrientationIsPreserved() throws {
        let expected = frame(page(), y: 80)
        let actual = try ImageTools.gray(image(expected), width: expected.width, height: expected.height)
        XCTAssertEqual(actual.pixels, expected.pixels)
    }
    func testStreamingOutputContainsEachRowOnceEvenAfterBacktracking() throws {
        let data = page(), stitcher = try ScrollStitcher(maxPixels: 64 * 1000)
        for position in [80, 110, 95, 140] { try stitcher.consume(image(frame(data, y: position))) }
        let result = try stitcher.finish()
        defer { try? FileManager.default.removeItem(at: result.file) }
        XCTAssertNil(result.partialReason)
        XCTAssertEqual(result.width, 64); XCTAssertEqual(result.height, 240)
        let output = try ImageTools.gray(ImageTools.read(result.file), width: 64, height: 240)
        let expected = Array(data[(80 * 64)..<(320 * 64)])
        // RGB PNG round-trips may differ by one grayscale level.
        let maximumDifference = zip(expected, output.pixels).map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(maximumDifference, 1)
    }
    func testStationaryVideoCannotBeReportedAsLongImage() throws {
        let stitcher = try ScrollStitcher(), still = try image(frame(page(), y: 80))
        for _ in 0..<5 { try stitcher.consume(still) }
        XCTAssertThrowsError(try stitcher.finish())
    }
    func testOversizedContentPreservesOnlyVerifiedPrefix() throws {
        let data = page(), stitcher = try ScrollStitcher(maxPixels: 64 * 240)
        for position in [80, 110, 140, 180] { try stitcher.consume(image(frame(data, y: position))) }
        let result = try stitcher.finish()
        defer { try? FileManager.default.removeItem(at: result.file) }
        XCTAssertNotNil(result.partialReason); XCTAssertEqual(result.height, 240)
    }
}
