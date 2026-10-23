import Foundation
import UIKit

private struct InboxRecord: Codable {
    let offer: TransferOffer
    let sender: String
    let entrySide: ThrowSide
    let date: Date
}

enum ReceiveInbox {
    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlickInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    /// Commit metadata last. Only verified complete files are restored as delivered.
    static func commit(_ photo: ReceivedPhoto) throws {
        guard let source = photo.originalURL else { throw PhotoFailure.invalid }
        let target = folder(photo.id)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let originals = target.appendingPathComponent("original", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let original = originals.appendingPathComponent(photo.offer.filename)
        if source != original {
            if FileManager.default.fileExists(atPath: original.path) { try FileManager.default.removeItem(at: original) }
            try FileManager.default.moveItem(at: source, to: original)
        }
        let cover = photo.image.jpegData(compressionQuality: 0.5)
        try cover?.write(to: target.appendingPathComponent(".preview.jpg"), options: .atomic)
        let record = InboxRecord(offer: photo.offer, sender: photo.sender, entrySide: photo.entrySide, date: Date())
        try JSONEncoder().encode(record).write(to: target.appendingPathComponent(".receipt.json"), options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: original.path)
    }
    static func load() -> [ReceivedPhoto] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> (Date, ReceivedPhoto)? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(".receipt.json")),
                  let record = try? JSONDecoder().decode(InboxRecord.self, from: data), record.offer.isValid else { return nil }
            let original = folder.appendingPathComponent("original").appendingPathComponent(record.offer.filename)
            guard (try? original.resourceValues(forKeys: [.fileSizeKey]).fileSize) == record.offer.byteCount else { return nil }
            let image = UIImage(contentsOfFile: folder.appendingPathComponent(".preview.jpg").path) ?? PhotoFiles.placeholder(record.offer.kind)
            return (record.date, ReceivedPhoto(id: record.offer.id, offer: record.offer, sender: record.sender, entrySide: record.entrySide, image: image, originalURL: original))
        }.sorted { $0.0 > $1.0 }.map { $0.1 }
    }
    static func remove(_ id: UUID) { try? FileManager.default.removeItem(at: folder(id)) }
}
