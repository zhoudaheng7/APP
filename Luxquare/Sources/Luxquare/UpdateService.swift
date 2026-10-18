import Foundation
import SwiftUI

struct NativeAppUpdate: Decodable {
    let schema: Int
    let bundleIdentifier: String
    let version: String
    let build: Int
    let manifestURL: String
    let releaseNotes: String
}

@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var update: NativeAppUpdate?
    @Published private(set) var checking = false
    @Published private(set) var message: String?
    private var lastCheck = Date.distantPast
    private let config = AppConfiguration()
    var installedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var installedBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    var installURL: URL? {
        guard let update, let remote = URL(string: update.manifestURL), trustedManifest(remote) else { return nil }
        var parts = URLComponents(); parts.scheme = "itms-services"
        parts.queryItems = [URLQueryItem(name: "action", value: "download-manifest"), URLQueryItem(name: "url", value: remote.absoluteString)]
        return parts.url
    }
    private func trustedManifest(_ url: URL) -> Bool {
        guard let configured = config.updateURL, url.scheme == "https", url.user == nil, url.password == nil,
              url.originURL == configured.originURL else { return false }
        let root = configured.deletingLastPathComponent().path
        return url.path.hasPrefix(root + "/") && url.path.hasSuffix(".plist")
    }
    func check(force: Bool = false) async {
        guard !checking, force || Date().timeIntervalSince(lastCheck) > 3600 else { return }
        guard let url = config.updateURL else { message = "此构建尚未配置原生版本更新。"; return }
        checking = true; defer { checking = false; lastCheck = Date() }
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
            configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 20
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.originURL == url.originURL, data.count < 65536 else { throw ClientError.invalidResponse }
            let candidate = try JSONDecoder().decode(NativeAppUpdate.self, from: data)
            guard candidate.schema == 1, candidate.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let manifest = URL(string: candidate.manifestURL), trustedManifest(manifest) else { throw ClientError.invalidResponse }
            update = candidate.build > installedBuild ? candidate : nil
            message = update == nil ? "已是最新原生版本。网页模块随服务器同步。" : "有新的原生版本可安装。"
        } catch { message = "暂时无法检查更新，请稍后重试。" }
    }
}
