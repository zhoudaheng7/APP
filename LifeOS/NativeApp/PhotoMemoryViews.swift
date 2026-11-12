import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct PreparedPhoto: Sendable {
    let data: Data
    let width: Int
    let height: Int
}
struct PhotoEditorDraft: Codable {
    var jpeg: Data?
    var width: Int?
    var height: Int?
    var caption: String
    var date: Date
    var memoryID: UUID?
    var tripID: UUID?
}
enum PhotoProcessor {
    static func prepare(_ bytes: Data,maxDimension: Int = 1600) throws -> PreparedPhoto {
        guard (1...1600).contains(maxDimension) else { throw LifeError.invalidValue }
        guard bytes.count <= 25 * 1024 * 1024, let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw LifeError.message("图片无法读取或超过25MB。") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else { throw LifeError.message("图片像素过大。") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxDimension, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw LifeError.message("无法处理这张图片。") }
        guard let colorSpace = CGColorSpace(name:CGColorSpace.sRGB), let context = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw LifeError.invalidValue }
        context.setFillColor(CGColor(srgbRed:1,green:1,blue:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:CGFloat(image.width),height:CGFloat(image.height)))
        context.draw(image,in:CGRect(x:0,y:0,width:CGFloat(image.width),height:CGFloat(image.height)))
        guard let normalized = context.makeImage() else { throw LifeError.invalidValue }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw LifeError.invalidValue }
        // Encode only decoded pixels. No source metadata, GPS, filename or EXIF is copied.
        CGImageDestinationAddImage(destination, normalized, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 2_000_000 else { throw LifeError.message("处理后的照片仍超过2MB，未保存。") }
        return PreparedPhoto(data: output as Data, width: image.width, height: image.height)
    }
    static func isSanitizedJPEG(_ bytes: Data, width: Int, height: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              props[kCGImagePropertyGPSDictionary] == nil,
              props[kCGImagePropertyExifAuxDictionary] == nil, props[kCGImagePropertyIPTCDictionary] == nil, props[kCGImagePropertyTIFFDictionary] == nil,
              props[kCGImagePropertyPixelWidth] as? Int == width, props[kCGImagePropertyPixelHeight] as? Int == height else { return false }
        let allowed: Set<String> = ["ColorModel","Depth","PixelWidth","PixelHeight","ProfileName","{JFIF}","{Exif}","Orientation"]
        guard Set(props.keys.map { $0 as String }).isSubset(of:allowed), (props[kCGImagePropertyDepth] as? Int) == 8,
              (props[kCGImagePropertyColorModel] as? String) == "RGB",
              (props[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
              ["sRGB IEC61966-2.1","sRGB"].contains(props[kCGImagePropertyProfileName] as? String ?? "") else { return false }
        if let exif = props[kCGImagePropertyExifDictionary] as? [String:Any] {
            guard Set(exif.keys).isSubset(of:["ColorSpace","PixelXDimension","PixelYDimension"]),
                  (exif["ColorSpace"] as? Int ?? 1) == 1,
                  (exif["PixelXDimension"] as? Int ?? width) == width,
                  (exif["PixelYDimension"] as? Int ?? height) == height else { return false }
        }
        if let jfif = props[kCGImagePropertyJFIFDictionary] as? [String:Any] {
            guard Set(jfif.keys).isSubset(of:["DensityUnit","JFIFVersion","XDensity","YDensity"]) else { return false }
        }
        return true
    }
}

struct PhotoStrip: View {
    @Environment(LifeStore.self) private var store
    let photos: [LifePhoto]
    @State private var deleting: LifePhoto?
    @State private var editing: LifePhoto?
    var body: some View {
        ForEach(photos) { photo in
            VStack(alignment: .leading, spacing: 8) {
                if let bytes = store.photoData(photo.id), let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 16)) }
                else { Label("照片副本暂不可读，文字仍保留", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                HStack { VStack(alignment: .leading) { if !photo.caption.isEmpty { Text(photo.caption) }; Text(photo.capturedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { editing = photo } label: { Image(systemName:"pencil") }.buttonStyle(.borderless).accessibilityLabel("编辑照片记忆"); Button(role: .destructive) { deleting = photo } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("删除照片副本") }
            }.padding(.vertical, 5)
        }
        .confirmationDialog("删除朝屿中的照片副本？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除副本", role: .destructive) { if let photo = deleting { store.deletePhoto(photo) }; deleting = nil }; Button("取消", role: .cancel) {}
        } message: { Text("不会删除系统相册中的原图。") }
        .sheet(item:$editing) { PhotoDetailEditor(photo:$0) }
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
    @State private var selectedMemoryID: UUID?
    @State private var selectedTripID: UUID?
    @State private var initialized = false
    @State private var saved = false
    var draftKey: String { "new-photo:" + (memoryID?.uuidString ?? "independent") + ":" + (tripID?.uuidString ?? "independent") }
    var draft: PhotoEditorDraft { PhotoEditorDraft(jpeg:prepared?.data,width:prepared?.width,height:prepared?.height,caption:caption,date:date,memoryID:selectedMemoryID,tripID:selectedTripID) }
    var body: some View {
        NavigationStack { Form {
            Section {
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) { Label("主动选择一张照片", systemImage: "photo.badge.plus") }
                if loading { ProgressView("正在生成不含位置元数据的副本…") }
                if let prepared, let image = UIImage(data: prepared.data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300) }
                if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            }
            Section { TextField("照片说明", text: $caption, axis: .vertical); DatePicker("这张记忆的日期", selection: $date) }
            Section("由你确认关联") {
                Picker("地点记忆", selection: $selectedMemoryID) { Text("不关联地点").tag(UUID?.none); ForEach(store.data.places) { Text($0.title).tag(Optional($0.id)) } }
                Picker("行程", selection: $selectedTripID) { Text("独立照片记忆").tag(UUID?.none); ForEach(store.data.trips) { Text($0.title).tag(Optional($0.id)) } }
                Text("关联只组织记忆，不自动确认到访，也不读取照片里的定位。") .font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("只保存你选中的这一张的压缩副本，不扫描相册、不读取照片位置或拍摄时间，不上传。全部照片副本总计上限64MB。") .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("一张生活记忆").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { if let prepared { let photo = LifePhoto(caption: caption, capturedAt: date, memoryID: selectedMemoryID, tripID: selectedTripID, sha256: LifeStore.fingerprint(prepared.data), width: prepared.width, height: prepared.height, bytes: prepared.data.count); if store.addPhoto(photo, bytes: prepared.data) { saved = true; EditorDrafts.remove(draftKey); dismiss() } } }.disabled(prepared == nil || loading) } }
            .onAppear { if !initialized { initialized = true; selectedMemoryID = memoryID; selectedTripID = tripID
                if let d = EditorDrafts.value(draftKey,as:PhotoEditorDraft.self) { caption = d.caption; date = d.date; selectedMemoryID = d.memoryID; selectedTripID = d.tripID; if let bytes = d.jpeg,let w = d.width,let h = d.height,bytes.count <= 2_000_000,PhotoProcessor.isSanitizedJPEG(bytes,width:w,height:h) { prepared = PreparedPhoto(data:bytes,width:w,height:h) } }
            } }
            .retainingDraft(draftKey,fields:EditorDrafts.fields(draft),active:initialized && !saved && (prepared != nil || !caption.isEmpty))
            .task(id: selection) {
                guard let selection else { return }; prepared = nil; issue = nil; loading = true; defer { loading = false }
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
    @State private var original: LifePlace?
    @State private var timeZone: String?
    var memory: LifePlace? { store.data.places.first { $0.id == memoryID } }
    var draftKey: String { "memory:" + memoryID.uuidString }
    var edited: LifePlace? { guard var value = original else { return nil }; value.title = title; value.note = note; value.people = aliases(people); value.occurredAt = date; value.favorite = favorite; value.tripID = tripID; value.knownPlaceID = knownID; value.timeZone = timeZone; return value }
    var draftFields: [String:String] { guard let original, let edited else { return [:] }; return EditorDrafts.fields(RecordDraft(original: original, edited: edited)) }
    var body: some View {
        if let memory {
            Form {
                EditorConflictNotice(changed: original.map { $0 != memory } ?? false, current: memory.title + "\n" + memory.note + "\n" + memory.occurredAt.formatted()) { original = memory }
                Section { TextField("记忆标题", text: $title, axis: .vertical); DatePicker("记忆时间", selection: $date); TextField("当时的故事", text: $note, axis: .vertical).lineLimit(5...15); TextField("人物别名，用逗号分开", text: $people); Toggle("收藏这段记忆", isOn: $favorite) }
                Section { AttributionZonePicker(zone:$timeZone); Text(recordTimeText(date,zone:timeZone)).font(.caption).foregroundStyle(.secondary) }
                Section("关联") {
                    Picker("稳定地点", selection: $knownID) { Text("独立地点记忆").tag(UUID?.none); ForEach(store.data.knownPlaces) { Text($0.title).tag(Optional($0.id)) } }
                    Picker("行程", selection: $tripID) { Text("不属于行程").tag(UUID?.none); ForEach(store.data.trips) { Text($0.title).tag(Optional($0.id)) } }
                    if let visitID = memory.visitID { NavigationLink("查看到访来源") { VisitDetailView(visitID: visitID) } }
                }
                Section("照片") { PhotoStrip(photos: store.data.photos.filter { $0.memoryID == memoryID }); Button("添加一张照片", systemImage: "photo.badge.plus") { addPhoto = true } }
                Section { Text("手动记忆不会被当作自动到访或统计为去过的城市；人物仅为你填写的别名。") .font(.caption).foregroundStyle(.secondary); Button("删除这段记忆及其照片副本", role: .destructive) { delete = true } }
            }.navigationTitle("生活记忆").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("保存") { if store.saveMemory(original ?? memory, title: title, note: note, favorite: favorite, tripID: tripID, people: aliases(people), occurredAt: date, knownPlaceID: knownID, timeZone:timeZone) { original = self.memory; EditorDrafts.remove(draftKey) } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                .environment(\.timeZone,timeZone.flatMap(TimeZone.init(identifier:)) ?? .current)
                .onAppear { if !initialized { initialized = true; let saved = EditorDrafts.value(draftKey, as: RecordDraft<LifePlace>.self); original = saved?.original ?? memory; let value = saved?.edited ?? memory; title = value.title; note = value.note; people = (value.people ?? []).joined(separator: "，"); date = value.occurredAt; favorite = value.favorite ?? false; tripID = value.tripID; knownID = value.knownPlaceID; timeZone = value.timeZone; if saved == nil, let draft = EditorDrafts.load(draftKey) { title = draft["title"] ?? title; note = draft["note"] ?? note; people = draft["people"] ?? people } } }
                .retainingDraft(draftKey, fields: draftFields, active: initialized && self.memory != nil && edited != self.memory)
                .sheet(isPresented: $addPhoto) { AddPhotoView(memoryID: memoryID, tripID: tripID) }
                .confirmationDialog("删除这段记忆和其照片副本？", isPresented: $delete, titleVisibility: .visible) { Button("删除", role: .destructive) { store.deletePlace(memory); dismiss() }; Button("取消", role: .cancel) {} } message: { Text("原始到访、路线、行程和系统相册原图保留。") }
        } else { ContentUnavailableView("记忆已删除", systemImage: "sparkles") }
    }
}

struct NewMemoryView: View {
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var seed: LifePlace
    var contextKey: String
    @State private var draft: LifePlace?
    @State private var saved = false
    var body: some View {
        NavigationStack { Group {
            if let value = draft {
                Form {
                    TextField("记忆标题", text: binding(\.title, fallback: value)).accessibilityIdentifier("memoryTitle")
                    DatePicker("记忆时间", selection: binding(\.occurredAt, fallback: value))
                    AttributionZonePicker(zone:binding(\.timeZone,fallback:value))
                    Text(recordTimeText(value.occurredAt,zone:value.timeZone)).font(.caption).foregroundStyle(.secondary)
                    TextField("留下当时的心情或故事", text: binding(\.note, fallback: value), axis: .vertical).lineLimit(5...12)
                    Text("保存后可继续添加照片与关联。关闭会保留本机草稿；点击保存前，不创建记忆、到访或活动。") .font(.caption).foregroundStyle(.secondary)
                }.environment(\.timeZone,value.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current).retainingDraft(contextKey, fields: EditorDrafts.fields(value), active: !saved)
            } else { ProgressView() }
        }.navigationTitle("记住这一刻").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    if var value = draft { value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines); if store.addPlace(value) { saved = true; EditorDrafts.remove(contextKey); dismiss() } }
                }.disabled(draft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false).accessibilityIdentifier("saveMemory") }
            }.onAppear { if draft == nil { draft = EditorDrafts.value(contextKey, as: LifePlace.self) ?? seed } }
        }
    }
    func binding<Value>(_ path: WritableKeyPath<LifePlace,Value>, fallback: LifePlace) -> Binding<Value> {
        Binding(get: { (draft ?? fallback)[keyPath:path] }, set: { draft?[keyPath:path] = $0 })
    }
}

func aliases(_ text: String) -> [String] { text.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
