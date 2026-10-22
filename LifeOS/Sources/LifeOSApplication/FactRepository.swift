import LifeOSDomain

public enum ApplicationError: Error, Equatable, Sendable {
    case notFound, duplicateIdentity, revisionConflict, canonicalReviewExists
    case initialRevisionMustBeOne
}

/// A transaction working set, not a persisted model or an exchange generation.
/// A production mapper must validate dataset-scoped identities and uniqueness before committing.
public struct FactSnapshot: Equatable, Sendable {
    public var tasks: [TaskID: LifeOSDomain.Task] = [:]
    public var draftPlans: [DraftPlanID: DraftPlan] = [:]
    public var calendarCommitments: [CalendarCommitmentID: CalendarCommitment] = [:]
    public var actualSessions: [ActualSessionID: ActualSession] = [:]
    public var dailyReviews: [DailyReviewID: DailyReview] = [:]
    public init() {}
}

/// Implementations serialize commands; mutation cannot suspend or call external adapters.
/// Success means an explicit durable save. Any failure discards every change from this command.
/// In-memory implementations are test doubles and make no durability claim.
public protocol FactRepository: Sendable {
    func transaction<Result: Sendable>(
        _ mutation: @escaping @Sendable (inout FactSnapshot) throws -> Result
    ) async throws -> Result
}
