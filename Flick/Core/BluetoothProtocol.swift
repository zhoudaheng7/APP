import Foundation
import CryptoKit

public enum BluetoothFailure: Error { case malformed, oversized, authentication, sequence, offset }

/// GATT notifications and writes are fragments, never message boundaries.
public struct BluetoothFramer {
    public static let limit = 1024 * 1024
    private var buffer = Data()
    public init() {}
    public static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= limit else { throw BluetoothFailure.oversized }
        let size = UInt32(payload.count)
        return Data([UInt8(size >> 24), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]) + payload
    }
    public mutating func append(_ fragment: Data) throws -> [Data] {
        guard fragment.count <= Self.limit, buffer.count + fragment.count <= Self.limit + 4096 else { throw BluetoothFailure.oversized }
        buffer.append(fragment)
        var messages: [Data] = []
        while buffer.count >= 4 {
            let bytes = Array(buffer.prefix(4))
            let count = bytes.reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= Self.limit else { throw BluetoothFailure.malformed }
            guard buffer.count >= count + 4 else { break }
            messages.append(Data(buffer.dropFirst(4).prefix(count)))
            buffer = Data(buffer.dropFirst(count + 4))
        }
        return messages
    }
}

public struct BluetoothHello: Codable, Equatable {
    public let id: String
    public let signingKey: Data
    public let exchangeKey: Data
    public let nonce: String
    public init(id: String, signingKey: Data, exchangeKey: Data, nonce: String) {
        self.id = id; self.signingKey = signingKey; self.exchangeKey = exchangeKey; self.nonce = nonce
    }
    public var valid: Bool { UUID(uuidString: id) != nil && signingKey.count == 64 && exchangeKey.count == 32 && UUID(uuidString: nonce) != nil }
}

public enum BluetoothHandshake {
    public static func transcript(_ a: BluetoothHello, _ b: BluetoothHello) throws -> Data {
        guard a.valid, b.valid, a.id != b.id, a.nonce != b.nonce else { throw BluetoothFailure.authentication }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Data("FLICK-BLE-v4|".utf8) + (try encoder.encode([a, b].sorted { $0.id < $1.id }))
    }
    public static func proof(local: BluetoothHello, remote: BluetoothHello, signer: String) throws -> Data {
        try transcript(local, remote) + Data(("|signer=" + signer).utf8)
    }
}

/// Fresh ephemeral keys per connection; directional keys and strict counters reject replay.
public final class BluetoothCipher {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0
    public init(privateKey: Curve25519.KeyAgreement.PrivateKey, local: BluetoothHello, remote: BluetoothHello) throws {
        let transcript = try BluetoothHandshake.transcript(local, remote)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: remote.exchangeKey))
        let salt = Data(SHA256.hash(data: transcript))
        sendKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data((local.id + ">" + remote.id).utf8), outputByteCount: 32)
        receiveKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data((remote.id + ">" + local.id).utf8), outputByteCount: 32)
    }
    private func counterData(_ number: UInt64) -> Data { Data((0..<8).reversed().map { UInt8((number >> ($0 * 8)) & 255) }) }
    public func seal(_ plaintext: Data) throws -> Data {
        guard sendCounter < UInt64.max else { throw BluetoothFailure.sequence }
        let counter = counterData(sendCounter)
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + counter)
        let box = try AES.GCM.seal(plaintext, using: sendKey, nonce: nonce, authenticating: counter)
        guard let combined = box.combined else { throw BluetoothFailure.authentication }
        sendCounter += 1
        return counter + combined
    }
    public func open(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count >= 36 else { throw BluetoothFailure.malformed }
        let counterBytes = Data(ciphertext.prefix(8))
        let counter = counterBytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard counter == receiveCounter, receiveCounter < UInt64.max else { throw BluetoothFailure.sequence }
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext.dropFirst(8)), using: receiveKey, authenticating: counterBytes)
        receiveCounter += 1
        return plaintext
    }
}

public struct BluetoothFileCursor {
    public let total: Int
    public private(set) var offset = 0
    public init(total: Int) throws {
        guard total > 0, total <= FlickRules.maxFileBytes else { throw BluetoothFailure.oversized }
        self.total = total
    }
    public mutating func accept(offset: Int, count: Int) throws {
        guard offset == self.offset, count > 0, count <= 16 * 1024, count <= total - self.offset else { throw BluetoothFailure.offset }
        self.offset += count
    }
    public var complete: Bool { offset == total }
}
