import Foundation
import SwiftUI
import WebKit

struct WorkbenchModule: Codable, Identifiable, Hashable {
    let moduleID: String
    let title: String
    let description: String
    let available: Bool
    let enabled: Bool
    let entry: String?
    let presentationOrigin: String?
    let logoURL: String?
    let accent: String?
    let openMode: String?
    var id: String { moduleID }
    var url: URL? { entry.flatMap(URL.init(string:)) }
    var origin: URL? { presentationOrigin.flatMap(URL.init(string:)) ?? url?.originURL }
    var opensExternally: Bool { openMode == "external" || moduleID.hasPrefix("feishu-") }
    enum CodingKeys: String, CodingKey {
        case moduleID = "module_id", title, description, available, enabled, entry, accent
        case presentationOrigin = "presentation_origin", logoURL = "logo_url", openMode = "open_mode"
    }
    var symbol: String {
        switch moduleID {
        case "finance": return "chart.pie.fill"
        case "crm": return "person.2.fill"
        case "contracts": return "doc.text.fill"
        case "projects": return "checklist"
        case "recordings": return "waveform"
        case "companies": return "building.2.fill"
        case "easel": return "sparkles"
        case "lightsquare": return "play.rectangle.fill"
        case "remnawave": return "network"
        case "feishu-approval": return "checkmark.seal.fill"
        case "feishu-library": return "books.vertical.fill"
        default: return "square.grid.2x2.fill"
        }
    }
    var tint: Color {
        switch accent {
        case "amber": return .orange
        case "blue": return .blue
        case "cyan": return .cyan
        case "teal": return .mint
        default: return .purple
        }
    }
}

struct WorkbenchUser: Decodable {
    let identityID: String
    let displayName: String
    let avatarURL: String?
    enum CodingKeys: String, CodingKey {
        case identityID = "identity_id", displayName = "display_name", avatarURL = "avatar_url"
    }
}

struct WorkbenchCatalog: Decodable { let version: Int; let modules: [WorkbenchModule] }

struct AppConfiguration {
    let baseURL: URL?
    let updateURL: URL?
    let authOrigins: Set<String>
    let isUITesting: Bool
    init(bundle: Bundle = .main) {
        let testing = ProcessInfo.processInfo.arguments.contains("-ui-testing") || ProcessInfo.processInfo.environment["LUXQUARE_UI_TESTING"] == "1"
        isUITesting = testing
        func httpsURL(_ key: String) -> URL? {
            guard !testing, let raw = bundle.object(forInfoDictionaryKey: key) as? String,
                  let url = URL(string: raw), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else { return nil }
            return url
        }
        baseURL = httpsURL("LuxquareBaseURL")?.originURL
        updateURL = httpsURL("LuxquareUpdateURL")
        authOrigins = Set((bundle.object(forInfoDictionaryKey: "LuxquareAuthOrigins") as? [String] ?? []).compactMap { raw in
            guard let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil else { return nil }
            return url.originURL?.absoluteString
        })
    }
}

