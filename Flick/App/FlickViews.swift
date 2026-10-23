import SwiftUI
import PhotosUI
import UIKit

private struct PhotoPresentation: Identifiable { let id: UUID }

struct FlickRootView: View {
    @ObservedObject var link: PeerLink
    @AppStorage("flick.throwSide") private var side: ThrowSide = .right
    @State private var pickerItem: PhotosPickerItem?
    @State private var selected: PhotoAsset?
    @State private var importing = false
    @State private var showConnection = false
    @State private var presentation: PhotoPresentation?
    var body: some View {
        TabView {
            Tab("分享", systemImage: "arrow.up.right") {
                NavigationStack {
                    SendScreen(link: link, photo: selected, side: side, pickerItem: $pickerItem, importing: importing, openConnection: { showConnection = true })
                        .navigationTitle("一甩")
                        .toolbar { connectionToolbar }
                }
            }
            Tab("接收", systemImage: "square.and.arrow.down") {
                NavigationStack {
                    ReceiveHome(link: link, openConnection: { showConnection = true }, openPhoto: {
                        if let id = link.receivedPhoto?.id { presentation = PhotoPresentation(id: id) }
                    })
                    .navigationTitle("接住这一刻")
                    .toolbar { connectionToolbar }
                }
            }
        }
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(link: link, side: $side)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $presentation) { item in ReceivedPhotoView(link: link, photoID: item.id).id(item.id) }
        .alert(item: $link.invitation) { request in
            Alert(title: Text("连接并允许本次自动展示？"), message: Text("\(request.name) 想与你连接。请核对对方手机显示的连接码：\(request.code)\n\n连接后可随时暂停接收。"), primaryButton: .default(Text("允许连接")) { link.answerInvitation(true) }, secondaryButton: .cancel(Text("拒绝")) { link.answerInvitation(false) })
        }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            importing = true
            Task { @MainActor in
                defer { importing = false; pickerItem = nil }
                do {
                    guard let imported = try await item.loadTransferable(type: ImportedPhoto.self) else { throw PhotoFailure.invalid }
                    let asset = try await Task.detached(priority: .userInitiated) { try PhotoAsset.prepare(imported.url) }.value
                    selected = asset; link.note("照片准备好了，向\(side.label)甩给朋友。")
                    UISelectionFeedbackGenerator().selectionChanged()
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
    }
    @ToolbarContentBuilder private var connectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showConnection = true } label: {
                Label(link.peerName ?? (link.connecting ? "连接中" : "连接"), systemImage: link.connected ? "link" : "antenna.radiowaves.left.and.right")
                    .font(.subheadline)
            }
            .accessibilityLabel(link.connected ? "管理与\(link.peerName ?? "对方")的连接" : "连接附近的 iPhone")
        }
    }
}

