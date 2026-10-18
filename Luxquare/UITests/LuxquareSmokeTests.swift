import XCTest

final class LuxquareSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNativeShellAndTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["LUXQUARE_UI_TESTING"] = "1"
        app.launch()

        let brand = app.descendants(matching: .any).matching(identifier: "luxquare.brand").firstMatch
        XCTAssertTrue(brand.waitForExistence(timeout: 15), "Cold launch must render the real native shell")
        capture("01-home")

        tap("native.tab.tools", in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "native.tools.screen").firstMatch.waitForExistence(timeout: 5))
        capture("02-native-tools")

        tap("native.tab.settings", in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "native.settings.screen").firstMatch.waitForExistence(timeout: 5))
        capture("03-settings")

        tap("native.tab.dialogue", in: app)
        capture("04-dialogue")
        tap("native.tab.home", in: app)
        XCTAssertTrue(brand.waitForExistence(timeout: 5))
        capture("05-return-home")
    }

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing native navigation: \(identifier)")
        XCTAssertTrue(element.isHittable, "Navigation must be reachable: \(identifier)")
        element.tap()
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
