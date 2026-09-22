import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct PixelMap {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public init?(cgImage: CGImage, targetWidth: Int = 520) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        let scale = Double(targetWidth) / Double(w)
        let tw = max(1, Int(Double(w) * scale))
        let th = max(1, Int(Double(h) * scale))

        var data = [UInt8](repeating: 0, count: tw * th * 4)
        let ok = data.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: tw,
                height: th,
                bitsPerComponent: 8,
                bytesPerRow: tw * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
            return true
        }
        guard ok else { return nil }
        self.width = tw
        self.height = th
        self.rgba = data
    }

    @inline(__always)
    public func hueSaturationValue(x: Int, y: Int) -> (h: Double, s: Double, v: Double) {
        let idx = (y * width + x) * 4
        let r = Double(rgba[idx]) / 255.0
        let g = Double(rgba[idx + 1]) / 255.0
        let b = Double(rgba[idx + 2]) / 255.0
        let mx = max(r, g, b), mn = min(r, g, b)
        let delta = mx - mn
        let v = mx
        let s = mx == 0 ? 0 : delta / mx
        var h: Double = 0
        if delta > 0 {
            if mx == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0) }
            else if mx == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h, s, v)
    }

    @inline(__always)
    public func luminance(x: Int, y: Int) -> Double {
        let idx = (y * width + x) * 4
        return (0.299 * Double(rgba[idx]) + 0.587 * Double(rgba[idx + 1]) + 0.114 * Double(rgba[idx + 2])) / 255.0
    }

    public func jpegData(compressionQuality: CGFloat = 0.72) -> Data? {
        var mutable = rgba
        return mutable.withUnsafeMutableBytes { ptr -> Data? in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .medium
            guard let img = ctx.makeImage() else { return nil }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, img, [
                kCGImageDestinationLossyCompressionQuality: compressionQuality
            ] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return out as Data
        }
    }
}

public struct ComponentStats {
    public var area: Int = 0
    public var minX: Int = .max
    public var maxX: Int = -1
    public var minY: Int = .max
    public var maxY: Int = -1
    public var boundaryPixels: Int = 0

    public var bboxWidth: Int { maxX - minX + 1 }
    public var bboxHeight: Int { maxY - minY + 1 }
    public var aspectRatio: Double {
        bboxHeight == 0 ? 0 : Double(bboxWidth) / Double(bboxHeight)
    }
    public var circularity: Double {
        perimeter == 0 ? 0 : 4.0 * .pi * Double(area) / (Double(perimeter) * Double(perimeter))
    }
    public var perimeter: Int { boundaryPixels }
    public var fillRatio: Double {
        let bboxArea = bboxWidth * bboxHeight
        return bboxArea == 0 ? 0 : Double(area) / Double(bboxArea)
    }

    public init() {}
}

public enum ConnectedComponents {
    public static func label(mask: [Bool], width: Int, height: Int) -> [[(x: Int, y: Int)]] {
        var visited = [Bool](repeating: false, count: mask.count)
        var components: [[(x: Int, y: Int)]] = []
        var stack: [Int] = []

        for start in 0..<mask.count {
            guard mask[start], !visited[start] else { continue }
            visited[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var pixels: [(x: Int, y: Int)] = []

            while let current = stack.popLast() {
                let cy = current / width
                let cx = current % width
                pixels.append((cx, cy))

                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let ni = ny * width + nx
                    if mask[ni], !visited[ni] {
                        visited[ni] = true
                        stack.append(ni)
                    }
                }
            }
            components.append(pixels)
        }
        return components
    }

    public static func stats(for component: [(x: Int, y: Int)], mask: [Bool], width: Int, height: Int) -> ComponentStats {
        var stats = ComponentStats()
        for p in component {
            stats.area += 1
            stats.minX = min(stats.minX, p.x)
            stats.maxX = max(stats.maxX, p.x)
            stats.minY = min(stats.minY, p.y)
            stats.maxY = max(stats.maxY, p.y)

            var isBoundary = false
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = p.x + dx, ny = p.y + dy
                if nx < 0 || nx >= width || ny < 0 || ny >= height || !mask[ny * width + nx] {
                    isBoundary = true
                    break
                }
            }
            if isBoundary { stats.boundaryPixels += 1 }
        }
        return stats
    }
}