private struct SendScreen: View {
    @ObservedObject var link: PeerLink
    let photo: PhotoAsset?
    let side: ThrowSide
    @Binding var pickerItem: PhotosPickerItem?
    let importing: Bool
    let openConnection: () -> Void
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
                        Text(photo == nil ? "把这一刻，甩给朋友。" : "让照片飞过去。")
                            .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    photoStage(width: max(geometry.size.width - 40, 100), height: max(260, min(geometry.size.height * 0.61, 520)))
                    VStack(spacing: 10) {
                        if link.isSending {
                            ProgressView(value: link.sendProgress).tint(.green)
                                .accessibilityLabel("原图发送进度")
                        }
                        Label(link.sendStatus, systemImage: link.sendError ? "exclamationmark.circle" : link.outgoingStage == .delivered ? "checkmark.circle.fill" : "arrow.left.and.right")
                            .font(.footnote).foregroundStyle(link.sendError ? Color.red : Color.secondary)
                            .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.updatesFrequently)
                        if link.connected {
                            Text(link.peerAccepting ? "对方在\(side.label) · 按住照片向\(side.label)甩出" : "对方已暂停接收，照片仍保留")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    if let photo = photo {
                        HStack {
                            Label("原图", systemImage: "photo")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(photo.byteCount), countStyle: .file))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 10) { actionBar.padding(.horizontal, 20).padding(.vertical, 8) }
        }
        .onChange(of: link.outgoingStage) { _, stage in
            switch stage {
            case .awaitingPreview:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(reduceMotion ? .linear(duration: 0.1) : .easeIn(duration: 0.3)) {
                    offset = CGSize(width: side.sign * 540, height: -45); opacity = 0
                }
            case .failed, .delivered:
                withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.82)) { offset = .zero; opacity = 1; lifted = false }
            default: break
            }
        }
        .onChange(of: photo?.id) { _, _ in offset = .zero; opacity = 1 }
    }
    @ViewBuilder private func photoStage(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Color(.secondarySystemGroupedBackground))
            if let photo = photo {
                Image(uiImage: photo.image).resizable().scaledToFill()
                    .frame(width: width, height: height).clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text("分享这一刻").font(.headline).foregroundStyle(.white)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .scaleEffect(lifted ? 1.025 : 1)
                    .rotationEffect(.degrees(reduceMotion ? 0 : offset.width * 0.035))
                    .offset(offset).opacity(opacity)
                    .simultaneousGesture(DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard !link.isSending, abs(value.translation.width) > abs(value.translation.height) else { return }
                            lifted = true; offset = CGSize(width: value.translation.width, height: value.translation.height * 0.12)
                        }
                        .onEnded { value in
                            guard !link.isSending else { return }
                            if FlickRules.shouldThrow(dx: value.translation.width, dy: value.translation.height, velocityX: value.velocity.width, width: width, side: side) { performSend() }
                            if !link.isSending { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { offset = .zero; lifted = false } }
                        })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("选中的照片，向\(side.label)甩出发送")
                    .accessibilityAction(named: Text("发送照片")) { performSend() }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text("选一张想分享的照片").font(.headline)
                    PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                        Label("选择照片", systemImage: "plus")
                    }.buttonStyle(.glassProminent).controlSize(.large).disabled(importing)
                }.padding(20)
            }
            if importing { ProgressView("正在读取照片…").padding(20).glassEffect(in: .rect(cornerRadius: 20)) }
        }
        .frame(width: width, height: height)
        .clipped()
    }
    private var actionBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                    Image(systemName: "photo.badge.plus").font(.title3).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.glass).buttonBorderShape(.circle).disabled(link.isSending || importing).accessibilityLabel("选择另一张照片")
                Button(action: performSend) {
                    HStack(spacing: 8) {
                        Text(!link.connected ? "连接另一台 iPhone" : link.isSending ? "正在飞过去…" : "甩给 \(link.peerName ?? "朋友")")
                        if !link.isSending { Image(systemName: side == .right ? "arrow.up.right" : "arrow.up.left") }
                    }.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 44)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(importing || link.isSending || (link.connected && (photo == nil || !link.peerAccepting)))
            }
        }
    }
    private func performSend() {
        guard !link.isSending else { return }
        guard link.connected else { openConnection(); return }
        guard let photo = photo else { link.note("先选择一张照片。", error: true); return }
        link.send(photo, side: side)
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
                    Text(!link.connected ? "等你连过来。" : link.accepting ? "等你甩来一张。" : "想接时，再打开。")
                        .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    Text(!link.connected ? "双方打开一甩，连接后就能分享。" : link.accepting ? "来自已连接朋友的照片\n会从对应边缘飞入并自动展开。" : "本次自动展示已暂停。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if !link.connected {
                    Button("连接附近的 iPhone", systemImage: "link", action: openConnection).buttonStyle(.glassProminent).controlSize(.large)
                }
                Toggle("本次连接允许自动展示", isOn: Binding(get: { link.accepting }, set: link.setAccepting))
                    .padding(18).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                if let photo = link.receivedPhoto {
                    Button(action: openPhoto) {
                        HStack(spacing: 14) {
                            Image(uiImage: photo.image).resizable().scaledToFill().frame(width: 52, height: 64).clipped().clipShape(.rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("刚刚收到的照片").font(.headline)
                                Text(photo.originalReady ? "原图已接收 · 轻点查看" : photo.failure ?? "原图接收中")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(14).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                    }.buttonStyle(.plain)
                }
            }.padding(22)
        }.background(Color(.systemGroupedBackground))
    }
}

