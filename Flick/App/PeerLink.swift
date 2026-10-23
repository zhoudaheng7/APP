import Foundation
import UIKit
import Combine
@preconcurrency import MultipeerConnectivity

struct NearbyPhone: Identifiable {
    let peer: MCPeerID
    let name: String
    let code: String
    var id: String { peer.displayName }
}
struct ConnectionRequest: Identifiable {
    let id = UUID()
    let name: String
    let code: String
}
private struct InviteContext: Codable { let name: String; let code: String }

final class PeerLink: NSObject, ObservableObject {
    @Published private(set) var nearby: [NearbyPhone] = []
    @Published private(set) var peerName: String?
    @Published private(set) var connecting = false
    @Published private(set) var peerAccepting = false
    @Published private(set) var isSending = false
    @Published private(set) var sendProgress: Double = 0
    @Published private(set) var sendStatus = "ѡһ�ţ�������һ��"
    @Published private(set) var sendError = false
    @Published private(set) var outgoingStage: SendStage?
    @Published private(set) var receivedPhoto: ReceivedPhoto?
    @Published private(set) var receiveProgress: Double = 0
    @Published private(set) var diagnostic: String?
    @Published var invitation: ConnectionRequest?
    @Published private(set) var accepting = true
    let localName: String
    let code: String
    private let service = "flick-photo"
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
    var connected: Bool { connectedPeer != nil }

