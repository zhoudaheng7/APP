import Foundation
import UIKit
import Combine
import CryptoKit
@preconcurrency import MultipeerConnectivity

struct NearbyPhone: Identifiable {
    let peer: MCPeerID
    let name: String
    let code: String
    let deviceID: String
    let fingerprint: String
    var bluetoothID: UUID? = nil
    var id: String { peer.displayName }
}
struct ConnectionRequest: Identifiable {
    let id = UUID()
    let name: String
    let code: String
}
struct IncomingRequest: Identifiable {
    let id: UUID
    let sender: String
    let offer: TransferOffer
}
struct FriendInvitation: Identifiable {
    let id: UUID
    let sender: String
}
private struct InviteContext: Codable { let name: String; let code: String; let deviceID: String; let fingerprint: String }

final class PeerLink: NSObject, ObservableObject {
    @Published private(set) var nearby: [NearbyPhone] = []
    @Published private(set) var peerName: String?
    @Published private(set) var connecting = false
    @Published private(set) var peerAccepting = false
    @Published private(set) var isSending = false
    @Published private(set) var sendProgress: Double = 0
    @Published private(set) var sendStatus = "选中内容，分享这一刻"
    @Published private(set) var sendError = false
    @Published private(set) var outgoingStage: SendStage?
    @Published private(set) var lastThrowSide: ThrowSide = .right
    @Published private(set) var bearing: ThrowSide?
    @Published private(set) var distance: Float?
    @Published private(set) var bearingHint: String?
    @Published private(set) var authenticated = false
    @Published var autoReconnect = UserDefaults.standard.object(forKey: "flick.autoReconnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "flick.autoReconnect") }
    }
    @Published private(set) var receivedPhoto: ReceivedPhoto?
    @Published private(set) var inbox: [ReceivedPhoto] = []
    @Published private(set) var bluetoothNearby: [BluetoothPhone] = []
    @Published private(set) var usingBluetooth = false
    @Published private(set) var batchTotal = 0
    @Published private(set) var batchCompleted = 0
    @Published private(set) var batchActive = false
    @Published private(set) var deliveredAssetIDs: Set<UUID> = []
    @Published var bluetoothOnly = UserDefaults.standard.bool(forKey: "flick.bluetoothOnly") {
        didSet {
            UserDefaults.standard.set(bluetoothOnly, forKey: "flick.bluetoothOnly")
            if oldValue != bluetoothOnly { disconnect(reason: "传输方式已切换，请重新连接对方。") }
        }
    }
    var busySending: Bool { isSending || batchActive }
    var channelName: String { usingBluetooth ? "纯蓝牙 · 无需 Wi-Fi" : "高速直连 · 无需路由器" }
    var allNearby: [NearbyPhone] {
        // The visible list comes from actual BLE discovery, never a distance estimate.
        bluetoothNearby.map { device in
            if let phone = nearby.first(where: { $0.peer.displayName == device.name }) {
                return NearbyPhone(peer: phone.peer, name: phone.name, code: phone.code, deviceID: phone.deviceID, fingerprint: phone.fingerprint, bluetoothID: device.id)
            }
            return NearbyPhone(peer: MCPeerID(displayName: device.name), name: device.name, code: "连接后核对", deviceID: "", fingerprint: "", bluetoothID: device.id)
        }
    }
    @Published private(set) var receiveProgress: Double = 0
    @Published private(set) var diagnostic: String?
    @Published var invitation: ConnectionRequest?
    @Published var incomingRequest: IncomingRequest?
    @Published var friendInvitation: FriendInvitation?
    @Published private(set) var friends: [LocalFriend] = []
    @Published private(set) var requestingFriend = false
    @Published private(set) var blockedIDs: Set<String> = []
    @Published var discoverable = UserDefaults.standard.object(forKey: "flick.discoverable") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(discoverable, forKey: "flick.discoverable")
            if discoverable { if running { advertiser?.startAdvertisingPeer(); browser?.startBrowsingForPeers() } }
            else { advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers(); nearby = []; bluetoothNearby = [] }
            bluetooth.setDiscoverable(discoverable)
        }
    }
    @Published var allowNearby = UserDefaults.standard.object(forKey: "flick.nearReceive") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(allowNearby, forKey: "flick.nearReceive")
            if !allowNearby && !isCurrentFriend { cancelIncoming("对方关闭了附近接收。", notify: true) }
            sendHello()
        }
    }
    @Published var autoAcceptTrusted = UserDefaults.standard.object(forKey: "flick.autoTrusted.v4") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoAcceptTrusted, forKey: "flick.autoTrusted.v4") }
    }
    @Published private(set) var accepting = true
    let localName: String
    let code: String
    private let service = "flick-photo"
    private let identity = LocalIdentity()
    private let spatial = SpatialLocator()
    private let bluetooth = BluetoothTransport()
    private var exchangeKey = Curve25519.KeyAgreement.PrivateKey()
    private var bluetoothInvitation = false
    private var deferredBluetoothProof: WirePacket?
    private var connectionGeneration = UUID()
    private var queuedAssets: [PhotoAsset] = []
    private var batchSide: ThrowSide = .right
    private var bleReader: FileHandle?
    private var bleWriter: FileHandle?
    private var bleReceiveURL: URL?
    private var bleCursor: BluetoothFileCursor?
    private var bleSendOffset = 0
    private var bleExpectedAck: Int?
    #if !APP_EXTENSION
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    private var localNonce = UUID().uuidString
    private var remoteHello: WirePacket?
    private var manuallyConfirmed = false
    private var autoPendingID: String?
    private var allowAutoInvite = true
    private let peerID: MCPeerID
    private var session: MCSession!
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var connectedPeer: MCPeerID?
    private var expectedPeer: MCPeerID?
    private var invitationReply: ((Bool, MCSession?) -> Void)?
    private var transaction: SendTransaction?
    private var outboundPhoto: PhotoAsset?
    private var incomingOffer: TransferOffer?
    private var incomingPreview: UIImage?
    private var consentAccepted = false
    private var sentFriendRequest: UUID?
    private var friendTimeout: DispatchWorkItem?
    var canPresentIncoming = false
    private var presentedIDs = Set<UUID>()
    private var recentIDs: [UUID] = []
    private var resourceProgress: Progress?
    private var receiveResourceProgress: Progress?
    private var progressObservation: NSKeyValueObservation?
    private var receiveObservation: NSKeyValueObservation?
    private var timeout: DispatchWorkItem?
    private var receiveTimeout: DispatchWorkItem?
    private var connectionTimeout: DispatchWorkItem?
    private var running = false
    private let imageQueue = DispatchQueue(label: "flick.image-verification", qos: .userInitiated)
    var connected: Bool { (connectedPeer != nil || usingBluetooth && bluetooth.isConnected) && authenticated }
    var connectedDeviceID: String? { authenticated ? remoteHello?.deviceID : nil }
    var isCurrentFriend: Bool { connectedDeviceID.map { id in friends.contains { $0.id == id } } ?? false }
    var trustedDevices: [LocalFriend] { identity.trustedDevices }
    func revokeTrust(_ id: String) {
        identity.revoke(id); friends = identity.friends
        if connectedDeviceID == id { disconnect(reason: "已取消对此设备的信任，下次连接需要重新确认。") }
        objectWillChange.send()
    }
    private var isForeground: Bool {
        #if APP_EXTENSION
        return running
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }

    override init() {
        let savedID = UserDefaults.standard.string(forKey: "flick.identity.id") ?? UUID().uuidString
        UserDefaults.standard.set(savedID, forKey: "flick.identity.id")
        let suffix = String(savedID.suffix(4))
        localName = "iPhone · " + suffix
        code = String(Int.random(in: 100000...999999))
        peerID = MCPeerID(displayName: "Flick-" + suffix + "-" + String(UUID().uuidString.prefix(6)))
        super.init()
        friends = identity.friends
        blockedIDs = Set(UserDefaults.standard.stringArray(forKey: "flick.blocked.v3") ?? [])
        inbox = ReceiveInbox.load(); receivedPhoto = inbox.first
        PhotoFiles.cleanupOldFiles()
        bluetooth.discovered = { [weak self] phone in
            guard let self = self, self.discoverable else { return }
            self.bluetoothNearby.removeAll { $0.id == phone.id }; self.bluetoothNearby.append(phone)
        }
        bluetooth.status = { [weak self] text in self?.diagnostic = text }
        bluetooth.opened = { [weak self] name in self?.bluetoothOpened(name) }
        bluetooth.closed = { [weak self] reason in
            guard let self = self, self.usingBluetooth else { return }
            self.disconnect(reason: reason)
        }
        bluetooth.received = { [weak self] data in
            guard let self = self, self.usingBluetooth, data.count <= FlickRules.maxControlBytes,
                  let packet = try? JSONDecoder().decode(WirePacket.self, from: data) else { return }
            self.handle(packet, peer: nil)
        }
        #if APP_EXTENSION
        accepting = false
        #endif
        spatial.changed = { [weak self] side, distance, hint in
            self?.bearing = side; self?.distance = distance; self?.bearingHint = hint
        }
        newSession()
    }
    private func newSession() {
        localNonce = UUID().uuidString; remoteHello = nil; authenticated = false; exchangeKey = Curve25519.KeyAgreement.PrivateKey(); connectionGeneration = UUID()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }
    func activate() {
        bluetooth.start(name: peerID.displayName, discoverable: discoverable)
        guard !running else { return }
        running = true; diagnostic = nil; allowAutoInvite = true
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["name": localName, "code": code, "v": "4", "id": identity.deviceID, "key": identity.fingerprint], serviceType: service)
        advertiser?.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: service)
        browser?.delegate = self
        if discoverable { advertiser?.startAdvertisingPeer(); browser?.startBrowsingForPeers() }
    }
    func suspend() {
        SoundFeedback.shared.stop()
        running = false; browser?.stopBrowsingForPeers(); advertiser?.stopAdvertisingPeer()
        bluetooth.stop()
        disconnect(reason: "连接已结束，未发送的内容仍保留。")
        nearby = []
    }
    func background() {
        SoundFeedback.shared.stop()
        browser?.stopBrowsingForPeers(); advertiser?.stopAdvertisingPeer(); running = false
        if !usingBluetooth { disconnect(reason: "高速连接已暂停。后台接收请提前建立纯蓝牙连接。"); allowAutoInvite = true }
        // Core Bluetooth continues only while iOS grants event execution time.
        // No audio/location keepalive and no UI presentation from background.
    }
    private func bluetoothOpened(_ name: String) {
        if connectedPeer != nil || expectedPeer != nil || invitationReply != nil { bluetooth.disconnect("已有高速连接，请先断开后切换。"); return }
        usingBluetooth = true; connecting = true; peerName = name
        localNonce = UUID().uuidString; exchangeKey = Curve25519.KeyAgreement.PrivateKey(); remoteHello = nil; authenticated = false; connectionGeneration = UUID()
        sendHello()
        let generation = connectionGeneration
        let job = DispatchWorkItem { [weak self] in
            guard let self = self, self.connectionGeneration == generation, !self.authenticated else { return }
            self.disconnect(reason: "蓝牙设备核对超时，请双方打开 App 核对连接码。")
        }
        connectionTimeout?.cancel(); connectionTimeout = job; DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: job)
    }
    func connect(_ phone: NearbyPhone) {
        if let id = phone.bluetoothID, (bluetoothOnly || !nearby.contains(where: { $0.peer == phone.peer })) {
            guard !connected, !connecting else { return }
            manuallyConfirmed = true; autoPendingID = phone.deviceID.isEmpty ? nil : phone.deviceID; allowAutoInvite = true
            connecting = true; bluetooth.connect(id); return
        }
        guard running, discoverable, !blockedIDs.contains(phone.deviceID), !connected, !connecting, invitationReply == nil else { return }
        diagnostic = nil; expectedPeer = phone.peer; connecting = true; manuallyConfirmed = true; autoPendingID = nil; allowAutoInvite = true
        invite(phone)
    }
    private func invite(_ phone: NearbyPhone) {
        let context = try? JSONEncoder().encode(InviteContext(name: localName, code: code, deviceID: identity.deviceID, fingerprint: identity.fingerprint))
        browser?.invitePeer(phone.peer, to: session, withContext: context, timeout: 20)
        let job = DispatchWorkItem { [weak self] in
            guard let self = self, self.connecting else { return }
            self.disconnect(reason: "连接超时，请确认对方已打开一甩并接受邀请。")
        }
        connectionTimeout?.cancel(); connectionTimeout = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 22, execute: job)
    }
    func answerInvitation(_ allow: Bool) {
        if bluetoothInvitation {
            bluetoothInvitation = false; invitation = nil
            if allow {
                manuallyConfirmed = true; sendBluetoothProof()
                if let proof = deferredBluetoothProof { deferredBluetoothProof = nil; handle(proof, peer: nil) }
            }
            else { disconnect(reason: "已拒绝该设备的连接。") }
            return
        }
        guard let reply = invitationReply else { invitation = nil; return }
        invitationReply = nil; invitation = nil
        if allow {
            #if !APP_EXTENSION
            accepting = true
            #endif
            connecting = true; manuallyConfirmed = true; autoPendingID = nil
        }
        else { expectedPeer = nil }
        reply(allow, allow ? session : nil)
        if allow {
            let job = DispatchWorkItem { [weak self] in
                guard let self = self, self.connecting else { return }
                self.disconnect(reason: "连接未完成，请重新选择对方。")
            }
            connectionTimeout?.cancel(); connectionTimeout = job
            DispatchQueue.main.asyncAfter(deadline: .now() + 22, execute: job)
        }
    }
    func disconnect(reason: String = "连接已断开，选中的原文件仍保留。") {
        allowAutoInvite = false; spatial.stop()
        batchActive = false; queuedAssets = []
        let hadBluetooth = usingBluetooth; usingBluetooth = false; bluetoothInvitation = false
        deferredBluetoothProof = nil; manuallyConfirmed = false; autoPendingID = nil
        if hadBluetooth { bluetooth.disconnect(reason) }
        try? bleReader?.close(); bleReader = nil; try? bleWriter?.close(); bleWriter = nil
        if let url = bleReceiveURL { try? FileManager.default.removeItem(at: url) }; bleReceiveURL = nil; bleCursor = nil; bleExpectedAck = nil
        finishBackgroundTask()
        connectionTimeout?.cancel(); connectionTimeout = nil
        friendTimeout?.cancel(); sentFriendRequest = nil; requestingFriend = false; friendInvitation = nil
        invitationReply?(false, nil); invitationReply = nil; invitation = nil
        failOutgoing(reason, notify: false)
        cancelIncoming(reason, notify: false)
        session.disconnect(); session.delegate = nil
        connectedPeer = nil; expectedPeer = nil; peerName = nil; peerAccepting = false; connecting = false; authenticated = false
        newSession(); sendStatus = reason
    }
    func forgetDevices() { identity.forget(); friends = identity.friends; disconnect(reason: "已忘记配对与本地好友。下次连接需要重新确认。"); allowAutoInvite = true }
    func retryDiscovery() {
        allowAutoInvite = true
        for phone in nearby { scheduleAutoConnect(phone) }
    }
    func setAccepting(_ value: Bool) {
        #if APP_EXTENSION
        accepting = false
        #else
        accepting = value
        if !value { cancelIncoming("接收已暂停，原文件未接收完成。", notify: true) }
        #endif
        sendHello()
    }
    func note(_ text: String, error: Bool = false) { sendStatus = text; sendError = error }
    func requestFriend() {
        guard connected, connectedDeviceID != nil, !isCurrentFriend, !requestingFriend, !isSending, incomingOffer == nil else { return }
        let id = UUID()
        do {
            try sendPacket(WirePacket(.friendRequest, id: id))
            sentFriendRequest = id; requestingFriend = true; note("好友申请已发送，等待对方确认。")
            let job = DispatchWorkItem { [weak self] in
                guard self?.sentFriendRequest == id else { return }
                self?.sentFriendRequest = nil; self?.requestingFriend = false; self?.note("好友申请已过期，请重试。")
            }
            friendTimeout?.cancel(); friendTimeout = job; DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: job)
        } catch { note("好友申请发送失败，请重新连接。", error: true) }
    }
    func answerFriend(_ allow: Bool) {
        guard let request = friendInvitation, let id = connectedDeviceID else { friendInvitation = nil; return }
        friendInvitation = nil
        do {
            try sendPacket(WirePacket(.friendReply, id: request.id, accepting: allow))
            if allow { identity.addFriend(id: id, name: peerName ?? "朋友"); friends = identity.friends; sendHello() }
        } catch { note("好友确认未送达，请重试。", error: true) }
    }
    func removeFriend(_ id: String) {
        if id == connectedDeviceID { try? sendPacket(WirePacket(.friendRemoved)) }
        identity.removeFriend(id: id); friends = identity.friends; sendHello()
    }
    func unblock(_ id: String) { blockedIDs.remove(id); saveBlocks() }
    private func saveBlocks() { UserDefaults.standard.set(Array(blockedIDs), forKey: "flick.blocked.v3") }
    func answerIncoming(_ allow: Bool, block: Bool = false) {
        guard let request = incomingRequest, incomingOffer?.id == request.id else { return }
        incomingRequest = nil
        if block, let id = connectedDeviceID { blockedIDs.insert(id); nearby.removeAll { $0.deviceID == id }; saveBlocks() }
        if allow { consentAccepted = true }
        else { cancelIncoming(block ? "对方已屏蔽此设备。" : "对方拒绝了本次接收。", notify: true) }
        if block { disconnect(reason: "已屏蔽该设备，可在设置中解除。") }
    }
    func finishConsentPresentation() {
        guard consentAccepted else { return }; consentAccepted = false
        guard connected, accepting else { cancelIncoming("接收已暂停，请重新投送。", notify: true); return }
        openIncoming()
    }
    private func openIncoming() {
        guard let offer = incomingOffer, let preview = incomingPreview else { return }
        incomingRequest = nil
        receivedPhoto = ReceivedPhoto(id: offer.id, offer: offer, sender: peerName ?? "朋友", entrySide: bearing ?? offer.side.opposite, image: preview)
        inbox.insert(receivedPhoto!, at: 0)
        if inbox.count > 200 { inbox.removeLast() }
        incomingPreview = nil
        presentedIDs.insert(offer.id)
        if usingBluetooth {
            do {
                let file = PhotoFiles.directory.appendingPathComponent("ble-" + offer.id.uuidString)
                FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                bleWriter = try FileHandle(forWritingTo: file); bleReceiveURL = file; bleCursor = try BluetoothFileCursor(total: offer.byteCount)
            } catch { cancelIncoming("无法准备原文件接收，请检查剩余空间。", notify: true); return }
        }
        do { try sendPacket(WirePacket(.ready, id: offer.id)); armReceiveTimeout(offer.id) }
        catch { cancelIncoming("接收连接中断，请重试。", notify: false) }
    }
    func receivedItem(_ id: UUID) -> ReceivedPhoto? { inbox.first { $0.id == id } }
    func removeReceived(_ id: UUID) {
        guard incomingOffer?.id != id else { return }
        ReceiveInbox.remove(id); inbox.removeAll { $0.id == id }; if receivedPhoto?.id == id { receivedPhoto = inbox.first }
    }
    func sendBatch(_ assets: [PhotoAsset], side: ThrowSide) {
        guard !busySending, connected, peerAccepting, incomingOffer == nil, isForeground, running else { note("请先连接并等待当前接收完成。", error: true); return }
        queuedAssets = assets.filter { !deliveredAssetIDs.contains($0.id) }
        guard !queuedAssets.isEmpty else { note("这批内容均已确认送达。"); return }
        batchTotal = queuedAssets.count; batchCompleted = 0; batchSide = side; batchActive = true; sendNextInBatch()
    }
    private func sendNextInBatch() {
        guard batchActive, !isSending else { return }
        guard let asset = queuedAssets.first else { batchActive = false; note("\(batchCompleted) 个原文件已全部送达并校验。"); return }
        send(asset, side: batchSide)
        if !isSending { batchActive = false; queuedAssets = [] }
    }
    func cancelSending() { batchActive = false; queuedAssets = []; failOutgoing("发送已取消，未送达项目可重试。") }
    func send(_ asset: PhotoAsset, side: ThrowSide) {
        guard connected else { note("先连接附近的另一台 iPhone。", error: true); return }
        guard peerAccepting else { note("对方已暂停接收，原文件留在这里。", error: true); return }
        guard running, isForeground, !isSending, incomingOffer == nil else {
            note("请等待当前传输完成。", error: true); return
        }
        let offer = asset.offer(side: side)
        transaction = SendTransaction(offer: offer); outboundPhoto = asset
        isSending = true; sendError = false; sendProgress = 0; lastThrowSide = side; outgoingStage = .awaitingPreview
        sendStatus = "正在准备甩给 \(peerName ?? "对方")…"
        do {
            try sendPacket(WirePacket(.offer, id: offer.id, offer: offer, preview: usingBluetooth ? asset.bluetoothPreview : asset.previewData))
            SoundFeedback.shared.play(sending: true)
            sendStatus = "邀请已甩出，等待对方接收…"
            armSendTimeout(60, id: offer.id, reason: "对方未接收，原文件仍保留，可以重试。")
        } catch { failOutgoing("发送准备失败：\(error.localizedDescription)") }
    }
    func previewPresented(id: UUID) {
        guard receivedItem(id) != nil, connected, isForeground else { return }
        try? sendPacket(WirePacket(.presented, id: id))
        SoundFeedback.shared.play(sending: false)
    }
    private func sendHello() {
        var packet = WirePacket(.hello, accepting: accepting && (allowNearby || isCurrentFriend), name: localName)
        packet.deviceID = identity.deviceID; packet.publicKey = identity.publicKey; packet.nonce = localNonce; packet.nearbyToken = spatial.tokenData
        packet.code = code; if usingBluetooth { packet.exchangeKey = exchangeKey.publicKey.rawRepresentation }
        try? sendPacket(packet)
    }
    private func scheduleAutoConnect(_ phone: NearbyPhone) {
        guard !connected, !usingBluetooth, !bluetoothOnly, autoReconnect, allowAutoInvite, discoverable, !blockedIDs.contains(phone.deviceID), identity.trustedKey(for: phone.deviceID) != nil else { return }
        let delay = identity.deviceID < phone.deviceID ? 0.4 : 1.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.connected, !self.usingBluetooth, self.running, self.discoverable, !self.blockedIDs.contains(phone.deviceID), self.nearby.contains(where: { $0.peer == phone.peer }), self.autoReconnect, self.allowAutoInvite, self.connectedPeer == nil, !self.connecting, self.invitationReply == nil else { return }
            self.expectedPeer = phone.peer; self.connecting = true; self.manuallyConfirmed = false; self.autoPendingID = phone.deviceID
            self.invite(phone)
        }
    }
    private func sendPacket(_ packet: WirePacket) throws {
        let data = try JSONEncoder().encode(packet)
        guard data.count <= FlickRules.maxControlBytes else { throw PhotoFailure.tooLarge }
        if usingBluetooth {
            try bluetooth.send(data, handshake: packet.kind == .hello && !authenticated || packet.kind == .proof)
        } else {
            guard let peer = connectedPeer else { throw PhotoFailure.invalid }
            try session.send(data, toPeers: [peer], with: .reliable)
        }
    }
    private func handle(_ packet: WirePacket, peer: MCPeerID?) {
        guard packet.version == 4, usingBluetooth ? peer == nil : peer != nil && peer == connectedPeer else { return }
        if packet.kind != .hello && packet.kind != .proof && !authenticated { return }
        switch packet.kind {
        case .hello:
            guard let id = packet.deviceID, let key = packet.publicKey, key.count == 64, let nonce = packet.nonce, nonce.count == 36 else { disconnect(reason: "设备核对失败，请重新配对。"); return }
            guard !blockedIDs.contains(id) else { disconnect(reason: "此设备已屏蔽。"); return }
            if let expected = autoPendingID, expected != id { disconnect(reason: "设备身份不匹配，请重新配对。"); return }
            if let known = identity.trustedKey(for: id), known != key { disconnect(reason: "设备身份已变化，请先忘记配对再重新连接。"); return }
            if usingBluetooth {
                guard packet.exchangeKey?.count == 32 else { disconnect(reason: "对方不支持安全蓝牙连接。"); return }
                if authenticated {
                    guard let old = remoteHello, old.deviceID == id, old.publicKey == key, old.nonce == nonce, old.exchangeKey == packet.exchangeKey else { disconnect(reason: "蓝牙身份在连接中发生变化。"); return }
                    remoteHello = packet; peerAccepting = packet.accepting ?? false; return
                }
                remoteHello = packet; peerName = String((packet.name ?? "蓝牙设备").prefix(40)); peerAccepting = packet.accepting ?? false
                if manuallyConfirmed || identity.trustedKey(for: id) == key { sendBluetoothProof() }
                else if isForeground {
                    bluetoothInvitation = true; invitation = ConnectionRequest(name: peerName ?? "蓝牙设备", code: String((packet.code ?? "------").prefix(6)))
                } else { disconnect(reason: "首次信任需要双方打开 App 完成确认。") }
                return
            }
            guard manuallyConfirmed || identity.trustedKey(for: id) == key else { disconnect(reason: "需要先确认这台设备。"); return }
            remoteHello = packet
            var proof = WirePacket(.proof); proof.nonce = localNonce
            proof.signature = try? identity.key.signature(for: IdentityProof.message(challenge: nonce, responderNonce: localNonce)).rawRepresentation
            try? sendPacket(proof)
            peerAccepting = packet.accepting ?? false
            if let name = packet.name, !name.isEmpty { peerName = String(name.prefix(40)) }
            if !peerAccepting && isSending { failOutgoing("对方暂停了接收，原文件仍保留。") }
            if authenticated, let data = packet.nearbyToken { spatial.run(peerToken: data) }
        case .proof:
            guard let hello = remoteHello, let key = hello.publicKey, let id = hello.deviceID, let nonce = hello.nonce,
                  packet.nonce == nonce, let signature = packet.signature else { disconnect(reason: "设备验证未通过，请重新配对。"); return }
            if usingBluetooth {
                guard manuallyConfirmed || identity.trustedKey(for: id) == key else { deferredBluetoothProof = packet; return }
                do {
                    let remote = try bluetoothHello(hello), local = localBluetoothHello()
                    let signing = try P256.Signing.PublicKey(rawRepresentation: key)
                    guard signing.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: try BluetoothHandshake.proof(local: local, remote: remote, signer: id)) else { throw BluetoothFailure.authentication }
                    if !authenticated { bluetooth.installCipher(try BluetoothCipher(privateKey: exchangeKey, local: local, remote: remote)) }
                } catch { disconnect(reason: "蓝牙身份验证未通过，请重新配对。"); return }
            } else if !IdentityProof.verify(key: key, signature: signature, challenge: localNonce, responderNonce: nonce) { disconnect(reason: "设备验证未通过，请重新配对。"); return }
            if !authenticated {
                identity.remember(id: id, key: key, name: peerName ?? "朋友"); authenticated = true; connecting = false; connectionTimeout?.cancel()
                sendStatus = "连接好了，上下左右都可以甩出。"; sendError = false
                if let data = hello.nearbyToken { spatial.run(peerToken: data) }
                sendHello()
            }
        case .offer:
            guard let offer = packet.offer, packet.id == offer.id, offer.isValid,
                  let data = packet.preview, data.count <= FlickRules.maxPreviewBytes,
                  let preview = UIImage(data: data) else { reject(packet.id, "文件格式或大小不受支持。"); return }
            guard !recentIDs.contains(offer.id) else { reject(offer.id, "该次投送已处理，请重新发送。"); return }
            let trusted = connectedDeviceID.flatMap { identity.trustedKey(for: $0) } != nil
            let decision = ReceivePolicy.decide(enabled: accepting && (allowNearby || isCurrentFriend), trusted: trusted, automatic: autoAcceptTrusted, foreground: isForeground, bluetooth: usingBluetooth)
            guard decision != .reject else { reject(offer.id, "对方暂不允许自动接收，请打开 App 或检查接收设置。"); return }
            guard incomingOffer == nil, !isSending else { reject(offer.id, "对方正在传输，请稍后再甩。"); return }
            incomingOffer = offer; receiveProgress = 0
            incomingPreview = preview
            if decision == .open { openIncoming() }
            else { incomingRequest = IncomingRequest(id: offer.id, sender: peerName ?? "朋友", offer: offer) }
            armReceiveTimeout(offer.id)
        case .friendRequest:
            guard let id = packet.id else { return }
            if isCurrentFriend { try? sendPacket(WirePacket(.friendReply, id: id, accepting: true)); return }
            guard friendInvitation == nil, incomingOffer == nil, !isSending else { try? sendPacket(WirePacket(.friendReply, id: id, accepting: false)); return }
            friendInvitation = FriendInvitation(id: id, sender: peerName ?? "朋友")
            DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in
                guard self?.friendInvitation?.id == id else { return }; self?.answerFriend(false)
            }
        case .friendReply:
            guard let request = sentFriendRequest, packet.id == request, let id = connectedDeviceID else { return }
            sentFriendRequest = nil; requestingFriend = false; friendTimeout?.cancel()
            if packet.accepting == true { identity.addFriend(id: id, name: peerName ?? "朋友"); friends = identity.friends; note("已添加好友，可在附近连接时甩送。"); sendHello() }
            else { note("对方未同意好友申请。") }
        case .friendRemoved:
            if let id = connectedDeviceID { identity.removeFriend(id: id); friends = identity.friends; sendHello() }
        case .ready:
            guard let id = packet.id, transaction?.ready(id: id) == true, let asset = outboundPhoto, let offer = transaction?.offer else { return }
            outgoingStage = .transferring; sendStatus = "内容已飞过去 · 原文件传输中"
            timeout?.cancel()
            if usingBluetooth {
                do { bleReader = try FileHandle(forReadingFrom: asset.url); bleSendOffset = 0; bleExpectedAck = nil; sendBluetoothChunk() }
                catch { failOutgoing("无法读取原文件，请重新选择。") }
                return
            }
            guard let peer = peer else { failOutgoing("高速连接已断开。"); return }
            resourceProgress = session.sendResource(at: asset.url, withName: offer.resourceName, toPeer: peer) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self, self.transaction?.offer.id == id, self.isSending else { return }
                    if let error = error { self.failOutgoing("原文件传输失败：\(error.localizedDescription)") }
                }
            }
            guard let progress = resourceProgress else { failOutgoing("原文件无法开始传输，请重试。"); return }
            progressObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] value, _ in
                DispatchQueue.main.async { if self?.transaction?.offer.id == id { self?.sendProgress = value.fractionCompleted } }
            }
            armSendTimeout(120 + Double(offer.byteCount) / (200 * 1024), id: id, reason: "原文件传输超时，文件仍保留，可以重试。")
        case .presented:
            guard let id = packet.id else { return }
            transaction?.presented(id: id)
            if transaction?.offer.id == id, isSending { sendStatus = "对方已展开 · 原文件传输中" }
        case .received:
            guard let id = packet.id, transaction?.received(id: id) == true else { return }
            timeout?.cancel(); progressObservation = nil; resourceProgress = nil
            isSending = false; sendProgress = 1; outgoingStage = .delivered; sendError = false
            if let asset = outboundPhoto { deliveredAssetIDs.insert(asset.id) }
            try? bleReader?.close(); bleReader = nil; bleExpectedAck = nil
            sendStatus = "已送达 · 原文件已确认"; outboundPhoto = nil
            FlickFeedback.notification(.success)
            if batchActive {
                if !queuedAssets.isEmpty { queuedAssets.removeFirst(); batchCompleted += 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.sendNextInBatch() }
            }
        case .chunk:
            guard usingBluetooth, let offer = incomingOffer, packet.id == offer.id, presentedIDs.contains(offer.id),
                  let data = packet.chunk, let offset = packet.offset else { return }
            do {
                guard var cursor = bleCursor, let file = bleWriter else { throw BluetoothFailure.offset }
                try cursor.accept(offset: offset, count: data.count); try file.write(contentsOf: data)
                bleCursor = cursor; receiveProgress = Double(cursor.offset) / Double(offer.byteCount)
                var ack = WirePacket(.chunkAck, id: offer.id); ack.offset = cursor.offset; try sendPacket(ack); armReceiveTimeout(offer.id)
            } catch { cancelIncoming("蓝牙原文件写入失败，请检查剩余空间后重试。", notify: true) }
        case .chunkAck:
            guard usingBluetooth, let offer = transaction?.offer, packet.id == offer.id, isSending,
                  let expected = bleExpectedAck, packet.offset == expected else { return }
            bleSendOffset = expected; bleExpectedAck = nil; sendProgress = Double(expected) / Double(offer.byteCount); sendBluetoothChunk()
        case .fileEnd:
            guard usingBluetooth, let offer = incomingOffer, packet.id == offer.id, bleCursor?.complete == true, let url = bleReceiveURL else { return }
            do { try bleWriter?.synchronize(); try bleWriter?.close(); bleWriter = nil; bleReceiveURL = nil; verifyOriginal(url, offer: offer, generation: connectionGeneration) }
            catch { cancelIncoming("蓝牙原文件未保存完成，请重试。", notify: true) }
        case .cancel, .reject:
            if let id = packet.id, id == transaction?.offer.id, isSending { failOutgoing(packet.reason ?? "对方取消了接收，原文件仍保留。", notify: false) }
            if let id = packet.id, id == incomingOffer?.id { cancelIncoming(packet.reason ?? "发送方已取消。", notify: false) }
        }
    }
    private func reject(_ id: UUID?, _ reason: String) { try? sendPacket(WirePacket(.reject, id: id, reason: reason)) }
    private func armSendTimeout(_ seconds: Double, id: UUID, reason: String) {
        timeout?.cancel()
        let job = DispatchWorkItem { [weak self] in
            guard self?.transaction?.offer.id == id, self?.isSending == true else { return }
            self?.failOutgoing(reason)
        }
        timeout = job; DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: job)
    }
    private func failOutgoing(_ reason: String, notify: Bool = true) {
        guard isSending else { return }
        if notify { try? sendPacket(WirePacket(.cancel, id: transaction?.offer.id, reason: "发送已取消，请重新投送。")) }
        batchActive = false; queuedAssets = []; try? bleReader?.close(); bleReader = nil; bleExpectedAck = nil
        transaction?.fail(); resourceProgress?.cancel(); resourceProgress = nil; progressObservation = nil; timeout?.cancel()
        isSending = false; outgoingStage = .failed; outboundPhoto = nil; sendProgress = 0; sendStatus = reason; sendError = true
        FlickFeedback.notification(.error)
    }
    private func cancelIncoming(_ reason: String, notify: Bool) {
        guard let offer = incomingOffer else { return }
        if notify { try? sendPacket(WirePacket(.cancel, id: offer.id, reason: reason)) }
        receiveResourceProgress?.cancel(); receiveResourceProgress = nil; receiveObservation = nil; receiveTimeout?.cancel()
        if receivedPhoto?.id == offer.id { receivedPhoto?.failure = reason }
        if let index = inbox.firstIndex(where: { $0.id == offer.id }) { inbox[index].failure = reason }
        try? bleWriter?.close(); bleWriter = nil; bleCursor = nil
        if let url = bleReceiveURL { try? FileManager.default.removeItem(at: url) }; bleReceiveURL = nil
        finishBackgroundTask()
        incomingOffer = nil; incomingPreview = nil; incomingRequest = nil; consentAccepted = false; presentedIDs.remove(offer.id)
    }
    private func finishResource(_ url: URL, name: String, peer: MCPeerID, currentSession: MCSession) {
        guard currentSession === session, peer == connectedPeer, let offer = incomingOffer, name == offer.resourceName,
              presentedIDs.contains(offer.id), receivedPhoto?.id == offer.id else { try? FileManager.default.removeItem(at: url); return }
        verifyOriginal(url, offer: offer, generation: connectionGeneration)
    }
    private func verifyOriginal(_ url: URL, offer: TransferOffer, generation: UUID) {
        beginBackgroundTask()
        let preview = receivedItem(offer.id)?.image ?? PhotoFiles.placeholder(offer.kind)
        let sender = peerName ?? "朋友", entry = receivedItem(offer.id)?.entrySide ?? offer.side.opposite
        imageQueue.async { [weak self] in
            let result: Result<ReceivedPhoto, Error> = Result {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size == offer.byteCount, try PhotoFiles.digest(url) == offer.sha256 else { throw PhotoFailure.invalid }
                var photo = ReceivedPhoto(id: offer.id, offer: offer, sender: sender, entrySide: entry, image: preview, originalURL: url)
                try ReceiveInbox.commit(photo)
                photo.originalURL = ReceiveInbox.folder(offer.id).appendingPathComponent("original").appendingPathComponent(offer.filename)
                return photo
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.finishBackgroundTask()
                switch result {
                case .success(let photo):
                    if let index = self.inbox.firstIndex(where: { $0.id == offer.id }) { self.inbox[index] = photo } else { self.inbox.insert(photo, at: 0) }
                    if self.receivedPhoto?.id == offer.id { self.receivedPhoto = photo }
                    guard self.connectionGeneration == generation, self.incomingOffer?.id == offer.id else { return }
                    self.receiveProgress = 1; self.incomingOffer = nil; self.receiveTimeout?.cancel(); self.receiveObservation = nil; self.receiveResourceProgress = nil
                    self.bleCursor = nil; self.recentIDs.append(offer.id); if self.recentIDs.count > 64 { self.recentIDs.removeFirst() }
                    self.presentedIDs.remove(offer.id); try? self.sendPacket(WirePacket(.received, id: offer.id))
                    if self.isForeground { FlickFeedback.notification(.success) }
                case .failure:
                    try? FileManager.default.removeItem(at: url)
                    if self.connectionGeneration == generation { self.cancelIncoming("原文件校验或保存未完成，请让对方重新发送。", notify: true) }
                }
            }
        }
    }
    private func localBluetoothHello() -> BluetoothHello {
        BluetoothHello(id: identity.deviceID, signingKey: identity.publicKey, exchangeKey: exchangeKey.publicKey.rawRepresentation, nonce: localNonce)
    }
    private func bluetoothHello(_ packet: WirePacket) throws -> BluetoothHello {
        guard let id = packet.deviceID, let key = packet.publicKey, let exchange = packet.exchangeKey, let nonce = packet.nonce else { throw BluetoothFailure.authentication }
        let hello = BluetoothHello(id: id, signingKey: key, exchangeKey: exchange, nonce: nonce)
        guard hello.valid else { throw BluetoothFailure.authentication }; return hello
    }
    private func sendBluetoothProof() {
        guard let hello = remoteHello else { return }
        do {
            var proof = WirePacket(.proof); proof.nonce = localNonce
            proof.signature = try identity.key.signature(for: BluetoothHandshake.proof(local: localBluetoothHello(), remote: bluetoothHello(hello), signer: identity.deviceID)).rawRepresentation
            try sendPacket(proof)
        } catch { disconnect(reason: "蓝牙核对失败，请重试。") }
    }
    private func sendBluetoothChunk() {
        guard isSending, let offer = transaction?.offer, bleExpectedAck == nil else { return }
        do {
            if bleSendOffset == offer.byteCount {
                try sendPacket(WirePacket(.fileEnd, id: offer.id)); armSendTimeout(180, id: offer.id, reason: "对方未确认原文件校验，请检查对方接收列表。")
            } else {
                guard let data = try bleReader?.read(upToCount: min(16 * 1024, offer.byteCount - bleSendOffset)), !data.isEmpty else { throw PhotoFailure.invalid }
                var packet = WirePacket(.chunk, id: offer.id); packet.offset = bleSendOffset; packet.chunk = data
                bleExpectedAck = bleSendOffset + data.count; try sendPacket(packet)
                sendStatus = "纯蓝牙传输中 · \(batchCompleted + 1)/\(max(1, batchTotal)) · 请保持发送端打开"
                armSendTimeout(90, id: offer.id, reason: "蓝牙传输中断，已送达项目保留，未送达项目可重试。")
            }
        } catch { failOutgoing("蓝牙原文件读取或发送失败，请重试。") }
    }
    private func armReceiveTimeout(_ id: UUID) {
        receiveTimeout?.cancel()
        let job = DispatchWorkItem { [weak self] in guard self?.incomingOffer?.id == id else { return }; self?.cancelIncoming("接收已中断，请让对方重试。", notify: true) }
        receiveTimeout = job
        let seconds = usingBluetooth ? 120 : 120 + Double(incomingOffer?.byteCount ?? 0) / (200 * 1024)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: job)
    }
    private func beginBackgroundTask() {
        #if !APP_EXTENSION
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish received original") { [weak self] in
            self?.finishBackgroundTask()
            // Never acknowledge an unverified original when the OS expires execution time.
        }
        #endif
    }
    private func finishBackgroundTask() {
        #if !APP_EXTENSION
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
        #endif
    }
}

