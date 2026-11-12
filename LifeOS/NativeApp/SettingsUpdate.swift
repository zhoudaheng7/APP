import SwiftUI
import UniformTypeIdentifiers

struct ReleaseManifest: Decodable {
    var version: String
    var build: Int
    var notes: String
    var installURL: String
}

@MainActor @Observable final class UpdateService {
    var checking = false
    var message = ""
    var release: ReleaseManifest?
    func check() async {
        guard !checking else { return }
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "LifeOSUpdateManifestURL") as? String,
              let url = URL(string: configured), url.scheme == "https", let host = url.host else {
            message = "当前安装版本尚未配置更新通道。"; return
        }
        checking = true; release = nil; message = "正在检查新版本…"
        defer { checking = false }
        do {
            var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", http.url?.host == host, bytes.count <= 64 * 1024 else { throw LifeError.message("更新通道暂不可用，请稍后重试。") }
            let next = try JSONDecoder().decode(ReleaseManifest.self, from: bytes)
            guard next.build > 0, !next.version.isEmpty,
                  let install = URLComponents(string: next.installURL), install.scheme == "itms-services",
                  install.queryItems?.first(where: { $0.name == "action" })?.value == "download-manifest",
                  let manifest = install.queryItems?.first(where: { $0.name == "url" })?.value,
                  let manifestURL = URL(string: manifest), manifestURL.scheme == "https", manifestURL.host == host else {
                throw LifeError.message("更新信息未通过安全检查。")
            }
            let current = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
            if next.build > current { release = next; message = "新版本 \(next.version) 已准备好。" }
            else { message = "已经是最新版本。" }
        } catch { message = "暂时无法检查更新，请确认网络后重试。" }
    }
}

struct SettingsView: View {
    @Environment(LifeStore.self) private var store
    @Environment(LifeLocation.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var updates = UpdateService()
    @State private var exportFile: PrivateExport?
    @State private var exportURL: URL?
    @State private var notifications = LifeNotifications.shared
    @State private var restorePicker = false
    @State private var restoreCandidate: LifeBackup?
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var body: some View {
        List {
            Section { HStack(spacing: 16) { Image("BrandMark").resizable().scaledToFit().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16)); VStack(alignment: .leading, spacing: 5) { Text("朝屿").font(.title2.bold()); Text("认真生活，留下自己的轨迹。").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 10) }
            Section("版本与更新") {
                LabeledContent("当前版本", value: version + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") + ")")
                Button { Task { await updates.check() } } label: { HStack { Label("检查更新", systemImage: "arrow.triangle.2.circlepath"); Spacer(); if updates.checking { ProgressView() } } }.disabled(updates.checking)
                if !updates.message.isEmpty { Text(updates.message).font(.subheadline).foregroundStyle(.secondary) }
                if let release = updates.release {
                    Text(release.notes).font(.subheadline)
                    Button("更新到 \(release.version)", systemImage: "arrow.down.circle") { if let url = URL(string: release.installURL) { openURL(url) } }
                    Text("iPhone 会请求安装确认。请直接覆盖更新，保留本机数据；不要先卸载 App。") .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("我的数据") {
                Label("记录保存在这台 iPhone 上", systemImage: "lock.shield")
                Button("导出完整备份", systemImage: "square.and.arrow.up") { share(store.exportBackup()) }.disabled(exportURL != nil)
                Button("导出可读文字", systemImage: "doc.text") { share(store.readableExport()) }.disabled(exportURL != nil)
                Button("从备份恢复", systemImage: "arrow.clockwise.icloud") { restorePicker = true }
                Text("备份包含你的文字和精确位置。请保存到可信位置。恢复会替换 朝屿当前记录，建议先导出当前备份。") .font(.caption).foregroundStyle(.secondary)
            }
            Section("提醒与快捷指令") {
                Button("主动启用计划提醒", systemImage: "bell") { Task { await notifications.authorize(plans: store.data.plans) } }
                if !notifications.message.isEmpty { Text(notifications.message).font(.caption).foregroundStyle(.secondary) }
                Text("在系统“快捷指令”中搜索朝屿，可记任务、开始/结束投入、记复盘草稿。操作要求解锁手机；不会自动完成任务或写系统日历。") .font(.caption).foregroundStyle(.secondary)
                NavigationLink("自动到访与定位状态") { VisitInboxView() }
            }
            Section("本版能力") {
                Text("桌面小组件与灵动岛需要独立的苹果签名描述文件，现有签名条件尚不具备。这两项不作为本版已交付能力。") .font(.caption).foregroundStyle(.secondary)
            }
            if let configured = Bundle.main.object(forInfoDictionaryKey: "LifeOSWorkbenchURL") as? String,
               let url = URL(string: configured), url.scheme == "https" {
                Section { Link(destination: url) { Label("打开工作台网页版", systemImage: "safari") } }
            }
            Section("使用边界") {
                Text("计划与实际分开保存。计时不自动完成任务，位置和路线不自动证明活动或成果。")
                Text("自动到访须主动开启；短路线须主动开始，每段可选择是否允许后台。日历只在你明确操作时读取、导入或打开系统编辑器。")
            }.font(.subheadline).foregroundStyle(.secondary)
        }.navigationTitle("我的朝屿").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $restorePicker, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 128 * 1024 * 1024 else { throw LifeError.message("备份文件过大。") }
                    restoreCandidate = try LifeStore.decodeBackup(Data(contentsOf: url))
                } catch { store.error = "无法读取此备份，当前数据未改变。" }
            }
            .alert("用备份替换当前 朝屿记录？", isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })) {
                Button("取消", role: .cancel) { restoreCandidate = nil }
                Button("恢复", role: .destructive) { if let candidate = restoreCandidate, store.restoreBackup(candidate) { location.pauseAfterRestore() }; restoreCandidate = nil }
            } message: { Text(restoreSummary) }
            .sheet(item: $exportFile, onDismiss: cleanupExport) { PrivateShareSheet(url: $0.url) }
    }
    var restoreSummary: String {
        guard let backup = restoreCandidate else { return "" }
        return "此备份包含\(backup.snapshot.tasks.count)个任务、\(backup.snapshot.reviews.count)篇复盘、\(backup.snapshot.photos.count)张照片副本。将替换当前记录；本机已删除的内容不会从旧备份复活。恢复后自动到访暂停，未结束的路线等待确认继续。请先导出当前备份。"
    }
    func share(_ url: URL?) { if let url { exportURL = url; exportFile = PrivateExport(url: url) } }
    func cleanupExport() {
        guard let url = exportURL else { return }
        let allowed = ["Dayisle-private-backup.json","Dayisle-readable.md"]
        if url.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL && allowed.contains(url.lastPathComponent) {
            do { try FileManager.default.removeItem(at: url) } catch { store.error = "导出的临时副本未能清除，可再次打开设置后重试导出。" }
        }
        exportURL = nil
    }
}

struct PrivateExport: Identifiable { let id = UUID(); let url: URL }
struct PrivateShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
