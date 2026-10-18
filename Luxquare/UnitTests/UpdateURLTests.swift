import Foundation
import XCTest
@testable import Luxquare

final class UpdateURLTests: XCTestCase {
    @MainActor
    func testInstallLinkUsesAppleAuthorityForm() throws {
        let manifest = try XCTUnwrap(URL(string: "https://work.company.example/releases/channel/v1/manifest.plist"))
        let url = try XCTUnwrap(UpdateService.installationURL(for: manifest))
        XCTAssertTrue(url.absoluteString.hasPrefix("itms-services://?action=download-manifest&url="))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "itms-services")
        XCTAssertEqual(parts.host, "")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "action" }?.value, "download-manifest")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "url" }?.value, manifest.absoluteString)
    }

    @MainActor
    func testManifestURLRoundTripsThroughOneQueryItem() throws {
        let manifest = try XCTUnwrap(URL(string: "https://work.company.example/releases/test%20folder/manifest.plist?channel=first&version=next"))
        let url = try XCTUnwrap(UpdateService.installationURL(for: manifest))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.queryItems?.count, 2)
        XCTAssertEqual(parts.queryItems?.first { $0.name == "url" }?.value, manifest.absoluteString)
    }
}
