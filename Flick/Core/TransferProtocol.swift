import Foundation

public enum ThrowSide: String, Codable, CaseIterable, Sendable {
    case left, right
    public var sign: Double { self == .right ? 1 : -1 }
    public var label: String { self == .right ? "�Ҳ�" : "���" }
    public var entryLabel: String { self == .right ? "���" : "�Ҳ�" }
}

public enum FlickRules {
    public static let maxFileBytes = 80 * 1024 * 1024
    public static let maxPreviewBytes = 512 * 1024
    public static let maxControlBytes = 900 * 1024
    public static func shouldThrow(dx: Double, dy: Double, velocityX: Double, width: Double, side: ThrowSide) -> Bool {
        guard width > 0, dx.isFinite, dy.isFinite, velocityX.isFinite,
              abs(dx) > abs(dy), dx * side.sign > 0 else { return false }
        return dx * side.sign >= width * 0.34 || (dx * side.sign >= 26 && velocityX * side.sign >= 650)
    }
}

public struct TransferOffer: Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let byteCount: Int
    public let sha256: String
    public let fileExtension: String
    public let side: ThrowSide
    public init(id: UUID, title: String, byteCount: Int, sha256: String, fileExtension: String, side: ThrowSide) {
        self.id = id; self.title = title; self.byteCount = byteCount; self.sha256 = sha256
        self.fileExtension = fileExtension; self.side = side
    }
    public var resourceName: String { "flick-\(id.uuidString).\(fileExtension)" }
    public var isValid: Bool {
        let allowed = Set(["jpg", "jpeg", "heic", "heif", "png", "gif", "tif", "tiff", "webp", "avif", "dng"])
        return byteCount > 0 && byteCount <= FlickRules.maxFileBytes && title.count <= 120 &&
            sha256.count == 64 && sha256.allSatisfy { "0123456789abcdef".contains($0) } && allowed.contains(fileExtension)
    }
}

public enum PacketKind: String, Codable, Sendable { case hello, offer, ready, presented, received, cancel, reject }
public struct WirePacket: Codable, Sendable {
    public var version: Int = 1
    public var kind: PacketKind
    public var id: UUID?
    public var offer: TransferOffer?
    public var preview: Data?
    public var accepting: Bool?
    public var name: String?
    public var reason: String?
    public init(_ kind: PacketKind, id: UUID? = nil, offer: TransferOffer? = nil, preview: Data? = nil, accepting: Bool? = nil, name: String? = nil, reason: String? = nil) {
        self.kind = kind; self.id = id; self.offer = offer; self.preview = preview
        self.accepting = accepting; self.name = name; self.reason = reason
    }
}

public enum SendStage: String, Sendable { case awaitingPreview, transferring, delivered, failed }
public struct SendTransaction: Sendable {
    public let offer: TransferOffer
    public private(set) var stage: SendStage = .awaitingPreview
    public private(set) var previewWasPresented = false
    public init(offer: TransferOffer) { self.offer = offer }
    public mutating func ready(id: UUID) -> Bool {
        guard id == offer.id, stage == .awaitingPreview else { return false }
        stage = .transferring; return true
    }
    public mutating func presented(id: UUID) {
        if id == offer.id && stage != .failed { previewWasPresented = true }
    }
    public mutating func received(id: UUID) -> Bool {
        guard id == offer.id, stage == .transferring else { return false }
        stage = .delivered; return true
    }
    public mutating func fail() { if stage != .delivered { stage = .failed } }
}
