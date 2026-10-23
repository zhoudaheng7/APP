import SwiftUI
import PhotosUI
import UIKit
import AVKit
import QuickLook
import UniformTypeIdentifiers

private struct PhotoPresentation: Identifiable { let id: UUID; var composing = false }

#if !APP_EXTENSION
struct FlickRootView: View {
    @ObservedObject var link: PeerLink
    @AppStorage("flick.throwSide") private var side: ThrowSide = .right
    @State private var tab = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var selected: PhotoAsset?
    @State private var importing = false
    @State private var files = false
    @State private var showConnection = false
    @State private var presentation: PhotoPresentation?
    var body: some View {
        TabView(selection: $tab) {
            Tab("分享", systemImage: "arrow.up.right", value: 0) {
                NavigationStack {
                    SendScreen(link: link, photo: nil, side: side, pickerItem: $pickerItem, importing: importing, openConnection: { showConnection = true })
                        .navigationTitle("一甩")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { Button("选文件", systemImage: "doc.badge.plus") { files = true }.disabled(importing || link.isSending) }
                            connectionToolbar
                        }
                }
            }
            Tab("接收", systemImage: "square.and.arrow.down", value: 1) {
                NavigationStack {
                    ReceiveHome(link: link, openConnection: { showConnection = true }, openPhoto: {
                        if let id = link.receivedPhoto?.id { presentation = PhotoPresentation(id: id) }
                    })
                    .navigationTitle("接住这一刻").toolbar { connectionToolbar }
                }
            }
            Tab("好友", systemImage: "person.2", value: 2) {
                NavigationStack { FriendsView(link: link, connect: { showConnection = true }) }
            }
            Tab("设置", systemImage: "slider.horizontal.3", value: 3) {
                NavigationStack { FlickSettingsView(link: link) }
            }
        }
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(link: link, side: $side).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $link.incomingRequest, onDismiss: { link.finishConsentPresentation() }) { request in
            IncomingRequestView(link: link, request: request).presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $presentation) { item in
            if item.composing, let asset = selected {
                ComposerScreen(link: link, initialAsset: asset, initialSide: side)
            } else { ReceivedPhotoView(link: link, photoID: item.id).id(item.id) }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                importing = true
                Task { @MainActor in
                    defer { importing = false }
                    do {
                        let asset = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            return try PhotoAsset.prepare(PhotoFiles.copyImported(url))
                        }.value
                        compose(asset)
                    } catch { link.note(error.localizedDescription, error: true) }
                }
            case .failure(let error): link.note(error.localizedDescription, error: true)
            }
        }
        .modifier(LinkDialogs(link: link, enabled: !showConnection && presentation == nil))
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }; importing = true
            Task { @MainActor in
                defer { importing = false; pickerItem = nil }
                do {
                    guard let imported = try await item.loadTransferable(type: ImportedPhoto.self) else { throw PhotoFailure.invalid }
                    let asset = try await Task.detached(priority: .userInitiated) { try PhotoAsset.prepare(imported.url) }.value
                    compose(asset)
                } catch { link.note(error.localizedDescription, error: true) }
            }
        }
        .onChange(of: link.receivedPhoto?.id) { _, id in
            if let id = id {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { presentation = PhotoPresentation(id: id) }
            }
        }
        .onChange(of: link.connected) { _, value in if value { showConnection = false } }
        .onChange(of: tab) { _, _ in updateReceivingSurface() }
        .onChange(of: presentation?.id) { _, _ in updateReceivingSurface() }
        .onChange(of: showConnection) { _, _ in updateReceivingSurface() }
        .onOpenURL { url in if url.scheme == "flick", url.host == "receive" { startReceiving() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FlickStartReceiving"))) { _ in startReceiving() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in consumeShortcut() }
        .onAppear { consumeShortcut(); updateReceivingSurface() }
    }
    private func compose(_ asset: PhotoAsset) {
        selected = asset; presentation = PhotoPresentation(id: asset.id, composing: true)
        link.note("准备好了，上下左右都可以甩出。")
        FlickFeedback.selection()
    }
    private func consumeShortcut() { if UserDefaults.standard.bool(forKey: "flick.startReceiving") { startReceiving() } }
    private func updateReceivingSurface() { link.canPresentIncoming = tab == 1 && presentation == nil && !showConnection }
    private func startReceiving() {
        UserDefaults.standard.set(false, forKey: "flick.startReceiving")
        tab = 1; link.setAccepting(true); link.activate(); link.retryDiscovery()
    }
    @ToolbarContentBuilder private var connectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showConnection = true } label: {
                Label(link.peerName ?? (link.connecting ? "连接中" : "连接"), systemImage: link.connected ? "link" : "antenna.radiowaves.left.and.right").font(.subheadline)
            }.accessibilityLabel("管理附近 iPhone 的连接")
        }
    }
}
#endif

