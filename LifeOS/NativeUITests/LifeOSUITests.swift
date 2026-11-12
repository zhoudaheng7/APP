import XCTest

final class LifeOSUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testBaselineUpgradePreservesV1Task() throws {
        let app=XCUIApplication();app.launchArguments=["-ui-testing"];app.launch()
        let legacy=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","手机任务-")).firstMatch
        XCTAssertTrue(legacy.waitForExistence(timeout:15),"The baseline app's task must survive installing this new build")
        let title=legacy.label;app.terminate();app.launch();XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:10))
    }
    func testNativeTabsAndScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        for name in ["今天", "地图", "方向", "计划", "记忆"] {
            let tab = app.tabBars.buttons[name]; XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout:15),"The selected root must be displayed")
            // Capture the device screen without asking XCTest to snapshot the
            // complete application's accessibility hierarchy a second time.
            let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name = "LifeOS-" + name; attachment.lifetime = .keepAlways; add(attachment)
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
    func input(_ identifier: String,app: XCUIApplication) -> XCUIElement {
        let field = app.textFields[identifier]
        if field.waitForExistence(timeout:2) { return field }; return app.textViews[identifier]
    }
    func testClosingComposerKeepsDraftUntilExplicitSave() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        let title = "虚构草稿-" + String(UUID().uuidString.prefix(6))
        app.buttons["addTask"].tap(); let field = input("composerTitle",app:app); XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); field.typeText(title)
        app.buttons["关闭"].tap(); XCTAssertFalse(app.staticTexts[title].exists)
        app.buttons["addTask"].tap(); let restored = input("composerTitle",app:app); XCTAssertEqual(restored.value as? String,title)
        app.buttons["saveComposer"].tap(); XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:8))
    }
    func testStoryConfirmationPersistsAndOpensActualPDF() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch(); app.tabBars.buttons["记忆"].tap()
        app.buttons["storiesEntry"].tap(); app.buttons["制作一份故事"].tap()
        let title = "虚构故事-" + String(UUID().uuidString.prefix(6)),field = input("storyTitle",app:app)
        XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); if let value = field.value as? String { field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:value.count)) }; field.typeText(title)
        let narrative = input("storyNarrative",app:app); narrative.tap(); narrative.typeText("虚构示例：这是界面验证的手写故事，不代表真实生活记录。")
        let preview = app.buttons["storyPreview"]
        for _ in 0..<6 { if preview.exists && preview.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(preview.isHittable); preview.tap(); let save = app.buttons["saveStory"]; XCTAssertTrue(save.waitForExistence(timeout:8)); save.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:8)); app.staticTexts[title].tap(); app.buttons["storyActions"].tap(); app.buttons["查看PDF"].tap()
        XCTAssertTrue(app.navigationBars["PDF预览"].waitForExistence(timeout:10))
        let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name = "Dayisle-story-native-PDF-preview"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["完成"].tap(); app.terminate(); app.launch(); app.tabBars.buttons["记忆"].tap(); app.buttons["storiesEntry"].tap(); XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:8))
    }
}
