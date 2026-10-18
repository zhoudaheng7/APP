import SwiftUI
import UIKit

@main
struct LuxquareApp: App {
    @StateObject private var model = WorkbenchModel()
    @StateObject private var updates = UpdateService()
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "dark"
    var body: some Scene {
        WindowGroup {
            LuxquareRoot(model: model, updates: updates)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
                .tint(.cyan)
                .task { await model.refresh(); await updates.check() }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await model.refresh(); await updates.check() } }
                }
        }
    }
}

enum NativeTab: Hashable { case home, dialogue, tools, settings }
struct WebDestination: Identifiable { let id = UUID(); let url: URL; let title: String }

@MainActor
struct LuxquareRoot: View {
    @ObservedObject var model: WorkbenchModel
    @ObservedObject var updates: UpdateService
    @State private var tab = NativeTab.home
    @State private var destination: WebDestination?
    @State private var upload: UploadRecording?
    @State private var connectRecordingAfterDismiss = false
    @State private var locationNotice: String?
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { home }
                .tabItem { Label("工作台", systemImage: "square.grid.2x2.fill").accessibilityIdentifier("native.tab.home") }.tag(NativeTab.home)
            NavigationStack {
                NativeDialogueView(origin: model.availableModules.first { $0.moduleID == "easel" }?.origin,
                    identityID: model.user?.identityID, client: model.client,
                    onOpenWeb: { if let module = model.availableModules.first(where: { $0.moduleID == "easel" }) { open(module) } else { login() } })
            }.tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill").accessibilityIdentifier("native.tab.dialogue") }.tag(NativeTab.dialogue)
            NavigationStack {
                NativeToolsView(onRecordingReady: { upload = UploadRecording(url: $0) }, onLocationReady: { lat, lon, accuracy in
                    locationNotice = String(format: "纬度 %.6f · 经度 %.6f\n精度约 %.0f 米 · WGS84", lat, lon, accuracy)
                })
            }.tabItem { Label("工具", systemImage: "waveform.circle.fill").accessibilityIdentifier("native.tab.tools") }.tag(NativeTab.tools)
            NavigationStack { settings }
                .tabItem { Label("设置", systemImage: "person.crop.circle.fill").accessibilityIdentifier("native.tab.settings") }.tag(NativeTab.settings)
        }
        .sheet(item: $destination, onDismiss: { Task { await model.refresh(force: true) } }) { item in
            WorkbenchPage(url: item.url, title: item.title, model: model)
        }
        .sheet(item: $upload, onDismiss: {
            if connectRecordingAfterDismiss {
                connectRecordingAfterDismiss = false
                if let module = model.availableModules.first(where: { $0.moduleID == "recordings" }) { open(module) } else { login() }
            }
        }) { item in RecordingUploadView(file: item.url, model: model, onConnect: { connectRecordingAfterDismiss = true }) }
        .alert("当前位置", isPresented: Binding(get: { locationNotice != nil }, set: { if !$0 { locationNotice = nil } })) {
            Button("完成", role: .cancel) { locationNotice = nil }
        } message: { Text(locationNotice ?? "") }
        .onChange(of: model.showLogin) { _, visible in if visible { login() } }
        .onChange(of: model.identityEpoch) { _, _ in
            destination = nil; upload = nil; connectRecordingAfterDismiss = false
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image("BrandMark").resizable().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LUXQUARE").font(.system(size: 12, weight: .semibold, design: .rounded)).tracking(3).foregroundStyle(.secondary)
                        Text(model.user.map { "\($0.displayName)，你好" } ?? "光平方 · 工作空间").font(.title3.weight(.semibold))
                    }
                    Spacer()
                    if model.loading { ProgressView() }
                }.accessibilityIdentifier("luxquare.brand")
                if model.user == nil && !model.configuration.isUITesting { welcome }
                if !displayModules.isEmpty {
                    HStack {
                        Text("应用").font(.headline)
                        Text("\(displayModules.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if model.user != nil { Button { openWorkbench() } label: { Image(systemName: "sidebar.left") }.accessibilityLabel("打开网页工作台") }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(displayModules) { module in
                            Button { if !model.configuration.isUITesting { open(module) } } label: { ModuleTile(module: module) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("module." + module.moduleID)
                        }
                    }
                }
                if let notice = model.notice, model.user != nil {
                    Label(notice, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.secondary)
                }
                if let update = updates.update {
                    Button { tab = .settings } label: {
                        Label("Luxquare \(update.version) 可更新", systemImage: "arrow.down.circle").font(.subheadline)
                    }.padding(.vertical, 8)
                }
            }.padding(20).frame(maxWidth: 860).frame(maxWidth: .infinity)
        }
        .background(LuxquareBackdrop())
        .navigationTitle("Luxquare").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新应用目录") } }
        .refreshable { await model.refresh(force: true) }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.baseURL == nil ? "原生工作空间已就绪" : "连接你的公司工作台").font(.title2.weight(.semibold))
            Text(model.baseURL == nil ? "此构建用于原生界面预览。正式签名版本会配置企业入口。" : "使用已有企业飞书身份登录，应用和权限会自动同步。")
                .font(.subheadline).foregroundStyle(.secondary)
            if model.baseURL != nil { Button("使用企业身份登录") { login() }.buttonStyle(.borderedProminent) }
            HStack(spacing: 14) {
                Button { tab = .tools } label: { Label("本机录音", systemImage: "waveform") }
                Text("·").foregroundStyle(.tertiary)
                Text("原生玻璃界面").foregroundStyle(.secondary)
            }.font(.footnote)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).luxGlass(corner: 24)
    }
    private var displayModules: [WorkbenchModule] {
        model.configuration.isUITesting ? Self.demoModules : model.availableModules
    }
    private static var demoModules: [WorkbenchModule] {
        [("finance", "财务系统", "资金与经营收支", "amber"), ("crm", "客户 CRM", "客户、销售与合同", "blue"),
         ("projects", "工作统筹", "任务与项目进度", "purple"), ("recordings", "录音总结", "会议录音与待办", "teal"),
         ("easel", "Easel 创作", "策划、创作与对话", "purple"), ("lightsquare", "LightSquare", "团队内容工作空间", "teal"),
         ("companies", "公司档案", "企业资料与主体", "cyan"), ("aa", "AA账单", "团队分摊与结算", "blue")].map { id, title, detail, accent in
            WorkbenchModule(moduleID: id, title: title, description: detail, available: true, enabled: true,
                entry: "https://example.invalid/" + id, presentationOrigin: "https://example.invalid", logoURL: nil, accent: accent, openMode: "embedded")
        }
    }
    private var settings: some View {
        SettingsScreen(model: model, updates: updates, onLogin: login, onWorkbench: openWorkbench)
            .accessibilityIdentifier("native.settings.screen")
    }
    private func login() {
        guard !model.transitioning, let base = model.baseURL else { return }
        model.showLogin = false
        destination = WebDestination(url: base.appendingPathComponent("auth/entry"), title: "企业身份登录")
    }
    private func openWorkbench() {
        guard let base = model.baseURL else { return }
        destination = WebDestination(url: base.appendingPathComponent("workbench"), title: "工作台管理")
    }
    private func open(_ module: WorkbenchModule) {
        guard let url = module.url, url.scheme == "https", url.user == nil, url.password == nil else { return }
        if module.opensExternally { UIApplication.shared.open(url) }
        else { destination = WebDestination(url: url, title: module.title) }
    }
}

