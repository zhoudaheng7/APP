import Foundation
import XCTest
@testable import Luxquare

/// These tests call the real request preparation and cookie matching paths.
/// The injected reader supplies inert cookies; response/bytes/upload are never called.
final class WorkbenchHTTPClientTests: XCTestCase {
    private let origin = "https://recordings.company.example"

    @MainActor
    func testUnapprovedOriginIsRejectedBeforeReadingAnyCookie() async throws {
        let reader = CookieReadRecorder([])
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        let input = URLRequest(url: URL(string: "https://unregistered.company.example/api/me")!)
        do {
            _ = try await client.prepared(input)
            XCTFail("An unregistered origin must be rejected before cookie access")
        } catch { assertForbiddenOrigin(error) }
        XCTAssertEqual(reader.count, 0)
    }

    @MainActor
    func testPreparedRequestAttachesOnlyTargetModuleCookiesAndReplacesCallerHeader() async throws {
        let reader = CookieReadRecorder([
            try cookie("recordings_session", domain: "recordings.company.example", value: "recordings-example"),
            try cookie("workbench_session", domain: "work.company.example", value: "workbench-example"),
            try cookie("easel_session", domain: "easel.company.example", value: "easel-example")
        ])
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin, "https://work.company.example", "https://easel.company.example"]
        var input = URLRequest(url: URL(string: origin + "/api/me")!)
        input.setValue("caller_supplied=must-not-survive", forHTTPHeaderField: "Cookie")
        let result = try await client.prepared(input)
        XCTAssertEqual(cookieHeader(result), ["recordings_session": "recordings-example"])
        XCTAssertFalse(result.httpShouldHandleCookies)
        XCTAssertEqual(result.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(reader.count, 1)
    }

    @MainActor
    func testActualHostMatcherRespectsHostOnlyAndDomainBoundaries() throws {
        let exact = try cookie("exact", domain: "Recordings.Company.Example")
        let parent = try cookie("parent", domain: ".company.example")
        XCTAssertTrue(WorkbenchHTTPClient.cookie(exact, matchesHost: "recordings.company.example"))
        XCTAssertFalse(WorkbenchHTTPClient.cookie(exact, matchesHost: "child.recordings.company.example"))
        XCTAssertFalse(WorkbenchHTTPClient.cookie(exact, matchesHost: "recordings.company.example.attacker.example"))
        XCTAssertTrue(WorkbenchHTTPClient.cookie(parent, matchesHost: "company.example"))
        XCTAssertTrue(WorkbenchHTTPClient.cookie(parent, matchesHost: "recordings.company.example"))
        XCTAssertFalse(WorkbenchHTTPClient.cookie(parent, matchesHost: "notcompany.example"))
        XCTAssertFalse(WorkbenchHTTPClient.cookie(parent, matchesHost: "company.example.attacker.example"))
    }

    @MainActor
    func testPreparedRequestHonorsCookiePathSlashBoundaries() async throws {
        let reader = CookieReadRecorder([
            try cookie("root", domain: "recordings.company.example", path: "/"),
            try cookie("api", domain: "recordings.company.example", path: "/api"),
            try cookie("apiSlash", domain: "recordings.company.example", path: "/api/"),
            try cookie("exactAudio", domain: "recordings.company.example", path: "/api/recordings/audio"),
            try cookie("other", domain: "recordings.company.example", path: "/api-private")
        ])
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        let audio = try await client.prepared(URLRequest(url: URL(string: origin + "/api/recordings/audio")!))
        XCTAssertEqual(Set(cookieHeader(audio).keys), Set(["root", "api", "apiSlash", "exactAudio"]))
        let api = try await client.prepared(URLRequest(url: URL(string: origin + "/api")!))
        XCTAssertEqual(Set(cookieHeader(api).keys), Set(["root", "api"]))
        let lookalike = try await client.prepared(URLRequest(url: URL(string: origin + "/apix")!))
        XCTAssertEqual(Set(cookieHeader(lookalike).keys), Set(["root"]))
    }

    @MainActor
    func testExpiredCookiesAreExcludedWhileSessionAndFutureCookiesRemain() async throws {
        let reader = CookieReadRecorder([
            try cookie("expired", domain: "recordings.company.example", expires: Date(timeIntervalSinceNow: -120)),
            try cookie("future", domain: "recordings.company.example", expires: Date(timeIntervalSinceNow: 3_600)),
            try cookie("session", domain: "recordings.company.example")
        ])
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        let result = try await client.prepared(URLRequest(url: URL(string: origin + "/api/me")!))
        XCTAssertEqual(Set(cookieHeader(result).keys), Set(["future", "session"]))
    }

