import SwiftUI
import UIKit

#if !APP_EXTENSION
struct FlickSettingsView: View {
    @ObservedObject var link: PeerLink
    @AppStorage("flick.haptics") private var haptics = true
    var body: some View {
        Form {
            Section {
                NavigationLink { SoundSettingsView() } label: { Label("甩送音效", systemImage: "speaker.wave.2") }
                NavigationLink { IconSettingsView() } label: { Label("App 图标", systemImage: "app.badge") }
                Toggle("触感反馈", isOn: $haptics)
            }
            Section("附近与接收") {
                Toggle("允许附近设备发现我", isOn: $link.discoverable)
                Toggle("接收附近的人发来的内容", isOn: $link.allowNearby)
                Toggle("信任后连续接收", isOn: $link.autoAcceptTrusted)
                Toggle("纯蓝牙传输（可关闭 Wi-Fi）", isOn: $link.bluetoothOnly).disabled(link.busySending)
                Toggle("已确认设备自动重连", isOn: $link.autoReconnect)
                Text("首次连接核对身份并信任，之后可连续接收。附近设备通过蓝牙发现，不判断距离。在 App 任意页面均可接收。后台接收需提前建立纯蓝牙连接，受 iOS 调度限制；强制退出后不可接收。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("已信任设备") {
                ForEach(link.trustedDevices) { device in
                    HStack { Text(device.name); Spacer(); Button("撤销信任", role: .destructive) { link.revokeTrust(device.id) } }
                }
                if link.trustedDevices.isEmpty { Text("首次连接并确认后会显示在这里。").foregroundStyle(.secondary) }
            }
            if !link.blockedIDs.isEmpty {
                Section("已屏蔽设备") {
                    ForEach(Array(link.blockedIDs).sorted(), id: \.self) { id in
                        HStack { Text(String(id.suffix(8))).font(.footnote.monospaced()); Spacer(); Button("解除屏蔽") { link.unblock(id) } }
                    }
                }
            }
            Section("本版功能状态") {
                LabeledContent("iPhone 之间原文件传输", value: "可测试")
                LabeledContent("好友申请与本地好友", value: "可测试")
                LabeledContent("纯蓝牙与后台接收", value: "待双机实测")
                LabeledContent("远程、聊天与推送", value: "未接入服务")
                LabeledContent("Android / HarmonyOS", value: "客户端未完成")
                Text("模拟版中的远程与跨系统流程尚未接入真实服务。本版不会为未发生的传输显示成功，也不使用后台音频保活。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("一甩 0.4 开发版 · 原生 Liquid Glass\n多选最多 50 个，每个原文件最大 2 GiB；双方安装相同版本。分享扩展有独立的配对、音效和好友设置。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("设置")
    }
}

struct IconSettingsView: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var changing = false
    @State private var failure: String?
    private let options: [(String, String?, String)] = [
        ("青柠轨迹", nil, "IconPreview0"), ("飞起的照片", "FlickPhoto", "IconPreview1"),
        ("相遇涟漪", "FlickRipple", "IconPreview2"), ("一笔甩出", "FlickOrange", "IconPreview3"),
        ("双向瞬间", "FlickDuet", "IconPreview4"), ("快乐一甩", "FlickHappy", "IconPreview5")
    ]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 16) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button { change(option.1) } label: {
                        VStack(spacing: 12) {
                            Image(option.2).resizable().scaledToFit().frame(width: 82, height: 82).clipShape(.rect(cornerRadius: 20))
                            Label(option.0, systemImage: current == option.1 ? "checkmark.circle.fill" : "circle").font(.subheadline)
                        }.frame(maxWidth: .infinity).padding(.vertical, 16)
                    }.buttonStyle(.glass).disabled(changing)
                }
            }.padding(20)
            Text("选中后由系统更换主屏幕图标。系统可能显示更换提示；若签名工具删除了备用图标配置，需要保留完整 IPA 重签。").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 22)
        }.navigationTitle("一甩图标").background(Color(.systemGroupedBackground))
            .alert("图标未更换", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("好", role: .cancel) {} } message: { Text(failure ?? "") }
    }
    private func change(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { failure = "此安装的图标配置不可用，请检查重签时是否保留了备用图标。"; return }
        guard current != name else { return }; changing = true
        UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                changing = false
                if let error = error { failure = error.localizedDescription }
                else { current = UIApplication.shared.alternateIconName; FlickFeedback.selection() }
            }
        }
    }
}