private func connectionAlert(_ request: ConnectionRequest, link: PeerLink) -> Alert {
    Alert(title: Text("连接此设备？"), message: Text("\(request.name) 想与你连接。请核对对方连接码：\(request.code)\n\n每次接收先询问；好友可在设置中允许自动展开。可随时暂停接收或忘记配对。"), primaryButton: .default(Text("允许连接")) { link.answerInvitation(true) }, secondaryButton: .cancel(Text("拒绝")) { link.answerInvitation(false) })
}

private enum LinkDialog: Identifiable {
    case connection(ConnectionRequest), friend(FriendInvitation)
    var id: UUID { switch self { case .connection(let value): return value.id; case .friend(let value): return value.id } }
}
private struct LinkDialogs: ViewModifier {
    @ObservedObject var link: PeerLink
    var enabled = true
    func body(content: Content) -> some View {
        content.alert(item: Binding<LinkDialog?>(get: {
            guard enabled else { return nil }
            if let value = link.invitation { return .connection(value) }
            if let value = link.friendInvitation { return .friend(value) }
            return nil
        }, set: { _ in })) { dialog in
            switch dialog { case .connection(let value): return connectionAlert(value, link: link); case .friend(let value): return friendAlert(value, link: link) }
        }
    }
}

struct ComposerScreen: View {
    @ObservedObject var link: PeerLink
    let initialAsset: PhotoAsset
    let initialSide: ThrowSide
    var finish: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showConnection = false
    @State private var picker: PhotosPickerItem?
    @State private var side: ThrowSide = .right
    var body: some View {
        NavigationStack {
            SendScreen(link: link, photo: initialAsset, side: side, pickerItem: $picker, importing: false, openConnection: { showConnection = true }, allowsPicker: false)
                .navigationTitle(initialAsset.kind == .video ? "甩出视频" : initialAsset.kind == .file ? "甩出文件" : "甩出照片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(link.connected ? "已连接" : "连接", systemImage: "link") { showConnection = true } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { if let finish = finish { finish() } else { dismiss() } }.disabled(link.isSending) }
                }
        }
        .onAppear { side = initialSide }
        .sheet(isPresented: $showConnection) { ConnectionSheet(link: link, side: $side).presentationDetents([.medium, .large]) }
        .onChange(of: link.connected) { _, value in if value { showConnection = false } }
        .modifier(LinkDialogs(link: link, enabled: !showConnection))
        .interactiveDismissDisabled(link.isSending)
    }
}