struct LuxquareBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(colors: [.indigo.opacity(scheme == .dark ? 0.18 : 0.07), .clear, .cyan.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder func luxGlass(corner: CGFloat = 22) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .rect(cornerRadius: corner)) }
        else { self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: corner)) }
    }
}

struct ModuleTile: View {
    let module: WorkbenchModule
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                if let raw = module.logoURL, let url = URL(string: raw), url.scheme == "https" {
                    AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
                        Image(systemName: module.symbol).foregroundStyle(module.tint)
                    }.frame(width: 28, height: 28)
                } else {
                    Image(systemName: module.symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(module.tint)
                }
                Spacer()
                if module.opensExternally { Image(systemName: "arrow.up.forward").font(.caption2).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(module.title).font(.system(size: 15, weight: .semibold)).lineLimit(1).foregroundStyle(.primary)
                Text(module.description.isEmpty ? "打开应用" : module.description).font(.caption).lineLimit(1).foregroundStyle(.secondary)
            }
        }.padding(17).frame(maxWidth: .infinity, minHeight: 108, alignment: .leading).luxGlass()
    }
}

@MainActor
struct WorkbenchPage: View {
    @StateObject private var browser: WorkbenchBrowser
    @Environment(\.dismiss) private var dismiss
    let initialTitle: String
    init(url: URL, title: String, model: WorkbenchModel) {
        initialTitle = title
        _browser = StateObject(wrappedValue: WorkbenchBrowser(url: url, model: model))
    }
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WorkbenchWebView(browser: browser)
                if browser.progress < 1 && browser.errorMessage == nil { ProgressView(value: browser.progress).tint(.cyan) }
                if let error = browser.errorMessage {
                    ContentUnavailableView { Label("暂时无法打开", systemImage: "wifi.exclamationmark") } description: { Text(error) } actions: { Button("重新加载") { browser.reload() } }
                        .background(.regularMaterial)
                }
            }
            .navigationTitle(initialTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if browser.canGoBack { Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }.accessibilityLabel("上一页") }
                    Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新模块")
                }
            }
            .sheet(item: $browser.shareFile) { file in NativeAudioShareSheet(url: file.url) }
        }
    }
}

