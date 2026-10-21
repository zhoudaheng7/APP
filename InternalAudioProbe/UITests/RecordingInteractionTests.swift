import XCTest

final class RecordingInteractionTests: XCTestCase {
    func testAudioExportUsesStartTimeForLegacyRecording() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let export = app.buttons["导出音频"].firstMatch
        reveal(export, in: app)
        export.tap()
        // The fixture deliberately keeps the old recording.m4a source URL.
        // The actual system share preview must receive the timestamp alias.
        // LinkPresentation exposes the system preview caption as Other, not StaticText.
        let name = app.otherElements["LP.CaptionBar.TopCaption"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(NSPredicate(format: "SELF MATCHES %@",
            "^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}(\\.m4a)?$").evaluate(with: name.label), name.label)
        XCTAssertTrue(app.navigationBars[name.label].exists)
        XCTAssertFalse(name.label == "recording" || name.label == "recording.m4a")
        snapshot(app, "timestamp-audio-export-name")
    }

    func testQuickMenuModesAreDirectAndPhoneFeaturesRemoved() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["recording-mode"].tap()
        app.buttons["内部音＋麦克风"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["内部音与麦克风混为一份"].exists)
        app.buttons["recording-mode"].tap()
        app.buttons["仅内部音"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["麦克风关闭"].exists)
        app.buttons["quick-recording-menu"].tap()
        let menu = app.navigationBars["选择模式"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["仅内部音"].firstMatch.exists)
        XCTAssertTrue(app.buttons["内部音＋麦克风"].firstMatch.exists)
        XCTAssertFalse(app.buttons["内部录音"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "通话")).firstMatch.exists)
        snapshot(app, "compact-direct-recording-menu")
        menu.buttons["取消"].tap()
        app.buttons["recording-help"].tap()
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 3))
        for text in ["通话", "AirBeep", "TrollRecorder", "企业签名", "方案说明", "验证版"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists)
        }
        snapshot(app, "brief-help-no-development-discussion")
        app.navigationBars["使用说明"].buttons["完成"].tap()
        XCTAssertTrue(app.buttons["开始内录"].firstMatch.isHittable)
    }
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
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 3))
        app.navigationBars["使用说明"].buttons["完成"].tap()
        XCTAssertFalse(app.navigationBars["选择模式"].waitForExistence(timeout: 1), "Help must not also activate the quick-menu button in the same List row")
        let check = app.buttons["检查音轨"].firstMatch
        reveal(check, in: app)
        XCTAssertLessThan(app.otherElements["recording-card"].firstMatch.frame.height, 170)
        print("LAYOUT_METRICS panelHeight=\(panel.frame.height) recordingCardHeight=\(app.otherElements["recording-card"].firstMatch.frame.height)")
        check.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "音轨 · 无视频")).firstMatch
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
        assertProgressAdvances(in: app, after: initialSecond, percent: initialPercent)
        XCTAssertTrue((slider.value as? String ?? "").contains("定位提交 0"))
        print("AUTOPLAY_METRICS firstPlayTime=\(clock.label) progress=\(slider.value ?? "")")
        snapshot(app, "first-play-progress-without-touch")
        app.buttons["暂停"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已暂停"].firstMatch.waitForExistence(timeout: 2))
        let pausedClock = clock.label
        let pausedProgress = slider.value as? String
        let changedWhilePaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts["playback-time"].firstMatch.label != pausedClock ||
                (app.descendants(matching: .any)["audio-progress"].firstMatch.value as? String) != pausedProgress
        }, object: nil)
        changedWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changedWhilePaused], timeout: 2), .completed)
        let pausedSecond = elapsedSeconds(clock)
        let pausedPercent = progressPercent(slider)
        app.buttons["播放"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["正在播放"].firstMatch.waitForExistence(timeout: 3))
        assertProgressAdvances(in: app, after: pausedSecond, percent: pausedPercent)
        XCTAssertTrue((slider.value as? String ?? "").contains("定位提交 0"))
        print("AUTOPLAY_METRICS resumeTime=\(clock.label) progress=\(slider.value ?? "")")
        let value = slider.value as? String ?? "0%"
        let percent = Double(value.components(separatedBy: "%")[0]) ?? 0
        let thumb = (9 + (slider.frame.width - 18) * percent / 100) / slider.frame.width
        let from = slider.coordinate(withNormalizedOffset: CGVector(dx: thumb, dy: 0.5))
        let to = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        assertSeekCommit(1, in: app)
        XCTAssertTrue(app.staticTexts["正在播放"].exists)
        app.buttons["暂停"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已暂停"].firstMatch.waitForExistence(timeout: 2))
        let time = app.staticTexts["playback-time"].firstMatch.label
        let current = time.components(separatedBy: " / ")[0].split(separator: ":").compactMap { Int($0) }
        XCTAssertGreaterThan((current.first ?? 0) * 60 + (current.last ?? 0), 30)
        snapshot(app, "compact-recording-waveform-after-scrub")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        assertSeekCommit(2, in: app)
        XCTAssertTrue(app.staticTexts["已暂停"].exists)
        let tappedTime = app.staticTexts["playback-time"].firstMatch.label
        let tapped = tappedTime.components(separatedBy: " / ")[0].split(separator: ":").compactMap { Int($0) }
        XCTAssertLessThan((tapped.first ?? 0) * 60 + (tapped.last ?? 0), 20)
        XCTAssertEqual(tappedTime.components(separatedBy: " / ").last, time.components(separatedBy: " / ").last)
        snapshot(app, "integrated-waveform-tap-to-seek")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)))
        assertSeekCommit(3, in: app)
        XCTAssertTrue(app.staticTexts["已暂停"].exists)
        let finalTime = app.staticTexts["playback-time"].firstMatch.label
        let final = finalTime.components(separatedBy: " / ")[0].split(separator: ":").compactMap { Int($0) }
        XCTAssertGreaterThan((final.first ?? 0) * 60 + (final.last ?? 0), 45)
        XCTAssertEqual(finalTime.components(separatedBy: " / ").last, time.components(separatedBy: " / ").last)
    }
    func testPlayFromMiddleAfterPausedDragAdvancesWithoutMoreTouches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-performance-probe"]
        app.launch()
        let play = app.buttons["播放"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        reveal(play, in: app)
        let slider = app.descendants(matching: .any)["audio-progress"].firstMatch
        let clock = app.staticTexts["playback-time"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 9 / slider.frame.width, dy: 0.5))
        start.press(forDuration: 0.1,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        assertSeekCommit(1, in: app)
        XCTAssertTrue(app.staticTexts["已暂停"].firstMatch.exists)
        let middleSecond = elapsedSeconds(clock)
        let middlePercent = progressPercent(slider)
        XCTAssertGreaterThan(middleSecond, 25)
        XCTAssertLessThan(middleSecond, 40)
        let total = clock.label.components(separatedBy: " / ").last
        play.tap()
        XCTAssertTrue(app.staticTexts["正在播放"].firstMatch.waitForExistence(timeout: 3))
        assertProgressAdvances(in: app, after: middleSecond, percent: middlePercent)
        XCTAssertTrue((slider.value as? String ?? "").contains("定位提交 1"))
        XCTAssertEqual(clock.label.components(separatedBy: " / ").last, total)
        print("AUTOPLAY_METRICS seekThenPlayTime=\(clock.label) progress=\(slider.value ?? "")")
        snapshot(app, "play-from-middle-progress-without-more-touch")
        app.buttons["暂停"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已暂停"].firstMatch.waitForExistence(timeout: 2))
    }
    private func assertSeekCommit(_ count: Int, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        // A bound XCUIElement can retain the value from before a drag completed.
        // Re-query the actual waveform on every poll, retaining the original deadline.
        let commit = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let cursor = app.descendants(matching: .any)["audio-progress"].firstMatch
            guard cursor.exists else { return false }
            return (cursor.value as? String ?? "").contains("定位提交 \(count)")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [commit], timeout: 5), .completed,
                       "The waveform must commit exactly the requested seek", file: file, line: line)
    }
    private func assertProgressAdvances(in app: XCUIApplication, after seconds: Int, percent: Double,
                                       file: StaticString = #filePath, line: UInt = #line) {
        // Binding an XCUIElement as a block predicate's object pins its old snapshot.
        // Re-query both controls on each poll, without a bound accessibility element.
        let advance = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let freshClock = app.staticTexts["playback-time"].firstMatch
            let freshCursor = app.descendants(matching: .any)["audio-progress"].firstMatch
            guard freshClock.exists, freshCursor.exists else { return false }
            return self.elapsedSeconds(freshClock) >= seconds + 3 && self.progressPercent(freshCursor) > percent
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advance], timeout: 12), .completed,
                       "Clock and rendered cursor must advance without waveform touches", file: file, line: line)
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