extension PeerLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.discoverable, browser === self.browser, info?["v"] == "4", let id = info?["id"], !self.blockedIDs.contains(id), let fingerprint = info?["key"] else { return }
            self.nearby.removeAll { $0.peer == peerID }
            let phone = NearbyPhone(peer: peerID, name: String((info?["name"] ?? "附近的 iPhone").prefix(40)), code: String((info?["code"] ?? "------").prefix(6)), deviceID: id, fingerprint: fingerprint)
            self.nearby.append(phone); self.scheduleAutoConnect(phone)
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, browser === self.browser else { return }
            self.nearby.removeAll { $0.peer == peerID }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in self?.diagnostic = "无法发现附近设备。请在设置中允许一甩使用本地网络，并打开 Wi-Fi 和蓝牙。\n\(error.localizedDescription)" }
    }
}
extension PeerLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.discoverable, !self.bluetoothOnly, !self.usingBluetooth, advertiser === self.advertiser, self.running, self.connectedPeer == nil, !self.connecting, self.invitationReply == nil,
                  let context = context, context.count < 2048, let invite = try? JSONDecoder().decode(InviteContext.self, from: context), !self.blockedIDs.contains(invite.deviceID) else { invitationHandler(false, nil); return }
            self.expectedPeer = peerID; self.invitationReply = invitationHandler
            if self.autoReconnect, self.allowAutoInvite, let key = self.identity.trustedKey(for: invite.deviceID), SHA256.hash(data: key).map({ String(format: "%02x", $0) }).joined() == invite.fingerprint {
                self.manuallyConfirmed = false; self.autoPendingID = invite.deviceID; self.connecting = true; self.invitationReply = nil
                invitationHandler(true, self.session); return
            }
            self.invitation = ConnectionRequest(name: String(invite.name.prefix(40)), code: String(invite.code.prefix(6)))
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in self?.diagnostic = "附近广播未开启。请检查本地网络权限。\n\(error.localizedDescription)" }
    }
}
extension PeerLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, session === self.session else { return }
            if self.usingBluetooth { session.disconnect(); return }
            switch state {
            case .connected:
                guard self.connectedPeer == nil, self.expectedPeer == peerID else { self.disconnect(reason: "连接对象已变化，请重新确认。"); return }
                self.connectedPeer = peerID; self.connecting = true
                self.peerName = self.nearby.first(where: { $0.peer == peerID })?.name ?? self.invitation?.name ?? "另一台 iPhone"
                self.sendStatus = "正在核对已连接设备…"; self.sendError = false; self.sendHello()
                let job = DispatchWorkItem { [weak self] in
                    guard let self = self, self.session === session, !self.authenticated else { return }
                    self.disconnect(reason: "设备核对超时，请重新连接。")
                }
                self.connectionTimeout?.cancel(); self.connectionTimeout = job
                DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: job)
            case .notConnected:
                if self.connectedPeer == peerID || self.expectedPeer == peerID {
                    let retry = self.authenticated && self.autoReconnect && self.running
                    self.disconnect(reason: "对方已断开连接，原文件仍保留。")
                    if retry {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                            guard let self = self, self.running, !self.connected, !self.connecting else { return }
                            self.retryDiscovery()
                        }
                    }
                }
            case .connecting: self.connecting = true
            @unknown default: break
            }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= FlickRules.maxControlBytes, let packet = try? JSONDecoder().decode(WirePacket.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in guard let self = self, session === self.session else { return }; self.handle(packet, peer: peerID) }
    }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, session === self.session, peerID == self.connectedPeer, let offer = self.incomingOffer,
                  offer.resourceName == resourceName, self.presentedIDs.contains(offer.id), self.receivedPhoto?.id == offer.id, self.accepting else { progress.cancel(); return }
            self.receiveResourceProgress = progress
            self.receiveObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] value, _ in
                DispatchQueue.main.async { if self?.incomingOffer?.resourceName == resourceName { self?.receiveProgress = value.fractionCompleted } }
            }
        }
    }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard error == nil, let source = localURL else {
            DispatchQueue.main.async { [weak self] in if session === self?.session, self?.incomingOffer?.resourceName == resourceName { self?.cancelIncoming("原文件传输中断，请重新发送。", notify: true) } }; return
        }
        do {
            let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= FlickRules.maxFileBytes else { throw PhotoFailure.tooLarge }
            let suffix = URL(fileURLWithPath: resourceName).pathExtension
            guard suffix.count <= 16, suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw PhotoFailure.invalid }
            let copy = PhotoFiles.directory.appendingPathComponent("received-\(UUID().uuidString).\(suffix)")
            try FileManager.default.copyItem(at: source, to: copy)
            DispatchQueue.main.async { [weak self] in self?.finishResource(copy, name: resourceName, peer: peerID, currentSession: session) }
        } catch {
            DispatchQueue.main.async { [weak self] in if session === self?.session, self?.incomingOffer?.resourceName == resourceName { self?.cancelIncoming("无法读取收到的原文件，请重试。", notify: true) } }
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
}
