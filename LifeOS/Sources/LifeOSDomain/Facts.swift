import Foundation

public struct TimeRange: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) throws {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end > start else { throw DomainError.invalidTimeRange }
        self.start = start
        self.end = end
    }
}

public struct AttributionTimeZone: Equatable, Sendable {
    public let identifier: String
    public init(_ identifier: String) throws {
        guard TimeZone.knownTimeZoneIdentifiers.contains(identifier) || identifier == "UTC" else {
            throw DomainError.invalidTimeZone
        }
        self.identifier = identifier
    }
}

public struct Task: Equatable, Sendable {
    public let id: TaskID
    public let title: String
    public private(set) var revision: Revision
    public private(set) var state: TaskState

    public init(id: TaskID, title: String, revision: Revision, state: TaskState = .open) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DomainError.emptyTitle }
        self.id = id; self.title = title; self.revision = revision; self.state = state
    }

    public mutating func transition(to next: TaskState) throws {
        try Lifecycle.require(state, next, in: Lifecycle.task)
        let newRevision = try revision.next()
        state = next; revision = newRevision
    }
}

/// A private plan never contains an EventKit identifier or exports itself.
public struct DraftPlan: Equatable, Sendable {
    public let id: DraftPlanID
    public let taskID: TaskID?
    public let time: TimeRange
    public let attributionTimeZone: AttributionTimeZone
    public private(set) var revision: Revision
    public private(set) var state: DraftPlanState

    public init(id: DraftPlanID, taskID: TaskID?, time: TimeRange,
                attributionTimeZone: AttributionTimeZone, revision: Revision,
                state: DraftPlanState = .active) {
        self.id = id; self.taskID = taskID; self.time = time
        self.attributionTimeZone = attributionTimeZone; self.revision = revision; self.state = state
    }

    public mutating func transition(to next: DraftPlanState) throws {
        try Lifecycle.require(state, next, in: Lifecycle.draftPlan)
        let newRevision = try revision.next()
        state = next; revision = newRevision
    }
}

/// A LifeOS fact. Presence here does not mean an Apple Calendar event exists.
public struct CalendarCommitment: Equatable, Sendable {
    public let id: CalendarCommitmentID
    public let title: String
    public let time: TimeRange
    public let attributionTimeZone: AttributionTimeZone
    public private(set) var revision: Revision
    public private(set) var state: CalendarCommitmentState

    public init(id: CalendarCommitmentID, title: String, time: TimeRange,
                attributionTimeZone: AttributionTimeZone, revision: Revision,
                state: CalendarCommitmentState = .active) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DomainError.emptyTitle }
        self.id = id; self.title = title; self.time = time
        self.attributionTimeZone = attributionTimeZone; self.revision = revision; self.state = state
    }

    public mutating func transition(to next: CalendarCommitmentState) throws {
        try Lifecycle.require(state, next, in: Lifecycle.calendarCommitment)
        let newRevision = try revision.next()
        state = next; revision = newRevision
    }
}

public struct ActualSession: Equatable, Sendable {
    public let id: ActualSessionID
    public let taskID: TaskID?
    public let primaryDraftPlanID: DraftPlanID?
    public let startedAt: Date
    public let attributionTimeZone: AttributionTimeZone
    public private(set) var endedAt: Date?
    public private(set) var revision: Revision
    public private(set) var factState: FactState
    // Derivation makes a running session with a stop timestamp unrepresentable.
    public var runState: RunState { endedAt == nil ? .running : .stopped }

    public init(id: ActualSessionID, taskID: TaskID?, primaryDraftPlanID: DraftPlanID?,
                startedAt: Date, endedAt: Date? = nil, attributionTimeZone: AttributionTimeZone,
                revision: Revision, factState: FactState = .inferred) throws {
        guard startedAt.timeIntervalSince1970.isFinite else { throw DomainError.invalidTimeRange }
        if let endedAt { _ = try TimeRange(start: startedAt, end: endedAt) }
        self.id = id; self.taskID = taskID; self.primaryDraftPlanID = primaryDraftPlanID
        self.startedAt = startedAt; self.endedAt = endedAt; self.attributionTimeZone = attributionTimeZone
        self.revision = revision; self.factState = factState
    }

    /// Stopping does not confirm a fact, complete a Task, or modify a DraftPlan.
    public mutating func stop(at end: Date) throws {
        try Lifecycle.require(runState, .stopped, in: Lifecycle.run)
        _ = try TimeRange(start: startedAt, end: end)
        let newRevision = try revision.next()
        endedAt = end; revision = newRevision
    }

    /// Fact confidence and run state are independent axes.
    public mutating func classify(as next: FactState) throws {
        try Lifecycle.require(factState, next, in: Lifecycle.fact)
        let newRevision = try revision.next()
        factState = next; revision = newRevision
    }
}

/// Internal calendar day, not a definition of the wire dayKey encoding.
public struct ReviewDay: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let zone = TimeZone(secondsFromGMT: 0) else { throw DomainError.invalidReviewDay }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components) else { throw DomainError.invalidReviewDay }
        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year, normalized.month == month, normalized.day == day else {
            throw DomainError.invalidReviewDay
        }
        self.year = year; self.month = month; self.day = day
    }
}

public struct DailyReview: Equatable, Sendable {
    public let id: DailyReviewID
    public let day: ReviewDay
    public let attributionTimeZone: AttributionTimeZone
    public let revision: Revision
    public let reflection: String
    public init(id: DailyReviewID, day: ReviewDay, attributionTimeZone: AttributionTimeZone,
                revision: Revision, reflection: String) {
        self.id = id; self.day = day; self.attributionTimeZone = attributionTimeZone
        self.revision = revision; self.reflection = reflection
    }
}
