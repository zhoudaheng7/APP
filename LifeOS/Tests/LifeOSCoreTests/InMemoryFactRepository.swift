import LifeOSApplication

enum InjectedFailure: Error, Equatable { case save }

/// Copy-on-write transaction test double. No SQLite/Core Data durability claim.
actor InMemoryFactRepository: FactRepository {
    private var committed = FactSnapshot()
    private var failNextSave = false
    private(set) var saves = 0

    func injectSaveFailure() { failNextSave = true }
    func snapshot() -> FactSnapshot { committed }

    func transaction<Result: Sendable>(
        _ mutation: @escaping @Sendable (inout FactSnapshot) throws -> Result
    ) async throws -> Result {
        var candidate = committed
        let result = try mutation(&candidate)
        if failNextSave {
            failNextSave = false
            throw InjectedFailure.save
        }
        committed = candidate
        saves += 1
        return result
    }
}
