import Foundation
import LifeOSDomain

struct LifeTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var note = ""
    var goalID: UUID?
    var createdAt = Date()
    var completedAt: Date?
    var revision: Int64 = 1
    var dueAt: Date?
    var priority: Int?
    var archivedAt: Date?
    var deletedAt: Date?
    var cancelledAt: Date?
    var placeID: UUID?
    var isOpen: Bool { completedAt == nil && archivedAt == nil && deletedAt == nil && cancelledAt == nil }
}

struct LifePlan: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var taskID: UUID?
    var start: Date
    var end: Date
    var timeZone = TimeZone.current.identifier
    var isCommitment = false
    var cancelled = false
    var revision: Int64 = 1
    var note: String?
    var placeID: UUID?
    var seriesID: UUID?
    var reminderMinutes: Int?
    var deletedAt: Date?
    var allDay: Bool?
}

struct LifeSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var taskID: UUID?
    var start = Date()
    var end: Date?
    var confirmed = false
    var timeZone = TimeZone.current.identifier
    var revision: Int64 = 1
    var note: String?
    var placeID: UUID?
    var tripID: UUID?
    var deletedAt: Date?
}

struct LifeGoal: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var intention: String
    var target: Double
    var unit: String
    var due: Date
    var archived = false
    var cycleStart: Date?
    var assessment: String?
    var revision: Int64?
}

struct LifeMeasurement: Codable, Identifiable, Equatable {
    var id = UUID()
    var goalID: UUID
    var value: Double
    var note: String
    var recordedAt = Date()
    var keyResultID: UUID?
    var observedAt: Date?
    var rejectedAt: Date?
    var effectiveAt: Date { observedAt ?? recordedAt }
}

struct LifeReview: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: String
    var timeZone = TimeZone.current.identifier
    var reflection: String
    var mood: Int?
    var createdAt = Date()
    var revision: Int64?
    var people: [String]?
    var canonical: Bool?
    var sourceOperationID: UUID?
}

struct LifePlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var note: String
    var latitude: Double
    var longitude: Double
    var occurredAt = Date()
    var knownPlaceID: UUID?
    var visitID: UUID?
    var tripID: UUID?
    var favorite: Bool?
    var people: [String]?
}

struct RoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var at = Date()
    var segment = 0
    var accuracy: Double?
}

struct LifeRoute: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start = Date()
    var end: Date?
    var points: [RoutePoint] = []
    var note: String?
    var transport: String?
    var tripID: UUID?
    var backgroundEnabled: Bool?
    var gaps: [RouteGap]?
}

/// Internal durable pending-change journal. Not an exchange generation or wire DTO.
struct LocalChange: Codable, Identifiable {
    var id = UUID()
    var at = Date()
    var kind: String
    var entityID: UUID
}

struct LifeSnapshot: Codable {
    var schemaVersion = 2
    var tasks: [LifeTask] = []
    var plans: [LifePlan] = []
    var sessions: [LifeSession] = []
    var goals: [LifeGoal] = []
    var measurements: [LifeMeasurement] = []
    var reviews: [LifeReview] = []
    var places: [LifePlace] = []
    var routes: [LifeRoute] = []
    var pendingChanges: [LocalChange] = []
    var keyResults: [LifeKeyResult] = []
    var knownPlaces: [KnownPlace] = []
    var visits: [LifeVisit] = []
    var trips: [LifeTrip] = []
    var photos: [LifePhoto] = []
    var periodReviews: [PeriodReview] = []
    var amendments: [LifeAmendment] = []
    var tombstones: [LocalTombstone] = []
    var calendarLinks: [CalendarLink] = []
    var collectionWindows: [CollectionWindow] = []
    var disclosure: DisclosureSettings = .init()
    var vaultOperations: [VaultOperation] = []