struct FriendsView: View {
    @ObservedObject var link: PeerLink
    let connect: () -> Void
    var body: some View {
        List {
            Section("当前连接") {
                if link.connected {
                    Label(link.peerName ?? "朋友", systemImage: "iphone.radiowaves.left.and.right")
                    if link.isCurrentFriend { Label("双方已确认好友", systemImage: "person.crop.circle.badge.checkmark") }
                    else { Button(link.requestingFriend ? "等待对方确认…" : "发送好友申请", systemImage: "person.badge.plus") { link.requestFriend() }.disabled(link.requestingFriend) }
                } else { Button("连接并添加朋友", systemImage: "person.badge.plus", action: connect) }
            }
            Section("我的好友") {
                if link.friends.isEmpty { Text("先核对连接码，再发起好友申请。对方同意后才会添加。").foregroundStyle(.secondary) }
                ForEach(link.friends) { friend in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(friend.name, systemImage: "person.crop.circle")
                        Text(friend.id == link.connectedDeviceID ? "已连接 · 到分享页选中内容即可甩送" : "未连接 · 对方在附近并打开 App 后可重新连接")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if friend.id != link.connectedDeviceID {
                                Button("附近连接") {
                                    if let phone = link.nearby.first(where: { $0.deviceID == friend.id }) { link.connect(phone) }
                                    else { connect() }
                                }.buttonStyle(.glass)
                            }
                            Button("移除好友", role: .destructive) { link.removeFriend(friend.id) }.buttonStyle(.glass)
                        }
                    }.padding(.vertical, 7)
                }
            }
            Section {
                Text("这是设备间确认的本地好友列表，不是云账号通讯录。远程连接与聊天服务尚未接入；这里不会假装发送远程图片。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("好友")
    }
}
#endif

struct SoundSettingsView: View {
    @AppStorage("flick.sound.send") private var send: SoundPack = .swish
    @AppStorage("flick.sound.receive") private var receive: SoundPack = .swish
    @AppStorage("flick.sound.volume") private var volume = 0.45
    @AppStorage("flick.haptics") private var haptics = true
    @State private var message: String?
    var body: some View {
        Form {
            Section("配对音效") {
                ForEach(SoundPack.allCases) { pack in
                    Button {
                        send = pack; receive = pack; FlickFeedback.selection()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(pack.title).foregroundStyle(.primary); Text(pack.detail).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if send == pack && receive == pack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }.padding(.vertical, 5)
                    }
                }
            }
            Section("分别选择") {
                Picker("发送声音", selection: $send) { ForEach(SoundPack.allCases) { Text($0.title).tag($0) } }
                Picker("接收声音", selection: $receive) { ForEach(SoundPack.allCases) { Text($0.title).tag($0) } }
                HStack { Image(systemName: "speaker.wave.2"); Slider(value: $volume, in: 0...1); Text(volume, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).frame(minWidth: 38) }
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("试听发送", systemImage: "arrow.up.right") { preview(true) }.buttonStyle(.glass)
                        Button("试听接收", systemImage: "arrow.down.left") { preview(false) }.buttonStyle(.glassProminent)
                    }.frame(maxWidth: .infinity)
                }.padding(.vertical, 6)
                Toggle("触感反馈", isOn: $haptics)
            }
            Section {
                Text("接收者使用自己选择的声音。此测试版使用原创合成音效与普通合成语音演示，不是现成动漫人物原声。声音遵循 iPhone 静音开关及系统媒体音量；静音时仍可看动画。分享扩展设置独立保存。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("甩送音效")
            .onDisappear { SoundFeedback.shared.stop() }
            .alert("音效提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好", role: .cancel) {} } message: { Text(message ?? "") }
    }
    private func preview(_ sending: Bool) { if let error = SoundFeedback.shared.play(sending: sending, pack: sending ? send : receive) { message = error } }
}

struct IncomingRequestView: View {
    @ObservedObject var link: PeerLink
    let request: IncomingRequest
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.green)
                Text("\(request.sender) 想分享给你").font(.title2).multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    Text(request.offer.filename).font(.headline).multilineTextAlignment(.center)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(request.offer.byteCount), countStyle: .file) + " · 原文件").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("确认后才展开内容并开始接收原文件。").font(.footnote).foregroundStyle(.secondary)
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 14) {
                        Button("拒绝") { link.answerIncoming(false) }.buttonStyle(.glass).frame(maxWidth: .infinity)
                        Button("接收并打开") { link.answerIncoming(true) }.buttonStyle(.glassProminent).frame(maxWidth: .infinity)
                    }.controlSize(.large)
                }
                Button("屏蔽此设备", role: .destructive) { link.answerIncoming(false, block: true) }.buttonStyle(.glass)
                Spacer(minLength: 0)
            }.padding(26).padding(.top, 24)
                .navigationTitle("接收邀请").navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
    }
}

func friendAlert(_ request: FriendInvitation, link: PeerLink) -> Alert {
    Alert(title: Text("添加好友？"), message: Text("\(request.sender) 想与你成为好友。双方确认后，可在附近连接时分享；远程服务尚未接入。"), primaryButton: .default(Text("同意")) { link.answerFriend(true) }, secondaryButton: .cancel(Text("拒绝")) { link.answerFriend(false) })
}
