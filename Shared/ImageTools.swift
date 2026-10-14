import CoreGraphics
import CoreImage
import ImageIO
import Foundation
import UniformTypeIdentifiers

enum ScrollShotError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum ImageTools {
    static func gray(_ image: CGImage, width: Int, height: Int) throws -> GrayFrame {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard ok else { throw ScrollShotError.message("无法读取画面像素。") }
        return GrayFrame(width: width, height: height, pixels: pixels)
    }

    static func normalize(_ image: CIImage, context: CIContext, width: Int,
                          top: Double, bottom: Double) throws -> CGImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, top >= 0, bottom >= 0, top + bottom < 0.75 else {
            throw ScrollShotError.message("裁剪范围无效。")
        }
        // Core Image uses a bottom-left origin; crop out the fixed top and bottom bars.
        let region = CGRect(x: extent.minX, y: extent.minY + extent.height * CGFloat(bottom),
                            width: extent.width, height: extent.height * CGFloat(1 - top - bottom))
        let cropped = image.cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
        let scale = min(1, CGFloat(width) / region.width)
        let small = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(max(1, Int(region.width * scale))), height: CGFloat(max(1, Int(region.height * scale))))
        guard let result = context.createCGImage(small, from: bounds) else {
            throw ScrollShotError.message("视频画面转换失败。")
        }
        return result
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ScrollShotError.message("无法创建长图文件。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScrollShotError.message("长图写入失败。") }
    }

    static func read(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScrollShotError.message("无法读取拼接片段。")
        }
        return image
    }
}
