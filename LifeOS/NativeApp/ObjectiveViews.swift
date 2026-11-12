import SwiftUI
import Charts

func decimalValue(_ text: String) -> Double? {
    let formatter = NumberFormatter(); formatter.numberStyle = .decimal
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let decimal = NSRegularExpression.escapedPattern(for: formatter.decimalSeparator ?? ".")
    let group = NSRegularExpression.escapedPattern(for: formatter.groupingSeparator ?? ",")
    let integer = "(?:[0-9]+|[0-9]{1,3}(?:" + group + "[0-9]{3})+)"
    let pattern = "^[+-]?(?:" + integer + "(?:" + decimal + "[0-9]*)?|" + decimal + "[0-9]+)(?:[eE][+-]?[0-9]+)?$"
    guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
    let normalized = trimmed.replacingOccurrences(of: formatter.groupingSeparator ?? ",", with: "").replacingOccurrences(of: formatter.decimalSeparator ?? ".", with: ".")
    return Double(normalized)
}

struct ObjectiveListView: View {
    @Environment(LifeStore.self) private var store
    @State private var add = false
    @State private var showArchived = false
    var body: some View {
        List {
            Section {
                Text("把方向落在日常，把成果留给事实。") .font(.title2.bold()).padding(.vertical, 8)
                Toggle("查看归档方向", isOn: $showArchived)
            }
            ForEach(store.data.goals.filter { $0.archived == showArchived }) { goal in
                NavigationLink { ObjectiveDetailView(objectiveID: goal.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(goal.title).font(.headline)
                        if !goal.intention.isEmpty { Text(goal.intention).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        if let progress = store.data.objectiveProgress(goal.id) { ProgressView(value: progress); Text("成果进度 \(progress.formatted(.percent.precision(.fractionLength(0))))").font(.caption) }
                        else { Text("尚有未记录读数的关键结果").font(.caption).foregroundStyle(.secondary) }
                        HStack { Text("\(store.data.keyResults.filter { $0.objectiveID == goal.id && !$0.archived }.count) 个关键结果"); Spacer(); Text(goal.due.formatted(date: .abbreviated, time: .omitted)) }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if store.data.goals.filter({ $0.archived == showArchived }).isEmpty { ContentUnavailableView("你想朝哪里走？", systemImage: "scope", description: Text("方向可以有多个关键结果，投入和成果各自记录。")) }
            Button { add = true } label: { Label("添加一个方向", systemImage: "plus") }
        }.navigationTitle("方向")
            .toolbar { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加方向") }
            .sheet(isPresented: $add) { ComposerView(kind: .goal) }
    }
}

struct ObjectiveDetailView: View {
    @Environment(LifeStore.self) private var store
    let objectiveID: UUID
    @State private var edit = false
    @State private var addKR = false
    @State private var addTask = false
    @State private var showArchivedKR = false
    var goal: LifeGoal? { store.data.goals.first { $0.id == objectiveID } }
    var body: some View {
        if let goal {
            List {
                Section {
                    Text(goal.title).font(.title2.bold()); if !goal.intention.isEmpty { Text(goal.intention) }
                    LabeledContent("周期截止", value: goal.due.formatted(date: .abbreviated, time: .omitted))
                    if let score = store.data.objectiveProgress(goal.id) { LabeledContent("成果进度", value: score.formatted(.percent.precision(.fractionLength(0)))) }
                    else { Text("部分成果尚无读数，不把未知当作零。") .foregroundStyle(.secondary) }
                    if let assessment = goal.assessment, !assessment.isEmpty { LabeledContent("我的评估", value: assessment) }
                }
                Section("关键结果") {
                    Toggle("显示已归档关键结果", isOn: $showArchivedKR)
                    ForEach(store.data.keyResults.filter { $0.objectiveID == goal.id && (showArchivedKR || !$0.archived) }) { result in
                        NavigationLink { KeyResultDetailView(resultID: result.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.title + (result.archived ? " · 已归档":"")).font(.headline)
                                if let reading = store.data.currentMeasurement(for: result.id), let progress = store.data.progress(for: result) {
                                    Text("\(reading.value.formatted()) / \(result.target.formatted()) \(result.unit)").font(.subheadline)
                                    ProgressView(value: progress)
                                    Text("发生于 " + reading.effectiveAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                } else { Text("尚未记录 · 目标 \(result.target.formatted()) \(result.unit)").font(.subheadline).foregroundStyle(.secondary) }
                            }.padding(.vertical, 5)
                        }
                    }
                    Button("添加关键结果", systemImage: "plus") { addKR = true }
                }
                Section("相关任务") {
                    ForEach(store.data.tasks.filter { $0.goalID == goal.id && $0.deletedAt == nil }) { task in
                        NavigationLink { TaskDetailView(taskID: task.id) } label: { Label(task.title, systemImage: task.completedAt == nil ? "circle" : "checkmark.circle.fill") }
                    }
                    Button("添加相关任务", systemImage: "plus") { addTask = true }
                }
                Section("真实投入") {
                    LabeledContent("已确认、不重叠合计", value: minutesText(store.data.unionActualSeconds(from: .distantPast, to: Date(), goalID: goal.id)))
                    Text("重叠活动的时间取并集；成果读数与主观评估独立。") .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("方向详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("编辑") { edit = true } }
                .sheet(isPresented: $edit) { ObjectiveEditor(original: goal) }
                .sheet(isPresented: $addKR) { KeyResultEditor(objectiveID: goal.id) }
                .sheet(isPresented: $addTask) { ComposerView(kind: .task, initialGoalID: goal.id) }
        }
    }
}

struct ObjectiveEditor: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: LifeGoal
    @State private var title = ""
    @State private var intention = ""
    @State private var assessment = ""
    @State private var due = Date()
    @State private var cycleStart = Date()
    @State private var hasCycleStart = false
    @State private var captured: LifeGoal?
    @State private var initialized = false
    @State private var saved = false
    var draftKey: String { "goal:" + original.id.uuidString }
    var draftFields: [String:String] { guard let captured else { return [:] }; var value = captured; value.title = title; value.intention = intention; value.assessment = assessment; value.due = due; value.cycleStart = hasCycleStart ? cycleStart : nil; return EditorDrafts.fields(RecordDraft(original: captured, edited: value)) }
    var body: some View {
        NavigationStack { Form {
            if let current = store.data.goals.first(where: { $0.id == original.id }) { EditorConflictNotice(changed: captured.map { $0 != current } ?? false, current: current.title + "\n" + current.intention + "\n" + current.due.formatted()) { captured = current } }
            TextField("方向", text: $title, axis: .vertical)
            TextField("为什么重要", text: $intention, axis: .vertical).lineLimit(3...8)
            DatePicker("周期截止", selection: $due, displayedComponents: .date)
            Toggle("记录周期开始", isOn: $hasCycleStart)
            if hasCycleStart { DatePicker("周期开始", selection: $cycleStart, in: ...due, displayedComponents: .date) }
            TextField("我的主观评估（可留空）", text: $assessment, axis: .vertical).lineLimit(3...8)
            Text("评估不自动修改成果读数。") .font(.caption).foregroundStyle(.secondary)
            Button(original.archived ? "恢复到方向列表" : "归档这个方向") {
                if store.commit(kind: "goal.archive", id: original.id, { state in if let i = state.goals.firstIndex(where: { $0.id == original.id }) { state.goals[i].archived.toggle(); state.goals[i].revision = (state.goals[i].revision ?? 1) + 1 } }) { dismiss() }
            }
        }.navigationTitle("编辑方向").navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.editGoal(captured ?? original, title: title.trimmingCharacters(in: .whitespacesAndNewlines), intention: intention, due: due, assessment: assessment, cycleStart: hasCycleStart ? cycleStart : nil) { saved = true; EditorDrafts.remove(draftKey); dismiss() } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (hasCycleStart && cycleStart > due)) }
        }.onAppear { if !initialized { initialized = true; let draft = EditorDrafts.value(draftKey, as: RecordDraft<LifeGoal>.self); captured = draft?.original ?? original; let value = draft?.edited ?? original; title = value.title; intention = value.intention; due = value.due; assessment = value.assessment ?? ""; hasCycleStart = value.cycleStart != nil; cycleStart = value.cycleStart ?? min(Date(),due) } }
            .retainingDraft(draftKey, fields: draftFields, active: initialized && !saved)
        }
    }
}

struct KeyResultEditor: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let objectiveID: UUID
    var original: LifeKeyResult?
    @State private var title = ""
    @State private var baseline = "0"
    @State private var target = ""
    @State private var unit = "次"
    @State private var weight = "1"
    @State private var captured: LifeKeyResult?
    @State private var initialized = false
    @State private var saved = false
    var draftKey: String { "kr:" + (original?.id.uuidString ?? "new:" + objectiveID.uuidString) }
    var draftFields: [String:String] { ["title":title,"baseline":baseline,"target":target,"unit":unit,"weight":weight,"base":captured.flatMap { EditorDrafts.fields($0)["record"] } ?? ""] }
    var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && decimalValue(baseline)?.isFinite == true && decimalValue(target)?.isFinite == true && decimalValue(baseline) != decimalValue(target) && (1...10).contains(decimalValue(weight) ?? 0) }
    var body: some View {
        NavigationStack { Form {
            if let captured, let current = store.data.keyResults.first(where: { $0.id == captured.id }) { EditorConflictNotice(changed: captured != current, current: current.title + "\n" + current.baseline.formatted() + " → " + current.target.formatted() + " " + current.unit) { self.captured = current } }
            TextField("关键结果", text: $title, axis: .vertical).accessibilityIdentifier("krTitle")
            TextField("起点", text: $baseline).keyboardType(.numbersAndPunctuation)
            TextField("目标值", text: $target).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("krTarget")
            TextField("单位", text: $unit)
            TextField("权重（1至10）", text: $weight).keyboardType(.decimalPad)
            Text("记录的是累计当前值，不把多次读数相加。目标可以递增或递减；发生时间决定当前读数。") .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle(original == nil ? "添加关键结果" : "编辑关键结果").navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                guard valid else { return }; let success: Bool
                if let original = captured ?? original { success = store.editKeyResult(original, title: title, baseline: decimalValue(baseline)!, target: decimalValue(target)!, unit: unit, weight: decimalValue(weight)!) }
                else { success = store.addKeyResult(LifeKeyResult(objectiveID: objectiveID, title: title, baseline: decimalValue(baseline)!, target: decimalValue(target)!, unit: unit, weight: decimalValue(weight)!)) }
                if success { saved = true; EditorDrafts.remove(draftKey); dismiss() }
            }.disabled(!valid) }
        }.onAppear { if !initialized { initialized = true; captured = original; if let original { title = original.title; baseline = original.baseline.formatted(); target = original.target.formatted(); unit = original.unit; weight = original.weight.formatted() }; if let draft = EditorDrafts.load(draftKey) { title = draft["title"] ?? title; baseline = draft["baseline"] ?? baseline; target = draft["target"] ?? target; unit = draft["unit"] ?? unit; weight = draft["weight"] ?? weight; if let text = draft["base"], !text.isEmpty { captured = (try? JSONDecoder().decode(LifeKeyResult.self, from: Data(text.utf8))) ?? captured } } } }
            .retainingDraft(draftKey, fields: draftFields, active: initialized && !saved)
        }
    }
}

