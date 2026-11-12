import SwiftUI
import UniformTypeIdentifiers

struct VaultSettingsView: View {
    @Environment(LifeStore.self) private var store
    @State private var service = LifeVault.shared
    @State private var folderPicker = false
    @State private var preview = false
    @State private var pendingFolder: URL?
    @State private var chooseBinding = false
    @State private var unbind = false
    var body: some View {
        List {
            Section("连接我的Obsidian Vault") {
                Text(service.binding == nil ? "尚未绑定目录" : "已保存所选目录的持续访问授权")
                Button("在“文件”中选择Vault文件夹", systemImage: "folder") { folderPicker = true }.disabled(service.busy)
                Text("需要能在iPhone“文件”里实际选到同一Vault，例如iCloud Drive中的Vault。只在电脑本地的目录不会因此自动传到手机。") .font(.caption).foregroundStyle(.secondary)
                if service.binding != nil { Button("停止发布并忘记目录授权", role: .destructive) { unbind = true }.disabled(service.busy) }
            }
            if service.binding != nil {
                Section("我决定披露什么") {
                    NavigationLink("逐项选择披露或撤回") { DisclosureSelectionView() }
                    Text("默认不披露。任务、计划、承诺、实际和日复盘可逐项选择，文字可单独关闭；精确位置、到访、路线、照片、EXIF、人物和私密目标不进入Vault。") .font(.subheadline)
                    if store.data.disclosure.grants != store.data.disclosure.lastPublishedGrants { Text("披露选择尚未发布。") .foregroundStyle(.orange) }
                    Button("完整预览并准备发布", systemImage: "eye") { Task { await service.makePreview(); if service.publicationReady { preview = true } } }.disabled(service.busy)
                    Text("撤回保留手机原记录，配套新插件在校验新代后清除当前视图。旧受管块须另行更新；手改内容、旧插件和外部/离线副本不冒充已抹去。") .font(.caption).foregroundStyle(.secondary)
                }
                Section("可编辑笔记中的派生块") {
                    Toggle("允许在Dayisle目录写入受管块", isOn: Binding(get: { service.binding?.projectionEnabled ?? false }, set: { service.setProjection($0) })).disabled(service.busy)
                    Text("开启后先发布新同步代，再核对和确认写入。只更新自己的标记块；块外文字保留。块被手改、重复或移走时会阻断，避免覆盖或复制你的内容。") .font(.caption).foregroundStyle(.secondary)
                    Button("核对派生块和笔记原文") { Task { await service.prepareProjection() } }.disabled(service.busy)
                    if service.projectionReady { Button("确认写入已核对的派生块") { Task { await service.writeProjection() } }.disabled(service.busy) }
                }
                Section("插件与复盘草稿") {
                    Button("安装或更新此Vault的朝屿插件") { Task { await service.installPlugin() } }.disabled(service.busy)
                    Text("只写入朝屿插件文件，不替你打开Obsidian受限模式。之后在Obsidian第三方插件里启用。手机插件只读；桌面插件可发草稿请求，由这里逐条确认。") .font(.caption).foregroundStyle(.secondary)
                    Button("读取待核对的复盘草稿") { Task { await service.scanRequests() } }.disabled(service.busy)
                    Button("重发已保存的结果回执") { Task { await service.resendReceipts() } }.disabled(service.busy)
                    ForEach(service.incoming) { request in NavigationLink { IncomingReviewView(service: service, request: request) } label: { VStack(alignment: .leading) { Text(request.day); Text(request.reflection).font(.caption).foregroundStyle(.secondary).lineLimit(2) } } }
                }
            }
            Section { if service.busy { ProgressView("正在处理所选目录…") }; if !service.message.isEmpty { Text(service.message).font(.subheadline).textSelection(.enabled) } }
        }.navigationTitle("Obsidian文件交换").navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { result in do { pendingFolder = try result.get(); chooseBinding = true } catch { service.message = "未选择目录，原绑定保留。" } }
            .confirmationDialog("绑定这个Vault目录", isPresented: $chooseBinding, titleVisibility: .visible) {
                Button("沿用原数据集绑定") { if let folder = pendingFolder { service.bind(folder) }; pendingFolder = nil }
                Button("在新的空目录建立独立数据集") { if let folder = pendingFolder { service.bind(folder, newDataset: true) }; pendingFolder = nil }
                Button("取消", role: .cancel) { pendingFolder = nil }
            } message: { Text("沿用要求原永久账本可达。新数据集只用于新的空目录，本机记录保留；不会删除旧Vault中的历史披露。") }
            .confirmationDialog("停止后续发布并忘记目录？", isPresented: $unbind, titleVisibility: .visible) { Button("停止并忘记授权", role: .destructive) { service.unbind() }; Button("取消", role: .cancel) {} } message: { Text("保留本机事实。已经披露到Vault及其他设备的文件不会自动撤回或删除。") }
            .sheet(isPresented:$preview) { DisclosurePublicationPreview(service:service) }
    }
}

struct IncomingReviewView: View {
    var service: LifeVault
    let request: IncomingReview
    @State private var accept = false
    var body: some View {
        List {
            Section(request.day) { Text(request.reflection).textSelection(.enabled); LabeledContent("归属时区", value: request.zone); LabeledContent("当前检查", value: request.validation) }
            Section("核对来源") { Text(request.clientID.uuidString.lowercased()).font(.caption.monospaced()); Text("仅在你认识这个插件实例并同意采用正文时确认。这次授权只针对眼前这份请求，不授予插件持续改写正式复盘的权限。") .font(.caption).foregroundStyle(.secondary) }
            Section {
                Button("采用这份草稿，建立正式日复盘") { accept = true }.disabled(service.busy || request.validation != "valid")
                Button("拒绝这份请求", role: .destructive) { Task { await service.process(request, accept: false) } }.disabled(service.busy)
                Text("已有正式复盘时拒绝覆盖；接受后仍需发布下一份完整同步代。") .font(.caption).foregroundStyle(.secondary)
                if !service.message.isEmpty { Text(service.message).font(.subheadline) }
            }
        }.navigationTitle("核对复盘草稿").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("确认来源与正文，并建立正式复盘？", isPresented: $accept, titleVisibility: .visible) { Button("确认采用") { Task { await service.process(request, accept: true) } }; Button("取消", role: .cancel) {} }
    }
}