    @MainActor
    func testSecureCookiesCanReachHTTPSButHTTPIsRejectedBeforeCookieAccess() async throws {
        let secure = try cookie("secure", domain: "recordings.company.example", secure: true)
        XCTAssertTrue(secure.isSecure)
        let reader = CookieReadRecorder([secure])
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin, "http://recordings.company.example"]
        let result = try await client.prepared(URLRequest(url: URL(string: origin + "/api/me")!))
        XCTAssertEqual(Set(cookieHeader(result).keys), Set(["secure"]))
        let before = reader.count
        do {
            _ = try await client.prepared(URLRequest(url: URL(string: "http://recordings.company.example/api/me")!))
            XCTFail("No cookie, secure or otherwise, may be prepared for HTTP")
        } catch { assertForbiddenOrigin(error) }
        XCTAssertEqual(reader.count, before)
    }

    @MainActor
    func testIdentityInvalidationDuringCookieAwaitRejectsOldPreparedRequest() async throws {
        let entered = expectation(description: "Cookie reader is suspended")
        let reader = SuspendedCookieReader { entered.fulfill() }
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        let previousGeneration = client.generation
        let request = URLRequest(url: URL(string: origin + "/api/me")!)
        let task = Task { try await client.prepared(request) }
        await fulfillment(of: [entered], timeout: 2)
        defer { reader.release([]); task.cancel() }
        guard reader.isSuspended else { XCTFail("The real preparation path did not reach the injected reader"); return }
        client.invalidateRequests()
        reader.release([try cookie("old_identity", domain: "recordings.company.example")])
        do {
            _ = try await task.value
            XCTFail("A cookie captured before an identity transition must never yield a usable request")
        } catch { assertIdentityChanged(error) }
        XCTAssertEqual(client.generation, previousGeneration + 1)
    }

    @MainActor
    func testAllowlistRevocationDuringCookieAwaitRejectsPreparedRequest() async throws {
        let entered = expectation(description: "Cookie reader is suspended")
        let reader = SuspendedCookieReader { entered.fulfill() }
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        let previousGeneration = client.generation
        let request = URLRequest(url: URL(string: origin + "/api/me")!)
        let task = Task { try await client.prepared(request) }
        await fulfillment(of: [entered], timeout: 2)
        defer { reader.release([]); task.cancel() }
        guard reader.isSuspended else { XCTFail("The reader was not reached"); return }
        client.allowedOrigins = []
        reader.release([try cookie("revoked", domain: "recordings.company.example")])
        do {
            _ = try await task.value
            XCTFail("An origin revoked while cookie access was waiting must be rejected")
        } catch { assertIdentityChanged(error) }
        XCTAssertEqual(client.generation, previousGeneration)
    }

    @MainActor
    func testNamedCookieLookupAlsoRejectsIdentityInvalidationWhileWaiting() async throws {
        let entered = expectation(description: "Named-cookie reader is suspended")
        let reader = SuspendedCookieReader { entered.fulfill() }
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        let target = URL(string: origin + "/api/recordings/audio")!
        let task = Task { await client.cookie(named: "csrf_example", for: target) }
        await fulfillment(of: [entered], timeout: 2)
        defer { reader.release([]); task.cancel() }
        guard reader.isSuspended else { XCTFail("The reader was not reached"); return }
        client.invalidateRequests()
        reader.release([try cookie("csrf_example", domain: "recordings.company.example")])
        let result = await task.value
        XCTAssertNil(result)
    }

    @MainActor
    func testNamedCookieLookupAlsoRejectsAllowlistRevocationWhileWaiting() async throws {
        let entered = expectation(description: "Named-cookie reader is suspended")
        let reader = SuspendedCookieReader { entered.fulfill() }
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        let target = URL(string: origin + "/api/recordings/audio")!
        let task = Task { await client.cookie(named: "csrf_example", for: target) }
        await fulfillment(of: [entered], timeout: 2)
        defer { reader.release([]); task.cancel() }
        guard reader.isSuspended else { XCTFail("The reader was not reached"); return }
        client.allowedOrigins = []
        reader.release([try cookie("csrf_example", domain: "recordings.company.example")])
        let result = await task.value
        XCTAssertNil(result)
    }

    @MainActor
    func testNewPreparationAfterInvalidationUsesTheNewGeneration() async throws {
        let reader = CookieReadRecorder([try cookie("new_identity", domain: "recordings.company.example")])
        let client = WorkbenchHTTPClient(cookieReader: { await reader.read() })
        client.allowedOrigins = [origin]
        client.invalidateRequests()
        let result = try await client.prepared(URLRequest(url: URL(string: origin + "/api/me")!))
        XCTAssertEqual(Set(cookieHeader(result).keys), Set(["new_identity"]))
        XCTAssertEqual(reader.count, 1)
    }

    private func cookie(_ name: String, domain: String, path: String = "/", value: String = "inert-example",
                        secure: Bool = false, expires: Date? = nil) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }

    private func cookieHeader(_ request: URLRequest) -> [String: String] {
        let fields = request.value(forHTTPHeaderField: "Cookie")?.split(separator: ";") ?? []
        var result: [String: String] = [:]
        for field in fields {
            let pieces = field.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pieces.count == 2 { result[String(pieces[0])] = String(pieces[1]) }
        }
        return result
    }

    private func assertForbiddenOrigin(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard let clientError = error as? ClientError, case .forbiddenOrigin = clientError else {
            XCTFail("Expected forbiddenOrigin, received \(error)", file: file, line: line); return
        }
    }

    private func assertIdentityChanged(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard let clientError = error as? ClientError, case .identityChanged = clientError else {
            XCTFail("Expected identityChanged, received \(error)", file: file, line: line); return
        }
    }
}

@MainActor
private final class CookieReadRecorder {
    private let result: [HTTPCookie]
    private(set) var count = 0
    init(_ result: [HTTPCookie]) { self.result = result }
    func read() async -> [HTTPCookie] { count += 1; return result }
}

@MainActor
private final class SuspendedCookieReader {
    private let onRead: () -> Void
    private var continuation: CheckedContinuation<[HTTPCookie], Never>?
    var isSuspended: Bool { continuation != nil }
    init(onRead: @escaping () -> Void) { self.onRead = onRead }
    func read() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onRead()
        }
    }
    func release(_ result: [HTTPCookie]) {
        let waiting = continuation; continuation = nil
        waiting?.resume(returning: result)
    }
}
