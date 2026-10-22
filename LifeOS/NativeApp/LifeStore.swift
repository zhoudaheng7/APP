import Foundation
import CoreData
import Observation
import LifeOSDomain

@MainActor @Observable final class LifeStore {
    private(set) var data = LifeSnapshot()
    private(set) var ready = false
    var error: String?
    private let container: NSPersistentContainer
    private var row: NSManagedObject?

    init(directory: URL? = nil, inMemory: Bool = false) {
        let entity = NSEntityDescription(); entity.name = "LifeOSSnapshot"; entity.managedObjectClassName = "NSManagedObject"
        let key = NSAttributeDescription(); key.name = "key"; key.attributeType = .stringAttributeType; key.isOptional = false
        let payload = NSAttributeDescription(); payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
        entity.properties = [key, payload]; entity.uniquenessConstraints = [["key"]]
        let model = NSManagedObjectModel(); model.entities = [entity]; model.versionIdentifiers = ["LifeOSLocalV1"]
        container = NSPersistentContainer(name: "LifeOSLocalV1", managedObjectModel: model)
        do {
            let parent = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("LifeOS", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let description = NSPersistentStoreDescription(url: inMemory ? URL(fileURLWithPath: "/dev/null") : parent.appendingPathComponent("LifeOS-v1.sqlite"))
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
            description.shouldMigrateStoreAutomatically = true; description.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [description]
            var loadingError: Error?
            container.loadPersistentStores { _, problem in loadingError = problem }
            if let loadingError { throw loadingError }
            container.viewContext.mergePolicy = NSMergePolicy.error
            container.viewContext.undoManager = nil
            let request = NSFetchRequest<NSManagedObject>(entityName: "LifeOSSnapshot"); request.fetchLimit = 2
            let rows = try container.viewContext.fetch(request)
            guard rows.count <= 1 else { throw LifeError.message("发现多个数据快照，已停止写入并保留原件。") }
            row = rows.first
            if let bytes = row?.value(forKey: "payload") as? Data {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
                let loaded = try decoder.decode(LifeSnapshot.self, from: bytes)
                try loaded.validate(); data = loaded
            }
            ready = true
        } catch {
            self.error = "无法打开本机数据。原数据没有被重置。\n" + error.localizedDescription
        }
    }

    @discardableResult func commit(kind: String, id: UUID, _ change: (inout LifeSnapshot) throws -> Void) -> Bool {
        guard ready else { error = "本机数据尚未成功打开，暂时不能保存。"; return false }
        var candidate = data
        do {
            try change(&candidate)
            candidate.pendingChanges.append(LocalChange(kind: kind, entityID: id))
            try candidate.validate()
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(candidate)
            guard bytes.count < 128 * 1024 * 1024 else { throw LifeError.message("本机数据达到首版保存上限，请先导出备份。") }
            let object = row ?? NSEntityDescription.insertNewObject(forEntityName: "LifeOSSnapshot", into: container.viewContext)
            object.setValue("current", forKey: "key"); object.setValue(bytes, forKey: "payload")
            try container.viewContext.save()
            row = object; data = candidate
            return true
        } catch {
            container.viewContext.rollback()
            self.error = error.localizedDescription
            return false
        }
    }

    var runningSession: LifeSession? { data.sessions.first { $0.end == nil } }
    var runningRoute: LifeRoute? { data.routes.first { $0.end == nil } }
    func addTask(title: String, note: String, goalID: UUID?) -> Bool {
        let task = LifeTask(title: title.trimmingCharacters(in: .whitespacesAndNewlines), note: note, goalID: goalID)
        return commit(kind: "task.create", id: task.id) { $0.tasks.insert(task, at: 0) }
    }
    func completeTask(_ task: LifeTask) {
        guard task.completedAt == nil else { return }
        _ = commit(kind: "task.complete", id: task.id) { state in
            guard let i = state.tasks.firstIndex(where: { $0.id == task.id }), state.tasks[i].revision == task.revision else { throw LifeError.message("任务已变化，请重试。") }
            var domain = try LifeOSDomain.Task(id: TaskID(task.id), title: task.title, revision: Revision(task.revision))
            try domain.transition(to: .completed)
            state.tasks[i].completedAt = Date(); state.tasks[i].revision = domain.revision.value
        }
    }
    func startSession(title: String, taskID: UUID? = nil) -> Bool {
        guard runningSession == nil else { error = "请先结束当前计时。"; return false }
        let session = LifeSession(title: title.trimmingCharacters(in: .whitespacesAndNewlines), taskID: taskID)
        guard !session.title.isEmpty else { error = "给这段时间起个名字。"; return false }
        return commit(kind: "actual.start", id: session.id) { $0.sessions.insert(session, at: 0) }
    }
    func stopSession(at end: Date = Date()) {
        guard let session = runningSession else { return }
        _ = commit(kind: "actual.stop", id: session.id) { state in
            guard let i = state.sessions.firstIndex(where: { $0.id == session.id }) else { throw LifeError.invalidReference }
            let stop = max(end, session.start.addingTimeInterval(0.001))
            _ = try TimeRange(start: session.start, end: stop)
            state.sessions[i].end = stop; state.sessions[i].revision += 1
        }
    }
    func confirmSession(_ session: LifeSession) {
        guard session.end != nil && !session.confirmed else { return }
        _ = commit(kind: "actual.confirm", id: session.id) { state in
            guard let i = state.sessions.firstIndex(where: { $0.id == session.id }) else { throw LifeError.invalidReference }
            state.sessions[i].confirmed = true; state.sessions[i].revision += 1
        }
    }
    func addPlan(_ plan: LifePlan) -> Bool { commit(kind: plan.isCommitment ? "commitment.create" : "plan.create", id: plan.id) { $0.plans.append(plan) } }
    func cancelPlan(_ plan: LifePlan) {
        _ = commit(kind: "plan.cancel", id: plan.id) { state in
            if let i = state.plans.firstIndex(where: { $0.id == plan.id }) { state.plans[i].cancelled = true; state.plans[i].revision += 1 }
        }
    }
    func addGoal(_ goal: LifeGoal) -> Bool { commit(kind: "goal.create", id: goal.id) { $0.goals.append(goal) } }
    func addMeasurement(_ measurement: LifeMeasurement) -> Bool { commit(kind: "measurement.create", id: measurement.id) { $0.measurements.append(measurement) } }
    func addReview(_ review: LifeReview) -> Bool {
        commit(kind: "review.create", id: review.id) { state in
            guard !state.reviews.contains(where: { $0.day == review.day && $0.timeZone == review.timeZone }) else { throw LifeError.message("这一天已保存复盘。") }
            state.reviews.insert(review, at: 0)
        }
    }
    func addPlace(_ place: LifePlace) -> Bool { commit(kind: "place.manual", id: place.id) { $0.places.insert(place, at: 0) } }
    func deletePlace(_ place: LifePlace) { _ = commit(kind: "place.delete", id: place.id) { $0.places.removeAll { $0.id == place.id } } }
    func startRoute() -> Bool {
        guard runningRoute == nil else { return false }
        let route = LifeRoute(title: "散步与沿途")
        return commit(kind: "route.start", id: route.id) { $0.routes.insert(route, at: 0) }
    }
    func appendRoutePoint(_ point: RoutePoint) {
        guard let route = runningRoute else { return }
        guard route.points.count < 20_000 else { stopRoute(); error = "这段路线已达记录上限，已保存并结束。"; return }
        _ = commit(kind: "route.point", id: route.id) { state in
            guard let i = state.routes.firstIndex(where: { $0.id == route.id }) else { throw LifeError.invalidReference }
            state.routes[i].points.append(point)
        }
    }
    func stopRoute() {
        guard let route = runningRoute else { return }
        _ = commit(kind: "route.stop", id: route.id) { state in
            if let i = state.routes.firstIndex(where: { $0.id == route.id }) { state.routes[i].end = Date() }
        }
    }
    func exportBackup() -> URL? {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LifeOS-backup.json")
            try encoder.encode(data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        } catch { self.error = error.localizedDescription; return nil }
    }
}
