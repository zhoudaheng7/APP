import Foundation
import Testing
import LifeOSDomain
import LifeOSApplication

@Test func sessionsNeverCompleteTaskOrOverwritePlan() async throws {
    let repository = InMemoryFactRepository()
    let commands = LocalFactCommands(repository: repository)
    let task = try LifeOSDomain.Task(id: .new(), title: "Work", revision: Revision())
    let plan = try DraftPlan(id: .new(), taskID: task.id,
        time: TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100)),
        attributionTimeZone: AttributionTimeZone("UTC"), revision: Revision())
    try await commands.createTask(task)
    try await commands.createDraftPlan(plan)
    for _ in 0..<2 {
        let session = try ActualSession(id: .new(), taskID: task.id, primaryDraftPlanID: plan.id,
            startedAt: Date(timeIntervalSince1970: 0), attributionTimeZone: AttributionTimeZone("UTC"), revision: Revision())
        try await commands.recordActualSession(session)
        try await commands.stopActualSession(session.id, baseRevision: Revision(), at: Date(timeIntervalSince1970: 60))
        try await commands.classifyActualSession(session.id, baseRevision: Revision(2), as: .confirmed)
    }
    let result = await repository.snapshot()
    #expect(result.tasks[task.id] == task)
    #expect(result.draftPlans[plan.id] == plan)
    #expect(result.actualSessions.count == 2)
    #expect(result.actualSessions.values.allSatisfy { $0.primaryDraftPlanID == plan.id && $0.factState == .confirmed })
    #expect(result.calendarCommitments.isEmpty)
}

@Test func staleRevisionCannotOverwriteNewFact() async throws {
    let repository = InMemoryFactRepository()
    let commands = LocalFactCommands(repository: repository)
    let task = try LifeOSDomain.Task(id: .new(), title: "Work", revision: Revision())
    try await commands.createTask(task)
    try await commands.changeTask(task.id, baseRevision: Revision(), to: .completed)
    let before = await repository.snapshot()
    await #expect(throws: ApplicationError.revisionConflict) {
        try await commands.changeTask(task.id, baseRevision: Revision(), to: .cancelled)
    }
    let after = await repository.snapshot()
    #expect(after == before)
}

@Test func newFactsCannotStartAtARehydratedRevision() async throws {
    let repository = InMemoryFactRepository()
    let commands = LocalFactCommands(repository: repository)
    let task = try LifeOSDomain.Task(id: .new(), title: "Rehydrated", revision: Revision(7))
    await #expect(throws: ApplicationError.initialRevisionMustBeOne) { try await commands.createTask(task) }
    let result = await repository.snapshot()
    #expect(result.tasks.isEmpty)
}

@Test func failedSaveDoesNotLeakIntoNextCommand() async throws {
    let repository = InMemoryFactRepository()
    let commands = LocalFactCommands(repository: repository)
    let failed = try LifeOSDomain.Task(id: .new(), title: "Must not persist", revision: Revision())
    let next = try LifeOSDomain.Task(id: .new(), title: "Next command", revision: Revision())
    await repository.injectSaveFailure()
    await #expect(throws: InjectedFailure.save) { try await commands.createTask(failed) }
    let afterFailure = await repository.snapshot()
    #expect(afterFailure.tasks.isEmpty)
    try await commands.createTask(next)
    let afterNext = await repository.snapshot()
    #expect(afterNext.tasks.count == 1 && afterNext.tasks[next.id] == next)
    #expect(afterNext.tasks[failed.id] == nil)
    let saves = await repository.saves
    #expect(saves == 1)
}

@Test func mutationFailureDiscardsWholeWorkingSet() async throws {
    let repository = InMemoryFactRepository()
    let task = try LifeOSDomain.Task(id: .new(), title: "Example", revision: Revision())
    await #expect(throws: ApplicationError.revisionConflict) {
        try await repository.transaction { state in
            state.tasks[task.id] = task
            throw ApplicationError.revisionConflict
        }
    }
    let result = await repository.snapshot()
    #expect(result.tasks.isEmpty)
}

@Test func concurrentDailyReviewsCannotCreateTwoCanonicalFacts() async throws {
    let repository = InMemoryFactRepository()
    let commands = LocalFactCommands(repository: repository)
    let day = try ReviewDay(year: 2026, month: 9, day: 11)
    let first = try DailyReview(id: .new(), day: day, attributionTimeZone: AttributionTimeZone("Asia/Shanghai"),
                               revision: Revision(), reflection: "First")
    let second = try DailyReview(id: .new(), day: day, attributionTimeZone: AttributionTimeZone("UTC"),
                                revision: Revision(), reflection: "Second")
    let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
        for review in [first, second] {
            group.addTask {
                do { try await commands.createCanonicalDailyReview(review); return true }
                catch { return false }
            }
        }
        var values: [Bool] = []
        for await value in group { values.append(value) }
        return values
    }
    #expect(outcomes.filter { $0 }.count == 1)
    let result = await repository.snapshot()
    #expect(result.dailyReviews.count == 1)
}

@Test func duplicateCanonicalReviewIsAnExplicitConflict() async throws {
    let repository = InMemoryFactRepository()
    let commands = LocalFactCommands(repository: repository)
    let day = try ReviewDay(year: 2026, month: 9, day: 11)
    let first = try DailyReview(id: .new(), day: day, attributionTimeZone: AttributionTimeZone("UTC"),
                               revision: Revision(), reflection: "First")
    let second = try DailyReview(id: .new(), day: day, attributionTimeZone: AttributionTimeZone("UTC"),
                                revision: Revision(), reflection: "Second")
    try await commands.createCanonicalDailyReview(first)
    await #expect(throws: ApplicationError.canonicalReviewExists) { try await commands.createCanonicalDailyReview(second) }
}

@Test func explicitTaskCompletionAndDuplicateIdentityGuard() async throws {
    let repository = InMemoryFactRepository()
    let commands = LocalFactCommands(repository: repository)
    let task = try LifeOSDomain.Task(id: .new(), title: "Example", revision: Revision())
    try await commands.createTask(task)
    await #expect(throws: ApplicationError.duplicateIdentity) { try await commands.createTask(task) }
    try await commands.changeTask(task.id, baseRevision: Revision(), to: .completed)
    let result = await repository.snapshot()
    #expect(result.tasks[task.id]?.state == .completed)
}

@Test func calendarCapabilityIsDisabledAndWriteOnlyCannotReconcile() async {
    let adapter = DisabledCalendarAdapter()
    let access = await adapter.access()
    #expect(access == .unavailable)
    #expect(!CalendarAccess.writeOnly.canReadForReconciliation)
    #expect(CalendarAccess.fullAccess.canReadForReconciliation)
}
