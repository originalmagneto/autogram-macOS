import Foundation
import CoreGraphics
import Vision

public enum SnapperError: Error { case assetsUnavailable, emptyMask }

public protocol SegmentationSnapping: Sendable {
    func ensureAssets(progress: @Sendable @escaping (Double) -> Void) async throws
    func snap(pageImage: CGImage, seed: NormalizedPoint) async throws -> NormalizedRect
    func refine(pageImage: CGImage, box: NormalizedRect) async throws -> NormalizedRect
}

/// Wraps Vision 27 iterative segmentation. Coordinates in and out use the
/// app's bottom-origin normalized convention.
public struct SegmentationSnapper: SegmentationSnapping {
    public var padding: Double = 0.04
    public init() {}

    public func ensureAssets(progress: @Sendable @escaping (Double) -> Void) async throws {
        let request = GenerateIterativeSegmentationRequest(seedPoint: Vision.NormalizedPoint(x: 0.5, y: 0.5))
        if case .ready = await request.assetStatus { return }
        progress(0)
        try await request.downloadAssets()
        progress(1)
        guard case .ready = await request.assetStatus else { throw SnapperError.assetsUnavailable }
    }

    public func snap(pageImage: CGImage, seed: NormalizedPoint) async throws -> NormalizedRect {
        // Vision seed points are lower-left origin, same as the app.
        let request = GenerateIterativeSegmentationRequest(seedPoint: Vision.NormalizedPoint(x: seed.x, y: seed.y))
        return try await perform(request, on: pageImage)
    }

    public func refine(pageImage: CGImage, box: NormalizedRect) async throws -> NormalizedRect {
        let request = GenerateIterativeSegmentationRequest(seedBox: Vision.NormalizedRect(
            x: box.x, y: box.y, width: box.width, height: box.height))
        return try await perform(request, on: pageImage)
    }

    private func perform(_ request: GenerateIterativeSegmentationRequest, on image: CGImage) async throws -> NormalizedRect {
        guard case .ready = await request.assetStatus else { throw SnapperError.assetsUnavailable }
        guard let observation = try await request.perform(on: image) else { throw SnapperError.emptyMask }
        let cgMask = try observation.cgImage
        let (mask, width, height) = Self.mask(from: cgMask)
        guard let rect = Self.boundingRect(ofMask: mask, width: width, height: height, padding: padding) else {
            throw SnapperError.emptyMask
        }
        return rect
    }

    /// Reads a Vision segmentation mask via its rendered CGImage rather than
    /// the raw pixel buffer (CVReadOnlyPixelBuffer is opaque in this SDK).
    public static func mask(from image: CGImage, threshold: Double = 0.5) -> (mask: [Bool], width: Int, height: Int) {
        guard let pixels = PixelMap(cgImage: image, targetWidth: image.width) else {
            return ([], 0, 0)
        }
        var mask = [Bool](repeating: false, count: pixels.width * pixels.height)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                mask[y * pixels.width + x] = pixels.luminance(x: x, y: y) > threshold
            }
        }
        return (mask, pixels.width, pixels.height)
    }

    public static func boundingRect(ofMask mask: [Bool], width: Int, height: Int, padding: Double = 0.04) -> NormalizedRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let pixel = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let base = PageCrop.normalizedRect(fromPixelRect: pixel, imageWidth: width, imageHeight: height)
        let padX = base.width * padding, padY = base.height * padding
        let x0 = max(0, base.x - padX), y0 = max(0, base.y - padY)
        let x1 = min(1, base.x + base.width + padX), y1 = min(1, base.y + base.height + padY)
        return NormalizedRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
