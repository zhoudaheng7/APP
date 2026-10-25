import SwiftUI

@main struct WeChatAssistApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.startPolling() }
                    else { model.stopPolling() }
                }
        }
    }
}

private let accent = Color(red: 0.07, green: 0.42, blue: 0.34)

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pairingText = ""
    @State private var pairingBusy = false
    var body: some View {
        Group {
            if model.hasPairing {
                TabView {
                    NavigationStack { ReplyView() }.tabItem { Label("回复助手", systemImage: "sparkles") }
                    NavigationStack { ContextView() }.tabItem { Label("上下文", systemImage: "text.bubble") }
                    NavigationStack { settings }.tabItem { Label("连接", systemImage: "link") }
                }
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 23) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 45)).foregroundStyle(accent)
                            Text("理解这句话，\n再想好怎么回。").font(.largeTitle.bold())
                            Text("连接你的 Windows 助手，接收指定微信聊天的识别文字。手机 App 打开时同步，回复由你审核后发送。")
                                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(5)
                            TextEditor(text: $pairingText).font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 150).padding(10).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.3)))
                            PasteButton(payloadType: String.self) { values in pairingText = values.first ?? "" }
                            Button {
                                pairingBusy = true
                                Task { await model.pair(pairingText); pairingBusy = false }
                            } label: { HStack { if pairingBusy { ProgressView() }; Text("连接 Windows").frame(maxWidth: .infinity) }.padding(7) }
                                .buttonStyle(.borderedProminent).disabled(pairingBusy || pairingText.isEmpty)
                            Text("在 Windows 工作台中打开「iPhone 配对」，复制整段配对信息后粘贴到这里。两台设备需在同一局域网。")
                                .font(.footnote).foregroundStyle(.secondary)
                            if !model.error.isEmpty { Text(model.error).font(.footnote).foregroundStyle(.orange) }
                        }.padding(26)
                    }.background(Color(.systemGroupedBackground)).navigationTitle("知会")
                }
            }
        }.tint(accent)
    }
    private var settings: some View {
        List {
            Section("Windows 连接") {
                Label(model.connected ? "已连接" : "连接中断", systemImage: model.connected ? "checkmark.circle.fill" : "exclamationmark.circle")
                Text(model.state.capture.message).font(.subheadline).foregroundStyle(.secondary)
                Button("重新连接") { model.stopPolling(); model.startPolling() }
            }
            Section("AI 模型") {
                LabeledContent("模型", value: model.state.model.name)
                LabeledContent("自动生成", value: model.state.model.auto ? "已开启" : "未开启")
                Text("模型和自动生成开关在 Windows 工作台配置。密钥不下发到手机。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("使用条件") {
                Text("Windows 保持开机、微信处于选定聊天且在前台。手机 App 打开时同步；进入后台或锁屏后不保证继续刷新。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("首版识别可见文字，不含语音转写和未显示历史；复制回复后在微信发送。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section { Button("移除本机配对", role: .destructive) { model.disconnect() } }
        }.navigationTitle("连接与设置")
    }
}

struct StatusCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.connected && model.state.capture.status == "reading" ? "circle.fill" : "pause.circle.fill")
                .font(.caption).padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.state.snapshot?.chat_title ?? "等待 Windows 上下文").font(.subheadline.weight(.semibold))
                Text(model.state.capture.message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.foregroundStyle(accent).padding(15).background(accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ReplyView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusCard()
                if let draft = model.state.draft {
                    Text("理解这段对话").font(.caption).foregroundStyle(.secondary)
                    Text(draft.analysis).font(.subheadline).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(17).background(accent.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 15))
                    Text("选择一条，继续修改").font(.caption).foregroundStyle(.secondary)
                    ForEach(draft.replies) { reply in
                        Button { model.choose(reply) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(reply.label).font(.caption.weight(.semibold)).foregroundStyle(accent)
                                Text(reply.text).font(.subheadline).lineSpacing(4).foregroundStyle(.primary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                } else {
                    ContentUnavailableView("从一句不确定的话开始", systemImage: "sparkles",
                        description: Text("开始读取后，生成解释和候选回复。"))
                }
                HStack {
                    TextField("问 AI：这句话什么意思？", text: $model.question).textFieldStyle(.roundedBorder)
                    Button("提问") { Task { await model.generate(model.question) } }.disabled(!model.canGenerate || model.question.isEmpty)
                }
                Divider()
                HStack { Text("我的最终回复").font(.subheadline.weight(.semibold)); Spacer(); Text("由你确认后发送").font(.caption2).foregroundStyle(.secondary) }
                TextEditor(text: $model.editor).font(.subheadline).frame(minHeight: 130).padding(10)
                    .background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
                HStack {
                    Button("更自然") { Task { await model.tune("保留原意，表达得更自然") } }
                    Button("再简短些") { Task { await model.tune("保留原意，缩短一半") } }
                    Button("更委婉") { Task { await model.tune("保留原意，表达得更委婉") } }
                }.font(.caption).buttonStyle(.bordered).disabled(!model.canGenerate || model.editor.isEmpty)
                if model.stale { Text("聊天已更新，你的草稿已保留。请核对最新上下文后重新生成。").font(.caption).foregroundStyle(.orange) }
                if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.orange) }
                Button { model.copy() } label: { Label("复制回复，回微信发送", systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(6) }
                    .buttonStyle(.borderedProminent).disabled(model.editor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.stale)
                Text("截图 OCR 可能有误，不推断说话人。生成内容仅为草稿。").font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }.background(Color(.systemGroupedBackground)).navigationTitle("回复助手")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.generate() } } label: {
                    if model.generating { ProgressView() } else { Text("生成回复") }
                }.disabled(!model.canGenerate)
            } }
    }
}

struct ContextView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard()
                if let snapshot = model.state.snapshot {
                    HStack {
                        Text("上下文 \(snapshot.revision)")
                        Spacer()
                        Text(Date(timeIntervalSince1970: snapshot.captured_at), style: .time)
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(snapshot.text).font(.subheadline).lineSpacing(8).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 15))
                } else { ContentUnavailableView("还没有聊天上下文", systemImage: "text.bubble", description: Text("请在 Windows 选择聊天区域并开始读取。")) }
                Text("这里是当前选区的文字识别结果。没有导出全部历史，也没有读取 iPhone 微信数据库。").font(.footnote).foregroundStyle(.secondary)
            }.padding(18)
        }.background(Color(.systemGroupedBackground)).navigationTitle("当前上下文")
    }
}