struct SendScreen: View {
    @ObservedObject var link: PeerLink
    let photo: PhotoAsset?
    let side: ThrowSide
    @Binding var pickerItem: PhotosPickerItem?
    let importing: Bool
    let openConnection: () -> Void
    var allowsPicker = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset = CGSize.zero
    @State private var opacity = 1.0
    @State private var lifted = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("面对面，分享刚刚好").font(.subheadline).foregroundStyle(.secondary)
                        Text(photo == nil ? "选中，即可甩出。" : "向朋友的方向，一甩。")
                            .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    photoStage(width: max(geometry.size.width - 40, 100), height: max(260, min(geometry.size.height * 0.61, 520)))
                    VStack(spacing: 10) {
                        if link.isSending { ProgressView(value: link.sendProgress).tint(.green).accessibilityLabel("原文件发送进度") }
                        Label(link.sendStatus, systemImage: link.sendError ? "exclamationmark.circle" : link.outgoingStage == .delivered ? "checkmark.circle.fill" : "arrow.left.and.right")
                            .font(.footnote).foregroundStyle(link.sendError ? Color.red : Color.secondary)
                            .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                        if link.connected {
                            if let bearing = link.bearing {
                                Label("对方在\(bearing.label)\(distanceText) · 四向均可甩送", systemImage: bearing.symbol).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(link.peerAccepting ? (link.bearingHint ?? "暂时测不到真实方位 · 可上下左右甩送") : "对方已暂停接收")
                                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        }
                    }
                    if let photo = photo {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(photo.title).lineLimit(2)
                            HStack {
                                Label("原文件，不转码", systemImage: photo.kind == .video ? "video" : photo.kind == .file ? "doc" : "photo")
                                Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(photo.byteCount), countStyle: .file))
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("也可在系统照片或文件中：分享 → 一甩，直接甩送。无需加入主页。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden).background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 10) { actionBar.padding(.horizontal, 20).padding(.vertical, 8) }
        }
        .onChange(of: link.outgoingStage) { _, stage in
            switch stage {
            case .awaitingPreview:
                FlickFeedback.impact(.medium)
                withAnimation(reduceMotion ? .linear(duration: 0.1) : .easeIn(duration: 0.3)) {
                    offset = CGSize(width: link.lastThrowSide.x * 560, height: link.lastThrowSide.y * 800); opacity = 0
                }
            case .failed, .delivered:
                withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.82)) { offset = .zero; opacity = 1; lifted = false }
            default: break
            }
        }
        .onChange(of: photo?.id) { _, _ in offset = .zero; opacity = 1 }
    }
    private var distanceText: String { link.distance.map { String(format: " · %.1f 米", $0) } ?? "" }
    @ViewBuilder private func photoStage(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Color(.secondarySystemGroupedBackground))
            if let photo = photo {
                Image(uiImage: photo.image).resizable().scaledToFit()
                    .frame(width: width, height: height)
                    .overlay(alignment: .bottomLeading) {
                        Label("按住并甩向任一方向", systemImage: "hand.draw").font(.headline).foregroundStyle(.white)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 30)).contentShape(Rectangle())
                    .scaleEffect(lifted ? 1.025 : 1).rotationEffect(.degrees(reduceMotion ? 0 : offset.width * 0.035))
                    .offset(offset).opacity(opacity)
                    .highPriorityGesture(DragGesture(minimumDistance: 8)
                        .onChanged { value in guard !link.isSending else { return }; lifted = true; offset = value.translation }
                        .onEnded { value in
                            guard !link.isSending else { return }
                            if let direction = FlickRules.throwDirection(dx: value.translation.width, dy: value.translation.height, velocityX: value.velocity.width, velocityY: value.velocity.height, width: width, height: height) { performSend(direction) }
                            if !link.isSending { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { offset = .zero; lifted = false } }
                        })
                    .accessibilityElement(children: .ignore).accessibilityLabel("选中的内容，上下左右甩出发送")
                    .accessibilityAction(named: Text("发送原文件")) { performSend() }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text("照片、视频，保留原样。").font(.headline)
                    PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                        Label("选择照片或视频", systemImage: "plus")
                    }.buttonStyle(.glassProminent).controlSize(.large).disabled(importing)
                }.padding(20)
            }
            if importing { ProgressView("正在读取原文件…").padding(20).glassEffect(in: .rect(cornerRadius: 20)) }
        }.frame(width: width, height: height).clipped()
    }
    private var actionBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                if allowsPicker {
                    PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                        Image(systemName: "photo.badge.plus").font(.title3).frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.glass).buttonBorderShape(.circle).disabled(link.isSending || importing).accessibilityLabel("选择照片或视频")
                }
                Button { performSend() } label: {
                    HStack(spacing: 8) {
                        Text(!link.connected ? "连接另一台 iPhone" : link.isSending ? "正在飞过去…" : "甩给 \(link.peerName ?? "朋友")")
                        if !link.isSending { Image(systemName: (link.bearing ?? side).symbol) }
                    }.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 44)
                }.buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(importing || link.isSending || (link.connected && (photo == nil || !link.peerAccepting)))
            }
        }
    }
    private func performSend(_ direction: ThrowSide? = nil) {
        guard !link.isSending else { return }
        guard link.connected else { openConnection(); return }
        guard let photo = photo else { link.note("先选择照片、视频或文件。", error: true); return }
        link.send(photo, side: direction ?? link.bearing ?? side)
    }
}

