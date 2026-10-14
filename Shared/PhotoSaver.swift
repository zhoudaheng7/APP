import Photos
import Foundation

enum PhotoSaver {
    static var isAuthorized: Bool { PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized }

    static func save(_ file: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard isAuthorized else {
            completion(.failure(ScrollShotError.message("没有相册保存权限。请先在主 App 中授权，再开始录屏。")))
            return
        }
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = file.lastPathComponent
            request.addResource(with: .photo, fileURL: file, options: options)
        }) { success, error in
            if success { completion(.success(())) }
            else { completion(.failure(error ?? ScrollShotError.message("保存到相册失败。"))) }
        }
    }
}
