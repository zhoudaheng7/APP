import SwiftUI

struct PhotoDetailEditor: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let photo: LifePhoto
    @State private var draft: RecordDraft<LifePhoto>?
    @State private var saved = false
    var key: String { "photo:" + photo.id.uuidString }
    var current: LifePhoto? { store.data.photos.first { $0.id == photo.id } }
    var body: some View {
        NavigationStack { Group {
            if let value = draft,let current {
                Form {
                    EditorConflictNotice(changed:current != value.original,current:current.caption + "\n" + current.capturedAt.formatted()) { draft?.original = current }
                    Section { TextField("照片说明",text:binding(\.caption,fallback:value.edited),axis:.vertical); DatePicker("记忆日期",selection:binding(\.capturedAt,fallback:value.edited)) }
                    Section("关联") {
                        Picker("地点记忆",selection:binding(\.memoryID,fallback:value.edited)) { Text("独立照片").tag(UUID?.none); ForEach(store.data.places) { Text($0.title).tag(Optional($0.id)) } }
                        Picker("行程",selection:binding(\.tripID,fallback:value.edited)) { Text("不关联").tag(UUID?.none); ForEach(store.data.trips) { Text($0.title).tag(Optional($0.id)) } }
                    }
                    Text("只修改本机照片记忆，系统相册原图与已保存故事快照保留。") .font(.caption).foregroundStyle(.secondary)
                }.retainingDraft(key,fields:EditorDrafts.fields(value),active:!saved && value.edited != current)
            } else { ContentUnavailableView("照片记录暂不可编辑",systemImage:"photo") }
        }.navigationTitle("编辑照片记忆").toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement:.confirmationAction) { Button("保存") {
                if let value = draft,store.editPhoto(value.original,edited:value.edited) { saved = true; EditorDrafts.remove(key); dismiss() }
            }.disabled(draft == nil || current == nil) }
        }.onAppear { if draft == nil { draft = EditorDrafts.value(key,as:RecordDraft<LifePhoto>.self) ?? RecordDraft(original:photo,edited:photo) } }
        }
    }
    func binding<Value>(_ path: WritableKeyPath<LifePhoto,Value>,fallback: LifePhoto) -> Binding<Value> { Binding(get:{ (draft?.edited ?? fallback)[keyPath:path] },set:{ draft?.edited[keyPath:path] = $0 }) }
}

extension LifeStore {
    func editPhoto(_ original: LifePhoto,edited: LifePhoto) -> Bool {
        commit(kind:"photo.edit",id:original.id) { state in
            guard let i = state.photos.firstIndex(where:{ $0.id == original.id }),state.photos[i] == original,original.id == edited.id,original.sha256 == edited.sha256,original.bytes == edited.bytes,original.width == edited.width,original.height == edited.height else { throw LifeError.message("照片记录已改变，请核对后重试。") }
            try state.audit(original,id:original.id,kind:"photo",revision:Int64(state.amendments.filter { $0.entityID == original.id }.count + 1))
            state.photos[i] = edited
        }
    }
}
