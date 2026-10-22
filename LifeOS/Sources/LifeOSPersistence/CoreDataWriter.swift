#if canImport(CoreData)
import CoreData

public enum WriterError: Error, Equatable, Sendable {
    case requiresOneLoadedSQLiteStore
    case dirtyWriterContext
}

/// Transaction primitive only; not a FactRepository implementation or a production store model.
/// All context access is confined to perform; only Sendable results leave the queue.
/// unchecked Sendable is limited to this queue-confined adapter. Callers must not retain the context.
public final class CoreDataWriter: @unchecked Sendable {
    private let context: NSManagedObjectContext

    /// The composition root must finish loading exactly one local SQLite store before construction.
    /// This writer owns its context; do not share it with a view or another command dispatcher.
    public init(container: NSPersistentContainer) throws {
        let stores = container.persistentStoreCoordinator.persistentStores
        guard stores.count == 1, stores[0].type == NSSQLiteStoreType else {
            throw WriterError.requiresOneLoadedSQLiteStore
        }
        let writer = container.newBackgroundContext()
        writer.performAndWait {
            writer.mergePolicy = NSMergePolicy.error
            writer.undoManager = nil
            writer.automaticallyMergesChangesFromParent = false
        }
        self.context = writer
    }

    /// Mapping, invariant/revision checks, facts, and local outbox insertion belong in this closure.
    /// It must be synchronous and may not perform EventKit, file, or network operations.
    /// It must not call save itself. The writer is the sole owner of save/rollback.
    public func commit<Result: Sendable>(
        _ mutation: @escaping @Sendable (NSManagedObjectContext) throws -> Result
    ) async throws -> Result {
        try await context.perform(schedule: .enqueued) {
            guard !self.context.hasChanges else {
                self.context.rollback()
                self.context.reset()
                throw WriterError.dirtyWriterContext
            }
            do {
                let result = try mutation(self.context)
                try self.context.save()
                return result
            } catch {
                self.context.rollback()
                self.context.reset()
                throw error
            }
        }
    }
}
#endif
