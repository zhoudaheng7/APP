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
        candidate.disclosure = data.disclosure
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
        let routeIDs = deleted("route"), visitIDs = deleted("visit"), tripIDs = deleted("trip"), knownIDs = deleted("known-place"), planIDs = deleted("plan"), reviewIDs = deleted("review")
        tasks.removeAll { taskIDs.contains($0.id) }; sessions.removeAll { actualIDs.contains($0.id) }
        places.removeAll { memoryIDs.contains($0.id) }; photos.removeAll { photoIDs.contains($0.id) || $0.memoryID.map { memoryIDs.contains($0) } == true }
        routes.removeAll { routeIDs.contains($0.id) }; visits.removeAll { visitIDs.contains($0.id) }
        trips.removeAll { tripIDs.contains($0.id) }; knownPlaces.removeAll { knownIDs.contains($0.id) }
        plans.removeAll { planIDs.contains($0.id) }; reviews.removeAll { reviewIDs.contains($0.id) }
        for i in plans.indices { if plans[i].taskID.map({ taskIDs.contains($0) }) == true { plans[i].taskID = nil }; if plans[i].placeID.map({ knownIDs.contains($0) }) == true { plans[i].placeID = nil } }
        for i in sessions.indices { if sessions[i].taskID.map({ taskIDs.contains($0) }) == true { sessions[i].taskID = nil }; if sessions[i].tripID.map({ tripIDs.contains($0) }) == true { sessions[i].tripID = nil } }
        for i in tasks.indices where tasks[i].placeID.map({ knownIDs.contains($0) }) == true { tasks[i].placeID = nil }
        for i in places.indices { if places[i].tripID.map({ tripIDs.contains($0) }) == true { places[i].tripID = nil }; if places[i].knownPlaceID.map({ knownIDs.contains($0) }) == true { places[i].knownPlaceID = nil }; if places[i].visitID.map({ visitIDs.contains($0) }) == true { places[i].visitID = nil } }
        for i in visits.indices where visits[i].placeID.map({ knownIDs.contains($0) }) == true { visits[i].placeID = nil }
        for i in routes.indices where routes[i].tripID.map({ tripIDs.contains($0) }) == true { routes[i].tripID = nil }
        for i in photos.indices where photos[i].tripID.map({ tripIDs.contains($0) }) == true { photos[i].tripID = nil }
        for i in trips.indices { trips[i].memoryIDs.removeAll { memoryIDs.contains($0) }; trips[i].visitIDs.removeAll { visitIDs.contains($0) }; trips[i].routeIDs.removeAll { routeIDs.contains($0) } }
        calendarLinks.removeAll { planIDs.contains($0.planID) }
        amendments.removeAll { amendment in tombstones.contains { $0.id == amendment.entityID } }
    }
}
