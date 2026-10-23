import XCTest
import CryptoKit
@testable import FlickCore

final class BluetoothTests: XCTestCase {
    func peers() -> (Curve25519.KeyAgreement.PrivateKey, BluetoothHello, Curve25519.KeyAgreement.PrivateKey, BluetoothHello) {
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        let aa = BluetoothHello(id: UUID().uuidString, signingKey: P256.Signing.PrivateKey().publicKey.rawRepresentation, exchangeKey: a.publicKey.rawRepresentation, nonce: UUID().uuidString)
        let bb = BluetoothHello(id: UUID().uuidString, signingKey: P256.Signing.PrivateKey().publicKey.rawRepresentation, exchangeKey: b.publicKey.rawRepresentation, nonce: UUID().uuidString)
        return (a, aa, b, bb)
    }
    func testFramingAcrossSingleByteFragmentsAndCoalescedFrames() throws {
        let messages = [Data([1]), Data(repeating: 47, count: 1400), Data([2, 3, 4])]
        let stream = try messages.reduce(Data()) { $0 + (try BluetoothFramer.frame($1)) }
        for mtu in [1, 20, 185, stream.count] {
            var decoder = BluetoothFramer(), received: [Data] = []
            for start in stride(from: 0, to: stream.count, by: mtu) { received += try decoder.append(Data(stream.dropFirst(start).prefix(mtu))) }
            XCTAssertEqual(received, messages)
        }
    }
    func testInvalidLengthsRejectedBeforeAllocation() throws {
        var decoder = BluetoothFramer()
        XCTAssertThrowsError(try decoder.append(Data([127, 255, 255, 255])))
        decoder = BluetoothFramer()
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 0])))
        XCTAssertThrowsError(try BluetoothFramer.frame(Data()))
        XCTAssertThrowsError(try BluetoothFramer.frame(Data(repeating: 0, count: BluetoothFramer.limit + 1)))
    }
    func testDirectionalEncryptionAndReplayRejection() throws {
        let (keyA, a, keyB, b) = peers()
        let sender = try BluetoothCipher(privateKey: keyA, local: a, remote: b)
        let receiver = try BluetoothCipher(privateKey: keyB, local: b, remote: a)
        let plaintext = Data("original video bytes".utf8)
        let encrypted = try sender.seal(plaintext)
        XCTAssertEqual(try receiver.open(encrypted), plaintext)
        XCTAssertThrowsError(try receiver.open(encrypted))
        let reply = try receiver.seal(Data("ack".utf8))
        XCTAssertEqual(try sender.open(reply), Data("ack".utf8))
        var tampered = try sender.seal(plaintext); tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try receiver.open(tampered))
    }
    func testProofBindsBothEphemeralKeysAndRoles() throws {
        let (_, a, _, b) = peers(), signingKey = P256.Signing.PrivateKey()
        let message = try BluetoothHandshake.proof(local: a, remote: b, signer: a.id)
        let signature = try signingKey.signature(for: message)
        XCTAssertEqual(try BluetoothHandshake.transcript(a, b), try BluetoothHandshake.transcript(b, a))
        XCTAssertTrue(signingKey.publicKey.isValidSignature(signature, for: message))
        XCTAssertFalse(signingKey.publicKey.isValidSignature(signature, for: try BluetoothHandshake.proof(local: a, remote: b, signer: b.id)))
        let changed = BluetoothHello(id: b.id, signingKey: b.signingKey, exchangeKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation, nonce: b.nonce)
        XCTAssertFalse(signingKey.publicKey.isValidSignature(signature, for: try BluetoothHandshake.proof(local: a, remote: changed, signer: a.id)))
        XCTAssertThrowsError(try BluetoothHandshake.transcript(a, a))
    }
    func testFileOffsetsRejectGapsDuplicatesOverrunsAndEmptyChunks() throws {
        var cursor = try BluetoothFileCursor(total: 20000)
        XCTAssertThrowsError(try cursor.accept(offset: 1, count: 50))
        XCTAssertThrowsError(try cursor.accept(offset: 0, count: 0))
        XCTAssertThrowsError(try cursor.accept(offset: 0, count: 17000))
        try cursor.accept(offset: 0, count: 16384)
        XCTAssertThrowsError(try cursor.accept(offset: 0, count: 50))
        XCTAssertThrowsError(try cursor.accept(offset: 16384, count: 4000))
        XCTAssertEqual(cursor.offset, 16384)
        try cursor.accept(offset: 16384, count: 3616); XCTAssertTrue(cursor.complete)
    }
    func testTwoMiBOriginalSurvivesEncryptedGATTFragmentation() throws {
        let (keyA, a, keyB, b) = peers()
        let sender = try BluetoothCipher(privateKey: keyA, local: a, remote: b)
        let receiver = try BluetoothCipher(privateKey: keyB, local: b, remote: a)
        let original = Data((0..<(2 * 1024 * 1024 + 19)).map { UInt8($0 % 251) })
        var received = Data(), decoder = BluetoothFramer(), cursor = try BluetoothFileCursor(total: original.count)
        for offset in stride(from: 0, to: original.count, by: 16384) {
            let chunk = Data(original.dropFirst(offset).prefix(16384))
            let wire = try BluetoothFramer.frame(sender.seal(chunk))
            var decoded: [Data] = []
            for start in stride(from: 0, to: wire.count, by: 185) { decoded += try decoder.append(Data(wire.dropFirst(start).prefix(185))) }
            XCTAssertEqual(decoded.count, 1)
            let clear = try receiver.open(decoded[0]); try cursor.accept(offset: offset, count: clear.count); received.append(clear)
        }
        XCTAssertTrue(cursor.complete); XCTAssertEqual(SHA256.hash(data: received), SHA256.hash(data: original))
    }
}
