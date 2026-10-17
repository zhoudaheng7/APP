import Foundation

public struct AudioSegment: Codable, Identifiable, Sendable {
    public var id: Int
    public var filename: String
    public var duration: Double
    public var state: String
    public var error: String?
}

public struct SessionReport: Codable, Identifiable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var state = "recording"
    public var audioBuffers = 0
    public var nonSilentBuffers = 0
    public var meteredBuffers = 0
    public var videoFramesDiscarded = 0
    public var audioSeconds: Double = 0
    public var droppedBuffers = 0
    public var rejectedTimestamps = 0
    public var peak: Double = 0
    public var sampleRate: Double = 0
    public var channelCount: UInt32 = 0
    public var segments: [AudioSegment] = []
    public var error: String?
    public var captureSource: String?
    public var mergedFrom: [UUID]?
    public var microphoneRequested: Bool?
    public var microphoneBuffers: Int?
    public internal(set) var microphoneRecorded = false
    public private(set) var videoSaved = false

    public init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
    }

    public static func load(from folder: URL) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: Data(contentsOf: folder.appendingPathComponent("session.json")))
    }
}
