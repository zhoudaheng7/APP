import Foundation
import JavaScriptCore

@MainActor final class WireRuntime {
    private let context: JSContext
    init() throws {
        guard let context = JSContext(), let url = Bundle.main.url(forResource: "DayisleWire", withExtension: "js") else { throw LifeError.message("内置同步校验器不可用。") }
        self.context = context
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil, context.objectForKeyedSubscript("DayisleWire")?.isUndefined == false else { throw LifeError.message("内置同步校验器未能启动。") }
    }
    func call(_ operation: String, _ input: [String:Any]) throws -> [String:Any] {
        let bytes = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        guard let text = String(data: bytes, encoding: .utf8), let api = context.objectForKeyedSubscript("DayisleWire"), let function = api.objectForKeyedSubscript("invoke") else { throw LifeError.invalidValue }
        context.exception = nil
        guard let response = function.call(withArguments: [operation,text])?.toString(), context.exception == nil,
              let data = response.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw LifeError.message("同步校验器异常，未采用候选数据。") }
        guard object["ok"] as? Bool == true else {
            let raw = object["code"] as? String ?? "RUNTIME_FAILURE"
            let code = raw.range(of: "^[A-Z0-9_]{1,80}$", options: .regularExpression) != nil ? raw : "RUNTIME_FAILURE"
            throw LifeError.message("同步检查未通过（" + code + "），原数据保留。")
        }
        guard let value = object["value"] as? [String:Any] else { throw LifeError.invalidValue }; return value
    }
}

func wireInstant(_ date: Date) -> String {
    let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; format.timeZone = TimeZone(secondsFromGMT: 0)
    return format.string(from: date)
}
extension UUID { var wire: String { uuidString.lowercased() } }

extension LifeSnapshot {
    func wireEntities() -> [[String:Any]] {
        var result: [[String:Any]] = tasks.filter { $0.deletedAt == nil }.map { task in
            var row: [String:Any] = ["entityType":"Task","entityID":task.id.wire,"revision":task.revision,"title":task.title,"lifecycleStatus":task.archivedAt != nil ? "archived" : task.cancelledAt != nil ? "cancelled" : task.completedAt != nil ? "completed" : "open"]
            if let goal = task.goalID { row["goalID"] = goal.wire }; return row
        }
        for plan in plans where plan.deletedAt == nil {
            var row: [String:Any] = ["entityType":plan.isCommitment ? "CalendarCommitment" : "DraftPlan","entityID":plan.id.wire,"revision":plan.revision,"title":plan.title,"lifecycleStatus":plan.cancelled ? "cancelled":"active"]
            if plan.isCommitment {
                row["allDay"] = plan.allDay ?? false
                if plan.allDay == true { let zone = TimeZone(identifier: plan.timeZone) ?? .current; row["localStartDate"] = Self.dayKey(plan.start, zone: zone); row["localEndDateExclusive"] = Self.dayKey(plan.end, zone: zone); row["calendarTimeZone"] = plan.timeZone }
                else { row["start"] = wireInstant(plan.start); row["end"] = wireInstant(plan.end); row["attributionTimeZone"] = plan.timeZone }
            } else { row["plannedStart"] = wireInstant(plan.start); row["plannedEnd"] = wireInstant(plan.end); row["attributionTimeZone"] = plan.timeZone }
            if let task = plan.taskID { row["taskID"] = task.wire }; result.append(row)
        }
        for session in sessions where session.deletedAt == nil {
            var row: [String:Any] = ["entityType":"ActualSession","entityID":session.id.wire,"revision":session.revision,"title":session.title,"runState":session.end == nil ? "running":"stopped","factState":session.confirmed ? "confirmed":"inferred","actualStart":wireInstant(session.start),"actualEnd":session.end.map { wireInstant($0) as Any } ?? NSNull(),"attributionTimeZone":session.timeZone]
            if let task = session.taskID { row["taskID"] = task.wire }; result.append(row)
        }
        result += reviews.filter { $0.canonical != false }.map { review in ["entityType":"DailyReview","entityID":review.id.wire,"revision":review.revision ?? 1,"dayKey":review.day,"reflection":review.reflection] as [String:Any] }
        return result
    }
    func wireTombstones() -> [[String:Any]] {
        let kinds = ["task":"Task","plan":"DraftPlan","commitment":"CalendarCommitment","actual":"ActualSession","review":"DailyReview"]
        return tombstones.compactMap { stamp in guard let kind = kinds[stamp.kind] else { return nil }; return ["entityType":kind,"entityID":stamp.id.wire] }
    }
    func dailyProjectionBody(day: Date) -> String {
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        var lines = ["## 朝屿 · " + Self.dayKey(day), "", "### 想完成的事"]
        lines += tasks.filter(\.isOpen).map { "- " + plain($0.title).replacingOccurrences(of: "\n", with: " ") }
        lines += ["", "### 计划与承诺"]
        lines += plans.filter { !$0.cancelled && overlapsDay($0.start, $0.end, day: day) }.map { "- " + plain($0.title).replacingOccurrences(of: "\n", with: " ") + ($0.isCommitment ? "（日历承诺）":"（私人计划）") }
        let bounds = attributedDayBounds(day, zone: .current)
        lines += ["", "已确认实际投入（重叠合并）：" + minutesText(unionActualSeconds(from: bounds.0, to: bounds.1))]
        if let review = reviews.first(where: { $0.day == Self.dayKey(day) && $0.canonical != false }) { lines += ["", "### 日复盘"] + plain(review.reflection).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 } }
        return lines.joined(separator: "\n") + "\n"
    }
}
