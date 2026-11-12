import SwiftUI
import HealthKit

struct HealthContextSnapshot {
    var start: Date
    var end: Date
    var readAt: Date
    var zone: String
    var steps: Double?
    var sleepSeconds: Double?
    var workouts: [String]
    var sources: [String]
    var summary: String {
        ["健康上下文 · " + LifeSnapshot.dayKey(start, zone: TimeZone(identifier: zone) ?? .current),
         "查询范围：" + recordTimeText(start, zone: zone) + " 至 " + recordTimeText(end, zone: zone),
         "可读步数：" + (steps.map { String(Int($0)) } ?? "未知"),
         "可读睡眠区间并集：" + (sleepSeconds.map(minutesText) ?? "未知"),
         "可读锻炼：" + (workouts.isEmpty ? "未知" : workouts.joined(separator: "；")),
         "来源：" + (sources.isEmpty ? "无可读来源" : sources.joined(separator: "、")),
         "读取于：" + readAt.formatted(),
         "仅含本次可读样本，可能不完整；不代表医疗判断或实际投入。"].joined(separator: "\n")
    }
}

enum HealthContextMath {
    static func unionSeconds(_ intervals: [(Date,Date)], from start: Date, to end: Date) -> Double? {
        let clipped = intervals.map { (max(start,$0.0),min(end,$0.1)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard let first = clipped.first else { return nil }
        var active = first; var seconds = 0.0
        for next in clipped.dropFirst() {
            if next.0 <= active.1 { active.1 = max(active.1,next.1) }
            else { seconds += active.1.timeIntervalSince(active.0); active = next }
        }
        return seconds + active.1.timeIntervalSince(active.0)
    }
}

@MainActor @Observable final class HealthContextReader {
    var busy = false
    var message = "尚未读取健康数据。"
    var snapshot: HealthContextSnapshot?
    var enabled: Bool { Bundle.main.object(forInfoDictionaryKey: "DayisleHealthEnabled") as? Bool == true }
    func clear() { snapshot = nil; message = "已清除本页读取结果；苹果健康中的原数据未改变。" }
    func read(day: Date) async {
        guard !busy else { return }; snapshot = nil
        guard enabled else { message = "此安装包未启用健康签名能力。"; return }
        guard HKHealthStore.isHealthDataAvailable() else { message = "这台设备暂不可用健康数据。"; return }
        busy = true; defer { busy = false }
        do {
            let health = HKHealthStore()
            let stepType = HKQuantityType(.stepCount), sleepType = HKCategoryType(.sleepAnalysis)
            let readTypes: Set<HKObjectType> = [stepType,sleepType,HKWorkoutType.workoutType()]
            try await health.requestAuthorization(toShare: [], read: readTypes)
            let calendar = Calendar.current, start = calendar.startOfDay(for: day)
            let end = min(Date(),calendar.date(byAdding: .day,value: 1,to: start)!)
            guard end > start else { throw LifeError.message("请选择已经开始的日期。") }
            let predicate = HKQuery.predicateForSamples(withStart: start,end: end)
            let statistics = try await HKStatisticsQueryDescriptor(predicate: .quantitySample(type: stepType,predicate: predicate),options: .cumulativeSum).result(for: health)
            let sleep = try await HKSampleQueryDescriptor(predicates: [.categorySample(type: sleepType,predicate: predicate)],sortDescriptors: [SortDescriptor(\HKCategorySample.startDate)],limit: 1001).result(for: health)
            let workouts = try await HKSampleQueryDescriptor(predicates: [.workout(predicate)],sortDescriptors: [SortDescriptor(\HKWorkout.startDate)],limit: 101).result(for: health)
            guard sleep.count <= 1000, workouts.count <= 100 else { throw LifeError.message("该日可读样本较多，本次不显示可能截断的结果，请在苹果健康中查看。") }
            let asleepValues = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,HKCategoryValueSleepAnalysis.asleepCore.rawValue,HKCategoryValueSleepAnalysis.asleepDeep.rawValue,HKCategoryValueSleepAnalysis.asleepREM.rawValue])
            let asleep = sleep.filter { asleepValues.contains($0.value) }
            let sum = statistics?.sumQuantity()?.doubleValue(for: .count())
            let stepValue = sum.flatMap { $0.isFinite && $0 >= 0 && $0 < Double(Int.max) ? $0 : nil }
            let names = (statistics?.sources()?.map(\.name) ?? []) + sleep.map { $0.sourceRevision.source.name } + workouts.map { $0.sourceRevision.source.name }
            let exercise = workouts.map { item in
                recordTimeText(item.startDate,zone: calendar.timeZone.identifier) + " · " + minutesText(item.duration) + " · " + item.sourceRevision.source.name
            }
            snapshot = HealthContextSnapshot(start:start,end:end,readAt:Date(),zone:calendar.timeZone.identifier,steps:stepValue,sleepSeconds:HealthContextMath.unionSeconds(asleep.map { ($0.startDate,$0.endDate) },from:start,to:end),workouts:exercise,sources:Array(Set(names)).sorted())
            message = "本次读取已结束。空结果保持未知，不能据此判断你未授权或当天没有活动。"
        } catch { message = "未取得本次健康上下文。" + error.localizedDescription }
    }
}

struct HealthContextView: View {
    @State private var reader = HealthContextReader()
    @State private var day = Date()
    var body: some View {
        Form {
            Section("由你主动读取") {
                DatePicker("查看日期",selection:$day,in:...Date(),displayedComponents:.date).disabled(reader.busy)
                Button("授权并读取这一天",systemImage:"heart.text.clipboard") { Task { await reader.read(day:day) } }.disabled(reader.busy || !reader.enabled)
                if reader.busy { ProgressView("正在读取…") }
                Text(reader.message).font(.subheadline).foregroundStyle(.secondary)
            }
            if let snapshot = reader.snapshot {
                Section("本次可读内容") { Text(snapshot.summary).textSelection(.enabled); ShareLink("分享这份文字",item:snapshot.summary); Button("清除本页结果",role:.destructive) { reader.clear() } }
            }
            Section("仅作生活回顾") {
                Text("只申请读取步数、睡眠与锻炼，不写入苹果健康，不请求临床记录或后台更新。样本可能因设备、授权时间窗口、同步延迟而不完整。睡眠按所选日裁剪后合并重叠区间；锻炼逐条显示来源，不转为实际投入或任务成果。")
                Text("结果仅在本页内存中显示；离开后不会自动保存或发布。分享由你主动选择。可在系统“健康”或“设置”中更改读取权限。")
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("健康上下文").onChange(of:day) { _,_ in reader.clear() }
    }
}
