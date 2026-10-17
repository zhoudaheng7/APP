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
        XCTAssertLessThan(app.otherElements["recording-card"].firstMatch.frame.height, 170)
        print("LAYOUT_METRICS panelHeight=\(panel.frame.height) recordingCardHeight=\(app.otherElements["recording-card"].firstMatch.frame.height)")
        check.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0 条视频轨")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let play = app.buttons["播放"].firstMatch
        reveal(play, in: app)
        XCTAssertTrue(app.staticTexts["audio-file-size"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["waveform-drag-hint"].firstMatch.exists)
        let slider = app.descendants(matching: .any)["audio-progress"].firstMatch
        let clock = app.staticTexts["playback-time"].firstMatch
        XCTAssertTrue(slider.exists)
        let initialSecond = elapsedSeconds(clock)
        let initialPercent = progressPercent(slider)
        play.tap()
        XCTAssertTrue(app.staticTexts["正在播放"].firstMatch.waitForExistence(timeout: 3))
        // No waveform touches or seeks: both the clock and the actual rendered cursor
        // must advance on the very first play, rather than being woken by a drag.
        expectation(for: NSPredicate { _, _ in
            self.elapsedSeconds(clock) >= initialSecond + 3 && self.progressPercent(slider) > initialPercent
        }, evaluatedWith: slider)
        waitForExpectations(timeout: 12)
        XCTAssertTrue((slider.value as? String ?? "").contains("定位提交 0"))
        print("AUTOPLAY_METRICS firstPlayTime=\(clock.label) progress=\(slider.value ?? "")")
        snapshot(app, "first-play-progress-without-touch")
        app.buttons["暂停"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已暂停"].firstMatch.waitForExistence(timeout: 2))
        let pausedClock = clock.label
        let pausedProgress = slider.value as? String
        let changedWhilePaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            clock.label != pausedClock || (slider.value as? String) != pausedProgress
        }, object: clock)
        changedWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changedWhilePaused], timeout: 2), .completed)
        let pausedSecond = elapsedSeconds(clock)
        let pausedPercent = progressPercent(slider)
        app.buttons["播放"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["正在播放"].firstMatch.waitForExistence(timeout: 3))
        expectation(for: NSPredicate { _, _ in
            self.elapsedSeconds(clock) >= pausedSecond + 3 && self.progressPercent(slider) > pausedPercent
        }, evaluatedWith: slider)
        waitForExpectations(timeout: 12)
        XCTAssertTrue((slider.value as? String ?? "").contains("定位提交 0"))
        print("AUTOPLAY_METRICS resumeTime=\(clock.label) progress=\(slider.value ?? "")")
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
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "定位提交 2"), evaluatedWith: slider)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["已暂停"].exists)
        let tappedTime = app.staticTexts["playback-time"].firstMatch.label
        let tapped = tappedTime.components(separatedBy: " / ")[0].split(separator: ":").compactMap { Int($0) }
        XCTAssertLessThan((tapped.first ?? 0) * 60 + (tapped.last ?? 0), 20)
        XCTAssertEqual(tappedTime.components(separatedBy: " / ").last, time.components(separatedBy: " / ").last)
        snapshot(app, "integrated-waveform-tap-to-seek")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "定位提交 3"), evaluatedWith: slider)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["已暂停"].exists)
        let finalTime = app.staticTexts["playback-time"].firstMatch.label
        let final = finalTime.components(separatedBy: " / ")[0].split(separator: ":").compactMap { Int($0) }
        XCTAssertGreaterThan((final.first ?? 0) * 60 + (final.last ?? 0), 45)
        XCTAssertEqual(finalTime.components(separatedBy: " / ").last, time.components(separatedBy: " / ").last)
    }
    private func elapsedSeconds(_ clock: XCUIElement) -> Int {
        clock.label.components(separatedBy: " / ")[0].split(separator: ":")
            .reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }
    private func progressPercent(_ slider: XCUIElement) -> Double {
        Double((slider.value as? String ?? "0%").components(separatedBy: "%")[0]) ?? 0
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
