import XCTest

final class RecordingInteractionTests: XCTestCase {
    func testCompactLayoutTrackCheckPlaybackAndScrubCommit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-performance-probe"]
        app.launch()
        let panel = app.otherElements["capture-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertLessThan(panel.frame.height, 260)
        XCTAssertTrue(app.buttons["开始内录"].firstMatch.isHittable)
        snapshot(app, "compact-capture-panel")
        app.buttons["recording-help"].tap()
        XCTAssertTrue(app.staticTexts["从控制中心开始"].waitForExistence(timeout: 3))
        app.buttons["知道了"].tap()
        let check = app.buttons["检查音轨"].firstMatch
        reveal(check, in: app)
        XCTAssertLessThan(app.otherElements["recording-card"].firstMatch.frame.height, 210)
        check.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0 条视频轨")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let play = app.buttons["播放"].firstMatch
        reveal(play, in: app)
        XCTAssertTrue(app.staticTexts["audio-file-size"].firstMatch.exists)
        play.tap()
        XCTAssertTrue(app.staticTexts["正在播放"].firstMatch.waitForExistence(timeout: 3))
        let slider = app.sliders["audio-progress"].firstMatch
        XCTAssertTrue(slider.exists)
        let value = slider.value as? String ?? "0%"
        let percent = Double(value.components(separatedBy: "%")[0]) ?? 0
        let thumb = (9 + (slider.frame.width - 18) * percent / 100) / slider.frame.width
        let from = slider.coordinate(withNormalizedOffset: CGVector(dx: thumb, dy: 0.5))
        let to = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        expectation(for: NSPredicate(format: "value CONTAINS %@", "定位提交 1"), evaluatedWith: slider)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["正在播放"].exists)
        app.buttons["暂停"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已暂停"].firstMatch.waitForExistence(timeout: 2))
        let time = app.staticTexts["playback-time"].firstMatch.label
        let current = time.components(separatedBy: " / ")[0].split(separator: ":").compactMap { Int($0) }
        XCTAssertGreaterThan((current.first ?? 0) * 60 + (current.last ?? 0), 30)
        snapshot(app, "compact-recording-waveform-after-scrub")
    }
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
