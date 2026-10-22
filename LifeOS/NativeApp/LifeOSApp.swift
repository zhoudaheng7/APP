import SwiftUI

@main struct LifeOSApp: App {
    @State private var store = LifeStore()
    @State private var location = LifeLocation()
    @AppStorage("lifeos.onboarded.v1") private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded || ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                    LifeRootView()
                } else {
                    WelcomeView { onboarded = true }
                }
            }
            .environment(store).environment(location).tint(.teal)
            .alert("未能完成操作", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("知道了", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .onAppear { location.store = store }
            .onChange(of: scenePhase) { _, phase in location.setForeground(phase == .active) }
        }
    }
}

struct LifeRootView: View {
    @Environment(LifeStore.self) private var store
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView() }.tabItem { Label("今天", systemImage: "sun.max") }.tag(0)
            NavigationStack { PlacesView() }.tabItem { Label("地图", systemImage: "map") }.tag(1)
            NavigationStack { GoalsView() }.tabItem { Label("方向", systemImage: "scope") }.tag(2)
            NavigationStack { PlansView() }.tabItem { Label("计划", systemImage: "calendar") }.tag(3)
            NavigationStack { MemoriesView() }.tabItem { Label("记忆", systemImage: "sparkles") }.tag(4)
        }
        .modifier(NativeTabChrome())
        .disabled(!store.ready)
        .overlay { if !store.ready { ContentUnavailableView("本机数据暂不可用", systemImage: "externaldrive.badge.exclamationmark", description: Text("请保留 App，原数据未被重置。")) } }
    }
}

struct NativeTabChrome: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.tabBarMinimizeBehavior(.onScrollDown) } else { content }
    }
}

struct PrimaryAction: View {
    var title: String
    var symbol: String
    var action: () -> Void
    @ViewBuilder var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.glassProminent).controlSize(.large)
        } else {
            Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

struct WelcomeView: View {
    var start: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "sun.horizon.fill").font(.system(size: 68)).symbolRenderingMode(.hierarchical).foregroundStyle(.teal)
            Text("LifeOS").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("认真生活，\n慢慢留下自己的轨迹。")
                .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text("给今天留一点方向，给时间留一点空间。\n计划、真实投入和生活记忆，在这里相遇。")
                .font(.body).foregroundStyle(.secondary).lineSpacing(6)
            Label("记录保存在这台 iPhone 上", systemImage: "lock.shield").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            PrimaryAction(title: "开始我的一天", symbol: "arrow.right", action: start)
        }
        .padding(28)
        .background(LinearGradient(colors: [Color.teal.opacity(0.13), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

func minutesText(_ seconds: TimeInterval) -> String {
    let minutes = Int(max(0, seconds) / 60)
    return minutes >= 60 ? "\(minutes / 60)小时\(minutes % 60)分" : "\(minutes)分钟"
}

func overlapsDay(_ start: Date, _ end: Date, day: Date) -> Bool {
    let lower = Calendar.current.startOfDay(for: day)
    let upper = Calendar.current.date(byAdding: .day, value: 1, to: lower)!
    return start < upper && end > lower
}

func clippedSeconds(_ start: Date, _ end: Date, day: Date) -> TimeInterval {
    let lower = Calendar.current.startOfDay(for: day)
    let upper = Calendar.current.date(byAdding: .day, value: 1, to: lower)!
    return max(0, min(end, upper).timeIntervalSince(max(start, lower)))
}
