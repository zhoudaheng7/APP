import AVFoundation
import CoreImage
import CoreMedia
import Foundation

final class VideoProcessor {
    static func convert(_ url: URL, top: Double, bottom: Double,
                        progress: @escaping (Double) -> Void) throws -> StitchResult {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw ScrollShotError.message("视频没有可读取的画面。")
        }
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0, duration <= 180 else {
            throw ScrollShotError.message("请选取 180 秒以内的滚动录屏。")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ScrollShotError.message("无法解码该视频。") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ScrollShotError.message("视频读取失败。") }
        let imageContext = CIContext(options: [.cacheIntermediates: false])
        let stitcher = try ScrollStitcher(maxPixels: 3_600_000)
        var lastTime = -Double.infinity
        while let sample = output.copyNextSampleBuffer() {
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            if time - lastTime < 0.2 { continue }
            lastTime = time
            try autoreleasepool {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
                let source = CIImage(cvPixelBuffer: buffer).transformed(by: track.preferredTransform)
                let frame = try ImageTools.normalize(source, context: imageContext, width: 720, top: top, bottom: bottom)
                try stitcher.consume(frame)
            }
            progress(min(1, time / duration))
            if stitcher.stopReason != nil { break }
        }
        if reader.status == .failed { throw reader.error ?? ScrollShotError.message("视频解码中断。") }
        reader.cancelReading()
        let result = try stitcher.finish()
        progress(1)
        return result
    }
}
