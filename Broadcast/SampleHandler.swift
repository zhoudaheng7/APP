import ReplayKit
import CoreImage
import ImageIO
import CoreMedia
import Photos
import UserNotifications
import os

final class SampleHandler: RPBroadcastSampleHandler {
    private let logger = Logger(subsystem: "com.zhoudaheng7.ScrollShot", category: "Broadcast")
    private lazy var imageContext = CIContext(options: [.cacheIntermediates: false])
    private var stitcher: ScrollStitcher?
    private var lastFrameTime = -Double.infinity

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        do {
            guard PhotoSaver.isAuthorized else {
                throw ScrollShotError.message("请先打开「录屏转长图」并允许保存照片。若已经授权，此设备可能未把权限共享给录屏扩展，请使用 App 内导入录屏测试。")
            }
            stitcher = try ScrollStitcher(maxPixels: 1_800_000)
            lastFrameTime = -Double.infinity
        } catch { finishBroadcastWithError(error) }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let stitcher, stitcher.stopReason == nil else { return }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard time.isFinite, time - lastFrameTime >= 0.2,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = time
        do {
            try autoreleasepool {
                var image = CIImage(cvPixelBuffer: buffer)
                if let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
                   let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) {
                    image = image.oriented(orientation)
                }
                let normalized = try ImageTools.normalize(image, context: imageContext, width: 480, top: 0.12, bottom: 0.14)
                try stitcher.consume(normalized)
            }
            // Do not auto-save interim images: the user asked for one final long image.
        } catch {
            logger.error("处理画面失败: \(error.localizedDescription, privacy: .public)")
            finishBroadcastWithError(error)
        }
    }

    override func broadcastFinished() {
        guard let stitcher else { return }
        do {
            let result = try autoreleasepool { try stitcher.finish() }
            self.stitcher = nil
            let semaphore = DispatchSemaphore(value: 0)
            let outcome = SaveOutcome()
            PhotoSaver.save(result.file) { value in
                outcome.set(value)
                try? FileManager.default.removeItem(at: result.file)
                semaphore.signal()
            }
            // ReplayKit may terminate the extension after this callback returns.
            // Keep this callback alive for a bounded period while PhotoKit commits.
            guard semaphore.wait(timeout: .now() + 12) == .success else {
                logger.error("相册保存超时。录屏扩展结束回调的存活时间需实机验证。")
                notify("长图保存尚未确认", text: "请检查照片图库。录屏扩展保存超时，不能确认本次成功。")
                return
            }
            switch outcome.get() {
            case .success?:
                let text = result.partialReason ?? "长图已保存到照片，\(result.width) × \(result.height) 像素。"
                notify(result.partialReason == nil ? "长图已保存" : "已保存部分长图", text: text)
                logger.info("长图保存成功，\(result.width) × \(result.height)")
            case .failure(let error)?:
                logger.error("相册保存失败: \(error.localizedDescription, privacy: .public)")
                notify("长图保存失败", text: error.localizedDescription)
            case nil:
                notify("长图保存失败", text: "相册保存未返回结果。")
            }
        } catch {
            logger.error("长图生成失败: \(error.localizedDescription, privacy: .public)")
            notify("未生成长图", text: error.localizedDescription)
        }
    }

    private func notify(_ title: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

private final class SaveOutcome {
    private let lock = NSLock()
    private var value: Result<Void, Error>?
    func set(_ newValue: Result<Void, Error>) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Result<Void, Error>? { lock.lock(); defer { lock.unlock() }; return value }
}
