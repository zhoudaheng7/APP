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
            else { advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers(); nearby = [] }
        }
    }
    @Published var allowNearby = UserDefaults.standard.object(forKey: "flick.nearReceive") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(allowNearby, forKey: "flick.nearReceive")
            if !allowNearby && !isCurrentFriend { cancelIncoming("对方关闭了附近接收。", notify: true) }
            sendHello()
        }
    }
    @Published var autoAcceptFriends = UserDefaults.standard.bool(forKey: "flick.autoFriends") {
        didSet { UserDefaults.standard.set(autoAcceptFriends, forKey: "flick.autoFriends") }
    }
    @Published private(set) var accepting = true
    let localName: String
    let code: String
    private let service = "flick-photo"
    private let identity = LocalIdentity()
    private let spatial = SpatialLocator()
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
    var connected: Bool { connectedPeer != nil && authenticated }
    var connectedDeviceID: String? { authenticated ? remoteHello?.deviceID : nil }
    var isCurrentFriend: Bool { connectedDeviceID.map { id in friends.contains { $0.id == id } } ?? false }
    var withinTwentyMeters: Bool { ReceivePolicy.isWithinTwentyMeters(distance, fresh: distance != nil) }
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
        PhotoFiles.cleanupOldFiles()
        #if APP_EXTENSION
        accepting = false
        #endif
        spatial.changed = { [weak self] side, distance, hint in
            self?.bearing = side; self?.distance = distance; self?.bearingHint = hint
        }
        newSession()
    }
    private func newSession() {
        localNonce = UUID().uuidString; remoteHello = nil; authenticated = false
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }
    func activate() {
        guard !running else { return }
        running = true; diagnostic = nil; allowAutoInvite = true
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["name": localName, "code": code, "v": "3", "id": identity.deviceID, "key": identity.fingerprint], serviceType: service)
        advertiser?.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: service)
        browser?.delegate = self
        if discoverable { advertiser?.startAdvertisingPeer(); browser?.startBrowsingForPeers() }
    }
    func suspend() {
        SoundFeedback.shared.stop()
        running = false; browser?.stopBrowsingForPeers(); advertiser?.stopAdvertisingPeer()
        disconnect(reason: "已暂停连接，回到前台后请重新连接。")
        nearby = []
    }
    func connect(_ phone: NearbyPhone) {
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
        guard connected, accepting, isForeground else { cancelIncoming("接收界面已关闭，请重新投送。", notify: true); return }
        openIncoming()
    }
    private func openIncoming() {
        guard let offer = incomingOffer, let preview = incomingPreview else { return }
        incomingRequest = nil
        receivedPhoto = ReceivedPhoto(id: offer.id, offer: offer, sender: peerName ?? "朋友", entrySide: bearing ?? offer.side.opposite, image: preview)
        incomingPreview = nil
    }
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
            try sendPacket(WirePacket(.offer, id: offer.id, offer: offer, preview: asset.previewData))
            SoundFeedback.shared.play(sending: true)
            sendStatus = "邀请已甩出，等待对方接收…"
            armSendTimeout(60, id: offer.id, reason: "对方未接收，原文件仍保留，可以重试。")
        } catch { failOutgoing("发送准备失败：\(error.localizedDescription)") }
    }
    func previewPresented(id: UUID) {
        guard let offer = incomingOffer, offer.id == id, accepting, connected, !presentedIDs.contains(id),
              isForeground else { return }
        presentedIDs.insert(id)
        do {
            try sendPacket(WirePacket(.ready, id: id))
            try sendPacket(WirePacket(.presented, id: id))
            SoundFeedback.shared.play(sending: false)
        } catch { cancelIncoming("连接中断，原文件未接收完成。", notify: false) }
    }
    private func sendHello() {
        var packet = WirePacket(.hello, accepting: accepting && (allowNearby || isCurrentFriend), name: localName)
        packet.deviceID = identity.deviceID; packet.publicKey = identity.publicKey; packet.nonce = localNonce; packet.nearbyToken = spatial.tokenData
        try? sendPacket(packet)
    }
    private func scheduleAutoConnect(_ phone: NearbyPhone) {
        guard autoReconnect, allowAutoInvite, discoverable, !blockedIDs.contains(phone.deviceID), identity.trustedKey(for: phone.deviceID) != nil else { return }
        let delay = identity.deviceID < phone.deviceID ? 0.4 : 1.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.running, self.discoverable, !self.blockedIDs.contains(phone.deviceID), self.nearby.contains(where: { $0.peer == phone.peer }), self.autoReconnect, self.allowAutoInvite, self.connectedPeer == nil, !self.connecting, self.invitationReply == nil else { return }
            self.expectedPeer = phone.peer; self.connecting = true; self.manuallyConfirmed = false; self.autoPendingID = phone.deviceID
            self.invite(phone)
        }
    }
    private func sendPacket(_ packet: WirePacket) throws {
        guard let peer = connectedPeer else { throw NSError(domain: "Flick", code: 1, userInfo: [NSLocalizedDescriptionKey: "尚未连接设备"] ) }
        let data = try JSONEncoder().encode(packet)
        guard data.count <= FlickRules.maxControlBytes else { throw PhotoFailure.tooLarge }
        try session.send(data, toPeers: [peer], with: .reliable)
    }
    private func handle(_ packet: WirePacket, peer: MCPeerID) {
        guard packet.version == 3, peer == connectedPeer else { return }
        if packet.kind != .hello && packet.kind != .proof && !authenticated { return }
        switch packet.kind {
        case .hello:
            guard let id = packet.deviceID, let key = packet.publicKey, key.count == 64, let nonce = packet.nonce, nonce.count == 36 else { disconnect(reason: "设备核对失败，请重新配对。"); return }
            guard !blockedIDs.contains(id) else { disconnect(reason: "此设备已屏蔽。"); return }
            if let expected = autoPendingID, expected != id { disconnect(reason: "设备身份不匹配，请重新配对。"); return }
            if let known = identity.trustedKey(for: id), known != key { disconnect(reason: "设备身份已变化，请先忘记配对再重新连接。"); return }
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
                  packet.nonce == nonce, let signature = packet.signature,
                  IdentityProof.verify(key: key, signature: signature, challenge: localNonce, responderNonce: nonce) else { disconnect(reason: "设备验证未通过，请重新配对。"); return }
            if !authenticated {
                identity.remember(id: id, key: key); authenticated = true; connecting = false; connectionTimeout?.cancel()
                sendStatus = "连接好了，上下左右都可以甩出。"; sendError = false
                if let data = hello.nearbyToken { spatial.run(peerToken: data) }
                sendHello()
            }
        case .offer:
            guard let offer = packet.offer, packet.id == offer.id, offer.isValid,
                  let data = packet.preview, data.count <= FlickRules.maxPreviewBytes,
                  let preview = UIImage(data: data) else { reject(packet.id, "文件格式或大小不受支持。"); return }
            guard !recentIDs.contains(offer.id) else { reject(offer.id, "该次投送已处理，请重新发送。"); return }
            let decision = ReceivePolicy.decide(enabled: accepting && (allowNearby || isCurrentFriend), isFriend: isCurrentFriend, autoFriends: autoAcceptFriends, surfaceReady: canPresentIncoming && running && isForeground && friendInvitation == nil)
            guard decision != .reject else { reject(offer.id, "请对方打开接收页，并开启接收。"); return }
            guard isCurrentFriend || withinTwentyMeters else { reject(offer.id, "尚未确认在 20 米内。请等待测距，或双方确认添加好友。"); return }
            guard incomingOffer == nil, !isSending else { reject(offer.id, "对方正在传输，请稍后再甩。"); return }
            incomingOffer = offer; receiveProgress = 0
            incomingPreview = preview
            if decision == .open { openIncoming() }
            else { incomingRequest = IncomingRequest(id: offer.id, sender: peerName ?? "朋友", offer: offer) }
            let job = DispatchWorkItem { [weak self] in
                guard self?.incomingOffer?.id == offer.id else { return }
                self?.cancelIncoming("原文件接收超时，请让对方重试。", notify: true)
            }
            receiveTimeout?.cancel(); receiveTimeout = job
            DispatchQueue.main.asyncAfter(deadline: .now() + 120 + Double(offer.byteCount) / (200 * 1024), execute: job)
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
            sendStatus = "已送达 · 原文件已确认"; outboundPhoto = nil
            FlickFeedback.notification(.success)
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
        transaction?.fail(); resourceProgress?.cancel(); resourceProgress = nil; progressObservation = nil; timeout?.cancel()
        isSending = false; outgoingStage = .failed; outboundPhoto = nil; sendProgress = 0; sendStatus = reason; sendError = true
        FlickFeedback.notification(.error)
    }
    private func cancelIncoming(_ reason: String, notify: Bool) {
        guard let offer = incomingOffer else { return }
        if notify { try? sendPacket(WirePacket(.cancel, id: offer.id, reason: reason)) }
        receiveResourceProgress?.cancel(); receiveResourceProgress = nil; receiveObservation = nil; receiveTimeout?.cancel()
        if receivedPhoto?.id == offer.id { receivedPhoto?.failure = reason }
        incomingOffer = nil; incomingPreview = nil; incomingRequest = nil; consentAccepted = false; presentedIDs.remove(offer.id)
    }
    private func finishResource(_ url: URL, name: String, peer: MCPeerID, currentSession: MCSession) {
        guard currentSession === session, peer == connectedPeer, let offer = incomingOffer, name == offer.resourceName,
              presentedIDs.contains(offer.id), receivedPhoto?.id == offer.id else { try? FileManager.default.removeItem(at: url); return }
        let folder = PhotoFiles.directory.appendingPathComponent(offer.id.uuidString, isDirectory: true)
        let finalURL = folder.appendingPathComponent(offer.filename)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); try FileManager.default.moveItem(at: url, to: finalURL) }
        catch { cancelIncoming("无法保存原文件，请重试。", notify: true); return }
        let url = finalURL
        imageQueue.async { [weak self] in
            let result: Result<UIImage, Error> = Result {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size == offer.byteCount, try PhotoFiles.digest(url) == offer.sha256 else { throw PhotoFailure.invalid }
                return try PhotoFiles.preview(url, kind: offer.kind)
            }
            DispatchQueue.main.async {
                guard let self = self, self.session === currentSession, self.incomingOffer?.id == offer.id, self.accepting else { try? FileManager.default.removeItem(at: url); return }
                switch result {
                case .success(let image):
                    self.receivedPhoto?.image = image; self.receivedPhoto?.originalURL = url; self.receivedPhoto?.failure = nil
                    self.receiveProgress = 1; self.incomingOffer = nil; self.receiveTimeout?.cancel(); self.receiveObservation = nil; self.receiveResourceProgress = nil
                    self.recentIDs.append(offer.id); if self.recentIDs.count > 64 { self.recentIDs.removeFirst() }
                    self.presentedIDs.remove(offer.id)
                    try? self.sendPacket(WirePacket(.received, id: offer.id))
                    FlickFeedback.notification(.success)
                case .failure:
                    try? FileManager.default.removeItem(at: url)
                    self.cancelIncoming("原文件校验未通过，请让对方重新发送。", notify: true)
                }
            }
        }
    }
}

extension PeerLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.discoverable, browser === self.browser, info?["v"] == "3", let id = info?["id"], !self.blockedIDs.contains(id), let fingerprint = info?["key"] else { return }
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
            guard let self = self, self.discoverable, advertiser === self.advertiser, self.running, self.connectedPeer == nil, !self.connecting, self.invitationReply == nil,
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
