import Foundation
import CryptoKit

public enum IdentityProof {
    public static func message(challenge: String, responderNonce: String) -> Data { Data("FLICK-v2|\(challenge)|\(responderNonce)".utf8) }
    public static func verify(key: Data, signature: Data, challenge: String, responderNonce: String) -> Bool {
        guard challenge.count >= 24, responderNonce.count >= 24, let key = try? P256.Signing.PublicKey(rawRepresentation: key), let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
        return key.isValidSignature(signature, for: message(challenge: challenge, responderNonce: responderNonce))
    }
}
