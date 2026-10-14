import Foundation

struct GrayFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

struct MatchResult {
    let shift: Int
    let error: Double
    let valid: Bool
}

enum VerticalMatcher {
    static func match(_ a: GrayFrame, _ b: GrayFrame) -> MatchResult {
        guard a.width == b.width, a.height == b.height,
              a.width >= 16, a.height >= 24,
              a.pixels.count == a.width * a.height,
              b.pixels.count == b.width * b.height else {
            return MatchResult(shift: 0, error: .infinity, valid: false)
        }
        let width = a.width, height = a.height
        let limit = Int(Double(height) * 0.65)
        func score(_ shift: Int) -> (Double, Int) {
            let first = max(1, 1 - shift), last = min(height - 1, height - shift)
            guard first < last else { return (.infinity, 0) }
            var error = 0, samples = 0
            for y in stride(from: first, to: last, by: 2) {
                for x in stride(from: 3, to: width - 3, by: 3) {
                    let i = (y + shift) * width + x, j = y * width + x
                    let textureA = abs(Int(a.pixels[i]) - Int(a.pixels[i - 2])) + abs(Int(a.pixels[i]) - Int(a.pixels[i - width]))
                    let textureB = abs(Int(b.pixels[j]) - Int(b.pixels[j - 2])) + abs(Int(b.pixels[j]) - Int(b.pixels[j - width]))
                    guard max(textureA, textureB) >= 18 else { continue }
                    error += abs(Int(a.pixels[i]) - Int(b.pixels[j]))
                    samples += 1
                }
            }
            return (samples > 0 ? Double(error) / Double(samples) : .infinity, samples)
        }
        let stationary = score(0)
        if stationary.1 >= 50 && stationary.0 < 3 {
            return MatchResult(shift: 0, error: stationary.0, valid: true)
        }
        var bestShift = 0, best = stationary
        for d in -limit...limit {
            let candidate = score(d)
            if candidate.1 >= 50 && candidate.0 < best.0 {
                best = candidate; bestShift = d
            }
        }
        if abs(bestShift) > 2 && best.0 > stationary.0 * 0.72 {
            bestShift = 0; best = stationary
        }
        return MatchResult(shift: bestShift, error: best.0, valid: best.1 >= 50 && best.0 < 18)
    }

    // Refine the coarse displacement at full vertical resolution before cutting a seam.
    static func refine(_ a: GrayFrame, _ b: GrayFrame, estimate: Int, radius: Int) -> MatchResult {
        guard a.width == b.width, a.height == b.height, a.width >= 16,
              a.pixels.count == a.width * a.height, b.pixels.count == b.width * b.height else {
            return MatchResult(shift: 0, error: .infinity, valid: false)
        }
        let width = a.width, height = a.height
        var bestShift = estimate, bestError = Double.infinity, bestCount = 0
        let lo = max(1 - height, estimate - radius), hi = min(height - 1, estimate + radius)
        guard lo <= hi else { return MatchResult(shift: 0, error: .infinity, valid: false) }
        for shift in lo...hi {
            let first = max(1, 1 - shift), last = min(height - 1, height - shift)
            guard first < last else { continue }
            var sum = 0, count = 0
            for y in stride(from: first, to: last, by: 4) {
                for x in stride(from: 3, to: width - 3, by: 3) {
                    let i = (y + shift) * width + x, j = y * width + x
                    let gradientA = abs(Int(a.pixels[i]) - Int(a.pixels[i - width])) + abs(Int(a.pixels[i]) - Int(a.pixels[i - 2]))
                    let gradientB = abs(Int(b.pixels[j]) - Int(b.pixels[j - width])) + abs(Int(b.pixels[j]) - Int(b.pixels[j - 2]))
                    guard max(gradientA, gradientB) >= 18 else { continue }
                    sum += abs(Int(a.pixels[i]) - Int(b.pixels[j])); count += 1
                }
            }
            let error = count > 0 ? Double(sum) / Double(count) : .infinity
            if count >= 80 && error < bestError {
                bestError = error; bestShift = shift; bestCount = count
            }
        }
        return MatchResult(shift: bestShift, error: bestError, valid: bestCount >= 80 && bestError < 20)
    }
}
