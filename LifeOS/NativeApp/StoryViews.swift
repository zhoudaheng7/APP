import SwiftUI
import PDFKit

struct StoryListView: View {
    @Environment(LifeStore.self) private var store
    @State private var add = false
    var body: some View {
        List {
            Section { Text("先选择记录、核对脱敏预览，再保存一份不可变故事。生成过程在本机，不调用写作服务。") .font(.subheadline).foregroundStyle(.secondary); Button("制作一份故事",systemImage:"book.pages") { add = true } }
            ForEach(store.data.stories) { story in NavigationLink { StoryDetailView(storyID:story.id) } label: { VStack(alignment:.leading) { Text(story.title).font(.headline); Text("第\(story.version)版 · \(story.sections.count)段记录 · \(story.photos.count)张照片").font(.caption).foregroundStyle(.secondary) } } }
        }.navigationTitle("自己的故事").sheet(isPresented:$add) { NewStoryView() }
    }
}

struct StoryChoiceRow: View {
    var label: String
    var key: String
    @Binding var choice: StorySelection
    var body: some View { Toggle(label,isOn:Binding(get:{ choice.sources.contains(key) },set:{ enabled in if enabled { if choice.sources.count < 100 { choice.sources.append(key) } } else { choice.sources.removeAll { $0 == key } } })) }
}

struct NewStoryView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var previous: StoryRecord?
    @State private var choice = StorySelection()
    @State private var initialized = false
    @State private var saved = false
    @State private var preview: StoryRecord?
    @State private var sourceFingerprint = ""
    var draftKey: String { "new-story:" + (previous?.id.uuidString ?? "independent") }
    var body: some View {
        NavigationStack { Form {
            Section("写给自己的话") { TextField("故事名称",text:$choice.title).accessibilityIdentifier("storyTitle"); TextField("用自己的话讲述这段日子",text:$choice.narrative,axis:.vertical).lineLimit(5...12).accessibilityIdentifier("storyNarrative") }
            Section("本次带出什么") {
                Toggle("带出日期和时间",isOn:$choice.dates); Toggle("带出地点及行程标题",isOn:$choice.places); Toggle("带出已记录的人物别名",isOn:$choice.people); Toggle("带出所选记录原文和照片说明",isOn:$choice.sourceText)
                Text("关闭地点或人物时会替换已登记的名称；无法识别所有自由文字中的隐私。照片本身可能含人脸、门牌与地标，分享前逐项核对预览。不会导出精确坐标或路线图。") .font(.caption).foregroundStyle(.secondary)
            }
            Section("选择复盘") { ForEach(store.data.reviews.sorted { $0.day > $1.day }.prefix(300)) { r in StoryChoiceRow(label:r.day + (r.canonical == false ? " · 附加草稿" : ""),key:"review:" + r.id.uuidString,choice:$choice) } }
            Section("选择生活记忆") { ForEach(store.data.places.prefix(300)) { r in StoryChoiceRow(label:r.title,key:"memory:" + r.id.uuidString,choice:$choice) } }
            Section("选择行程与路线") {
                ForEach(store.data.trips.prefix(200)) { r in StoryChoiceRow(label:r.title,key:"trip:" + r.id.uuidString,choice:$choice) }
                ForEach(store.data.routes.prefix(200)) { r in StoryChoiceRow(label:r.title,key:"route:" + r.id.uuidString,choice:$choice) }
            }
            Section("主动选照片 · 最多3张") { ForEach(store.data.photos.prefix(300)) { photo in Toggle(photo.caption.isEmpty ? "一张照片 · " + photo.capturedAt.formatted(date:.abbreviated,time:.omitted) : photo.caption,isOn:Binding(get:{ choice.photos.contains(photo.id) },set:{ enabled in if enabled { if choice.photos.count < 3 { choice.photos.append(photo.id) } } else { choice.photos.removeAll { $0 == photo.id } } })) } }
            Section { Button("生成本次预览",systemImage:"eye") {
                do { preview = try store.makeStory(choice); sourceFingerprint = try Self.fingerprint(store.data) } catch { store.error = error.localizedDescription }
            }.disabled(choice.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || choice.sources.count > 100).accessibilityIdentifier("storyPreview")
                Text("保存的是本次确认的快照。以后修改、删除原记录，不会静默改写已保存故事；可单独删除故事。已分享出去的PDF由接收方保留，无法远程撤回。") .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(previous == nil ? "制作故事" : "制作下一版").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("关闭") { dismiss() } } }
            .onAppear { if !initialized { initialized = true; if let draft = EditorDrafts.value(draftKey,as:StorySelection.self) { choice = draft } else if let previous { choice.title = previous.title; choice.narrative = previous.narrative; choice.previousID = previous.id } } }
            .retainingDraft(draftKey,fields:EditorDrafts.fields(choice),active:initialized && !saved)
            .sheet(item:$preview) { story in NavigationStack { StoryPreviewContent(story:story).navigationTitle("核对本次故事").toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("返回修改") { preview = nil } }
                ToolbarItem(placement:.confirmationAction) { Button("确认并保存") {
                    do {
                        guard try Self.fingerprint(store.data) == sourceFingerprint else { throw LifeError.message("来源记录已变化，请返回重新生成预览。") }
                        if store.saveStory(story) { saved = true; EditorDrafts.remove(draftKey); preview = nil; dismiss() }
                    } catch { store.error = error.localizedDescription }
                }.accessibilityIdentifier("saveStory") }
            } } }
        }
    }
    static func fingerprint(_ snapshot: LifeSnapshot) throws -> String { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return LifeStore.fingerprint(try encoder.encode(snapshot)) }
}

