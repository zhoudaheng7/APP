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
}

struct LifeGoal: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var intention: String
    var target: Double
    var unit: String
    var due: Date
    var archived = false
}

struct LifeMeasurement: Codable, Identifiable, Equatable {
    var id = UUID()
    var goalID: UUID
    var value: Double
    var note: String
    var recordedAt = Date()
}

struct LifeReview: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: String
    var timeZone = TimeZone.current.identifier
    var reflection: String
    var mood: Int
    var createdAt = Date()
}

struct LifePlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var note: String
    var latitude: Double
    var longitude: Double
    var occurredAt = Date()
}

struct RoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var at = Date()
}

struct LifeRoute: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start = Date()
    var end: Date?
    var points: [RoutePoint] = []
}

/// Internal durable pending-change journal. Not an exchange generation or wire DTO.
struct LocalChange: Codable, Identifiable {
    var id = UUID()
    var at = Date()
    var kind: String
    var entityID: UUID
}

struct LifeSnapshot: Codable {
    var schemaVersion = 1
    var tasks: [LifeTask] = []
    var plans: [LifePlan] = []
    var sessions: [LifeSession] = []
    var goals: [LifeGoal] = []
    var measurements: [LifeMeasurement] = []
    var reviews: [LifeReview] = []
    var places: [LifePlace] = []
    var routes: [LifeRoute] = []
    var pendingChanges: [LocalChange] = []

    func validate() throws {
        guard schemaVersion == 1 else { throw LifeError.message("数据来自更新版本，请先更新 LifeOS。") }
        let groups = [tasks.map(\.id), plans.map(\.id), sessions.map(\.id), goals.map(\.id),
                      measurements.map(\.id), reviews.map(\.id), places.map(\.id), routes.map(\.id)]
        guard groups.allSatisfy({ Set($0).count == $0.count }),
              sessions.filter({ $0.end == nil }).count <= 1,
              routes.filter({ $0.end == nil }).count <= 1,
              Set(reviews.map { $0.timeZone + ":" + $0.day }).count == reviews.count else {
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
              measurements.allSatisfy({ m in m.value.isFinite && m.value >= 0 && goals.contains(where: { $0.id == m.goalID }) }),
              reviews.allSatisfy({ (1...5).contains($0.mood) && !$0.reflection.isEmpty }),
              places.allSatisfy({ (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) && !$0.title.isEmpty }),
              routes.allSatisfy({ $0.end == nil || $0.end! >= $0.start }) else { throw LifeError.invalidValue }
        for route in routes {
            guard route.points.count <= 20_000, route.points.allSatisfy({ (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }) else { throw LifeError.invalidValue }
        }
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
