import Foundation
import CoreGraphics

public enum ElementGeometry {
    public static let defaultPlacementSize = NormalizedRect(x: 0.37, y: 0.80, width: 0.26, height: 0.10)
    public static let minSize = NormalizedRect(x: 0, y: 0, width: 0.03, height: 0.02)
    public static let resizeHandleFraction: Double = 0.22

    public static func clampedCentered(center: NormalizedPoint,
                                       width: Double = defaultPlacementSize.width,
                                       height: Double = defaultPlacementSize.height) -> NormalizedRect {
        let w = min(max(width, minSize.width), 1)
        let h = min(max(height, minSize.height), 1)
        return NormalizedRect(
            x: min(max(center.x - w / 2, 0), 1 - w),
            y: min(max(center.y - h / 2, 0), 1 - h),
            width: w,
            height: h)
    }

    public static func moved(_ box: NormalizedRect, center: NormalizedPoint) -> NormalizedRect {
        NormalizedRect(
            x: min(max(center.x - box.width / 2, 0), 1 - box.width),
            y: min(max(center.y - box.height / 2, 0), 1 - box.height),
            width: box.width,
            height: box.height)
    }

    public static func resized(from anchor: NormalizedPoint, to corner: NormalizedPoint) -> NormalizedRect {
        let x = min(anchor.x, corner.x)
        let y = min(anchor.y, corner.y)
        let width = max(abs(corner.x - anchor.x), minSize.width)
        let height = max(abs(corner.y - anchor.y), minSize.height)
        return NormalizedRect(
            x: min(max(x, 0), 1 - min(width, 1)),
            y: min(max(y, 0), 1 - min(height, 1)),
            width: min(width, 1),
            height: min(height, 1))
    }

    public static func contains(_ box: NormalizedRect, _ point: NormalizedPoint) -> Bool {
        point.x >= box.x && point.x <= box.x + box.width &&
        point.y >= box.y && point.y <= box.y + box.height
    }

    public static func isInResizeHandle(_ box: NormalizedRect, _ point: NormalizedPoint) -> Bool {
        guard contains(box, point) else { return false }
        let handleX = box.x + box.width * (1 - resizeHandleFraction)
        let handleY = box.y + box.height * (1 - resizeHandleFraction)
        return point.x >= handleX && point.y >= handleY
    }

    public static func hitTest(elements: [(id: UUID, pageIndex: Int, box: NormalizedRect)],
                               point: NormalizedPoint,
                               pageIndex: Int) -> UUID? {
        elements
            .filter { $0.pageIndex == pageIndex && contains($0.box, point) }
            .min { $0.box.width * $0.box.height < $1.box.width * $1.box.height }?
            .id
    }

    public struct AspectFitter {
        public let container: CGSize
        public let imageAspect: CGFloat

        public init(container: CGSize, imageAspect: CGFloat) {
            self.container = container
            self.imageAspect = max(imageAspect, 0.0001)
        }

        public var contentRect: CGRect {
            let containerAspect = container.width / max(container.height, 1)
            var size = container
            if imageAspect > containerAspect {
                size.height = container.width / imageAspect
            } else {
                size.width = container.height * imageAspect
            }
            return CGRect(
                x: (container.width - size.width) / 2,
                y: (container.height - size.height) / 2,
                width: size.width,
                height: size.height)
        }

        public func normalizedPoint(from viewPoint: CGPoint) -> NormalizedPoint {
            let rect = contentRect
            guard rect.width > 0, rect.height > 0 else { return .zero }
            let x = (viewPoint.x - rect.minX) / rect.width
            let y = (viewPoint.y - rect.minY) / rect.height
            return NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        }

        public func viewRect(for normalized: NormalizedRect) -> CGRect {
            let rect = contentRect
            return CGRect(x: rect.minX + normalized.x * rect.width,
                          y: rect.minY + normalized.y * rect.height,
                          width: normalized.width * rect.width,
                          height: normalized.height * rect.height)
        }
    }
}