struct StoryPreviewContent: View {
    let story: StoryRecord
    var body: some View {
        List {
            Section(story.title) { Text("第\(story.version)版").font(.caption); if !story.narrative.isEmpty { Text(story.narrative).textSelection(.enabled) } }
            ForEach(Array(story.sections.enumerated()),id:\.offset) { _,section in Section(section.title) { Text(section.text).textSelection(.enabled) } }
            ForEach(story.photos) { photo in Section { if let image = UIImage(data:photo.jpeg) { Image(uiImage:image).resizable().scaledToFit() }; if !photo.caption.isEmpty { Text(photo.caption) } } }
            Section { Text("以上是PDF中的内容。另含固定来源说明与页码，不含内部记录ID和来源坐标。") .font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct StoryDetailView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let storyID: UUID
    @State private var export: PrivateExport?
    @State private var exportURL: URL?
    @State private var delete = false
    @State private var next = false
    @State private var pdf: Data?
    var story: StoryRecord? { store.data.stories.first { $0.id == storyID } }
    var body: some View {
        if let story {
            StoryPreviewContent(story:story).navigationTitle("故事快照").navigationBarTitleDisplayMode(.inline).toolbar {
                Menu {
                    Button("查看PDF",systemImage:"doc.richtext") { do { pdf = try StoryPDF.render(story) } catch { store.error = error.localizedDescription } }
                    Button("导出PDF",systemImage:"square.and.arrow.up") {
                        do { let url = try PrivateArtifacts.export(StoryPDF.render(story),name:"Dayisle-story.pdf"); exportURL = url; export = PrivateExport(url:url) } catch { store.error = error.localizedDescription }
                    }.disabled(exportURL != nil)
                    Button("新建下一版",systemImage:"doc.badge.plus") { next = true }
                    Button("删除这份故事",role:.destructive) { delete = true }
                } label: { Image(systemName:"ellipsis.circle") }.accessibilityIdentifier("storyActions").accessibilityLabel("故事操作")
            }
            .sheet(item:$export,onDismiss:{ if let url = exportURL { do { try PrivateArtifacts.finishExport(url) } catch { store.error = error.localizedDescription } }; exportURL = nil }) { PrivateShareSheet(url:$0.url) }
            .sheet(isPresented:$next) { NewStoryView(previous:story) }
            .sheet(isPresented:Binding(get:{ pdf != nil },set:{ if !$0 { pdf = nil } })) { NavigationStack { if let pdf { StoryPDFPreview(data:pdf).navigationTitle("PDF预览").toolbar { Button("完成") { self.pdf = nil } } } } }
            .confirmationDialog("删除这份故事快照？",isPresented:$delete,titleVisibility:.visible) { Button("删除故事",role:.destructive) { store.deleteStory(story); dismiss() }; Button("取消",role:.cancel) {} } message: { Text("原记录和其他故事版本保留，已分享的PDF不会被远程删除。") }
        } else { ContentUnavailableView("故事已删除",systemImage:"book.closed") }
    }
}

struct StoryPDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.document = PDFDocument(data:data); return view }
    func updateUIView(_ view: PDFView,context: Context) { }
}
