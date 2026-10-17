import XCTest

final class RecordingInteractionTests: XCTestCase {
    func testTrackCheckAndVisiblePlaybackFeedback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let check = app.buttons["检查音轨"].firstMatch
        reveal(check, in: app)
        check.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0 条视频轨")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Track results must be visible inside the recording card")
        let play = app.buttons["播放"].firstMatch
        if !play.isHittable { app.swipeDown() }
        reveal(play, in: app)
        play.tap()
        XCTAssertTrue(app.staticTexts["正在播放"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders.firstMatch.exists)
        let pause = app.buttons["暂停"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 2))
        pause.tap()
        XCTAssertTrue(app.staticTexts["已暂停"].firstMatch.waitForExistence(timeout: 2))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "recording-waveform-and-track-result"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
