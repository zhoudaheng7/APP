import Foundation
import UIKit
import Photos
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO
import AVFoundation
import CryptoKit

enum PhotoFailure: LocalizedError {
    case invalid, tooLarge, cannotSave
    var errorDescription: String? {
        switch self {
        case .invalid: return "暂时无法读取这个文件。请选择照片、视频或普通文件。"
        case .tooLarge: return "此测试版支持单个 2 GB 以内的原文件。"
        case .cannotSave: return "请在系统设置中允许一甩添加照片，或使用分享按钮导出。"
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
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let part = try file.read(upToCount: 1024 * 1024), !part.isEmpty { hash.update(data: part) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func thumbnail(_ url: URL, maxPixels: Int = 1800) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw PhotoFailure.invalid }
        return UIImage(cgImage: image)
    }
    static func preview(_ url: URL, kind: MediaKind) throws -> UIImage {
        if kind == .photo { return try thumbnail(url) }
        if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 1200, height: 1200)
            if let frame = try? generator.copyCGImage(at: .zero, actualTime: nil) { return UIImage(cgImage: frame) }
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 480))
        return renderer.image { context in
            UIColor.secondarySystemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 480, height: 480))
            let icon = UIImage(systemName: kind == .video ? "video.fill" : "doc.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 150))?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            icon?.draw(in: CGRect(x: 150, y: 140, width: 180, height: 200))
        }
    }
    static func copyImported(_ source: URL, name: String? = nil) throws -> URL {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard values.isDirectory != true else { throw PhotoFailure.invalid }
        guard let count = values.fileSize, count > 0, count <= FlickRules.maxFileBytes else { throw PhotoFailure.tooLarge }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var filename = FlickRules.safeFilename(name ?? source.lastPathComponent)
        if URL(fileURLWithPath: filename).pathExtension.isEmpty && !source.pathExtension.isEmpty { filename += "." + source.pathExtension }
        let destination = folder.appendingPathComponent(FlickRules.safeFilename(filename))
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
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
        FileRepresentation(importedContentType: .image) { received in ImportedPhoto(url: try PhotoFiles.copyImported(received.file)) }
        FileRepresentation(importedContentType: .movie) { received in ImportedPhoto(url: try PhotoFiles.copyImported(received.file)) }
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
    let kind: MediaKind
    static func prepare(_ source: URL) throws -> PhotoAsset {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isDirectoryKey])
        let size = values.fileSize ?? 0
        guard values.isDirectory != true, size > 0, size <= FlickRules.maxFileBytes else { throw PhotoFailure.tooLarge }
        let type = values.contentType ?? UTType(filenameExtension: source.pathExtension)
        let raw = CGImageSourceCreateWithURL(source as CFURL, nil)
        let kind: MediaKind = raw != nil ? .photo : type?.conforms(to: .movie) == true || ["mov", "mp4", "m4v"].contains(source.pathExtension.lowercased()) ? .video : .file
        let image = try PhotoFiles.preview(source, kind: kind)
        let scaled: UIImage = kind == .photo ? try PhotoFiles.thumbnail(source, maxPixels: 900) : image
        var preview = scaled.jpegData(compressionQuality: 0.65)
        if (preview?.count ?? Int.max) > FlickRules.maxPreviewBytes { preview = scaled.jpegData(compressionQuality: 0.25) }
        guard let preview = preview, preview.count <= FlickRules.maxPreviewBytes else { throw PhotoFailure.invalid }
        var ext = source.pathExtension.lowercased()
        if let raw = raw, let imageType = CGImageSourceGetType(raw) { ext = UTType(imageType as String)?.preferredFilenameExtension ?? ext }
        if ext.count > 16 || !ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { ext = "bin" }
        let filename = FlickRules.safeFilename(source.lastPathComponent)
        let asset = PhotoAsset(id: UUID(), url: source, image: image, previewData: preview, sha256: try PhotoFiles.digest(source), byteCount: size, fileExtension: ext, title: filename, kind: kind)
        guard asset.offer(side: .right).isValid else { throw PhotoFailure.invalid }
        return asset
    }
    func offer(side: ThrowSide) -> TransferOffer {
        TransferOffer(id: UUID(), title: String(title.prefix(120)), byteCount: byteCount, sha256: sha256, fileExtension: fileExtension, side: side, kind: kind, filename: FlickRules.safeFilename(title))
    }
}
struct ReceivedPhoto: Identifiable {
    let id: UUID
    let offer: TransferOffer
    let sender: String
    let entrySide: ThrowSide
    var image: UIImage
    var originalURL: URL?
    var failure: String?
    var originalReady: Bool { originalURL != nil }
}
enum PhotoSave {
    static func save(_ url: URL, kind: MediaKind = .photo) async throws {
        let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard result == .authorized || result == .limited else { throw PhotoFailure.cannotSave }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: kind == .video ? .video : .photo, fileURL: url, options: nil)
        }
    }
}
