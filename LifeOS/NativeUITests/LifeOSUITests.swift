import XCTest

final class LifeOSUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testNativeTabsAndScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        for name in ["今天", "地图", "方向", "计划", "记忆"] {
            let tab = app.tabBars.buttons[name]; XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "LifeOS-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testCreateTaskSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        let title = "手机任务-" + String(UUID().uuidString.prefix(6))
        let add = app.buttons["addTask"]; XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let field = app.textFields["composerTitle"]
        if field.waitForExistence(timeout: 3) { field.tap(); field.typeText(title) }
        else { let input = app.textViews["composerTitle"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(title) }
        app.buttons["saveComposer"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8))
    }
}