struct KeyResultDetailView: View {
    @Environment(LifeStore.self) private var store
    let resultID: UUID
    @State private var add = false
    @State private var edit = false
    var result: LifeKeyResult? { store.data.keyResults.first { $0.id == resultID } }
    var readings: [LifeMeasurement] { store.data.measurements.filter { ($0.keyResultID ?? $0.goalID) == resultID }.sorted { $0.effectiveAt > $1.effectiveAt } }
    var body: some View {
        if let result {
            List {
                Section { Text(result.title).font(.title2.bold()); LabeledContent("起点 → 目标", value: "\(result.baseline.formatted()) → \(result.target.formatted()) \(result.unit)")
                    if let current = store.data.currentMeasurement(for: result.id) { LabeledContent("当前累计成果", value: current.value.formatted() + " " + result.unit); Text(current.effectiveAt.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
                if readings.filter({ $0.rejectedAt == nil }).count > 1 {
                    Section("成果变化") { Chart(readings.filter { $0.rejectedAt == nil }) { reading in LineMark(x: .value("发生时间", reading.effectiveAt), y: .value("累计值", reading.value)); PointMark(x: .value("发生时间", reading.effectiveAt), y: .value("累计值", reading.value)) }.frame(height: 180).accessibilityLabel("累计成果历史，不对读数求和") }
                }
                Section { Button("记录当前成果", systemImage: "plus") { add = true } }
                Section { Button(result.archived ? "恢复这个关键结果" : "归档这个关键结果") { _ = store.commit(kind: "kr.archive", id: result.id) { state in guard let i = state.keyResults.firstIndex(where: { $0.id == result.id }) else { throw LifeError.invalidReference }; state.keyResults[i].archived.toggle(); state.keyResults[i].revision += 1 } }; Text("归档保留历史读数，并从当前目标加权进度中移出。") .font(.caption).foregroundStyle(.secondary) }
                Section("来源与历史") {
                    ForEach(readings) { reading in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reading.value.formatted() + " " + result.unit).font(.headline)
                            if !reading.note.isEmpty { Text(reading.note) }
                            Text("发生 " + reading.effectiveAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if reading.rejectedAt != nil { Text("此读数已撤销，历史保留").font(.caption).foregroundStyle(.secondary) }
                            else { Button("撤销此读数", role: .destructive) { store.rejectMeasurement(reading) }.font(.caption).buttonStyle(.borderless) }
                        }.padding(.vertical, 4)
                    }
                }
            }.navigationTitle("关键结果").navigationBarTitleDisplayMode(.inline).toolbar { Button("编辑") { edit = true } }
                .sheet(isPresented: $add) { MeasurementEditor(result: result) }
                .sheet(isPresented: $edit) { KeyResultEditor(objectiveID: result.objectiveID, original: result) }
        }
    }
}

struct MeasurementEditor: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let result: LifeKeyResult
    @State private var value = ""
    @State private var note = ""
    @State private var observedAt = Date()
    @State private var initialized = false
    @State private var saved = false
    var draftKey: String { "measurement:" + result.id.uuidString }
    var body: some View {
        NavigationStack { Form {
            Section { Text(result.title).font(.headline); TextField("当前累计值（\(result.unit)）", text: $value).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("measurementValue"); DatePicker("实际发生时间", selection: $observedAt, in: ...Date()); TextField("成果依据或说明", text: $note, axis: .vertical).lineLimit(4...8) }
            Section { Text("可以补录历史读数。当前值优先按发生时间选择，再按录入时间和稳定身份决定，不累加读数。") .foregroundStyle(.secondary) }
        }.navigationTitle("记录成果").navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { if let number = decimalValue(value), number.isFinite { var reading = LifeMeasurement(goalID: result.objectiveID, value: number, note: note); reading.keyResultID = result.id; reading.observedAt = observedAt; if store.addMeasurement(reading) { saved = true; EditorDrafts.remove(draftKey); dismiss() } } }.disabled(decimalValue(value)?.isFinite != true).accessibilityIdentifier("saveMeasurement") }
        }.onAppear { if !initialized { initialized = true; if let draft = EditorDrafts.load(draftKey) { value = draft["value"] ?? ""; note = draft["note"] ?? ""; if let number = draft["observedAt"].flatMap(Double.init) { observedAt = Date(timeIntervalSince1970:number) } } } }
            .retainingDraft(draftKey, fields: ["value":value,"note":note,"observedAt":String(observedAt.timeIntervalSince1970)], active: initialized && !saved)
        }
    }
}
