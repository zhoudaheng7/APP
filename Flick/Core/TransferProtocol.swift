import Foundation

public enum ThrowSide: String, Codable, CaseIterable, Sendable {
    case left, right, up, down
    public var x: Double { self == .right ? 1 : self == .left ? -1 : 0 }
    public var y: Double { self == .down ? 1 : self == .up ? -1 : 0 }
    public var sign: Double { x }
    public var opposite: ThrowSide { switch self { case .left: return .right; case .right: return .left; case .up: return .down; case .down: return .up } }
    public var label: String { switch self { case .left: return "左侧"; case .right: return "右侧"; case .up: return "上方"; case .down: return "下方" } }
    public var symbol: String { switch self { case .left: return "arrow.left"; case .right: return "arrow.right"; case .up: return "arrow.up"; case .down: return "arrow.down" } }
    public var entryLabel: String { opposite.label }
}

public enum MediaKind: String, Codable, Sendable { case photo, video, file }

public enum FlickRules {
    public static let maxFileBytes = 2 * 1024 * 1024 * 1024
    public static let maxPreviewBytes = 512 * 1024
    public static let maxControlBytes = 900 * 1024
    public static func shouldThrow(dx: Double, dy: Double, velocityX: Double, width: Double, side: ThrowSide) -> Bool {
        guard side == .left || side == .right else { return false }
        return throwDirection(dx: dx, dy: dy, velocityX: velocityX, velocityY: 0, width: width, height: width) == side
    }
    public static func throwDirection(dx: Double, dy: Double, velocityX: Double, velocityY: Double, width: Double, height: Double) -> ThrowSide? {
        guard width > 0, height > 0, [dx, dy, velocityX, velocityY].allSatisfy({ $0.isFinite }) else { return nil }
        let horizontal = abs(dx) >= abs(dy)
        let d = horizontal ? dx : dy
        let v = horizontal ? velocityX : velocityY
        let length = horizontal ? width : height
        guard abs(d) >= length * 0.30 || (abs(d) >= 26 && d * v > 0 && abs(v) >= 650) else { return nil }
        return horizontal ? (d >= 0 ? .right : .left) : (d >= 0 ? .down : .up)
    }
    public static func safeFilename(_ value: String) -> String {
        let leaf = value.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? "文件"
        let clean = String(leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        var result = ""
        for c in clean { if (result + String(c)).utf8.count > 200 { break }; result.append(c) }
        return result.isEmpty || result == "." || result == ".." ? "文件" : result
    }
}

public struct TransferOffer: Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let byteCount: Int
    public let sha256: String
    public let fileExtension: String
    public let side: ThrowSide
    public let kind: MediaKind
    public let filename: String
    public init(id: UUID, title: String, byteCount: Int, sha256: String, fileExtension: String, side: ThrowSide, kind: MediaKind = .photo, filename: String? = nil) {
        self.id = id; self.title = title; self.byteCount = byteCount; self.sha256 = sha256
        self.fileExtension = fileExtension; self.side = side
        self.kind = kind; self.filename = filename ?? "照片.\(fileExtension)"
    }
    public var resourceName: String { "flick-\(id.uuidString).\(fileExtension.isEmpty ? "bin" : fileExtension)" }
    public var isValid: Bool {
        return byteCount > 0 && byteCount <= FlickRules.maxFileBytes && title.count <= 120 &&
            sha256.count == 64 && sha256.allSatisfy { "0123456789abcdef".contains($0) } &&
            fileExtension.count <= 16 && fileExtension.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } &&
            !filename.isEmpty && filename == FlickRules.safeFilename(filename)
    }
}

public enum PacketKind: String, Codable, Sendable { case hello, proof, offer, ready, presented, received, cancel, reject, friendRequest, friendReply, friendRemoved, chunk, chunkAck, fileEnd }
public struct WirePacket: Codable, Sendable {
    public var version: Int = 4
    public var kind: PacketKind
    public var id: UUID?
    public var offer: TransferOffer?
    public var preview: Data?
    public var accepting: Bool?
    public var name: String?
    public var reason: String?
    public var deviceID: String?
    public var publicKey: Data?
    public var nonce: String?
    public var signature: Data?
    public var nearbyToken: Data?
    public var exchangeKey: Data?
    public var code: String?
    public var chunk: Data?
    public var offset: Int?
    public var sha256: String?
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
    public mutating func storedReceipt(id: UUID, sha256: String) -> Bool {
        guard id == offer.id, sha256 == offer.sha256, stage == .awaitingPreview else { return false }
        stage = .delivered; return true
    }
    public mutating func fail() { if stage != .delivered { stage = .failed } }
}
