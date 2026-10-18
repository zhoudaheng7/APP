import SwiftUI

struct NativeDialogueView: View {
    let origin: URL?
    let identityID: String?
    let client: WorkbenchHTTPClient
    let onOpenWeb: () -> Void
    @StateObject private var store = DialogueStore()
    @State private var draft = ""
    @State private var historyShown = false
    @State private var followsReply = true
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var configurationID: String { (origin?.absoluteString ?? "") + "|" + (identityID ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            if !store.connected && !store.isDemo { connectionPanel }
            conversation
            if !store.notice.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").padding(.top, 2)
                    Text(store.notice).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 10)
                .accessibilityIdentifier("luxquare.dialogue.notice")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle("对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { composerFocused = false; historyShown = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("对话历史").accessibilityIdentifier("luxquare.dialogue.history")
                    .disabled(store.isBusy)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { composerFocused = false; store.newSession(); followsReply = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("新建对话").accessibilityIdentifier("luxquare.dialogue.new")
                    .disabled(store.isBusy)
                Menu {
                    Button("在创作工作台中打开", systemImage: "arrow.up.right.square", action: onOpenWeb)
                    Button("重新连接", systemImage: "arrow.clockwise") { store.probe() }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("更多对话操作")
            }
        }
        .task(id: configurationID) { store.configure(origin: origin, identityID: identityID, client: client) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !store.connected { store.probe() }
        }
        .onChange(of: configurationID) { _, _ in draft = ""; composerFocused = false }
        .sheet(isPresented: $historyShown) { history }
        .accessibilityIdentifier("luxquare.dialogue.screen")
    }

    private var connectionPanel: some View {
        VStack(spacing: 10) {
            Label("连接团队创作工作台", systemImage: "sparkles")
                .font(.headline)
            Text("沿用工作台的飞书身份，连接后即可开始。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("连接创作工作台") { composerFocused = false; onOpenWeb() }
                    .modifier(DialoguePrimaryStyle())
                    .accessibilityIdentifier("luxquare.dialogue.connect")
                Button { store.probe() } label: {
                    if store.checking { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.bordered).disabled(store.checking)
                .accessibilityLabel("重新检查连接")
            }
        }
        .padding(18).frame(maxWidth: .infinity)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if store.messages.isEmpty { emptyConversation }
                    ForEach(store.messages) { message in
                        messageBubble(message).id(message.id)
                    }
                    ForEach(store.pendingQuestions) { question in
                        DialogueQuestionCard(question: question, store: store, onOpenWeb: onOpenWeb)
                    }
                    if !store.activity.isEmpty {
                        HStack(spacing: 9) {
                            if store.isBusy { ProgressView().controlSize(.small) }
                            Text(store.activity).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .accessibilityIdentifier("luxquare.dialogue.activity")
                    }
                    Color.clear.frame(height: 2).id("dialogue-bottom")
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 14)
                .frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .simultaneousGesture(DragGesture(minimumDistance: 16).onChanged { _ in followsReply = false })
            .onChange(of: store.scrollRevision) { _, _ in
                if followsReply { proxy.scrollTo("dialogue-bottom", anchor: .bottom) }
            }
            .onChange(of: store.currentSessionID) { _, _ in
                followsReply = true
                proxy.scrollTo("dialogue-bottom", anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !followsReply && !store.messages.isEmpty {
                    Button {
                        followsReply = true
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("dialogue-bottom", anchor: .bottom) }
                    } label: { Image(systemName: "arrow.down").frame(width: 22, height: 22) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("回到最新回复").padding(16)
                }
            }
        }
    }

    private var emptyConversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkle").font(.system(size: 36, weight: .light)).foregroundStyle(.cyan)
            Text("从一个想法开始。")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("策划内容、梳理问题，或把灵感变成可执行的下一步。")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("团队创作工作区")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageBubble(_ message: DialogueMessage) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == "user" { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 7) {
                if message.role != "user" {
                    Text("LUXQUARE").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !store.isBusy && message.failure == nil {
                    Text("此轮暂无可显示的回复。").font(.subheadline).foregroundStyle(.secondary)
                }
                if let failure = message.failure {
                    Label(failure, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(message.role == "user" ? 15 : 0)
            .background {
                if message.role == "user" {
                    RoundedRectangle(cornerRadius: 21, style: .continuous).fill(Color.accentColor.opacity(0.12))
                }
            }
            if message.role != "user" { Spacer(minLength: 16) }
        }
        .accessibilityElement(children: .combine)
    }

    private var composer: some View {
        VStack(spacing: 9) {
            if store.hasPending && !store.isBusy {
                HStack(spacing: 12) {
                    Button("继续读取", systemImage: "arrow.triangle.2.circlepath") { followsReply = true; store.resume() }
                        .buttonStyle(.bordered).disabled(!store.connected)
                        .accessibilityIdentifier("luxquare.dialogue.resume")
                    Button("到创作工作台核对", action: onOpenWeb).font(.footnote)
                    Spacer(minLength: 0)
                }
            }
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    composerRow
                        .padding(10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 29))
                }
            } else {
                composerRow.padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 8)
        .frame(maxWidth: 850).frame(maxWidth: .infinity)
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("写下你的想法…", text: $draft, axis: .vertical)
                .font(.system(size: 17)).lineLimit(1...6).textFieldStyle(.plain)
                .focused($composerFocused).padding(.horizontal, 8).padding(.vertical, 9)
                .accessibilityIdentifier("luxquare.dialogue.composer")
            if composerFocused {
                Button { composerFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.vertical, 9)
                    .accessibilityLabel("收起键盘")
            }
            if store.isBusy {
                Button { store.stop() } label: {
                    if store.isStopping { ProgressView().frame(width: 22, height: 22) }
                    else { Image(systemName: "stop.fill").frame(width: 22, height: 22) }
                }
                .modifier(DialoguePrimaryStyle()).disabled(store.isStopping)
                .accessibilityLabel("停止本轮对话")
                .accessibilityIdentifier("luxquare.dialogue.stop")
            } else {
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard store.canSend, !text.isEmpty else { return }
                    draft = ""; composerFocused = false; followsReply = true; store.send(text)
                } label: { Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold)).frame(width: 22, height: 22) }
                .modifier(DialoguePrimaryStyle())
                .disabled(!store.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 50_000)
                .accessibilityLabel("发送消息").accessibilityIdentifier("luxquare.dialogue.send")
            }
        }
    }

    private var history: some View {
        NavigationStack {
            List {
                if store.sessions.isEmpty { Text("还没有对话").foregroundStyle(.secondary) }
                ForEach(store.sessions) { session in
                    Button {
                        store.select(session); draft = ""; historyShown = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(session.title).font(.headline).lineLimit(1).foregroundStyle(.primary)
                                Spacer()
                                if session.pending != nil { Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(session.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("对话历史").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { historyShown = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DialoguePrimaryStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.buttonStyle(.glassProminent).buttonBorderShape(.capsule) }
        else { content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
    }
}

private struct DialogueQuestionCard: View {
    let question: DialogueQuestion
    @ObservedObject var store: DialogueStore
    let onOpenWeb: () -> Void
    @State private var selections: [String: [String]] = [:]
    @State private var custom: [String: String] = [:]
    @State private var submitting = false
    @State private var resultUnknown = false
    @State private var failure = ""

    private var answers: [String: [String]] {
        var result: [String: [String]] = [:]
        for item in question.questions {
            let typed = (custom[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let picked = selections[item.id] ?? []
            result[item.id] = typed.isEmpty ? picked : (item.multiSelect == true ? picked + [typed] : [typed])
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(question.questions) { item in
                VStack(alignment: .leading, spacing: 9) {
                    if let header = item.header { Text(header).font(.caption).foregroundStyle(.secondary) }
                    Text(item.question).font(.headline).fixedSize(horizontal: false, vertical: true)
                    ForEach(item.options ?? [], id: \.label) { option in
                        Button {
                            var values = selections[item.id] ?? []
                            if item.multiSelect == true {
                                if values.contains(option.label) { values.removeAll { $0 == option.label } }
                                else { values.append(option.label) }
                            } else { values = [option.label]; custom[item.id] = "" }
                            selections[item.id] = values
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: (selections[item.id] ?? []).contains(option.label) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.label).foregroundStyle(.primary)
                                    if let description = option.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                        }
                        .buttonStyle(.bordered).disabled(submitting || resultUnknown)
                    }
                    TextField("补充你的回答", text: Binding(get: { custom[item.id] ?? "" }, set: { custom[item.id] = $0 }), axis: .vertical)
                        .font(.system(size: 17)).textFieldStyle(.roundedBorder).disabled(submitting || resultUnknown)
                }
            }
            if !failure.isEmpty { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            HStack {
                Button(submitting ? "正在提交…" : "提交选择") {
                    let captured = answers
                    submitting = true
                    Task {
                        let error = await store.answer(question, answers: captured)
                        submitting = false
                        if let error { failure = error; resultUnknown = true }
                    }
                }
                .modifier(DialoguePrimaryStyle())
                .disabled(submitting || resultUnknown || answers.values.contains(where: \.isEmpty) || !store.connected)
                Button("到创作工作台", action: onOpenWeb).font(.footnote)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("luxquare.dialogue.question")
    }
}