private struct ReceiveHome: View {
    @ObservedObject var link: PeerLink
    let openConnection: () -> Void
    let openPhoto: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle().stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 6])).frame(width: 220, height: 220)
                    Circle().stroke(.quaternary, lineWidth: 1).frame(width: 170, height: 170)
                    Image(systemName: "square.and.arrow.down").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.secondary)
                }.accessibilityHidden(true).padding(.top, 25)
                VStack(spacing: 10) {
                    Text(!link.connected ? "等你连过来。" : link.accepting ? "等你甩过来。" : "想接时，再打开。")
                        .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    Text(!link.connected ? "开启 Wi-Fi 和蓝牙，双方打开一甩。\n无需路由器，也不需要互联网。" : link.accepting ? "收到邀请后选择是否接收。\n请保持接收页在前台。" : "接收已暂停。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if !link.connected { Button("连接附近的 iPhone", systemImage: "link", action: openConnection).buttonStyle(.glassProminent).controlSize(.large) }
                if link.connected {
                    VStack(spacing: 10) {
                        Label(link.withinTwentyMeters ? "已确认在 20 米内" : "距离尚未确认在 20 米内", systemImage: link.withinTwentyMeters ? "location.circle.fill" : "location.slash")
                        if let distance = link.distance { Text(String(format: "实测距离 %.1f 米", distance)).font(.subheadline.monospacedDigit()) }
                        Text(link.isCurrentFriend ? "已是好友，可在本地连接时分享。" : "陌生人需先测得在 20 米内；也可双方确认添加好友。").font(.caption).foregroundStyle(.secondary)
                    }.multilineTextAlignment(.center).padding(16).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                }
                Toggle("允许接收", isOn: Binding(get: { link.accepting }, set: link.setAccepting))
                    .padding(18).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                if let photo = link.receivedPhoto {
                    Button(action: openPhoto) {
                        HStack(spacing: 14) {
                            Image(uiImage: photo.image).resizable().scaledToFit().frame(width: 52, height: 64).clipShape(.rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(photo.offer.filename).font(.headline).lineLimit(1)
                                Text(photo.originalReady ? "原文件已接收 · 轻点查看" : photo.failure ?? "原文件接收中").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(14).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                    }.buttonStyle(.plain)
                }
            }.padding(22)
        }.background(Color(.systemGroupedBackground))
    }
}

