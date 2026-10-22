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
    @State private var backup: URL?
    @State private var restorePicker = false
    @State private var restoreCandidate: LifeSnapshot?
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
                Button("准备导出备份", systemImage: "square.and.arrow.up") { backup = store.exportBackup() }
                if let backup { ShareLink(item: backup) { Label("保存或分享备份文件", systemImage: "doc") } }
                Button("从备份恢复", systemImage: "arrow.clockwise.icloud") { restorePicker = true }
                Text("备份包含你的文字和精确位置。请保存到可信位置。恢复会替换 朝屿当前记录，建议先导出当前备份。") .font(.caption).foregroundStyle(.secondary)
            }
            if let configured = Bundle.main.object(forInfoDictionaryKey: "LifeOSWorkbenchURL") as? String,
               let url = URL(string: configured), url.scheme == "https" {
                Section { Link(destination: url) { Label("打开工作台网页版", systemImage: "safari") } }
            }
            Section("使用边界") {
                Text("计划与实际分开保存。计时不自动完成任务，位置和路线不自动证明活动或成果。")
                Text("地点记忆为手动记录；路线只在你主动开启且 App 前台打开时采集。系统日历与 Obsidian 同步尚未启用。")
            }.font(.subheadline).foregroundStyle(.secondary)
        }.navigationTitle("我的朝屿").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $restorePicker, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 128 * 1024 * 1024 else { throw LifeError.message("备份文件过大。") }
                    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
                    let candidate = try decoder.decode(LifeSnapshot.self, from: Data(contentsOf: url))
                    try candidate.validate(); restoreCandidate = candidate
                } catch { store.error = "无法读取此备份，当前数据未改变。" }
            }
            .alert("用备份替换当前 朝屿记录？", isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })) {
                Button("取消", role: .cancel) { restoreCandidate = nil }
                Button("恢复", role: .destructive) { if let candidate = restoreCandidate { location.stopRoute(); _ = store.commit(kind: "backup.restore", id: UUID()) { $0 = candidate } }; restoreCandidate = nil }
            } message: { Text("仅替换 朝屿记录。此操作会覆盖当前数据，请确认已经导出需要保留的备份。") }
    }
}
