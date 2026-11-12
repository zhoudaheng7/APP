import Foundation

struct LifeKeyResult: Codable, Identifiable, Equatable {
    var id = UUID()
    var objectiveID: UUID
    var title: String
    var baseline: Double
    var target: Double
    var unit: String
    var weight: Double = 1
    var revision: Int64 = 1
    var archived = false
}
struct KnownPlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var latitude: Double
    var longitude: Double
    var radius: Double = 150
    var city = ""
    var country = ""
    var favorite = false
    var isSensitive = false
    var revision: Int64 = 1
}
struct LifeVisit: Codable, Identifiable, Equatable {
    var id = UUID()
    var observationKey: String
    var source: String
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var arrival: Date?
    var departure: Date?
    var receivedAt = Date()
    var timeZone = TimeZone.current.identifier
    var placeID: UUID?
    var state = "inferred"
    var note = ""
    var revision: Int64 = 1
    var timeZoneSource: String?
}
struct RouteGap: Codable, Equatable {
    var from: Date
    var to: Date?
    var reason: String
}
struct RouteStory: Codable {
    var title: String
    var note: String?
    var transport: String?
    var purpose: String?
    var tripID: UUID?
}
struct LifeTrip: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var note = ""
    var visitIDs: [UUID] = []
    var routeIDs: [UUID] = []
    var memoryIDs: [UUID] = []
    var favorite = false
    var revision: Int64 = 1
    var timeZone: String? = TimeZone.current.identifier
}
struct LifePhoto: Codable, Identifiable, Equatable {
    var id = UUID()
    var caption: String
    var capturedAt: Date
    var memoryID: UUID?
    var tripID: UUID?
    var sha256: String
    var width: Int
    var height: Int
    var bytes: Int
    var metadataRemoved = true
}
struct PeriodReview: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var reflection: String
    var nextStep: String
    var createdAt = Date()
    var revision: Int64 = 1
}
struct LifeAmendment: Codable, Identifiable {
    var id = UUID()
    var entityID: UUID
    var kind: String
    var priorRevision: Int64
    var previous: Data
    var at = Date()
}
struct LocalTombstone: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: String
    var at = Date()
}
struct CalendarLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var planID: UUID
    var eventIdentifier: String
    var calendarIdentifier: String
    var status: String
    var observedAt = Date()
    var sourcePlanID: UUID?
}
struct CollectionWindow: Codable, Identifiable, Equatable {
    var id = UUID()
    var start = Date()
    var end: Date?
    var mode: String
}
struct DisclosureGrant: Codable, Equatable, Identifiable {
    var entityType: String
    var entityID: UUID
    var text = true
    var id: String { entityType + ":" + entityID.wire }
    var wireValue: [String:Any] { ["entityType":entityType,"entityID":entityID.wire,"text":text] }
}
struct DisclosureSettings: Codable, Equatable {
    var enabled = false
    var datasetID = UUID()
    var writerID = UUID()
    var approvedAt: Date?
    var lastSequence: Int64 = 0
    var lastCommitID: String?
    var grants: [DisclosureGrant]?
    var lastPublishedGrants: [DisclosureGrant]?
}
struct LifeBackup: Codable {
    var format = "dayisle-private-backup/v2"
    var snapshot: LifeSnapshot
    var media: [String: Data]
    var exportedAt: Date? = Date()
}
struct VaultOperation: Codable, Identifiable {
    var id: UUID
    var datasetID: UUID
    var clientID: UUID
    var payloadHash: String
    var status: String
    var receipt: Data
    var finalEntityID: UUID?
    var at = Date()
}

