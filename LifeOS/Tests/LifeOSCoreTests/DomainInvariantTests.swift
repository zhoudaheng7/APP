import Foundation
import Testing
import LifeOSDomain

private let fixedUUID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

@Test func taskTransitionMatrix() throws {
    let allowed: Set<Transition<TaskState>> = [
        Transition(.open, .completed), Transition(.open, .cancelled),
        Transition(.completed, .archived), Transition(.cancelled, .archived),
    ]
    for from in TaskState.allCases {
        for to in TaskState.allCases {
            var task = try LifeOSDomain.Task(id: TaskID(fixedUUID), title: "Example", revision: Revision(), state: from)
            let original = task
            if allowed.contains(Transition(from, to)) {
                try task.transition(to: to)
                #expect(task.id == original.id)
                #expect(task.revision.value == 2)
                #expect(task.state == to)
            } else {
                #expect(throws: DomainError.invalidTransition) { try task.transition(to: to) }
                #expect(task == original)
            }
        }
    }
}

@Test func planAndCommitmentTransitionMatrices() throws {
    let time = try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60))
    let zone = try AttributionTimeZone("UTC")
    let planAllowed: Set<Transition<DraftPlanState>> = [
        Transition(.active, .cancelled), Transition(.active, .archived), Transition(.cancelled, .archived),
    ]
    for from in DraftPlanState.allCases {
        for to in DraftPlanState.allCases {
            var plan = DraftPlan(id: DraftPlanID(fixedUUID), taskID: nil, time: time,
                                 attributionTimeZone: zone, revision: try Revision(), state: from)
            let original = plan
            if planAllowed.contains(Transition(from, to)) {
                try plan.transition(to: to)
                #expect(plan.id == original.id && plan.revision.value == 2 && plan.state == to)
            } else {
                #expect(throws: DomainError.invalidTransition) { try plan.transition(to: to) }
                #expect(plan == original)
            }
        }
    }
    for from in CalendarCommitmentState.allCases {
        for to in CalendarCommitmentState.allCases {
            var item = try CalendarCommitment(id: CalendarCommitmentID(fixedUUID), title: "Appointment",
                time: time, attributionTimeZone: zone, revision: Revision(), state: from)
            let original = item
            if from == .active && to == .cancelled {
                try item.transition(to: to)
                #expect(item.id == original.id && item.revision.value == 2 && item.state == to)
            } else {
                #expect(throws: DomainError.invalidTransition) { try item.transition(to: to) }
                #expect(item == original)
            }
        }
    }
}

@Test func sessionAxesAreIndependent() throws {
    for from in FactState.allCases {
        for to in FactState.allCases {
            for runState in RunState.allCases {
                var session = try makeSession(endedAt: runState == .stopped ? Date(timeIntervalSince1970: 60) : nil,
                                              factState: from)
                let original = session
                if from == .inferred && (to == .confirmed || to == .rejected) {
                    try session.classify(as: to)
                    #expect(session.factState == to && session.revision.value == 2)
                    #expect(session.runState == original.runState)
                    #expect(session.startedAt == original.startedAt && session.endedAt == original.endedAt)
                    #expect(session.id == original.id)
                } else {
                    #expect(throws: DomainError.invalidTransition) { try session.classify(as: to) }
                    #expect(session == original)
                }
            }
        }
    }
}

@Test func stoppingPreservesConfidenceAndIdentity() throws {
    for fact in FactState.allCases {
        var session = try makeSession(factState: fact)
        let original = session
        try session.stop(at: Date(timeIntervalSince1970: 60))
        #expect(session.id == original.id && session.factState == fact)
        #expect(session.runState == .stopped && session.revision.value == 2)
        let stopped = session
        #expect(throws: DomainError.invalidTransition) { try session.stop(at: Date(timeIntervalSince1970: 120)) }
        #expect(session == stopped)
    }
}

@Test func invalidTimesAndRevisionOverflowAreAtomic() throws {
    var session = try makeSession()
    let original = session
    for end in [Date(timeIntervalSince1970: -1), Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: .infinity)] {
        #expect(throws: DomainError.invalidTimeRange) { try session.stop(at: end) }
        #expect(session == original)
    }
    #expect(throws: DomainError.invalidTimeRange) { try makeSession(endedAt: Date(timeIntervalSince1970: -1)) }
    #expect(throws: DomainError.invalidRevision) { try Revision(0) }
    var task = try LifeOSDomain.Task(id: TaskID(fixedUUID), title: "Example", revision: Revision(Int64.max))
    let overflowOriginal = task
    #expect(throws: DomainError.revisionOverflow) { try task.transition(to: .completed) }
    #expect(task == overflowOriginal)
}

@Test func crossMidnightSessionRemainsOneFact() throws {
    // 2026-09-10 23:30 to 2026-09-11 00:30 in Asia/Shanghai.
    let start = Date(timeIntervalSince1970: 1789054200)
    var session = try ActualSession(id: ActualSessionID(fixedUUID), taskID: nil, primaryDraftPlanID: nil,
        startedAt: start, attributionTimeZone: AttributionTimeZone("Asia/Shanghai"), revision: Revision())
    try session.stop(at: start.addingTimeInterval(3600))
    #expect(session.id.rawValue == fixedUUID)
    #expect(session.endedAt?.timeIntervalSince(session.startedAt) == 3600)
    #expect(session.attributionTimeZone.identifier == "Asia/Shanghai")
    // Display segmentation is intentionally absent; it must never replace this UUID.
}

@Test func calendarDaysAndZonesAreValidated() throws {
    _ = try ReviewDay(year: 2024, month: 2, day: 29)
    #expect(throws: DomainError.invalidReviewDay) { try ReviewDay(year: 2025, month: 2, day: 29) }
    #expect(throws: DomainError.invalidReviewDay) { try ReviewDay(year: 2026, month: 13, day: 1) }
    #expect(throws: DomainError.invalidTimeZone) { try AttributionTimeZone("Not/AZone") }
}

private func makeSession(endedAt: Date? = nil, factState: FactState = .inferred) throws -> ActualSession {
    try ActualSession(id: ActualSessionID(fixedUUID), taskID: nil, primaryDraftPlanID: nil,
        startedAt: Date(timeIntervalSince1970: 0), endedAt: endedAt,
        attributionTimeZone: AttributionTimeZone("UTC"), revision: Revision(), factState: factState)
}
