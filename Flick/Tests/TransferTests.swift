import XCTest
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
        XCTAssertEqual(copy.offer, offer); XCTAssertEqual(copy.preview, Data([1, 2, 3])); XCTAssertEqual(copy.version, 1)
    }
}