@MainActor
struct SettingsScreen: View {
    @ObservedObject var model: WorkbenchModel
    @ObservedObject var updates: UpdateService
    let onLogin: () -> Void
    let onWorkbench: () -> Void
    @AppStorage("appearance") private var appearance = "dark"
    @State private var showLogout = false
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("BrandMark").resizable().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Luxquare").font(.title3.weight(.semibold))
                        Text("光平方 · 公司工作空间").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
                LabeledContent("当前版本", value: "\(updates.installedVersion) (\(updates.installedBuild))")
            }
            Section("企业身份") {
                if let user = model.user {
                    LabeledContent("已登录", value: user.displayName)
                    Button("打开网页工作台", action: onWorkbench)
                    Button("退出此设备登录", role: .destructive) { showLogout = true }
                } else { Button("使用企业身份登录", action: onLogin).disabled(model.baseURL == nil) }
            }
            Section("外观") {
                Picker("显示模式", selection: $appearance) {
                    Text("深色").tag("dark"); Text("浅色").tag("light"); Text("跟随系统").tag("system")
                }
            }
            Section("更新") {
                Button { Task { await updates.check(force: true) } } label: {
                    HStack { Text("检查原生版本更新"); Spacer(); if updates.checking { ProgressView() } }
                }.disabled(updates.checking)
                if let update = updates.update, let url = updates.installURL {
                    Text("\(update.version) · \(update.releaseNotes)").font(.subheadline)
                    Button("安装新版本") { UIApplication.shared.open(url) }
                }
                if let text = updates.message { Text(text).font(.footnote).foregroundStyle(.secondary) }
                Text("网页业务随服务器更新；原生版本可在这里发起系统安装，无需手动导入IPA。安装时请保留旧App，不要先删除。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("本机权限") {
                Text("麦克风、相机、照片和定位仅在你主动使用时请求。录音先保存在本机。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("打开系统权限设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        }
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("退出此设备上的企业登录？", isPresented: $showLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await model.logout() } }
            Button("取消", role: .cancel) { }
        } message: { Text("请先保存网页中未完成的操作。退出会清理本App网页缓存；原生录音和对话仍按原账号保留。") }
    }
}
