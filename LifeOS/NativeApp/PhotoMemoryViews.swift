import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct PreparedPhoto: Sendable {
    let data: Data
    let width: Int
    let height: Int
}
enum PhotoProcessor {
    static func prepare(_ bytes: Data) throws -> PreparedPhoto {
        guard bytes.count <= 25 * 1024 * 1024, let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw LifeError.message("图片无法读取或超过25MB。") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else { throw LifeError.message("图片像素过大。") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw LifeError.message("无法处理这张图片。") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw LifeError.invalidValue }
        // Encode only decoded pixels. No source metadata, GPS, filename or EXIF is copied.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 2_000_000 else { throw LifeError.message("处理后的照片仍超过2MB，未保存。") }
        return PreparedPhoto(data: output as Data, width: image.width, height: image.height)
    }
    static func isSanitizedJPEG(_ bytes: Data, width: Int, height: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              props[kCGImagePropertyGPSDictionary] == nil, props[kCGImagePropertyExifDictionary] == nil,
              props[kCGImagePropertyPixelWidth] as? Int == width, props[kCGImagePropertyPixelHeight] as? Int == height else { return false }
        return true
    }
}

struct PhotoStrip: View {
    @Environment(LifeStore.self) private var store
    let photos: [LifePhoto]
    @State private var deleting: LifePhoto?
    var body: some View {
        ForEach(photos) { photo in
            VStack(alignment: .leading, spacing: 8) {
                if let bytes = store.photoData(photo.id), let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 16)) }
                else { Label("照片副本暂不可读，文字仍保留", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                HStack { VStack(alignment: .leading) { if !photo.caption.isEmpty { Text(photo.caption) }; Text(photo.capturedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive) { deleting = photo } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("删除照片副本") }
            }.padding(.vertical, 5)
        }
        .confirmationDialog("删除朝屿中的照片副本？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除副本", role: .destructive) { if let photo = deleting { store.deletePhoto(photo) }; deleting = nil }; Button("取消", role: .cancel) {}
        } message: { Text("不会删除系统相册中的原图。") }
    }
}

struct AddPhotoView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var memoryID: UUID?
    var tripID: UUID?
    @State private var selection: PhotosPickerItem?
    @State private var prepared: PreparedPhoto?
    @State private var caption = ""
    @State private var date = Date()
    @State private var loading = false
    @State private var issue: String?
    var body: some View {
        NavigationStack { Form {
            Section {
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) { Label("主动选择一张照片", systemImage: "photo.badge.plus") }
                if loading { ProgressView("正在生成不含位置元数据的副本…") }
                if let prepared, let image = UIImage(data: prepared.data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300) }
                if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            }
            Section { TextField("照片说明", text: $caption, axis: .vertical); DatePicker("这张记忆的日期", selection: $date) }
            Section { Text("只保存你选中的这一张的压缩副本，不扫描相册、不读取照片位置或拍摄时间，不上传。全部照片副本总计上限64MB。") .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("一张生活记忆").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { if let prepared { let photo = LifePhoto(caption: caption, capturedAt: date, memoryID: memoryID, tripID: tripID, sha256: LifeStore.fingerprint(prepared.data), width: prepared.width, height: prepared.height, bytes: prepared.data.count); if store.addPhoto(photo, bytes: prepared.data) { dismiss() } } }.disabled(prepared == nil || loading) } }
            .task(id: selection) {
                prepared = nil; issue = nil
                guard let selection else { return }; loading = true; defer { loading = false }
                do {
                    guard let bytes = try await selection.loadTransferable(type: Data.self) else { throw LifeError.invalidValue }
                    let result = try await Task.detached(priority: .userInitiated) { try PhotoProcessor.prepare(bytes) }.value
                    guard !Task.isCancelled else { return }; prepared = result
                } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            }
        }
    }
}

struct MemoryDetailView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID
    @State private var title = ""
    @State private var note = ""
    @State private var people = ""
    @State private var date = Date()
    @State private var favorite = false
    @State private var tripID: UUID?
    @State private var knownID: UUID?
    @State private var addPhoto = false
    @State private var delete = false
    @State private var initialized = false
    var memory: LifePlace? { store.data.places.first { $0.id == memoryID } }
    var body: some View {
        if let memory {
            Form {
                Section { TextField("记忆标题", text: $title, axis: .vertical); DatePicker("记忆时间", selection: $date); TextField("当时的故事", text: $note, axis: .vertical).lineLimit(5...15); TextField("人物别名，用逗号分开", text: $people); Toggle("收藏这段记忆", isOn: $favorite) }
                Section("关联") {
                    Picker("稳定地点", selection: $knownID) { Text("独立地点记忆").tag(UUID?.none); ForEach(store.data.knownPlaces) { Text($0.title).tag(Optional($0.id)) } }
                    Picker("行程", selection: $tripID) { Text("不属于行程").tag(UUID?.none); ForEach(store.data.trips) { Text($0.title).tag(Optional($0.id)) } }
                    if let visitID = memory.visitID { NavigationLink("查看到访来源") { VisitDetailView(visitID: visitID) } }
                }
                Section("照片") { PhotoStrip(photos: store.data.photos.filter { $0.memoryID == memoryID }); Button("添加一张照片", systemImage: "photo.badge.plus") { addPhoto = true } }
                Section { Text("手动记忆不会被当作自动到访或统计为去过的城市；人物仅为你填写的别名。") .font(.caption).foregroundStyle(.secondary); Button("删除这段记忆及其照片副本", role: .destructive) { delete = true } }
            }.navigationTitle("生活记忆").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存") { if store.saveMemory(memory, title: title, note: note, favorite: favorite, tripID: tripID, people: aliases(people), occurredAt: date, knownPlaceID: knownID) { EditorDrafts.remove("memory:" + memoryID.uuidString) } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                .onAppear { if !initialized { initialized = true; title = memory.title; note = memory.note; people = (memory.people ?? []).joined(separator: "，"); date = memory.occurredAt; favorite = memory.favorite ?? false; tripID = memory.tripID; knownID = memory.knownPlaceID; if let draft = EditorDrafts.load("memory:" + memoryID.uuidString) { title = draft["title"] ?? title; note = draft["note"] ?? note; people = draft["people"] ?? people } } }
                .onDisappear { if let saved = self.memory, saved.title != title || saved.note != note || (saved.people ?? []) != aliases(people) { EditorDrafts.save("memory:" + memoryID.uuidString, fields: ["title": title, "note": note, "people": people]) } }
                .sheet(isPresented: $addPhoto) { AddPhotoView(memoryID: memoryID, tripID: tripID) }
                .confirmationDialog("删除这段记忆和其照片副本？", isPresented: $delete, titleVisibility: .visible) { Button("删除", role: .destructive) { store.deletePlace(memory); dismiss() }; Button("取消", role: .cancel) {} } message: { Text("原始到访、路线、行程和系统相册原图保留。") }
        } else { ContentUnavailableView("记忆已删除", systemImage: "sparkles") }
    }
}

func aliases(_ text: String) -> [String] { text.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