private struct ConnectionSheet: View {
    @ObservedObject var link: PeerLink
    @Binding var side: ThrowSide
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("本机", value: link.localName)
                    LabeledContent("连接码") { Text(link.code).font(.title2.monospacedDigit().weight(.medium)).textSelection(.enabled) }
                } footer: { Text("在对方手机上选择本机，并核对连接码。双方确认后允许本次自动展示，可随时暂停。") }
                if link.connected {
                    Section("当前连接") {
                        Label(link.peerName ?? "朋友的 iPhone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Picker("对方在我的", selection: $side) {
                            Text("左侧").tag(ThrowSide.left); Text("右侧").tag(ThrowSide.right)
                        }.disabled(link.isSending)
                        Toggle("本次允许自动展示", isOn: Binding(get: { link.accepting }, set: link.setAccepting))
                        Button("断开连接", role: .destructive) { link.disconnect(); dismiss() }
                    }
                } else {
                    Section {
                        if link.nearby.isEmpty {
                            HStack { ProgressView(); Text("寻找打开一甩的设备…").foregroundStyle(.secondary) }
                        }
                        ForEach(link.nearby) { phone in
                            Button { link.connect(phone) } label: {
                                HStack {
                                    Image(systemName: "iphone.radiowaves.left.and.right")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(phone.name)
                                        Text("对方连接码：\(phone.code)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if link.connecting { ProgressView() } else { Image(systemName: "plus.circle") }
                                }
                            }.disabled(link.connecting)
                        }
                    } header: { Text("附近的 iPhone") } footer: { Text("先把两台手机连接同一 Wi-Fi，打开 Wi-Fi 和蓝牙，并允许本地网络权限。第一版建议并排竖屏测试。") }
                    Section {
                        Picker("对方在我的", selection: $side) {
                            Text("左侧").tag(ThrowSide.left); Text("右侧").tag(ThrowSide.right)
                        }
                    }
                }
                if let diagnostic = link.diagnostic { Section("连接提示") { Text(diagnostic).font(.footnote).foregroundStyle(.secondary) } }
                Section { Text("一甩 0.1.0 · 原生 Liquid Glass\n照片仅在已确认的设备之间传送。").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("面对面连接").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
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
    @State private var saveMessage: String?
    private var photo: ReceivedPhoto? { link.receivedPhoto?.id == photoID ? link.receivedPhoto : nil }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let photo = photo {
                    Image(uiImage: photo.image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(zoomed ? 1.8 : entered ? 1 : reduceMotion ? 1 : 0.3)
                        .offset(x: entered || reduceMotion ? 0 : -photo.offer.side.sign * geometry.size.width)
                        .rotationEffect(.degrees(entered || reduceMotion ? 0 : -photo.offer.side.sign * 12))
                        .opacity(entered ? 1 : 0)
                        .onTapGesture { withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.9)) { zoomed.toggle() } }
                        .accessibilityLabel("来自\(photo.sender)的照片")
                        .accessibilityAction(named: Text(zoomed ? "还原照片" : "放大照片")) { zoomed.toggle() }
                }
            }.clipped()
        }
        .safeAreaInset(edge: .top) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("接住这一刻").font(.headline)
                    Text("来自 \(photo?.sender ?? "朋友")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("收起照片，继续接收")
            }.padding(.horizontal, 20).padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                if let failure = photo?.failure { Text(failure).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
                else if photo?.originalReady == true { Label("原图已接收并校验", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
                else { ProgressView(value: link.receiveProgress) { Text("原图接收中…").font(.caption) }.tint(.green) }
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 14) {
                        Button { share = true } label: { Label("分享", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 40) }
                            .buttonStyle(.glass).disabled(photo?.originalURL == nil)
                        Button { savePhoto() } label: { Label(saving ? "保存中…" : "存入照片", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 40) }
                            .buttonStyle(.glassProminent).disabled(photo?.originalURL == nil || saving)
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
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .sheet(isPresented: $share) { if let url = photo?.originalURL { ActivitySheet(items: [url]) } }
        .alert("保存照片", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(saveMessage ?? "") }
    }
    private func savePhoto() {
        guard let url = photo?.originalURL, !saving else { return }
        saving = true
        Task { @MainActor in
            do { try await PhotoSave.save(url); saveMessage = "已保存到系统照片。" }
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
