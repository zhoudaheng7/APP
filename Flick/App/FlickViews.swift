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
            Tab("����", systemImage: "arrow.up.right") {
                NavigationStack {
                    SendScreen(link: link, photo: selected, side: side, pickerItem: $pickerItem, importing: importing, openConnection: { showConnection = true })
                        .navigationTitle("һ˦")
                        .toolbar { connectionToolbar }
                }
            }
            Tab("����", systemImage: "square.and.arrow.down") {
                NavigationStack {
                    ReceiveHome(link: link, openConnection: { showConnection = true }, openPhoto: {
                        if let id = link.receivedPhoto?.id { presentation = PhotoPresentation(id: id) }
                    })
                    .navigationTitle("��ס��һ��")
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
            Alert(title: Text("���Ӳ����������Զ�չʾ��"), message: Text("\(request.name) ���������ӡ���˶ԶԷ��ֻ���ʾ�������룺\(request.code)\n\n���Ӻ����ʱ��ͣ���ա�"), primaryButton: .default(Text("��������")) { link.answerInvitation(true) }, secondaryButton: .cancel(Text("�ܾ�")) { link.answerInvitation(false) })
        }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            importing = true
            Task { @MainActor in
                defer { importing = false; pickerItem = nil }
                do {
                    guard let imported = try await item.loadTransferable(type: ImportedPhoto.self) else { throw PhotoFailure.invalid }
                    let asset = try await Task.detached(priority: .userInitiated) { try PhotoAsset.prepare(imported.url) }.value
                    selected = asset; link.note("��Ƭ׼�����ˣ���\(side.label)˦�����ѡ�")
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
                Label(link.peerName ?? (link.connecting ? "������" : "����"), systemImage: link.connected ? "link" : "antenna.radiowaves.left.and.right")
                    .font(.subheadline)
            }
            .accessibilityLabel(link.connected ? "������\(link.peerName ?? "�Է�")������" : "���Ӹ����� iPhone")
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
                        Text("����棬�����ոպ�").font(.subheadline).foregroundStyle(.secondary)
                        Text(photo == nil ? "����һ�̣�˦�����ѡ�" : "����Ƭ�ɹ�ȥ��")
                            .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    photoStage(width: max(geometry.size.width - 40, 100), height: max(260, min(geometry.size.height * 0.61, 520)))
                    VStack(spacing: 10) {
                        if link.isSending {
                            ProgressView(value: link.sendProgress).tint(.green)
                                .accessibilityLabel("ԭͼ���ͽ���")
                        }
                        Label(link.sendStatus, systemImage: link.sendError ? "exclamationmark.circle" : link.outgoingStage == .delivered ? "checkmark.circle.fill" : "arrow.left.and.right")
                            .font(.footnote).foregroundStyle(link.sendError ? Color.red : Color.secondary)
                            .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.updatesFrequently)
                        if link.connected {
                            Text(link.peerAccepting ? "�Է���\(side.label) �� ��ס��Ƭ��\(side.label)˦��" : "�Է�����ͣ���գ���Ƭ�Ա���")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    if let photo = photo {
                        HStack {
                            Label("ԭͼ", systemImage: "photo")
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
                        Text("������һ��").font(.headline).foregroundStyle(.white)
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
                    .accessibilityLabel("ѡ�е���Ƭ����\(side.label)˦������")
                    .accessibilityAction(named: Text("������Ƭ")) { performSend() }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text("ѡһ�����������Ƭ").font(.headline)
                    PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                        Label("ѡ����Ƭ", systemImage: "plus")
                    }.buttonStyle(.glassProminent).controlSize(.large).disabled(importing)
                }.padding(20)
            }
            if importing { ProgressView("���ڶ�ȡ��Ƭ��").padding(20).glassEffect(in: .rect(cornerRadius: 20)) }
        }
        .frame(width: width, height: height)
        .clipped()
    }
    private var actionBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                    Image(systemName: "photo.badge.plus").font(.title3).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.glass).buttonBorderShape(.circle).disabled(link.isSending || importing).accessibilityLabel("ѡ����һ����Ƭ")
                Button(action: performSend) {
                    HStack(spacing: 8) {
                        Text(!link.connected ? "������һ̨ iPhone" : link.isSending ? "���ڷɹ�ȥ��" : "˦�� \(link.peerName ?? "����")")
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
        guard let photo = photo else { link.note("��ѡ��һ����Ƭ��", error: true); return }
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
                    Text(!link.connected ? "������������" : link.accepting ? "����˦��һ�š�" : "���ʱ���ٴ򿪡�")
                        .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    Text(!link.connected ? "˫����һ˦�����Ӻ���ܷ�����" : link.accepting ? "�������������ѵ���Ƭ\n��Ӷ�Ӧ��Ե���벢�Զ�չ����" : "�����Զ�չʾ����ͣ��")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if !link.connected {
                    Button("���Ӹ����� iPhone", systemImage: "link", action: openConnection).buttonStyle(.glassProminent).controlSize(.large)
                }
                Toggle("�������������Զ�չʾ", isOn: Binding(get: { link.accepting }, set: link.setAccepting))
                    .padding(18).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                if let photo = link.receivedPhoto {
                    Button(action: openPhoto) {
                        HStack(spacing: 14) {
                            Image(uiImage: photo.image).resizable().scaledToFill().frame(width: 52, height: 64).clipped().clipShape(.rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("�ո��յ�����Ƭ").font(.headline)
                                Text(photo.originalReady ? "ԭͼ�ѽ��� �� ���鿴" : photo.failure ?? "ԭͼ������")
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
                    LabeledContent("����", value: link.localName)
                    LabeledContent("������") { Text(link.code).font(.title2.monospacedDigit().weight(.medium)).textSelection(.enabled) }
                } footer: { Text("�ڶԷ��ֻ���ѡ�񱾻������˶������롣˫��ȷ�Ϻ����������Զ�չʾ������ʱ��ͣ��") }
                if link.connected {
                    Section("��ǰ����") {
                        Label(link.peerName ?? "���ѵ� iPhone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Picker("�Է����ҵ�", selection: $side) {
                            Text("���").tag(ThrowSide.left); Text("�Ҳ�").tag(ThrowSide.right)
                        }.disabled(link.isSending)
                        Toggle("���������Զ�չʾ", isOn: Binding(get: { link.accepting }, set: link.setAccepting))
                        Button("�Ͽ�����", role: .destructive) { link.disconnect(); dismiss() }
                    }
                } else {
                    Section {
                        if link.nearby.isEmpty {
                            HStack { ProgressView(); Text("Ѱ�Ҵ�һ˦���豸��").foregroundStyle(.secondary) }
                        }
                        ForEach(link.nearby) { phone in
                            Button { link.connect(phone) } label: {
                                HStack {
                                    Image(systemName: "iphone.radiowaves.left.and.right")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(phone.name)
                                        Text("�Է������룺\(phone.code)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if link.connecting { ProgressView() } else { Image(systemName: "plus.circle") }
                                }
                            }.disabled(link.connecting)
                        }
                    } header: { Text("������ iPhone") } footer: { Text("�Ȱ���̨�ֻ�����ͬһ Wi-Fi���� Wi-Fi ����������������������Ȩ�ޡ���һ�潨�鲢���������ԡ�") }
                    Section {
                        Picker("�Է����ҵ�", selection: $side) {
                            Text("���").tag(ThrowSide.left); Text("�Ҳ�").tag(ThrowSide.right)
                        }
                    }
                }
                if let diagnostic = link.diagnostic { Section("������ʾ") { Text(diagnostic).font(.footnote).foregroundStyle(.secondary) } }
                Section { Text("һ˦ 0.1.0 �� ԭ�� Liquid Glass\n��Ƭ������ȷ�ϵ��豸֮�䴫�͡�").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("���������").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("���") { dismiss() } } }
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
                        .accessibilityLabel("����\(photo.sender)����Ƭ")
                        .accessibilityAction(named: Text(zoomed ? "��ԭ��Ƭ" : "�Ŵ���Ƭ")) { zoomed.toggle() }
                }
            }.clipped()
        }
        .safeAreaInset(edge: .top) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("��ס��һ��").font(.headline)
                    Text("���� \(photo?.sender ?? "����")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("������Ƭ����������")
            }.padding(.horizontal, 20).padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                if let failure = photo?.failure { Text(failure).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
                else if photo?.originalReady == true { Label("ԭͼ�ѽ��ղ�У��", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
                else { ProgressView(value: link.receiveProgress) { Text("ԭͼ�����С�").font(.caption) }.tint(.green) }
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 14) {
                        Button { share = true } label: { Label("����", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 40) }
                            .buttonStyle(.glass).disabled(photo?.originalURL == nil)
                        Button { savePhoto() } label: { Label(saving ? "�����С�" : "������Ƭ", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 40) }
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
        .alert("������Ƭ", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) { Button("��", role: .cancel) {} } message: { Text(saveMessage ?? "") }
    }
    private func savePhoto() {
        guard let url = photo?.originalURL, !saving else { return }
        saving = true
        Task { @MainActor in
            do { try await PhotoSave.save(url); saveMessage = "�ѱ��浽ϵͳ��Ƭ��" }
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
