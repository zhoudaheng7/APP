import Foundation

extension LifeStore {
    static func decodeBackup(_ bytes: Data) throws -> LifeBackup {
        guard bytes.count <= 128 * 1024 * 1024 else { throw LifeError.message("备份超过128MB，未读取。") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let header = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        let backup: LifeBackup
        if header?["format"] != nil {
            backup = try decoder.decode(LifeBackup.self, from: bytes)
            guard backup.format == "dayisle-private-backup/v2" else { throw LifeError.message("不支持此备份版本。") }
        } else {
            backup = LifeBackup(snapshot: try decoder.decode(LifeSnapshot.self, from: bytes), media: [:], exportedAt: nil)
        }
        try backup.snapshot.validate()
        guard backup.media.count == backup.snapshot.photos.count else { throw LifeError.message("照片清单与备份不一致。") }
        for photo in backup.snapshot.photos {
            guard let content = backup.media[photo.id.uuidString], content.count == photo.bytes, fingerprint(content) == photo.sha256, PhotoProcessor.isSanitizedJPEG(content, width: photo.width, height: photo.height) else { throw LifeError.message("备份照片校验失败。") }
        }
        return backup
    }

    func restoreBackup(_ backup: LifeBackup) -> Bool {
        var candidate = backup.snapshot
        // A deleted private fact cannot silently reappear when restoring an older file.
        for tombstone in data.tombstones where !candidate.tombstones.contains(where: { $0.id == tombstone.id && $0.kind == tombstone.kind }) { candidate.tombstones.append(tombstone) }
        candidate.applyDeletionHistory()
        // Never restore a previous external publication cursor into a new folder/session.
        for i in candidate.sessions.indices where candidate.sessions[i].end == nil { candidate.sessions[i].restorePending = true }
        candidate.disclosure = data.disclosure
        candidate.vaultOperations = data.vaultOperations
        for task in data.tasks where !candidate.tasks.contains(where: { $0.id == task.id }) { candidate.tombstone(task.id, kind: "task") }
        for plan in data.plans where !candidate.plans.contains(where: { $0.id == plan.id }) { candidate.tombstone(plan.id, kind: plan.isCommitment ? "commitment":"plan") }
        for session in data.sessions where !candidate.sessions.contains(where: { $0.id == session.id }) { candidate.tombstone(session.id, kind: "actual") }
        for review in data.reviews where !candidate.reviews.contains(where: { $0.id == review.id }) { candidate.tombstone(review.id, kind: "review") }
        for visit in data.visits where !candidate.visits.contains(where: { $0.id == visit.id }) { candidate.tombstone(visit.id, kind: "visit") }
        for route in data.routes where !candidate.routes.contains(where: { $0.id == route.id }) { candidate.tombstone(route.id, kind: "route") }
        for memory in data.places where !candidate.places.contains(where: { $0.id == memory.id }) { candidate.tombstone(memory.id, kind: "memory") }
        for photo in data.photos where !candidate.photos.contains(where: { $0.id == photo.id }) { candidate.tombstone(photo.id, kind: "photo") }
        for trip in data.trips where !candidate.trips.contains(where: { $0.id == trip.id }) { candidate.tombstone(trip.id, kind: "trip") }
        for place in data.knownPlaces where !candidate.knownPlaces.contains(where: { $0.id == place.id }) { candidate.tombstone(place.id, kind: "known-place") }
        for goal in data.goals where !candidate.goals.contains(where: { $0.id == goal.id }) { candidate.tombstone(goal.id, kind: "goal") }
        for result in data.keyResults where !candidate.keyResults.contains(where: { $0.id == result.id }) { candidate.tombstone(result.id, kind: "kr") }
        for reading in data.measurements where !candidate.measurements.contains(where: { $0.id == reading.id }) { candidate.tombstone(reading.id, kind: "measurement") }
        for review in data.periodReviews where !candidate.periodReviews.contains(where: { $0.id == review.id }) { candidate.tombstone(review.id, kind: "period-review") }
        candidate.applyDeletionHistory()
        for i in candidate.collectionWindows.indices where candidate.collectionWindows[i].end == nil { candidate.collectionWindows[i].end = Date() }
        let kept = Set(candidate.photos.map(\.id))
        var media: [MediaMutation] = data.photos.filter { !kept.contains($0.id) }.map { .remove($0.id) }
        for photo in candidate.photos {
            guard let content = backup.media[photo.id.uuidString], Self.fingerprint(content) == photo.sha256 else { error = "照片副本缺失，未恢复。"; return false }
            media.append(.put(photo.id, content))
        }
        return commit(kind: "backup.restore", id: UUID(), media: media) { $0 = candidate }
    }

    func readableExport() -> URL? {
        do {
            var lines = ["# 朝屿 · 私人记录", "", "导出时间：" + Date().formatted(), "", "此文件含私人文字，请存放在可信位置。", "", "## 任务"]
            lines += data.tasks.map { "- [\($0.completedAt == nil ? " " : "x")] " + $0.title + ($0.note.isEmpty ? "" : "\n  " + $0.note.replacingOccurrences(of: "\n", with: "\n  ")) }
            lines += ["", "## 方向与成果"]
            for goal in data.goals {
                lines += ["### " + goal.title, goal.intention]
                for kr in data.keyResults.filter({ $0.objectiveID == goal.id }) {
                    let current = data.currentMeasurement(for: kr.id)
                    lines.append("- " + kr.title + "：" + (current.map { String($0.value) } ?? "未记录") + " / \(kr.target) \(kr.unit)")
                }
            }
            lines += ["", "## 日复盘"]
            for review in data.reviews.sorted(by: { $0.day < $1.day }) { lines += ["### " + review.day + " · " + review.timeZone, review.reflection, ""] }
            lines += ["## 生活记忆"]
            for memory in data.places { lines += ["### " + memory.title, memory.occurredAt.formatted(), memory.note, ""] }
            lines += ["## 周期回顾"]
            for review in data.periodReviews { lines += ["### " + review.title, review.reflection, "下一步：" + review.nextStep, ""] }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-readable.md")
            try Data(lines.joined(separator: "\n").utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        } catch { self.error = error.localizedDescription; return nil }
    }
}

extension LifeSnapshot {
    mutating func applyDeletionHistory() {
        func deleted(_ kind: String) -> Set<UUID> { Set(tombstones.filter { $0.kind == kind }.map(\.id)) }
        let taskIDs = deleted("task"), actualIDs = deleted("actual"), memoryIDs = deleted("memory"), photoIDs = deleted("photo")
        let routeIDs = deleted("route"), visitIDs = deleted("visit"), tripIDs = deleted("trip"), knownIDs = deleted("known-place"), planIDs = deleted("plan").union(deleted("commitment")), reviewIDs = deleted("review")
        let goalIDs = deleted("goal"), resultIDs = deleted("kr"), readingIDs = deleted("measurement"), periodIDs = deleted("period-review")
        goals.removeAll { goalIDs.contains($0.id) }; keyResults.removeAll { resultIDs.contains($0.id) || goalIDs.contains($0.objectiveID) }
        let validResults = Set(keyResults.map(\.id))
        measurements.removeAll { readingIDs.contains($0.id) || goalIDs.contains($0.goalID) || ($0.keyResultID != nil && !validResults.contains($0.keyResultID!)) }
        periodReviews.removeAll { periodIDs.contains($0.id) }
        tasks.removeAll { taskIDs.contains($0.id) }; sessions.removeAll { actualIDs.contains($0.id) }
        places.removeAll { memoryIDs.contains($0.id) }; photos.removeAll { photoIDs.contains($0.id) || $0.memoryID.map { memoryIDs.contains($0) } == true }
        routes.removeAll { routeIDs.contains($0.id) }; visits.removeAll { visitIDs.contains($0.id) }
        trips.removeAll { tripIDs.contains($0.id) }; knownPlaces.removeAll { knownIDs.contains($0.id) }
        plans.removeAll { planIDs.contains($0.id) }; reviews.removeAll { reviewIDs.contains($0.id) }
        for i in plans.indices { if plans[i].taskID.map({ taskIDs.contains($0) }) == true { plans[i].taskID = nil }; if plans[i].placeID.map({ knownIDs.contains($0) }) == true { plans[i].placeID = nil } }
        for i in sessions.indices { if sessions[i].taskID.map({ taskIDs.contains($0) }) == true { sessions[i].taskID = nil }; if sessions[i].tripID.map({ tripIDs.contains($0) }) == true { sessions[i].tripID = nil } }
        for i in tasks.indices where tasks[i].placeID.map({ knownIDs.contains($0) }) == true { tasks[i].placeID = nil }
        for i in tasks.indices where tasks[i].goalID.map({ goalIDs.contains($0) }) == true { tasks[i].goalID = nil }
        for i in places.indices { if places[i].tripID.map({ tripIDs.contains($0) }) == true { places[i].tripID = nil }; if places[i].knownPlaceID.map({ knownIDs.contains($0) }) == true { places[i].knownPlaceID = nil }; if places[i].visitID.map({ visitIDs.contains($0) }) == true { places[i].visitID = nil } }
        for i in visits.indices where visits[i].placeID.map({ knownIDs.contains($0) }) == true { visits[i].placeID = nil }
        for i in routes.indices where routes[i].tripID.map({ tripIDs.contains($0) }) == true { routes[i].tripID = nil }
        for i in photos.indices where photos[i].tripID.map({ tripIDs.contains($0) }) == true { photos[i].tripID = nil }
        for i in trips.indices { trips[i].memoryIDs.removeAll { memoryIDs.contains($0) }; trips[i].visitIDs.removeAll { visitIDs.contains($0) }; trips[i].routeIDs.removeAll { routeIDs.contains($0) } }
        calendarLinks.removeAll { planIDs.contains($0.planID) }
        amendments.removeAll { amendment in tombstones.contains { $0.id == amendment.entityID } }
    }
}
