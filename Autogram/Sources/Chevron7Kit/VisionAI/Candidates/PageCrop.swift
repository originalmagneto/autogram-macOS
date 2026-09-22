import Foundation
import CoreGraphics

/// Conversions between the app's bottom-origin normalized boxes and
/// top-origin pixel rects of a rendered page, plus cropping with margin.
public enum PageCrop {
    public static func pixelRect(for box: NormalizedRect, imageWidth: Int, imageHeight: Int,
                                 margin: Double = 0.12) -> CGRect {
        let w = Double(imageWidth), h = Double(imageHeight)
        let padX = box.width * margin, padY = box.height * margin
        let x0 = max(0, box.x - padX)
        let x1 = min(1, box.x + box.width + padX)
        let yBottom = max(0, box.y - padY)
        let yTop = min(1, box.y + box.height + padY)
        // Flip: pixel row 0 is the top of the page.
        let pxY = (1 - yTop) * h
        return CGRect(x: x0 * w, y: pxY, width: (x1 - x0) * w, height: (yTop - yBottom) * h)
    }

    public static func normalizedRect(fromPixelRect rect: CGRect, imageWidth: Int, imageHeight: Int) -> NormalizedRect {
        let w = Double(imageWidth), h = Double(imageHeight)
        let x = Double(rect.minX) / w
        let width = Double(rect.width) / w
        let height = Double(rect.height) / h
        let y = 1 - Double(rect.maxY) / h
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }

    public static func crop(_ image: CGImage, to box: NormalizedRect, margin: Double = 0.12) -> CGImage? {
        let rect = pixelRect(for: box, imageWidth: image.width, imageHeight: image.height, margin: margin)
            .integral
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return image.cropping(to: rect)
    }
}
