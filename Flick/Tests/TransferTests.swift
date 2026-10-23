import XCTest
import CryptoKit
@testable import FlickCore

final class TransferTests: XCTestCase {
    func makeOffer(bytes: Int = 1234, ext: String = "heic", hash: String = String(repeating: "a", count: 64)) -> TransferOffer {
        TransferOffer(id: UUID(), title: "照片", byteCount: bytes, sha256: hash, fileExtension: ext, side: .right)
    }
    func testDirectionAndDistance() {
        XCTAssertTrue(FlickRules.shouldThrow(dx: 120, dy: 5, velocityX: 20, width: 320, side: .right))
        XCTAssertFalse(FlickRules.shouldThrow(dx: 120, dy: 5, velocityX: 20, width: 320, side: .left))
        XCTAssertTrue(FlickRules.shouldThrow(dx: -120, dy: 5, velocityX: -20, width: 320, side: .left))
    }
    func testFastThrowAndVerticalScroll() {
        XCTAssertTrue(FlickRules.shouldThrow(dx: 40, dy: 3, velocityX: 800, width: 320, side: .right))
        XCTAssertFalse(FlickRules.shouldThrow(dx: 10, dy: 3, velocityX: 800, width: 320, side: .right))
        XCTAssertFalse(FlickRules.shouldThrow(dx: 120, dy: 180, velocityX: 800, width: 320, side: .right))
        XCTAssertFalse(FlickRules.shouldThrow(dx: .nan, dy: 1, velocityX: 900, width: 320, side: .right))
    }
    func testOfferBoundsAndPathRejection() {
        XCTAssertTrue(makeOffer().isValid)
        XCTAssertFalse(makeOffer(bytes: 0).isValid)
        XCTAssertFalse(makeOffer(bytes: FlickRules.maxFileBytes + 1).isValid)
        XCTAssertFalse(makeOffer(ext: "../../file").isValid)
        XCTAssertFalse(makeOffer(hash: String(repeating: "z", count: 64)).isValid)
    }
    func testNoSuccessBeforeReadyOrOnWrongID() {
        let offer = makeOffer(); var transaction = SendTransaction(offer: offer)
        XCTAssertFalse(transaction.received(id: offer.id))
        XCTAssertFalse(transaction.ready(id: UUID()))
        XCTAssertTrue(transaction.ready(id: offer.id))
        XCTAssertFalse(transaction.received(id: UUID()))
        XCTAssertEqual(transaction.stage, .transferring)
        XCTAssertTrue(transaction.received(id: offer.id))
        XCTAssertFalse(transaction.received(id: offer.id))
    }
    func testCancellationDoesNotBecomeDelivery() {
        let offer = makeOffer(); var transaction = SendTransaction(offer: offer)
        XCTAssertTrue(transaction.ready(id: offer.id)); transaction.fail()
        XCTAssertFalse(transaction.received(id: offer.id))
        XCTAssertEqual(transaction.stage, .failed)
    }
    func testPreviewIsNotOriginalDelivery() {
        let offer = makeOffer(); var transaction = SendTransaction(offer: offer)
        transaction.presented(id: offer.id)
        XCTAssertTrue(transaction.previewWasPresented)
        XCTAssertEqual(transaction.stage, .awaitingPreview)
    }
    func testPacketRoundTripPreservesOriginalMetadata() throws {
        let offer = makeOffer(); let packet = WirePacket(.offer, id: offer.id, offer: offer, preview: Data([1, 2, 3]))
        let copy = try JSONDecoder().decode(WirePacket.self, from: JSONEncoder().encode(packet))
        XCTAssertEqual(copy.offer, offer); XCTAssertEqual(copy.preview, Data([1, 2, 3])); XCTAssertEqual(copy.version, 2)
    }
    func testFourDirectionsAndOppositeEdges() {
        for direction in ThrowSide.allCases {
            XCTAssertEqual(FlickRules.throwDirection(dx: direction.x * 200, dy: direction.y * 200, velocityX: 0, velocityY: 0, width: 320, height: 500), direction)
            XCTAssertEqual(direction.opposite.opposite, direction)
            XCTAssertEqual(direction.x + direction.opposite.x, 0)
            XCTAssertEqual(direction.y + direction.opposite.y, 0)
        }
    }
    func testVerticalVelocityAndReversal() {
        XCTAssertEqual(FlickRules.throwDirection(dx: 4, dy: -30, velocityX: 0, velocityY: -900, width: 320, height: 600), .up)
        XCTAssertEqual(FlickRules.throwDirection(dx: 4, dy: 30, velocityX: 0, velocityY: 900, width: 320, height: 600), .down)
        XCTAssertNil(FlickRules.throwDirection(dx: 4, dy: -30, velocityX: 0, velocityY: 900, width: 320, height: 600))
        XCTAssertNil(FlickRules.throwDirection(dx: 4, dy: -10, velocityX: 0, velocityY: -900, width: 320, height: 600))
        XCTAssertNil(FlickRules.throwDirection(dx: 4, dy: 180, velocityX: 0, velocityY: .infinity, width: 320, height: 600))
    }
    func testFilenameSanitization() {
        XCTAssertEqual(FlickRules.safeFilename("../../原图.heic"), "原图.heic")
        XCTAssertEqual(FlickRules.safeFilename("C:\\folder\\视频.mov"), "视频.mov")
        XCTAssertEqual(FlickRules.safeFilename(".."), "文件")
        XCTAssertEqual(FlickRules.safeFilename("test\u{0}.pdf"), "test.pdf")
        XCTAssertLessThanOrEqual(FlickRules.safeFilename(String(repeating: "照片", count: 100)).utf8.count, 200)
    }
    func testVideoAndDocumentOriginalMetadata() throws {
        for (kind, ext, filename) in [(MediaKind.video, "mov", "原始视频.MOV"), (.file, "pdf", "合同 2026.pdf")] {
            let offer = TransferOffer(id: UUID(), title: filename, byteCount: FlickRules.maxFileBytes, sha256: String(repeating: "a", count: 64), fileExtension: ext, side: .down, kind: kind, filename: filename)
            XCTAssertTrue(offer.isValid)
            XCTAssertEqual(try JSONDecoder().decode(TransferOffer.self, from: JSONEncoder().encode(offer)), offer)
            XCTAssertFalse(TransferOffer(id: UUID(), title: filename, byteCount: 50, sha256: offer.sha256, fileExtension: ext, side: .down, kind: kind, filename: "../" + filename).isValid)
        }
    }
    func testRememberedDeviceRequiresPrivateKeyAndFreshChallenge() throws {
        let key = P256.Signing.PrivateKey(), other = P256.Signing.PrivateKey()
        let challenge = UUID().uuidString, nonce = UUID().uuidString
        let signature = try key.signature(for: IdentityProof.message(challenge: challenge, responderNonce: nonce)).rawRepresentation
        XCTAssertTrue(IdentityProof.verify(key: key.publicKey.rawRepresentation, signature: signature, challenge: challenge, responderNonce: nonce))
        XCTAssertFalse(IdentityProof.verify(key: other.publicKey.rawRepresentation, signature: signature, challenge: challenge, responderNonce: nonce))
        XCTAssertFalse(IdentityProof.verify(key: key.publicKey.rawRepresentation, signature: signature, challenge: UUID().uuidString, responderNonce: nonce))
        XCTAssertFalse(IdentityProof.verify(key: key.publicKey.rawRepresentation, signature: signature, challenge: challenge, responderNonce: UUID().uuidString))
    }
}
