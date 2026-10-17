import XCTest

final class ProbeSmokeTests: XCTestCase {
    func testIndependentProbeIsHonestAndShowsBothSources() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["通话采集实验"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["独立实验 · 尚未验证通话双方"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "未收到样本").count, 2)
        XCTAssertTrue(app.buttons["开始采集实验"].isEnabled)
        XCTAssertFalse(app.buttons["停止并保存"].exists)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "call-probe-initial"; initial.lifetime = .keepAlways; add(initial)
        app.buttons["开始采集实验"].tap()
        let unavailable = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "模拟器没有", "当前设备无法")).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["开始采集实验"].isEnabled)
        XCTAssertFalse(app.buttons["停止并保存"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "未收到样本").count, 2)
        let denied = XCTAttachment(screenshot: app.screenshot())
        denied.name = "call-probe-no-fake-simulator-recording"; denied.lifetime = .keepAlways; add(denied)
    }
}
