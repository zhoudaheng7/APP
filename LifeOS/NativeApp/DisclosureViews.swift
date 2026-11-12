import SwiftUI

private struct DisclosureSource: Identifiable {
    let entityType: String
    let entityID: UUID
    let title: String
    let detail: String
    var id: String { entityType + ":" + entityID.wire }
}
struct DisclosureSelectionView: View {
    @Environment(LifeStore.self) private var store
    @State private var search = ""
    @State private var scope = "all"
    private var rows: [DisclosureSource] {
        store.data.wireEntities().compactMap { row in
            guard let type = row["entityType"] as? String, let rawID = row["entityID"] as? String, let id = UUID(uuidString:rawID) else { return nil }
            let title = row["title"] as? String ?? row["dayKey"] as? String ?? "未命名记录"
            let detail = row["reflection"] as? String ?? row["plannedStart"] as? String ?? row["actualStart"] as? String ?? row["start"] as? String ?? ""
            return DisclosureSource(entityType:type,entityID:id,title:title,detail:detail)
        }.filter { (scope == "all" || $0.entityType == scope) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        List {
            Section("由你逐项选择") {
                Text("默认不披露任何记录。选中一项会发布它的同步身份、状态、时间；可以单独关闭标题或复盘正文。时间和状态也可能敏感，请先核对。")
                LabeledContent("当前选择",value:String((store.data.disclosure.grants ?? []).count) + " 条")
                Text("这里保存的是尚待发布的选择。回到上一页完整预览并确认发布后，配套插件才会采用新范围。取消选择保留手机原记录。") .font(.caption).foregroundStyle(.secondary)
                Button("取消全部选择（尚未发布）",role:.destructive) { _ = store.commit(kind:"disclosure.selection",id:store.data.disclosure.datasetID) { $0.disclosure.grants = [] } }
                Picker("记录类别",selection:$scope) { Text("全部").tag("all"); Text("任务").tag("Task"); Text("私人计划").tag("DraftPlan"); Text("日历承诺").tag("CalendarCommitment"); Text("实际投入").tag("ActualSession"); Text("日复盘").tag("DailyReview") }
            }
            ForEach(rows) { row in
                Section {
                    Toggle(isOn:Binding(get:{ permission(row) != nil },set:{ setPermission(row,enabled:$0) })) { VStack(alignment:.leading) { Text(row.title); if !row.detail.isEmpty { Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) } } }
                    if let grant = permission(row) { Toggle(row.entityType == "DailyReview" ? "披露复盘正文":"披露标题文字",isOn:Binding(get:{ permission(row)?.text ?? false },set:{ setPermission(row,enabled:true,text:$0) })); if !grant.text { Text("仅发布必要身份、时间和状态，不发布这条文字。") .font(.caption).foregroundStyle(.secondary) } }
                }
            }
            if rows.isEmpty { ContentUnavailableView("没有匹配记录",systemImage:"eye.slash") }
        }.navigationTitle("披露与撤回选择").navigationBarTitleDisplayMode(.inline).searchable(text:$search,prompt:"搜索本机记录")
    }
    private func permission(_ row: DisclosureSource) -> DisclosureGrant? { store.data.disclosure.grants?.first { $0.id == row.id } }
    private func setPermission(_ row: DisclosureSource, enabled: Bool, text: Bool = true) {
        _ = store.commit(kind:"disclosure.selection",id:store.data.disclosure.datasetID) { state in
            var choices = state.disclosure.grants ?? []; choices.removeAll { $0.id == row.id }
            if enabled { choices.append(DisclosureGrant(entityType:row.entityType,entityID:row.entityID,text:text)) }
            state.disclosure.grants = choices.sorted { $0.id < $1.id }
        }
    }
}

struct DisclosurePublicationPreview: View {
    @Environment(\.dismiss) private var dismiss
    var service: LifeVault
    var body: some View {
        NavigationStack { List {
            Section("本次实际发布内容") {
                Text(service.message)
                if let date = service.previewDate { Text("预览生成于 " + date.formatted(date:.abbreviated,time:.standard)).font(.caption).foregroundStyle(.secondary) }
                Text("下方是完整的已选记录，含你同意发布的文字、状态和时间；不是今日摘要。同步身份、修订和摘要另用于校验，撤回后仍保留已公开身份的最小历史。") .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(service.previewRecords) { record in
                Section(record.kind) {
                    Text(record.title).font(.headline)
                    if let reflection = record.reflection { Text(reflection).textSelection(.enabled) }
                    ForEach(record.fields) { field in LabeledContent(field.id,value:field.value) }
                }
            }
            Section("确认这份预览") {
                Text("确认只发布本次预览。记录或选择变化会要求重新预览；旧笔记受管块还需另行核对并更新。停止发布不等于撤回，外部/离线副本无法自动抹去。") .font(.caption).foregroundStyle(.secondary)
                Button("确认发布这份授权视图") { Task { await service.publish(); if !service.publicationReady { dismiss() } } }.disabled(service.busy || !service.publicationReady)
                if service.busy { ProgressView() }
            }
        }.navigationTitle("完整披露预览").navigationBarTitleDisplayMode(.inline).toolbar { Button("关闭") { dismiss() }.disabled(service.busy) } }
    }
}
