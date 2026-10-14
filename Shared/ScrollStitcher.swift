import CoreGraphics
import Foundation

struct StitchResult {
    let file: URL
    let width: Int
    let height: Int
    let capturedFrames: Int
    let movingFrames: Int
    let partialReason: String?
}

/// Streaming stitching. Full frames are not retained; only newly exposed strips go to disk.
final class ScrollStitcher {
    private struct Strip { let url: URL; let height: Int }
    private let directory: URL
    private let maxPixels: Int
    private var strips: [Strip] = []
    private var previous: GrayFrame?
    private var previousFine: GrayFrame?
    private var width = 0, frameHeight = 0, origin = 0, seenBottom = 0
    private(set) var totalHeight = 0
    private(set) var frames = 0
    private(set) var movements = 0
    private(set) var stopReason: String?

    init(maxPixels: Int = 1_800_000) throws {
        self.maxPixels = maxPixels
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("scrollshot-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func consume(_ image: CGImage) throws {
        guard stopReason == nil else { return }
        frames += 1
        let sampleWidth = 64
        let sampleHeight = max(24, Int(Double(image.height) * Double(sampleWidth) / Double(image.width)))
        let sample = try ImageTools.gray(image, width: sampleWidth, height: sampleHeight)
        let fine = try ImageTools.gray(image, width: sampleWidth, height: image.height)
        guard let previous, let previousFine else { try begin(image, sample: sample, fine: fine); return }
        if image.width != width || image.height != frameHeight {
            if movements == 0 { try begin(image, sample: sample, fine: fine) }
            else { stopReason = "录屏方向或画面尺寸改变，已保留改变前的内容。" }
            return
        }
        let match = VerticalMatcher.match(previous, sample)
        guard match.valid else {
            // Opening the target app after broadcast start changes the whole screen.
            // Until real scrolling starts, reset the initial frame rather than stitching the recorder UI.
            if movements == 0 { try begin(image, sample: sample, fine: fine) }
            else { stopReason = "画面无法可靠对齐。可能滚动过快、固定栏未裁净或有动画。保存的是匹配成功的部分。" }
            return
        }
        guard match.shift != 0 else { return }
        let estimate = Int((Double(match.shift) * Double(frameHeight) / Double(sample.height)).rounded())
        let refined = VerticalMatcher.refine(previousFine, fine, estimate: estimate,
                                             radius: Int(ceil(Double(frameHeight) / Double(sample.height) * 1.5)))
        guard refined.valid else {
            if movements == 0 { try begin(image, sample: sample, fine: fine) }
            else { stopReason = "画面变化过大，已停止拼接以避免错拼。" }
            return
        }
        let shift = refined.shift
        guard shift != 0 else { return }
        // A negative shift means the user scrolled back toward the beginning.
        if movements == 0 && shift < 0 {
            try begin(image, sample: sample, fine: fine)
            return
        }
        let nextOrigin = origin + shift
        guard nextOrigin >= 0 else { stopReason = "滚动超出起始位置，请从内容顶部向下录制。"; return }
        let newHeight = max(0, nextOrigin + frameHeight - seenBottom)
        if newHeight > 0 {
            guard width * (totalHeight + newHeight) <= maxPixels else {
                stopReason = "已达到本次长图的长度上限，请分段录制。保存的是上限之前的内容。"
                return
            }
            guard let strip = image.cropping(to: CGRect(x: 0, y: CGFloat(frameHeight - newHeight), width: CGFloat(width), height: CGFloat(newHeight))) else {
                throw ScrollShotError.message("新增画面裁剪失败。")
            }
            try append(strip)
            seenBottom = nextOrigin + frameHeight
            movements += 1
        }
        origin = nextOrigin; self.previous = sample; self.previousFine = fine
    }

    private func begin(_ image: CGImage, sample: GrayFrame, fine: GrayFrame) throws {
        for strip in strips { try? FileManager.default.removeItem(at: strip.url) }
        strips.removeAll(); totalHeight = 0
        width = image.width; frameHeight = image.height; origin = 0; seenBottom = image.height
        previous = sample; previousFine = fine
        guard width * frameHeight <= maxPixels else { throw ScrollShotError.message("首屏尺寸过大。") }
        try append(image)
    }

    private func append(_ image: CGImage) throws {
        let url = directory.appendingPathComponent("strip-\(strips.count).png")
        try ImageTools.writePNG(image, to: url)
        strips.append(Strip(url: url, height: image.height)); totalHeight += image.height
    }

    func finish() throws -> StitchResult {
        guard movements > 0 else {
            throw ScrollShotError.message("没有识别到有效的向下滚动，未生成长图。请从内容顶部开始、缓慢滚动。")
        }
        guard width > 0, totalHeight > 0, width * totalHeight <= maxPixels,
              let context = CGContext(data: nil, width: width, height: totalHeight,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScrollShotError.message("长图内存分配失败，请缩短录屏。")
        }
        var offset = 0
        for strip in strips {
            try autoreleasepool {
                let image = try ImageTools.read(strip.url)
                context.draw(image, in: CGRect(x: 0, y: CGFloat(totalHeight - offset - strip.height), width: CGFloat(width), height: CGFloat(strip.height)))
            }
            offset += strip.height
        }
        guard let result = context.makeImage() else { throw ScrollShotError.message("生成长图失败。") }
        // This file lives outside the scratch strip directory and survives release of this stitcher.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("scrollshot-result-" + UUID().uuidString + ".png")
        try ImageTools.writePNG(result, to: file)
        return StitchResult(file: file, width: width, height: totalHeight, capturedFrames: frames,
                            movingFrames: movements, partialReason: stopReason)
    }
}