struct ConnectionSheet: View {
    @ObservedObject var link: PeerLink
    @Binding var side: ThrowSide
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("本机", value: link.localName)
                    LabeledContent("连接码") { Text(link.code).font(.title2.monospacedDigit().weight(.medium)).textSelection(.enabled) }
                } footer: { Text("在对方手机选择本机并核对连接码。设备发现并不代表在 20 米内；连接后核验距离。接收时保持接收页在前台。") }
                if link.connected {
                    Section("当前连接") {
                        Label(link.peerName ?? "朋友的 iPhone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let bearing = link.bearing { Label("真实方位：\(bearing.label)", systemImage: bearing.symbol) }
                        else { Text(link.bearingHint ?? "正在测量方位；暂不可用时可四向甩送。").font(.footnote).foregroundStyle(.secondary) }
                        if let distance = link.distance { LabeledContent("距离", value: String(format: "%.1f 米", distance)) }
                        directionPicker
                        if !link.isCurrentFriend {
                            Button(link.requestingFriend ? "等待好友确认…" : "发送好友申请", systemImage: "person.badge.plus") { link.requestFriend() }.disabled(link.requestingFriend)
                        } else { Label("已是好友", systemImage: "person.crop.circle.badge.checkmark") }
                        #if !APP_EXTENSION
                        Toggle("允许接收", isOn: Binding(get: { link.accepting }, set: link.setAccepting))
                        #endif
                        Button("断开连接", role: .destructive) { link.disconnect(); dismiss() }
                    }
                } else {
                    Section {
                        if link.nearby.isEmpty { HStack { ProgressView(); Text("寻找打开一甩的设备…").foregroundStyle(.secondary) } }
                        ForEach(link.nearby) { phone in
                            Button { link.connect(phone) } label: {
                                HStack {
                                    Image(systemName: "iphone.radiowaves.left.and.right")
                                    VStack(alignment: .leading, spacing: 4) { Text(phone.name); Text("对方连接码：\(phone.code)").font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    if link.connecting { ProgressView() } else { Image(systemName: "plus.circle") }
                                }
                            }.disabled(link.connecting)
                        }
                        Button("重新寻找") { link.retryDiscovery() }.disabled(link.connecting)
                    } header: { Text("可手动核验的设备 · 距离未确认") } footer: { Text("这个列表不声称设备都在 20 米内。连接后进行实测，或核对身份并添加好友。无需路由器和互联网；对方保持接收页前台。") }
                    Section { directionPicker }
                }
                Section {
                    Toggle("已确认设备自动重连", isOn: $link.autoReconnect)
                    Button("忘记所有配对", role: .destructive) { link.forgetDevices() }
                } footer: { Text("真实方位需要超宽带权限和合适的手机朝向。测不到时不会显示虚假的方向，可手动向四边甩送给当前连接的设备。") }
                if let diagnostic = link.diagnostic { Section("连接提示") { Text(diagnostic).font(.footnote).foregroundStyle(.secondary) } }
                Section { NavigationLink("甩送音效", systemImage: "speaker.wave.2") { SoundSettingsView() } }
                Section { Text("一甩 0.3.0 · 原生 Liquid Glass\n原文件传输与 SHA-256 校验 · 单次一个，最大 2 GiB").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("面对面连接").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .modifier(LinkDialogs(link: link))
    }
    private var directionPicker: some View {
        Picker("按钮默认方向", selection: $side) { ForEach(ThrowSide.allCases, id: \.self) { Text($0.label).tag($0) } }.disabled(link.isSending)
    }
}

private struct ReceivedPhotoView: View {
    @ObservedObject var link: PeerLink
    let photoID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var zoomed = false
    @State private var saving = false
    @State private var share = false
    @State private var export = false
    @State private var quickLookURL: URL?
    @State private var player: AVPlayer?
    @State private var saveMessage: String?
    private var photo: ReceivedPhoto? { link.receivedPhoto?.id == photoID ? link.receivedPhoto : nil }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let photo = photo {
                    media(photo)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(zoomed ? 1.8 : entered ? 1 : reduceMotion ? 1 : 0.3)
                        .offset(x: entered || reduceMotion ? 0 : photo.entrySide.x * geometry.size.width,
                                y: entered || reduceMotion ? 0 : photo.entrySide.y * geometry.size.height)
                        .opacity(entered ? 1 : 0)
                }
            }.clipped()
        }
        .safeAreaInset(edge: .top) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("接住这一刻").font(.headline); Text("来自 \(photo?.sender ?? "朋友")").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("收起，继续接收")
            }.padding(.horizontal, 20).padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                Text(photo?.offer.filename ?? "").font(.caption).lineLimit(2)
                if let failure = photo?.failure { Text(failure).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
                else if photo?.originalReady == true { Label("原文件已接收并校验", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
                else { ProgressView(value: link.receiveProgress) { Text("原文件接收中…").font(.caption) }.tint(.green) }
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 14) {
                        Button { share = true } label: { Label("分享", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 40) }
                            .buttonStyle(.glass).disabled(photo?.originalURL == nil)
                        Button { if photo?.offer.kind == .file { export = true } else { savePhoto() } } label: {
                            Label(saving ? "保存中…" : photo?.offer.kind == .file ? "存储到文件" : "存入照片", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 40)
                        }.buttonStyle(.glassProminent).disabled(photo?.originalURL == nil || saving)
                    }
                }
            }.padding(20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.62, dampingFraction: 0.85)) { entered = true }
                link.previewPresented(id: photoID)
            }
            FlickFeedback.impact(.soft); preparePlayer()
        }
        .onChange(of: photo?.originalURL) { _, _ in preparePlayer() }
        .onDisappear { player?.pause() }
        .sheet(isPresented: $share) { if let url = photo?.originalURL { ActivitySheet(items: [url]) } }
        .sheet(isPresented: $export) { if let url = photo?.originalURL { FileExportSheet(url: url) } }
        .quickLookPreview($quickLookURL)
        .alert("保存内容", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(saveMessage ?? "") }
    }
    @ViewBuilder private func media(_ photo: ReceivedPhoto) -> some View {
        if photo.offer.kind == .video, let player = player { VideoPlayer(player: player) }
        else if photo.offer.kind == .file {
            VStack(spacing: 20) {
                Image(systemName: "doc.fill").font(.system(size: 90, weight: .ultraLight)).foregroundStyle(.secondary)
                Text(photo.offer.filename).font(.title3).multilineTextAlignment(.center)
                Button("打开文件预览", systemImage: "doc.text.magnifyingglass") { quickLookURL = photo.originalURL }
                    .buttonStyle(.glassProminent).disabled(photo.originalURL == nil)
            }.padding(30)
        } else {
            Image(uiImage: photo.image).resizable().scaledToFit()
                .onTapGesture { withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.9)) { zoomed.toggle() } }
                .accessibilityLabel("来自\(photo.sender)的内容").accessibilityAction(named: Text("放大或还原")) { zoomed.toggle() }
        }
    }
    private func preparePlayer() {
        guard photo?.offer.kind == .video, let url = photo?.originalURL, player == nil else { return }
        let newPlayer = AVPlayer(url: url); newPlayer.isMuted = true; player = newPlayer; newPlayer.play()
    }
    private func savePhoto() {
        guard let photo = photo, let url = photo.originalURL, photo.offer.kind != .file, !saving else { return }
        saving = true
        Task { @MainActor in
            do { try await PhotoSave.save(url, kind: photo.offer.kind); saveMessage = "已保存到系统照片。" }
            catch { saveMessage = error.localizedDescription }
            saving = false
        }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
private struct FileExportSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
