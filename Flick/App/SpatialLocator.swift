import Foundation
import NearbyInteraction
import simd

final class SpatialLocator: NSObject, NISessionDelegate {
    var changed: ((ThrowSide?, Float?, String?) -> Void)?
    private var session: NISession?
    private var remoteData: Data?
    private var expiry: DispatchWorkItem?
    var tokenData: Data? {
        guard let token = session?.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
    override init() {
        super.init()
        if NISession.deviceCapabilities.supportsDirectionMeasurement { session = NISession(); session?.delegate = self }
    }
    func run(peerToken data: Data) {
        guard data != remoteData, let session = session,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { return }
        remoteData = data; session.run(NINearbyPeerConfiguration(peerToken: token))
    }
    func stop() { expiry?.cancel(); session?.pause(); remoteData = nil; changed?(nil, nil, nil) }
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        var side: ThrowSide?
        if let v = object.direction, hypot(v.x, v.y) > 0.15 { side = abs(v.x) >= abs(v.y) ? (v.x >= 0 ? .right : .left) : (v.y >= 0 ? .up : .down) }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.remoteData != nil else { return }
            self.expiry?.cancel()
            self.changed?(side, object.distance, side == nil ? "暂时测不到方位，可对准对方后重试" : nil)
            let job = DispatchWorkItem { [weak self] in self?.changed?(nil, nil, "方位数据已过期，可继续四向甩送") }
            self.expiry = job; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: job)
        }
    }
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        DispatchQueue.main.async { [weak self] in
            self?.expiry?.cancel(); self?.changed?(nil, nil, "对方暂时离开测量范围，可继续四向甩送")
            if reason == .timeout, let data = self?.remoteData { self?.remoteData = nil; self?.run(peerToken: data) }
        }
    }
    func session(_ session: NISession, didInvalidateWith error: Error) {
        remoteData = nil
        DispatchQueue.main.async { [weak self] in self?.changed?(nil, nil, "附近交互暂不可用，可继续四向甩送") }
    }
    func sessionWasSuspended(_ session: NISession) { DispatchQueue.main.async { [weak self] in self?.changed?(nil, nil, "方位测量已暂停") } }
}