extension LifeSnapshot {
    func validateV2() throws {
        func unique(_ values: [UUID]) -> Bool { Set(values).count == values.count }
        func finite(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite && abs(date.timeIntervalSince1970) < 253_402_300_800 }
        guard photos.count <= 1000, photos.allSatisfy({ (1...2_000_000).contains($0.bytes) }), photos.reduce(0, { $0 + $1.bytes }) <= 64 * 1024 * 1024,
              keyResults.allSatisfy({ kr in goals.contains { $0.id == kr.objectiveID } && !kr.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kr.baseline.isFinite && kr.target.isFinite && kr.target != kr.baseline && kr.weight.isFinite && (1...10).contains(kr.weight) && kr.revision > 0 }),
              measurements.allSatisfy({ m in m.keyResultID == nil || keyResults.contains { $0.id == m.keyResultID && $0.objectiveID == m.goalID } }),
              knownPlaces.allSatisfy({ !$0.title.isEmpty && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) && (10...5000).contains($0.radius) }),
              plans.allSatisfy({ plan in plan.placeID == nil || knownPlaces.contains { $0.id == plan.placeID } }),
              visits.allSatisfy({ v in (-90...90).contains(v.latitude) && (-180...180).contains(v.longitude) && v.accuracy.isFinite && v.accuracy >= 0 && ["inferred","confirmed","rejected"].contains(v.state) && (v.arrival == nil || finite(v.arrival!)) && (v.departure == nil || finite(v.departure!)) && (v.arrival == nil || v.departure == nil || v.departure! >= v.arrival!) && (v.placeID == nil || knownPlaces.contains { $0.id == v.placeID }) }),
              trips.allSatisfy({ t in !t.title.isEmpty && t.end >= t.start && unique(t.visitIDs) && unique(t.routeIDs) && unique(t.memoryIDs) && t.visitIDs.allSatisfy { id in visits.contains { $0.id == id } } && t.routeIDs.allSatisfy { id in routes.contains { $0.id == id } } && t.memoryIDs.allSatisfy { id in places.contains { $0.id == id } } }),
              photos.allSatisfy({ p in p.bytes > 0 && p.bytes <= 2_000_000 && p.width > 0 && p.height > 0 && p.width <= 1600 && p.height <= 1600 && p.sha256.count == 64 && p.metadataRemoved && (p.memoryID == nil || places.contains { $0.id == p.memoryID }) && (p.tripID == nil || trips.contains { $0.id == p.tripID }) }),
              periodReviews.allSatisfy({ $0.end > $0.start && !$0.title.isEmpty }),
              tasks.allSatisfy({ task in (task.priority == nil || (0...3).contains(task.priority!)) && (task.placeID == nil || knownPlaces.contains { p in p.id == task.placeID }) }),
              routes.allSatisfy({ route in route.tripID == nil || trips.contains { t in t.id == route.tripID } }) else { throw LifeError.invalidValue }
        guard Set(visits.map(\.observationKey)).count == visits.count,
              Set(vaultOperations.map(\.id)).count == vaultOperations.count, vaultOperations.count <= 10000,
              vaultOperations.allSatisfy({ ["accepted","rejected","expired","cancelled"].contains($0.status) && $0.payloadHash.count == 64 && $0.receipt.count <= 65536 }),
              Set(tombstones.map { $0.kind + ":" + $0.id.uuidString }).count == tombstones.count else { throw LifeError.invalidValue }
        let permissions = disclosure.grants ?? []
        guard permissions.count <= 5000, Set(permissions.map(\.id)).count == permissions.count, permissions.allSatisfy({ ["Task","DraftPlan","CalendarCommitment","ActualSession","DailyReview"].contains($0.entityType) }) else { throw LifeError.invalidValue }
        var dates: [Date] = []
        for task in tasks { dates.append(task.createdAt); if let completed = task.completedAt { dates.append(completed) }; if let due = task.dueAt { dates.append(due) } }
        for plan in plans { dates.append(plan.start); dates.append(plan.end) }
        for session in sessions { dates.append(session.start); if let end = session.end { dates.append(end) } }
        for reading in measurements { dates.append(reading.recordedAt); dates.append(reading.effectiveAt) }
        for route in routes { dates.append(route.start); if let end = route.end { dates.append(end) }; for point in route.points { dates.append(point.at) } }
        for visit in visits { dates.append(visit.receivedAt); if let arrival = visit.arrival { dates.append(arrival) }; if let departure = visit.departure { dates.append(departure) } }
        for place in places { dates.append(place.occurredAt) }
        for goal in goals { dates.append(goal.due); if let start = goal.cycleStart { guard start <= goal.due else { throw LifeError.invalidValue }; dates.append(start) } }
        for photo in photos { dates.append(photo.capturedAt) }
        for review in reviews { dates.append(review.createdAt) }
        for review in periodReviews { dates.append(review.start); dates.append(review.end); dates.append(review.createdAt) }
        var revisions: [Int64] = tasks.map(\.revision)
        revisions.append(contentsOf: plans.map(\.revision)); revisions.append(contentsOf: sessions.map(\.revision)); revisions.append(contentsOf: keyResults.map(\.revision))
        revisions.append(contentsOf: goals.map { $0.revision ?? 1 }); revisions.append(contentsOf: reviews.map { $0.revision ?? 1 })
        revisions.append(contentsOf: knownPlaces.map(\.revision)); revisions.append(contentsOf: visits.map(\.revision)); revisions.append(contentsOf: trips.map(\.revision)); revisions.append(contentsOf: periodReviews.map(\.revision))
        revisions.append(contentsOf: routes.map { $0.metadataRevision ?? 1 })
        guard revisions.allSatisfy({ (1...9_007_199_254_740_991).contains($0) }), (0...9_007_199_254_740_991).contains(disclosure.lastSequence),
              routes.allSatisfy({ $0.points.allSatisfy { point in (0...9_007_199_254_740_991).contains(point.segment) && (point.accuracy == nil || (point.accuracy!.isFinite && point.accuracy! >= 0)) } }) else { throw LifeError.message("记录计数或采样信息无效，原数据已保留。") }
        let zones = plans.map(\.timeZone) + sessions.map(\.timeZone) + reviews.map(\.timeZone) + places.compactMap(\.timeZone) + routes.compactMap(\.timeZone) + trips.compactMap(\.timeZone)
        guard zones.allSatisfy({ TimeZone(identifier:$0) != nil }), visits.allSatisfy({ $0.timeZoneSource == nil || ($0.timeZoneSource == "user" && TimeZone(identifier:$0.timeZone) != nil) }) else { throw LifeError.invalidValue }
        guard dates.allSatisfy(finite), calendarLinks.allSatisfy({ link in plans.contains { $0.id == link.planID } }),
              collectionWindows.allSatisfy({ finite($0.start) && ($0.end == nil || $0.end! >= $0.start) }),
              routes.allSatisfy({ route in zip(route.points, route.points.dropFirst()).allSatisfy { pair in pair.0.at <= pair.1.at && pair.0.segment <= pair.1.segment } }) else { throw LifeError.invalidValue }
        let live: [String:Set<UUID>] = ["task":Set(tasks.map(\.id)),"plan":Set(plans.filter { !$0.isCommitment }.map(\.id)),"commitment":Set(plans.filter(\.isCommitment).map(\.id)),"actual":Set(sessions.map(\.id)),"review":Set(reviews.map(\.id)),"memory":Set(places.map(\.id)),"photo":Set(photos.map(\.id)),"visit":Set(visits.map(\.id)),"route":Set(routes.map(\.id)),"trip":Set(trips.map(\.id)),"known-place":Set(knownPlaces.map(\.id)),"goal":Set(goals.map(\.id)),"kr":Set(keyResults.map(\.id)),"measurement":Set(measurements.map(\.id)),"period-review":Set(periodReviews.map(\.id))]
        guard tombstones.allSatisfy({ live[$0.kind]?.contains($0.id) == false }) else { throw LifeError.message("删除记录不能被旧编辑或回调复活，原数据保留。") }
    }
    func currentMeasurement(for keyResultID: UUID) -> LifeMeasurement? {
        measurements.filter { ($0.keyResultID ?? $0.goalID) == keyResultID && $0.rejectedAt == nil }.max {
            if $0.effectiveAt != $1.effectiveAt { return $0.effectiveAt < $1.effectiveAt }
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    func progress(for keyResult: LifeKeyResult) -> Double? {
        guard let value = currentMeasurement(for: keyResult.id)?.value else { return nil }
        let scale = max(1,abs(value),abs(keyResult.baseline),abs(keyResult.target))
        return min(1, max(0, (value / scale - keyResult.baseline / scale) / (keyResult.target / scale - keyResult.baseline / scale)))
    }
    func objectiveProgress(_ id: UUID) -> Double? {
        let children = keyResults.filter { $0.objectiveID == id && !$0.archived }
        guard !children.isEmpty else { return nil }
        let measured = children.compactMap { kr -> (Double,Double)? in guard let p = progress(for: kr) else { return nil }; return (p,kr.weight) }
        guard measured.count == children.count else { return nil }
        return measured.reduce(0) { $0 + $1.0 * $1.1 } / children.reduce(0) { $0 + $1.weight }
    }
    mutating func audit<T: Encodable>(_ value: T, id: UUID, kind: String, revision: Int64) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        amendments.append(LifeAmendment(entityID: id, kind: kind, priorRevision: revision, previous: try encoder.encode(value)))
    }
    mutating func tombstone(_ id: UUID, kind: String) {
        if !tombstones.contains(where: { $0.id == id && $0.kind == kind }) { tombstones.append(LocalTombstone(id: id, kind: kind)) }
        amendments.removeAll { $0.entityID == id }
    }
    func unionActualSeconds(from start: Date, to end: Date, goalID: UUID? = nil) -> TimeInterval {
        let taskIDs = Set(tasks.filter { $0.goalID == goalID }.map(\.id))
        let intervals = sessions.filter { $0.confirmed && $0.deletedAt == nil && $0.end != nil && (goalID == nil || $0.taskID.map { taskIDs.contains($0) } == true) }.map { (max(start,$0.start),min(end,$0.end!)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        return unionIntervals(intervals)
    }
    func unionAttributedActualSeconds(day: Date) -> TimeInterval {
        let intervals = sessions.filter { $0.confirmed && $0.deletedAt == nil && $0.end != nil }.compactMap { session -> (Date,Date)? in
            let bounds = attributedDayBounds(day, zone:TimeZone(identifier:session.timeZone) ?? .current)
            let pair = (max(bounds.0,session.start), min(bounds.1,session.end!)); return pair.1 > pair.0 ? pair : nil
        }.sorted { $0.0 < $1.0 }
        return unionIntervals(intervals)
    }
    private func unionIntervals(_ intervals: [(Date,Date)]) -> TimeInterval {
        var total: TimeInterval = 0; var current: (Date,Date)?
        for next in intervals {
            if let interval = current {
                if next.0 <= interval.1 { current = (interval.0,max(interval.1,next.1)) }
                else { total += interval.1.timeIntervalSince(interval.0); current = next }
            } else { current = next }
        }
        if let current { total += current.1.timeIntervalSince(current.0) }
        return total
    }
}