    override init() {
        let suffix = String(Int.random(in: 1000...9999))
        localName = "iPhone �� " + suffix
        code = String(Int.random(in: 100000...999999))
        peerID = MCPeerID(displayName: "Flick-" + suffix + "-" + String(UUID().uuidString.prefix(6)))
        super.init()
        PhotoFiles.cleanupOldFiles()
        newSession()
    }
    private func newSession() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }
    func activate() {
        guard !running else { return }
        running = true; diagnostic = nil
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["name": localName, "code": code, "v": "1"], serviceType: service)
        advertiser?.delegate = self; advertiser?.startAdvertisingPeer()
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: service)
        browser?.delegate = self; browser?.startBrowsingForPeers()
    }
    func suspend() {
        running = false; browser?.stopBrowsingForPeers(); advertiser?.stopAdvertisingPeer()
        disconnect(reason: "����ͣ���ӣ��ص�ǰ̨�����������ӡ�")
        nearby = []
    }
    func connect(_ phone: NearbyPhone) {
        guard running, !connected, !connecting, invitationReply == nil else { return }
        diagnostic = nil; expectedPeer = phone.peer; connecting = true
        let context = try? JSONEncoder().encode(InviteContext(name: localName, code: code))
        browser?.invitePeer(phone.peer, to: session, withContext: context, timeout: 20)
        let job = DispatchWorkItem { [weak self] in
            guard let self = self, self.connecting else { return }
            self.disconnect(reason: "���ӳ�ʱ����ȷ�϶Է��Ѵ�һ˦���������롣")
        }
        connectionTimeout?.cancel(); connectionTimeout = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 22, execute: job)
    }
    func answerInvitation(_ allow: Bool) {
        guard let reply = invitationReply else { invitation = nil; return }
        invitationReply = nil; invitation = nil
        if allow { accepting = true; connecting = true }
        else { expectedPeer = nil }
        reply(allow, allow ? session : nil)
        if allow {
            let job = DispatchWorkItem { [weak self] in
                guard let self = self, self.connecting else { return }
                self.disconnect(reason: "����δ��ɣ�������ѡ��Է���")
            }
            connectionTimeout?.cancel(); connectionTimeout = job
            DispatchQueue.main.asyncAfter(deadline: .now() + 22, execute: job)
        }
    }
    func disconnect(reason: String = "�����ѶϿ���ѡ�е���Ƭ�Ա�����") {
        connectionTimeout?.cancel(); connectionTimeout = nil
        invitationReply?(false, nil); invitationReply = nil; invitation = nil
        failOutgoing(reason, notify: false)
        cancelIncoming(reason, notify: false)
        session.disconnect(); session.delegate = nil
        connectedPeer = nil; expectedPeer = nil; peerName = nil; peerAccepting = false; connecting = false
        newSession(); sendStatus = reason
    }
    func setAccepting(_ value: Bool) {
        accepting = value
        if !value { cancelIncoming("��������ͣ��ԭͼδ������ɡ�", notify: true) }
        sendHello()
    }
    func note(_ text: String, error: Bool = false) { sendStatus = text; sendError = error }
    func send(_ asset: PhotoAsset, side: ThrowSide) {
        guard connected else { note("�����Ӹ�������һ̨ iPhone��", error: true); return }
        guard peerAccepting else { note("�Է�����ͣ���գ���Ƭ�������", error: true); return }
        guard running, UIApplication.shared.applicationState == .active, !isSending, incomingOffer == nil else {
            note("��ȴ���ǰ������ɡ�", error: true); return
        }
        let offer = asset.offer(side: side)
        transaction = SendTransaction(offer: offer); outboundPhoto = asset
        isSending = true; sendError = false; sendProgress = 0; outgoingStage = .awaitingPreview
        sendStatus = "����׼��˦�� \(peerName ?? "�Է�")��"
        do {
            try sendPacket(WirePacket(.offer, id: offer.id, offer: offer, preview: asset.previewData))
            armSendTimeout(25, id: offer.id, reason: "�Է�û��׼���ã���Ƭ�Ա������������ԡ�")
        } catch { failOutgoing("����׼��ʧ�ܣ�\(error.localizedDescription)") }
    }
    func previewPresented(id: UUID) {
        guard let offer = incomingOffer, offer.id == id, accepting, connected, !presentedIDs.contains(id),
              UIApplication.shared.applicationState == .active else { return }
        presentedIDs.insert(id)
        do {
            try sendPacket(WirePacket(.ready, id: id))
            try sendPacket(WirePacket(.presented, id: id))
        } catch { cancelIncoming("�����жϣ�ԭͼδ������ɡ�", notify: false) }
    }
    private func sendHello() { try? sendPacket(WirePacket(.hello, accepting: accepting, name: localName)) }
    private func sendPacket(_ packet: WirePacket) throws {
        guard let peer = connectedPeer else { throw NSError(domain: "Flick", code: 1, userInfo: [NSLocalizedDescriptionKey: "��δ�����豸"] ) }
        let data = try JSONEncoder().encode(packet)
        guard data.count <= FlickRules.maxControlBytes else { throw PhotoFailure.tooLarge }
        try session.send(data, toPeers: [peer], with: .reliable)
    }
    private func handle(_ packet: WirePacket, peer: MCPeerID) {
        guard packet.version == 1, peer == connectedPeer else { return }
        switch packet.kind {
        case .hello:
            peerAccepting = packet.accepting ?? false
            if let name = packet.name, !name.isEmpty { peerName = String(name.prefix(40)) }
            if !peerAccepting && isSending { failOutgoing("�Է���ͣ�˽��գ���Ƭ�Ա�����") }
        case .offer:
            guard let offer = packet.offer, packet.id == offer.id, offer.isValid,
                  let data = packet.preview, data.count <= FlickRules.maxPreviewBytes,
                  let preview = UIImage(data: data) else { reject(packet.id, "��Ƭ��ʽ���С����֧�֡�"); return }
            guard !recentIDs.contains(offer.id) else { reject(offer.id, "����ƬͶ���Ѵ����������·��͡�"); return }
            guard accepting, running, UIApplication.shared.applicationState == .active else { reject(offer.id, "���շ�����ͣ���ա�"); return }
            guard incomingOffer == nil, !isSending else { reject(offer.id, "�Է����ڴ�ͼ�����Ժ���˦��"); return }
            incomingOffer = offer; receiveProgress = 0
            receivedPhoto = ReceivedPhoto(id: offer.id, offer: offer, sender: peerName ?? "����", image: preview)
            let job = DispatchWorkItem { [weak self] in
                guard self?.incomingOffer?.id == offer.id else { return }
                self?.cancelIncoming("ԭͼ���ճ�ʱ�����öԷ����ԡ�", notify: true)
            }
            receiveTimeout?.cancel(); receiveTimeout = job
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: job)
        case .ready:
            guard let id = packet.id, transaction?.ready(id: id) == true, let asset = outboundPhoto, let offer = transaction?.offer else { return }
            outgoingStage = .transferring; sendStatus = "��Ƭ�ѷɹ�ȥ �� ԭͼ������"
            timeout?.cancel()
            resourceProgress = session.sendResource(at: asset.url, withName: offer.resourceName, toPeer: peer) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self, self.transaction?.offer.id == id, self.isSending else { return }
                    if let error = error { self.failOutgoing("ԭͼ����ʧ�ܣ�\(error.localizedDescription)") }
                }
            }
            guard let progress = resourceProgress else { failOutgoing("ԭͼ�޷���ʼ���䣬�����ԡ�"); return }
            progressObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] value, _ in
                DispatchQueue.main.async { if self?.transaction?.offer.id == id { self?.sendProgress = value.fractionCompleted } }
            }
            armSendTimeout(120, id: id, reason: "ԭͼ���䳬ʱ����Ƭ�Ա������������ԡ�")
        case .presented:
            guard let id = packet.id else { return }
            transaction?.presented(id: id)
            if transaction?.offer.id == id, isSending { sendStatus = "�Է���չ�� �� ԭͼ������" }
        case .received:
            guard let id = packet.id, transaction?.received(id: id) == true else { return }
            timeout?.cancel(); progressObservation = nil; resourceProgress = nil
            isSending = false; sendProgress = 1; outgoingStage = .delivered; sendError = false
            sendStatus = "���ʹ� �� ԭͼ��ȷ��"; outboundPhoto = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .cancel, .reject:
            if let id = packet.id, id == transaction?.offer.id, isSending { failOutgoing(packet.reason ?? "�Է�ȡ���˽��գ���Ƭ�Ա�����", notify: false) }
            if let id = packet.id, id == incomingOffer?.id { cancelIncoming(packet.reason ?? "���ͷ���ȡ����", notify: false) }
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
        if notify { try? sendPacket(WirePacket(.cancel, id: transaction?.offer.id, reason: "������ȡ����������Ͷ�͡�")) }
        transaction?.fail(); resourceProgress?.cancel(); resourceProgress = nil; progressObservation = nil; timeout?.cancel()
        isSending = false; outgoingStage = .failed; outboundPhoto = nil; sendProgress = 0; sendStatus = reason; sendError = true
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    private func cancelIncoming(_ reason: String, notify: Bool) {
        guard let offer = incomingOffer else { return }
        if notify { try? sendPacket(WirePacket(.cancel, id: offer.id, reason: reason)) }
        receiveResourceProgress?.cancel(); receiveResourceProgress = nil; receiveObservation = nil; receiveTimeout?.cancel()
        if receivedPhoto?.id == offer.id { receivedPhoto?.failure = reason }
        incomingOffer = nil; presentedIDs.remove(offer.id)
    }
    private func finishResource(_ url: URL, name: String, peer: MCPeerID, currentSession: MCSession) {
        guard currentSession === session, peer == connectedPeer, let offer = incomingOffer, name == offer.resourceName else { try? FileManager.default.removeItem(at: url); return }
        imageQueue.async { [weak self] in
            let result: Result<UIImage, Error> = Result {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size == offer.byteCount, try PhotoFiles.digest(url) == offer.sha256 else { throw PhotoFailure.invalid }
                return try PhotoFiles.thumbnail(url)
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
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .failure:
                    try? FileManager.default.removeItem(at: url)
                    self.cancelIncoming("ԭͼУ��δͨ�������öԷ����·��͡�", notify: true)
                }
            }
        }
    }
}

