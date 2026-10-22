import XCTest
@testable import LifeOS

@MainActor final class LifeStoreTests: XCTestCase {
    func testTaskAndSessionAreIndependent() throws {
        let store = LifeStore(inMemory: true)
        XCTAssertTrue(store.ready)
        XCTAssertTrue(store.addTask(title: "阅读", note: "", goalID: nil))
        let task = try XCTUnwrap(store.data.tasks.first)
        XCTAssertTrue(store.startSession(title: task.title, taskID: task.id))
        store.stopSession()
        XCTAssertNil(store.data.tasks.first?.completedAt)
        let session = try XCTUnwrap(store.data.sessions.first)
        XCTAssertFalse(session.confirmed)
        store.confirmSession(session)
        XCTAssertTrue(store.data.sessions[0].confirmed)
        XCTAssertNil(store.data.tasks[0].completedAt)
        store.completeTask(task)
        XCTAssertNotNil(store.data.tasks[0].completedAt)
    }
    func testSecondTimerDoesNotChangePersistedState() {
        let store = LifeStore(inMemory: true)
        XCTAssertTrue(store.startSession(title: "第一段"))
        let count = store.data.pendingChanges.count
        XCTAssertFalse(store.startSession(title: "第二段"))
        XCTAssertEqual(store.data.sessions.count, 1)
        XCTAssertEqual(store.data.pendingChanges.count, count)
    }
    func testInvalidPlanRollsBackDataAndJournal() {
        let store = LifeStore(inMemory: true)
        let now = Date()
        XCTAssertFalse(store.addPlan(LifePlan(title: "无效", start: now, end: now)))
        XCTAssertTrue(store.data.plans.isEmpty)
        XCTAssertTrue(store.data.pendingChanges.isEmpty)
    }
    func testDurableReopenPreservesRecordsAndChangesTogether() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = LifeStore(directory: parent)
        XCTAssertTrue(first.addTask(title: "跨版本保留", note: "本机", goalID: nil))
        let id = first.data.tasks[0].id
        let reopened = LifeStore(directory: parent)
        XCTAssertTrue(reopened.ready)
        XCTAssertEqual(reopened.data.tasks[0].id, id)
        XCTAssertEqual(reopened.data.tasks[0].title, "跨版本保留")
        XCTAssertEqual(reopened.data.pendingChanges.count, 1)
    }
    func testCanonicalReviewCannotBeSilentlyOverwritten() {
        let store = LifeStore(inMemory: true)
        XCTAssertTrue(store.addReview(LifeReview(day: "2026-10-22", reflection: "原件", mood: 3)))
        XCTAssertFalse(store.addReview(LifeReview(day: "2026-10-22", reflection: "覆盖", mood: 4)))
        XCTAssertEqual(store.data.reviews.first?.reflection, "原件")
        XCTAssertEqual(store.data.pendingChanges.count, 1)
    }
    func testMidnightDurationUsesHalfOpenDay() throws {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        let start = day.addingTimeInterval(-1800), end = day.addingTimeInterval(1800)
        XCTAssertEqual(clippedSeconds(start, end, day: day), 1800, accuracy: 0.001)
        XCTAssertFalse(overlapsDay(start, day, day: day))
    }
    func testMeasurementsNeverDeriveFromTaskOrTime() throws {
        let store = LifeStore(inMemory: true)
        let goal = LifeGoal(title: "读书", intention: "", target: 12, unit: "本", due: Date())
        XCTAssertTrue(store.addGoal(goal))
        XCTAssertTrue(store.addTask(title: "读一章", note: "", goalID: goal.id))
        store.completeTask(try XCTUnwrap(store.data.tasks.first))
        XCTAssertTrue(store.data.measurements.isEmpty)
        XCTAssertTrue(store.addMeasurement(LifeMeasurement(goalID: goal.id, value: 2, note: "手动确认")))
        XCTAssertEqual(store.data.measurements.first?.value, 2)
    }
}
