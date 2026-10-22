/// These are internal domain states, not wire enums or receipt states.
public enum TaskState: String, CaseIterable, Sendable { case open, completed, cancelled, archived }
public enum DraftPlanState: String, CaseIterable, Sendable { case active, cancelled, archived }
public enum CalendarCommitmentState: String, CaseIterable, Sendable { case active, cancelled }
public enum RunState: String, CaseIterable, Sendable { case running, stopped }
public enum FactState: String, CaseIterable, Sendable { case inferred, confirmed, rejected }

public struct Transition<State: Hashable & Sendable>: Hashable, Sendable {
    public let from: State
    public let to: State
    public init(_ from: State, _ to: State) { self.from = from; self.to = to }
}

/// Supported command subset. Reopening, restoration, and correction need a separate decision.
/// Literal tables are consumed by Swift and inspected by the Windows validation script.
public enum Lifecycle {
    public static let task: Set<Transition<TaskState>> = [
        Transition(.open, .completed),
        Transition(.open, .cancelled),
        Transition(.completed, .archived),
        Transition(.cancelled, .archived),
    ]
    public static let draftPlan: Set<Transition<DraftPlanState>> = [
        Transition(.active, .cancelled),
        Transition(.active, .archived),
        Transition(.cancelled, .archived),
    ]
    public static let calendarCommitment: Set<Transition<CalendarCommitmentState>> = [
        Transition(.active, .cancelled),
    ]
    public static let run: Set<Transition<RunState>> = [
        Transition(.running, .stopped),
    ]
    public static let fact: Set<Transition<FactState>> = [
        Transition(.inferred, .confirmed),
        Transition(.inferred, .rejected),
    ]

    public static func require<State>(
        _ from: State, _ to: State, in allowed: Set<Transition<State>>
    ) throws where State: Hashable & Sendable {
        guard allowed.contains(Transition(from, to)) else { throw DomainError.invalidTransition }
    }
}
