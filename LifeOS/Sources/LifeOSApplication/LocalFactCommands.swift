import Foundation
import LifeOSDomain

/// Future native LifeOS command entry point. Not wired to a UI, wire intents, or Slice 1.
/// It has no Calendar/file/network dependency and cannot dispatch an external side effect.
public struct LocalFactCommands<Repository: FactRepository>: Sendable {
    private let repository: Repository
    public init(repository: Repository) { self.repository = repository }

    public func createTask(_ task: LifeOSDomain.Task) async throws {
        try await repository.transaction { state in
            try Self.requireInitialRevision(task.revision)
            guard state.tasks[task.id] == nil else { throw ApplicationError.duplicateIdentity }
            state.tasks[task.id] = task
        }
    }

    public func createDraftPlan(_ plan: DraftPlan) async throws {
        try await repository.transaction { state in
            try Self.requireInitialRevision(plan.revision)
            guard state.draftPlans[plan.id] == nil else { throw ApplicationError.duplicateIdentity }
            if let taskID = plan.taskID, state.tasks[taskID] == nil { throw ApplicationError.notFound }
            state.draftPlans[plan.id] = plan
        }
    }

    public func createCalendarCommitment(_ commitment: CalendarCommitment) async throws {
        try await repository.transaction { state in
            try Self.requireInitialRevision(commitment.revision)
            guard state.calendarCommitments[commitment.id] == nil else { throw ApplicationError.duplicateIdentity }
            state.calendarCommitments[commitment.id] = commitment
        }
    }

    public func recordActualSession(_ session: ActualSession) async throws {
        try await repository.transaction { state in
            try Self.requireInitialRevision(session.revision)
            guard state.actualSessions[session.id] == nil else { throw ApplicationError.duplicateIdentity }
            if let taskID = session.taskID, state.tasks[taskID] == nil { throw ApplicationError.notFound }
            if let planID = session.primaryDraftPlanID, state.draftPlans[planID] == nil { throw ApplicationError.notFound }
            state.actualSessions[session.id] = session
        }
    }

    public func changeTask(_ id: TaskID, baseRevision: Revision, to next: TaskState) async throws {
        try await repository.transaction { state in
            guard var task = state.tasks[id] else { throw ApplicationError.notFound }
            guard task.revision == baseRevision else { throw ApplicationError.revisionConflict }
            try task.transition(to: next)
            state.tasks[id] = task
        }
    }

    public func stopActualSession(_ id: ActualSessionID, baseRevision: Revision, at end: Date) async throws {
        try await repository.transaction { state in
            guard var session = state.actualSessions[id] else { throw ApplicationError.notFound }
            guard session.revision == baseRevision else { throw ApplicationError.revisionConflict }
            try session.stop(at: end)
            state.actualSessions[id] = session
        }
    }

    public func classifyActualSession(_ id: ActualSessionID, baseRevision: Revision, as next: FactState) async throws {
        try await repository.transaction { state in
            guard var session = state.actualSessions[id] else { throw ApplicationError.notFound }
            guard session.revision == baseRevision else { throw ApplicationError.revisionConflict }
            try session.classify(as: next)
            state.actualSessions[id] = session
        }
    }

    /// Local-only seam. This is deliberately not the Slice 4 DailyReviewDraft intent handler.
    public func createCanonicalDailyReview(_ review: DailyReview) async throws {
        try await repository.transaction { state in
            try Self.requireInitialRevision(review.revision)
            guard state.dailyReviews[review.id] == nil else { throw ApplicationError.duplicateIdentity }
            guard !state.dailyReviews.values.contains(where: { $0.day == review.day }) else {
                throw ApplicationError.canonicalReviewExists
            }
            state.dailyReviews[review.id] = review
        }
    }

    private static func requireInitialRevision(_ revision: Revision) throws {
        guard revision.value == 1 else { throw ApplicationError.initialRevisionMustBeOne }
    }
}
