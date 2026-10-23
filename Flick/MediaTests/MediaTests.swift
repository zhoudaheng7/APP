import XCTest
import UIKit
import AVFoundation
import CoreVideo
import UniformTypeIdentifiers
@testable import Flick

@MainActor final class MediaTests: XCTestCase {
    private func movie() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixel), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer, []); memset(CVPixelBufferGetBaseAddress(buffer), 90, CVPixelBufferGetDataSize(buffer)); CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<3 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }
    func testRealMoviePreparationPreservesEveryOriginalByte() async throws {
        let url = try await movie(); defer { try? FileManager.default.removeItem(at: url) }
        let before = try Data(contentsOf: url)
        let prepared = try await Task.detached { try PhotoAsset.prepare(url) }.value
        XCTAssertEqual(prepared.kind, .video); XCTAssertEqual(prepared.byteCount, before.count)
        XCTAssertEqual(prepared.sha256, try PhotoFiles.digest(url)); XCTAssertEqual(try Data(contentsOf: prepared.url), before)
        XCTAssertLessThanOrEqual(prepared.previewData.count, FlickRules.maxPreviewBytes)
        XCTAssertTrue(prepared.offer(side: .up).isValid)
    }
    func testUnavailableVideoCoverDoesNotRejectOriginal() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let original = Data(repeating: 127, count: 32000); try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try PhotoAsset.prepare(url)
        XCTAssertEqual(prepared.kind, .video); XCTAssertEqual(try Data(contentsOf: prepared.url), original)
        XCTAssertNotNil(UIImage(data: prepared.previewData))
    }
    func testMultiSelectionPrefersMovieOverImageThumbnailAndContinuesAfterFailure() async throws {
        let url = try await movie(); defer { try? FileManager.default.removeItem(at: url) }
        let image = NSItemProvider(contentsOf: url)!
        image.suggestedName = "first.mov"
        let both = NSItemProvider(); both.suggestedName = "second.mov"
        both.registerFileRepresentation(forTypeIdentifier: UTType.image.identifier, fileOptions: [], visibility: .all) { completion in completion(nil, false, PhotoFailure.invalid); return nil }
        both.registerFileRepresentation(forTypeIdentifier: UTType.movie.identifier, fileOptions: [], visibility: .all) { completion in completion(url, false, nil); return nil }
        let broken = NSItemProvider(); broken.registerFileRepresentation(forTypeIdentifier: UTType.movie.identifier, fileOptions: [], visibility: .all) { completion in completion(nil, false, PhotoFailure.invalid); return nil }
        let selection = MediaSelection(); selection.load([image, broken, both])
        for _ in 0..<1000 { if !selection.busy { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(selection.busy); XCTAssertEqual(selection.items.count, 3); XCTAssertEqual(selection.assets.count, 2)
        XCTAssertEqual(selection.assets.map(\.title), ["first.mov", "second.mov"])
        XCTAssertNotNil(selection.items[1].failure); XCTAssertTrue(selection.assets.allSatisfy { $0.kind == .video })
        selection.removeFailed(); XCTAssertEqual(selection.items.count, 2)
    }
    func testCancelStopsPreparationAndInboxMetadataCannotCollideWithOriginal() throws {
        let token = PreparationToken(); token.cancel(); XCTAssertThrowsError(try token.check())
        let data = Data([1, 2, 3, 4])
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try data.write(to: source)
        let offer = TransferOffer(id: UUID(), title: ".receipt.json", byteCount: data.count, sha256: try PhotoFiles.digest(source), fileExtension: "json", side: .down, kind: .file, filename: ".receipt.json")
        let photo = ReceivedPhoto(id: offer.id, offer: offer, sender: "test", entrySide: .up, image: PhotoFiles.placeholder(.file), originalURL: source)
        defer { ReceiveInbox.remove(offer.id); try? FileManager.default.removeItem(at: source) }
        try ReceiveInbox.commit(photo)
        let restored = try XCTUnwrap(ReceiveInbox.load().first { $0.id == offer.id })
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.originalURL)), data)
    }
}
