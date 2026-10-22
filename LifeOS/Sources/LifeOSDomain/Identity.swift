import Foundation

/// Internal identity only. Wire encoding belongs to the separately versioned protocol adapter.
public struct EntityID<Kind: Sendable>: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) { self.rawValue = rawValue }
    public static func new() -> Self { Self(UUID()) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

public enum TaskKind: Sendable {}
public enum DraftPlanKind: Sendable {}
public enum CalendarCommitmentKind: Sendable {}
public enum ActualSessionKind: Sendable {}
public enum DailyReviewKind: Sendable {}

public typealias TaskID = EntityID<TaskKind>
public typealias DraftPlanID = EntityID<DraftPlanKind>
public typealias CalendarCommitmentID = EntityID<CalendarCommitmentKind>
public typealias ActualSessionID = EntityID<ActualSessionKind>
public typealias DailyReviewID = EntityID<DailyReviewKind>

public struct Revision: Equatable, Sendable {
    public let value: Int64
    public init(_ value: Int64 = 1) throws {
        guard value > 0 else { throw DomainError.invalidRevision }
        self.value = value
    }
    public func next() throws -> Self {
        guard value < Int64.max else { throw DomainError.revisionOverflow }
        return try Self(value + 1)
    }
}

public enum DomainError: Error, Equatable, Sendable {
    case invalidRevision, revisionOverflow, invalidTransition
    case invalidTimeRange, invalidTimeZone, invalidReviewDay, emptyTitle
}
