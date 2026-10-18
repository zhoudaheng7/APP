import Foundation
import WebKit

extension WKHTTPCookieStore {
    func luxCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in getAllCookies { continuation.resume(returning: $0) } }
    }
    func luxDelete(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in delete(cookie) { continuation.resume() } }
    }
}

extension WKWebsiteDataStore {
    func luxClearLocalWebsiteData() async {
        let types = Self.allWebsiteDataTypes().subtracting([WKWebsiteDataTypeCookies])
        await withCheckedContinuation { continuation in
            removeData(ofTypes: types, modifiedSince: .distantPast) { continuation.resume() }
        }
    }
}

enum ClientError: LocalizedError {
    case forbiddenOrigin, invalidResponse, status(Int), identityChanged, unsignedDraft
    var errorDescription: String? {
        switch self {
        case .forbiddenOrigin: return "此地址不在当前企业模块目录中。"
        case .invalidResponse: return "服务返回了无法识别的结果。"
        case .status(401): return "请先连接此模块并完成企业登录。"
        case .status(403): return "当前账号未获此操作权限。"
        case .status(let code): return "服务暂时未能完成操作（\(code)）。"
        case .identityChanged: return "当前账号与这段录音的账号不一致，请切回原账号。"
        case .unsignedDraft: return "这段录音没有当前账号归属，请通过网页文件选择主动导入。"
        }
    }
}

private final class APIRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// API calls reuse only cookies for their exact approved origin, never a shared Cookie header.
@MainActor
final class WorkbenchHTTPClient {
    var allowedOrigins = Set<String>()
    private(set) var generation: UInt64 = 0
    private let cookieReader: (() async -> [HTTPCookie])?
    private let redirectGuard = APIRedirectGuard()
    private var sessionStorage: URLSession?
    init(cookieReader: (() async -> [HTTPCookie])? = nil) { self.cookieReader = cookieReader }
    func invalidateRequests() {
        generation &+= 1
        sessionStorage?.invalidateAndCancel(); sessionStorage = nil
    }
    private func session() -> URLSession {
        if let sessionStorage { return sessionStorage }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 900
        let result = URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
        sessionStorage = result; return result
    }
    static func cookie(_ cookie: HTTPCookie, matchesHost host: String) -> Bool {
        let domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") {
            let suffix = String(domain.dropFirst())
            return host.lowercased() == suffix || host.lowercased().hasSuffix("." + suffix)
        }
        return host.lowercased() == domain
    }
    private func cookies(for url: URL) async -> [HTTPCookie] {
        guard let host = url.host else { return [] }
        let all: [HTTPCookie]
        if let cookieReader { all = await cookieReader() }
        else { all = await WKWebsiteDataStore.default().httpCookieStore.luxCookies() }
        return all.filter { cookie in
            let requestedPath = url.path.isEmpty ? "/" : url.path
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = requestedPath == cookiePath || (requestedPath.hasPrefix(cookiePath) && (cookiePath.hasSuffix("/") || requestedPath.dropFirst(cookiePath.count).first == "/"))
            return Self.cookie(cookie, matchesHost: host) && pathMatches && (cookie.expiresDate == nil || cookie.expiresDate! > Date()) && (!cookie.isSecure || url.scheme == "https")
        }
    }
    func cookie(named: String, for url: URL) async -> String? {
        let expected = generation
        guard let origin = url.originURL?.absoluteString, allowedOrigins.contains(origin) else { return nil }
        let result = await cookies(for: url).first { $0.name == named }?.value
        guard expected == generation, allowedOrigins.contains(origin) else { return nil }
        return result
    }
    func prepared(_ input: URLRequest) async throws -> URLRequest {
        let expected = generation
        guard let url = input.url, let origin = url.originURL?.absoluteString,
              allowedOrigins.contains(origin), url.scheme == "https", url.user == nil, url.password == nil else { throw ClientError.forbiddenOrigin }
        var request = input
        request.httpShouldHandleCookies = false
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        let matching = await cookies(for: url)
        guard expected == generation, allowedOrigins.contains(origin) else { throw ClientError.identityChanged }
        for (key, value) in HTTPCookie.requestHeaderFields(with: matching) { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    func response(for input: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let expected = generation
        let request = try await prepared(input)
        guard expected == generation else { throw ClientError.identityChanged }
        let (data, response) = try await session().data(for: request)
        guard expected == generation else { throw ClientError.identityChanged }
        guard let response = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        return (data, response)
    }
    func bytes(for input: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let expected = generation
        var request = try await prepared(input)
        guard expected == generation else { throw ClientError.identityChanged }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session().bytes(for: request)
        guard expected == generation else { throw ClientError.identityChanged }
        guard let response = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        return (bytes, response)
    }
    func upload(file: URL, to input: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let expected = generation
        let request = try await prepared(input)
        guard expected == generation else { throw ClientError.identityChanged }
        let (data, response) = try await session().upload(for: request, fromFile: file)
        guard expected == generation else { throw ClientError.identityChanged }
        guard let response = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        return (data, response)
    }
}
