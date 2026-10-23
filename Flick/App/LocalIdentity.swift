import Foundation
import CryptoKit
import Security

struct LocalFriend: Codable, Identifiable {
    let id: String
    let name: String
}

final class LocalIdentity {
    let deviceID: String
    let key: P256.Signing.PrivateKey
    var publicKey: Data { key.publicKey.rawRepresentation }
    var fingerprint: String { SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined() }
    init() {
        let saved = UserDefaults.standard.string(forKey: "flick.identity.id") ?? UUID().uuidString
        deviceID = saved; UserDefaults.standard.set(saved, forKey: "flick.identity.id")
        let service = (Bundle.main.bundleIdentifier ?? "Flick") + ".identity.v2"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "P256", kSecReturnData as String: true]
        var value: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let raw = value as? Data, let savedKey = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            key = savedKey
        } else {
            key = P256.Signing.PrivateKey()
            let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "P256", kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecValueData as String: key.rawRepresentation]
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
    func trustedKey(for id: String) -> Data? {
        guard let text = UserDefaults.standard.dictionary(forKey: "flick.trusted.v2")?[id] as? String else { return nil }
        return Data(base64Encoded: text)
    }
    func remember(id: String, key: Data) {
        var values = UserDefaults.standard.dictionary(forKey: "flick.trusted.v2") ?? [:]
        values[id] = key.base64EncodedString(); UserDefaults.standard.set(values, forKey: "flick.trusted.v2")
    }
    func forget() {
        UserDefaults.standard.removeObject(forKey: "flick.trusted.v2")
        UserDefaults.standard.removeObject(forKey: "flick.friends.v3")
    }
    var friends: [LocalFriend] {
        guard let data = UserDefaults.standard.data(forKey: "flick.friends.v3"), let value = try? JSONDecoder().decode([LocalFriend].self, from: data) else { return [] }
        return value
    }
    func addFriend(id: String, name: String) {
        var value = friends.filter { $0.id != id }; value.append(LocalFriend(id: id, name: name))
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "flick.friends.v3")
    }
    func removeFriend(id: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(friends.filter { $0.id != id }), forKey: "flick.friends.v3")
    }
}
