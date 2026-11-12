import Foundation
import LifeOSDomain

extension LifeStore {
    func editTask(_ original: LifeTask, title: String, note: String, goalID: UUID?, due: Date?, priority: Int) -> Bool {
        commit(kind: "task.edit", id: original.id) { state in
            guard let i = state.tasks.firstIndex(where: { $0.id == original.id }), state.tasks[i].revision == original.revision else { throw LifeError.message("任务版本已变化，请重新打开。") }
            try state.audit(state.tasks[i], id: original.id, kind: "task", revision: original.revision)
            state.tasks[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines); state.tasks[i].note = note
            state.tasks[i].goalID = goalID; state.tasks[i].dueAt = due; state.tasks[i].priority = priority; state.tasks[i].revision += 1
        }
    }
    func archiveTask(_ task: LifeTask) {
        _ = commit(kind: "task.archive", id: task.id) { state in
            guard let i = state.tasks.firstIndex(where: { $0.id == task.id }) else { throw LifeError.invalidReference }
            state.tasks[i].archivedAt = Date(); state.tasks[i].revision += 1
        }
    }
    func deleteTask(_ task: LifeTask) {
        _ = commit(kind: "task.delete", id: task.id) { state in
            state.tasks.removeAll { $0.id == task.id }
            for i in state.plans.indices where state.plans[i].taskID == task.id { state.plans[i].taskID = nil; state.plans[i].revision += 1 }
            for i in state.sessions.indices where state.sessions[i].taskID == task.id { state.sessions[i].taskID = nil; state.sessions[i].revision += 1 }
            state.tombstone(task.id, kind: "task")
        }
    }
    func editPlan(_ original: LifePlan, title: String, start: Date, end: Date, taskID: UUID?, note: String, reminder: Int?) -> Bool {
        commit(kind: "plan.edit", id: original.id) { state in
            guard let i = state.plans.firstIndex(where: { $0.id == original.id }), state.plans[i].revision == original.revision else { throw LifeError.message("计划版本已变化，请重新打开。") }
            try state.audit(state.plans[i], id: original.id, kind: "plan", revision: original.revision)
            state.plans[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines); state.plans[i].start = start; state.plans[i].end = end
            state.plans[i].taskID = taskID; state.plans[i].note = note; state.plans[i].reminderMinutes = reminder; state.plans[i].revision += 1
        }
    }
    func repeatPlan(_ original: LifePlan, everyDays: Int, count: Int) -> Bool {
        guard (1...30).contains(everyDays), (1...30).contains(count) else { return false }
        return commit(kind: "plan.repeat", id: original.id) { state in
            let series = UUID(); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: original.timeZone) ?? .current
            for index in 1...count {
                guard let start = calendar.date(byAdding: .day, value: everyDays * index, to: original.start),
                      let end = calendar.date(byAdding: .day, value: everyDays * index, to: original.end) else { throw LifeError.invalidValue }
                var copy = LifePlan(title: original.title, taskID: original.taskID, start: start, end: end, timeZone: original.timeZone, isCommitment: false)
                copy.note = original.note; copy.seriesID = series; state.plans.append(copy)
            }
        }
    }
    func editSession(_ original: LifeSession, title: String, start: Date, end: Date, note: String, confirmed: Bool) -> Bool {
        commit(kind: "actual.correct", id: original.id) { state in
            guard let i = state.sessions.firstIndex(where: { $0.id == original.id }), state.sessions[i].revision == original.revision,
                  original.end != nil || original.restorePending == true else { throw LifeError.message("请先结束计时，再修正这段记录。") }
            try state.audit(state.sessions[i], id: original.id, kind: "actual", revision: original.revision)
            state.sessions[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines); state.sessions[i].start = start
            state.sessions[i].end = end; state.sessions[i].note = note; state.sessions[i].confirmed = confirmed; state.sessions[i].restorePending = false; state.sessions[i].revision += 1
        }
    }
    func deleteSession(_ session: LifeSession) {
        guard session.end != nil || session.restorePending == true else { error = "请先结束正在计时的记录。"; return }
        _ = commit(kind: "actual.delete", id: session.id) { $0.sessions.removeAll { $0.id == session.id }; $0.tombstone(session.id, kind: "actual") }
    }
    func reviseReview(_ original: LifeReview, text: String, mood: Int?, people: [String]) -> Bool {
        commit(kind: "review.revise", id: original.id) { state in
            guard let i = state.reviews.firstIndex(where: { $0.id == original.id }), (state.reviews[i].revision ?? 1) == (original.revision ?? 1) else { throw LifeError.message("复盘版本已变化，请重新打开。") }
            try state.audit(state.reviews[i], id: original.id, kind: "review", revision: original.revision ?? 1)
            state.reviews[i].reflection = text; state.reviews[i].mood = mood; state.reviews[i].people = people
            state.reviews[i].revision = (original.revision ?? 1) + 1
        }
    }
    func addKeyResult(_ result: LifeKeyResult) -> Bool { commit(kind: "kr.create", id: result.id) { $0.keyResults.append(result) } }
    func editKeyResult(_ original: LifeKeyResult, title: String, baseline: Double, target: Double, unit: String, weight: Double) -> Bool {
        commit(kind: "kr.edit", id: original.id) { state in
            guard let i = state.keyResults.firstIndex(where: { $0.id == original.id }), state.keyResults[i].revision == original.revision else { throw LifeError.invalidReference }
            try state.audit(state.keyResults[i], id: original.id, kind: "kr", revision: original.revision)
            state.keyResults[i].title = title; state.keyResults[i].baseline = baseline; state.keyResults[i].target = target
            state.keyResults[i].unit = unit; state.keyResults[i].weight = weight; state.keyResults[i].revision += 1
        }
    }
    func editGoal(_ original: LifeGoal, title: String, intention: String, due: Date, assessment: String) -> Bool {
        commit(kind: "goal.edit", id: original.id) { state in
            guard let i = state.goals.firstIndex(where: { $0.id == original.id }) else { throw LifeError.invalidReference }
            try state.audit(state.goals[i], id: original.id, kind: "goal", revision: original.revision ?? 1)
            state.goals[i].title = title; state.goals[i].intention = intention; state.goals[i].due = due
            state.goals[i].assessment = assessment; state.goals[i].revision = (original.revision ?? 1) + 1
        }
    }
    func archiveGoal(_ goal: LifeGoal) { _ = commit(kind: "goal.archive", id: goal.id) { state in if let i = state.goals.firstIndex(where: { $0.id == goal.id }) { state.goals[i].archived = true } } }
    func rejectMeasurement(_ reading: LifeMeasurement) {
        _ = commit(kind: "measurement.reject", id: reading.id) { state in if let i = state.measurements.firstIndex(where: { $0.id == reading.id }) { state.measurements[i].rejectedAt = Date() } }
    }
    func addPeriodReview(_ review: PeriodReview) -> Bool { commit(kind: "period-review.create", id: review.id) { $0.periodReviews.insert(review, at: 0) } }
    func saveTrip(_ trip: LifeTrip) -> Bool {
        commit(kind: "trip.save", id: trip.id) { state in
            if let i = state.trips.firstIndex(where: { $0.id == trip.id }) { var revised = trip; revised.revision += 1; state.trips[i] = revised }
            else { state.trips.insert(trip, at: 0) }
        }
    }
    func saveKnownPlace(_ place: KnownPlace) -> Bool {
        var place = place
        place.title = place.title.trimmingCharacters(in: .whitespacesAndNewlines); place.city = place.city.trimmingCharacters(in: .whitespacesAndNewlines); place.country = place.country.trimmingCharacters(in: .whitespacesAndNewlines)
        return commit(kind: "known-place.save", id: place.id) { state in
            if let i = state.knownPlaces.firstIndex(where: { $0.id == place.id }) { var revised = place; revised.revision += 1; state.knownPlaces[i] = revised }
            else { state.knownPlaces.append(place) }
        }
    }
    func saveMemory(_ original: LifePlace, title: String, note: String, favorite: Bool, tripID: UUID?, people: [String], occurredAt: Date, knownPlaceID: UUID?) -> Bool {
        commit(kind: "memory.edit", id: original.id) { state in
            guard let i = state.places.firstIndex(where: { $0.id == original.id }) else { throw LifeError.invalidReference }
            state.places[i].title = title; state.places[i].note = note; state.places[i].favorite = favorite
            state.places[i].tripID = tripID; state.places[i].people = people
            state.places[i].occurredAt = occurredAt; state.places[i].knownPlaceID = knownPlaceID
        }
    }
    func deletePhoto(_ photo: LifePhoto) {
        _ = commit(kind: "photo.delete", id: photo.id, media: [.remove(photo.id)]) { $0.photos.removeAll { $0.id == photo.id }; $0.tombstone(photo.id, kind: "photo") }
    }
    func addPhoto(_ photo: LifePhoto, bytes: Data) -> Bool { commit(kind: "photo.add", id: photo.id, media: [.put(photo.id, bytes)]) { $0.photos.append(photo) } }
}