extension PeerLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, browser === self.browser, info?["v"] == "1" else { return }
            self.nearby.removeAll { $0.peer == peerID }
            self.nearby.append(NearbyPhone(peer: peerID, name: String((info?["name"] ?? "������ iPhone").prefix(40)), code: String((info?["code"] ?? "------").prefix(6))))
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in self?.nearby.removeAll { $0.peer == peerID } }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in self?.diagnostic = "�޷����ָ����豸����������������һ˦ʹ�ñ������磬���� Wi-Fi ��������\n\(error.localizedDescription)" }
    }
}
extension PeerLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, advertiser === self.advertiser, self.running, !self.connected, !self.connecting, self.invitationReply == nil,
                  let context = context, context.count < 2048, let invite = try? JSONDecoder().decode(InviteContext.self, from: context) else { invitationHandler(false, nil); return }
            self.expectedPeer = peerID; self.invitationReply = invitationHandler
            self.invitation = ConnectionRequest(name: String(invite.name.prefix(40)), code: String(invite.code.prefix(6)))
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in self?.diagnostic = "�����㲥δ���������鱾������Ȩ�ޡ�\n\(error.localizedDescription)" }
    }
}
extension PeerLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, session === self.session else { return }
            switch state {
            case .connected:
                guard self.connectedPeer == nil, self.expectedPeer == peerID else { self.disconnect(reason: "���Ӷ����ѱ仯��������ȷ�ϡ�"); return }
                self.connectedPeer = peerID; self.connecting = false; self.connectionTimeout?.cancel()
                self.peerName = self.nearby.first(where: { $0.peer == peerID })?.name ?? self.invitation?.name ?? "��һ̨ iPhone"
                self.sendStatus = "���Ӻ��ˣ�������˦����Ƭ�ɡ�"; self.sendError = false; self.sendHello()
            case .notConnected:
                if self.connectedPeer == peerID || self.expectedPeer == peerID { self.disconnect(reason: "�Է��ѶϿ����ӣ���Ƭ�Ա�����") }
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
            guard let self = self, session === self.session, peerID == self.connectedPeer, self.incomingOffer?.resourceName == resourceName, self.accepting else { progress.cancel(); return }
            self.receiveResourceProgress = progress
            self.receiveObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] value, _ in
                DispatchQueue.main.async { if self?.incomingOffer?.resourceName == resourceName { self?.receiveProgress = value.fractionCompleted } }
            }
        }
    }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard error == nil, let source = localURL else {
            DispatchQueue.main.async { [weak self] in if session === self?.session, self?.incomingOffer?.resourceName == resourceName { self?.cancelIncoming("ԭͼ�����жϣ������·��͡�", notify: true) } }; return
        }
        do {
            let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= FlickRules.maxFileBytes else { throw PhotoFailure.tooLarge }
            let suffix = URL(fileURLWithPath: resourceName).pathExtension
            guard suffix.count <= 8, suffix.allSatisfy({ $0.isLetter }) else { throw PhotoFailure.invalid }
            let copy = PhotoFiles.directory.appendingPathComponent("received-\(UUID().uuidString).\(suffix)")
            try FileManager.default.copyItem(at: source, to: copy)
            DispatchQueue.main.async { [weak self] in self?.finishResource(copy, name: resourceName, peer: peerID, currentSession: session) }
        } catch {
            DispatchQueue.main.async { [weak self] in if session === self?.session, self?.incomingOffer?.resourceName == resourceName { self?.cancelIncoming("�޷���ȡ�յ���ԭͼ�������ԡ�", notify: true) } }
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
}