extension URL {
    var originURL: URL? {
        guard var parts = URLComponents(url: self, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host != nil, parts.user == nil, parts.password == nil else { return nil }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        return parts.url
    }
}

@MainActor
final class WorkbenchModel: ObservableObject {
    @Published var user: WorkbenchUser?
    @Published var modules: [WorkbenchModule] = []
    @Published var loading = false
    @Published var notice: String?
    @Published var showLogin = false
    @Published private(set) var identityEpoch = UUID()
    @Published private(set) var transitioning = false
    let configuration = AppConfiguration()
    let client = WorkbenchHTTPClient()
    private var lastRefresh = Date.distantPast
    private var lastIdentityID = UserDefaults.standard.string(forKey: "lastEnterpriseIdentity")
    var baseURL: URL? { configuration.baseURL }
    var availableModules: [WorkbenchModule] { modules.filter { $0.available && $0.enabled && $0.url?.scheme == "https" } }
    var businessOrigins: Set<String> {
        var result = Set(availableModules.filter { !$0.opensExternally }.compactMap { $0.origin?.absoluteString })
        if let base = baseURL { result.insert(base.absoluteString) }
        return result
    }
    init() {
        if let baseURL { client.allowedOrigins = [baseURL.absoluteString] }
        if configuration.isUITesting { notice = "原生界面预览" }
    }
    func refresh(force: Bool = false) async {
        guard !loading, !transitioning, force || Date().timeIntervalSince(lastRefresh) > 2 else { return }
        guard let baseURL else { return }
        var expected = identityEpoch
        loading = true
        defer { if expected == identityEpoch { loading = false; lastRefresh = Date() } }
        do {
            let (userData, response) = try await client.response(for: URLRequest(url: baseURL.appendingPathComponent("api/me")))
            guard expected == identityEpoch else { return }
            if response.statusCode == 401 {
                identityEpoch = UUID(); expected = identityEpoch
                client.invalidateRequests()
                user = nil; modules = []; client.allowedOrigins = [baseURL.absoluteString]
                NativeRecorder.shared.setAccountScope(nil)
                notice = "请先使用企业飞书身份登录。"; return
            }
            guard response.statusCode == 200 else { throw ClientError.status(response.statusCode) }
            let newUser = try JSONDecoder().decode(WorkbenchUser.self, from: userData)
            if lastIdentityID != newUser.identityID {
                identityEpoch = UUID(); expected = identityEpoch
                user = nil; modules = []; client.allowedOrigins = [baseURL.absoluteString]
                client.invalidateRequests(); NativeRecorder.shared.setAccountScope(nil)
                transitioning = true
                let store = WKWebsiteDataStore.default()
                for cookie in await store.httpCookieStore.luxCookies() {
                    guard expected == identityEpoch else { return }
                    if let host = baseURL.host, !WorkbenchHTTPClient.cookie(cookie, matchesHost: host) { await store.httpCookieStore.luxDelete(cookie) }
                }
                await store.luxClearLocalWebsiteData()
                guard expected == identityEpoch else { return }
                transitioning = false
            }
            let (catalogData, catalogResponse) = try await client.response(for: URLRequest(url: baseURL.appendingPathComponent("api/catalog/modules")))
            guard expected == identityEpoch else { return }
            guard catalogResponse.statusCode == 200 else { throw ClientError.status(catalogResponse.statusCode) }
            let catalog = try JSONDecoder().decode(WorkbenchCatalog.self, from: catalogData)
            guard catalog.version == 1 else { throw ClientError.invalidResponse }
            modules = catalog.modules; user = newUser
            client.allowedOrigins = businessOrigins
            NativeRecorder.shared.setAccountScope(newUser.identityID)
            lastIdentityID = newUser.identityID
            UserDefaults.standard.set(newUser.identityID, forKey: "lastEnterpriseIdentity")
            notice = nil; showLogin = false
        } catch {
            guard expected == identityEpoch else { return }
            transitioning = false
            notice = "暂时无法连接工作台，请检查网络后刷新。"
        }
    }
    func logout() async {
        guard !transitioning else { return }
        identityEpoch = UUID(); let expected = identityEpoch
        transitioning = true; loading = false
        client.invalidateRequests()
        NativeRecorder.shared.setAccountScope(nil)
        user = nil; modules = []; showLogin = false
        client.allowedOrigins = Set([baseURL?.absoluteString].compactMap { $0 })
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await store.luxCookies() { await store.luxDelete(cookie) }
        await WKWebsiteDataStore.default().luxClearLocalWebsiteData()
        guard expected == identityEpoch else { return }
        transitioning = false; lastIdentityID = nil
        UserDefaults.standard.removeObject(forKey: "lastEnterpriseIdentity")
        notice = "已退出此设备的企业会话。"
    }
    func permitsWebNavigation(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let origin = url.originURL?.absoluteString else { return false }
        if businessOrigins.contains(origin) || configuration.authOrigins.contains(origin) { return true }
        guard let host = url.host?.lowercased() else { return false }
        return ["feishu.cn", "larksuite.com", "larkoffice.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