    init() {}
    enum CodingKeys: String, CodingKey {
        case schemaVersion, tasks, plans, sessions, goals, measurements, reviews, places, routes, pendingChanges
        case keyResults, knownPlaces, visits, trips, photos, periodReviews, amendments, tombstones, calendarLinks, collectionWindows, disclosure, vaultOperations
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard (1...2).contains(version) else { throw LifeError.message("此备份来自更新版本，请先更新朝屿。") }
        tasks = try c.decode([LifeTask].self, forKey: .tasks)
        plans = try c.decode([LifePlan].self, forKey: .plans)
        sessions = try c.decode([LifeSession].self, forKey: .sessions)
        goals = try c.decode([LifeGoal].self, forKey: .goals)
        measurements = try c.decode([LifeMeasurement].self, forKey: .measurements)
        reviews = try c.decode([LifeReview].self, forKey: .reviews)
        places = try c.decode([LifePlace].self, forKey: .places)
        routes = try c.decode([LifeRoute].self, forKey: .routes)
        pendingChanges = try c.decode([LocalChange].self, forKey: .pendingChanges)
        keyResults = try c.decodeIfPresent([LifeKeyResult].self, forKey: .keyResults) ?? []
        knownPlaces = try c.decodeIfPresent([KnownPlace].self, forKey: .knownPlaces) ?? []
        visits = try c.decodeIfPresent([LifeVisit].self, forKey: .visits) ?? []
        trips = try c.decodeIfPresent([LifeTrip].self, forKey: .trips) ?? []
        photos = try c.decodeIfPresent([LifePhoto].self, forKey: .photos) ?? []
        periodReviews = try c.decodeIfPresent([PeriodReview].self, forKey: .periodReviews) ?? []
        amendments = try c.decodeIfPresent([LifeAmendment].self, forKey: .amendments) ?? []
        tombstones = try c.decodeIfPresent([LocalTombstone].self, forKey: .tombstones) ?? []
        calendarLinks = try c.decodeIfPresent([CalendarLink].self, forKey: .calendarLinks) ?? []
        collectionWindows = try c.decodeIfPresent([CollectionWindow].self, forKey: .collectionWindows) ?? []
        disclosure = try c.decodeIfPresent(DisclosureSettings.self, forKey: .disclosure) ?? .init()
        vaultOperations = try c.decodeIfPresent([VaultOperation].self, forKey: .vaultOperations) ?? []
        if version == 1 {
            // Deterministic, identity-preserving migration of the original one-metric goal.
            keyResults = goals.map { LifeKeyResult(id: $0.id, objectiveID: $0.id, title: $0.title, baseline: 0, target: $0.target, unit: $0.unit) }
            for i in measurements.indices { measurements[i].keyResultID = measurements[i].goalID }
            var days = Set<String>()
            for index in reviews.indices.sorted(by: { reviews[$0].createdAt < reviews[$1].createdAt }) {
                reviews[index].canonical = days.insert(reviews[index].day).inserted
            }
        }
        schemaVersion = 2
    }

    func validate() throws {
        guard schemaVersion == 2 else { throw LifeError.message("数据来自更新版本，请先更新朝屿。") }
        let groups = [tasks.map(\.id), plans.map(\.id), sessions.map(\.id), goals.map(\.id),
                      measurements.map(\.id), reviews.map(\.id), places.map(\.id), routes.map(\.id), keyResults.map(\.id), knownPlaces.map(\.id), visits.map(\.id), trips.map(\.id), photos.map(\.id), periodReviews.map(\.id)]
        guard groups.allSatisfy({ Set($0).count == $0.count }),
              sessions.filter({ $0.end == nil }).count <= 1,
              routes.filter({ $0.end == nil }).count <= 1,
              Set(reviews.filter { $0.canonical != false }.map(\.day)).count == reviews.filter({ $0.canonical != false }).count else {
            throw LifeError.message("数据一致性检查未通过，原数据已保留。")
        }
        for task in tasks {
            _ = try LifeOSDomain.Task(id: TaskID(task.id), title: task.title, revision: Revision(task.revision),
                                      state: task.completedAt == nil ? .open : .completed)
            guard task.goalID == nil || goals.contains(where: { $0.id == task.goalID }) else { throw LifeError.invalidReference }
        }
        for plan in plans {
            _ = try TimeRange(start: plan.start, end: plan.end)
            _ = try AttributionTimeZone(plan.timeZone)
            guard !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  plan.taskID == nil || tasks.contains(where: { $0.id == plan.taskID }) else { throw LifeError.invalidReference }
        }
        for session in sessions {
            _ = try ActualSession(id: ActualSessionID(session.id), taskID: session.taskID.map(TaskID.init),
                                  primaryDraftPlanID: nil, startedAt: session.start, endedAt: session.end,
                                  attributionTimeZone: AttributionTimeZone(session.timeZone),
                                  revision: Revision(session.revision), factState: session.confirmed ? .confirmed : .inferred)
            guard session.taskID == nil || tasks.contains(where: { $0.id == session.taskID }) else { throw LifeError.invalidReference }
        }
        guard goals.allSatisfy({ !$0.title.isEmpty && $0.target.isFinite && $0.target > 0 }),
              measurements.allSatisfy({ m in m.value.isFinite && goals.contains(where: { $0.id == m.goalID }) }),
              reviews.allSatisfy({ $0.mood == nil || (1...5).contains($0.mood!) }),
              places.allSatisfy({ (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) && !$0.title.isEmpty }),
              routes.allSatisfy({ $0.end == nil || $0.end! >= $0.start }) else { throw LifeError.invalidValue }
        for route in routes {
            guard route.points.count <= 20_000, route.points.allSatisfy({ (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }) else { throw LifeError.invalidValue }
        }
        try validateV2()
    }

    static func dayKey(_ date: Date, zone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let p = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
}

enum LifeError: LocalizedError {
    case message(String), invalidReference, invalidValue
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .invalidReference: return "关联记录不存在，操作未保存。"
        case .invalidValue: return "请检查时间、数值和位置后重试。"
        }
    }
}
