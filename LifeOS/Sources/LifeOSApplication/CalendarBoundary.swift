import LifeOSDomain

/// Authorization is adapter metadata, never a LifeOS fact or permission to perform a command.
public enum CalendarAccess: Equatable, Sendable {
    case notDetermined, restricted, denied, writeOnly, fullAccess, unavailable
    public var canReadForReconciliation: Bool { self == .fullAccess }
}

/// No write or permission-request method is exposed in this delivery.
/// An enabled adapter and explicit export command require a later implementation milestone.
public protocol CalendarCapability: Sendable {
    func access() async -> CalendarAccess
}

public struct DisabledCalendarAdapter: CalendarCapability, Sendable {
    public init() {}
    public func access() async -> CalendarAccess { .unavailable }
}
