import Foundation
import CryptoKit
import Security

struct Pairing: Codable {
    let url: String
    let token: String
    let fingerprint: String

    static func parse(_ text: String) throws -> Pairing {
        let value = try JSONDecoder().decode(Pairing.self, from: Data(text.utf8))
        guard let url = URL(string: value.url), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil,
              (url.path.isEmpty || url.path == "/"), url.query == nil, url.fragment == nil,
              value.token.count >= 32,
              value.fingerprint.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
            throw BridgeError.message("配对信息无效，请从 Windows 工作台重新复制。")
        }
        return value
    }
}

enum BridgeError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class PinnedDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pairing: Pairing
    init(_ pairing: Pairing) { self.pairing = pairing }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == URL(string: pairing.url)?.host,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02x", $0) }.joined()
        guard digest == pairing.fingerprint.lowercased() else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString))
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum PairingKeychain {
    private static let service = "com.personal.chatassist.pairing"
    static func load() -> Pairing? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "bridge",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }
    static func save(_ value: Pairing) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "bridge"]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw BridgeError.message("无法保存配对凭据，请重试。")
        }
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                      kSecAttrService as String: service, kSecAttrAccount as String: "bridge"] as CFDictionary)
    }
}

final class BridgeClient {
    private let pairing: Pairing
    private let session: URLSession
    init(_ pairing: Pairing) {
        self.pairing = pairing
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 55
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config, delegate: PinnedDelegate(pairing), delegateQueue: nil)
    }
    func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let base = URL(string: pairing.url), let url = URL(string: path, relativeTo: base) else {
            throw BridgeError.message("连接地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIError.self, from: data)
            throw BridgeError.message(error?.error ?? "无法连接 Windows，请检查网络和配对信息。")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    deinit { session.invalidateAndCancel() }
    private struct APIError: Decodable { let error: String }
}
