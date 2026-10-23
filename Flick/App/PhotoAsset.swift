import Foundation
import UIKit
import Photos
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO
import CryptoKit

enum PhotoFailure: LocalizedError {
    case invalid, tooLarge, cannotSave
    var errorDescription: String? {
        switch self {
        case .invalid: return "������Ƭ��ʱ�޷���ȡ���뻻һ�š�"
        case .tooLarge: return "��һ��֧�� 80 MB ���ڵĵ�����Ƭ��"
        case .cannotSave: return "����ϵͳ����������һ˦������Ƭ������ʹ�÷�����ť������"
        }
    }
}

enum PhotoFiles {
    static var directory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Flick", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let part = try file.read(upToCount: 1024 * 1024), !part.isEmpty { hash.update(data: part) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func thumbnail(_ url: URL, maxPixels: Int = 1800) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PhotoFailure.invalid }
        return UIImage(cgImage: image)
    }
    static func cleanupOldFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: file) }
        }
    }
}

struct ImportedPhoto: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= FlickRules.maxFileBytes else { throw PhotoFailure.tooLarge }
            let suffix = received.file.pathExtension.isEmpty ? "image" : received.file.pathExtension
            let copy = PhotoFiles.directory.appendingPathComponent("import-\(UUID().uuidString).\(suffix)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return ImportedPhoto(url: copy)
        }
    }
}

struct PhotoAsset: Identifiable {
    let id: UUID
    let url: URL
    let image: UIImage
    let previewData: Data
    let sha256: String
    let byteCount: Int
    let fileExtension: String
    let title: String
    static func prepare(_ source: URL) throws -> PhotoAsset {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= FlickRules.maxFileBytes else { throw PhotoFailure.tooLarge }
        guard let raw = CGImageSourceCreateWithURL(source as CFURL, nil), let type = CGImageSourceGetType(raw), let ext = UTType(type as String)?.preferredFilenameExtension else { throw PhotoFailure.invalid }
        let image = try PhotoFiles.thumbnail(source)
        let small = try PhotoFiles.thumbnail(source, maxPixels: 900)
        guard let preview = small.jpegData(compressionQuality: 0.72), preview.count <= FlickRules.maxPreviewBytes else { throw PhotoFailure.invalid }
        let id = UUID()
        let asset = PhotoAsset(id: id, url: source, image: image, previewData: preview, sha256: try PhotoFiles.digest(source), byteCount: size, fileExtension: ext.lowercased(), title: "������һ��")
        guard asset.offer(side: .right).isValid else { throw PhotoFailure.invalid }
        return asset
    }
    func offer(side: ThrowSide) -> TransferOffer {
        TransferOffer(id: UUID(), title: title, byteCount: byteCount, sha256: sha256, fileExtension: fileExtension, side: side)
    }
}

struct ReceivedPhoto: Identifiable {
    let id: UUID
    let offer: TransferOffer
    let sender: String
    var image: UIImage
    var originalURL: URL?
    var failure: String?
    var originalReady: Bool { originalURL != nil }
}

enum PhotoSave {
    static func save(_ url: URL) async throws {
        let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard result == .authorized || result == .limited else { throw PhotoFailure.cannotSave }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: url, options: nil)
        }
    }
}
