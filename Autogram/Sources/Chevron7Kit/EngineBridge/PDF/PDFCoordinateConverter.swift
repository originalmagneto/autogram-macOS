import CoreGraphics

public struct DSSVisibleField: Sendable, Equatable {
    public let page: Int
    public let originX: CGFloat
    public let originY: CGFloat
    public let width: CGFloat
    public let height: CGFloat
}

public struct PDFCoordinateConverter {
    public func pageRect(_ cropBoxLocalRect: CGRect, in cropBox: CGRect) -> CGRect {
        cropBoxLocalRect.offsetBy(dx: cropBox.minX, dy: cropBox.minY)
    }

    public func cropBoxLocalRect(_ pageRect: CGRect, cropBox: CGRect) -> CGRect {
        pageRect.offsetBy(dx: -cropBox.minX, dy: -cropBox.minY)
    }

    public func dssField(
        _ placement: VisibleSignaturePlacement,
        cropBox: CGRect,
        pageRotation: Int
    ) -> DSSVisibleField {
        let pageRect = self.pageRect(placement.pageRect, in: cropBox)
        let rect = cropBoxLocalRect(pageRect, cropBox: cropBox)
        let rotation = ((pageRotation % 360) + 360) % 360

        switch rotation {
        case 90:
            return DSSVisibleField(
                page: placement.pageIndex + 1,
                originX: cropBox.height - rect.maxY,
                originY: cropBox.width - rect.maxX,
                width: rect.height,
                height: rect.width
            )
        case 180:
            return DSSVisibleField(
                page: placement.pageIndex + 1,
                originX: cropBox.width - rect.maxX,
                originY: rect.minY,
                width: rect.width,
                height: rect.height
            )
        case 270:
            return DSSVisibleField(
                page: placement.pageIndex + 1,
                originX: rect.minY,
                originY: rect.minX,
                width: rect.height,
                height: rect.width
            )
        default:
            return DSSVisibleField(
                page: placement.pageIndex + 1,
                originX: rect.minX,
                originY: cropBox.height - rect.minY - rect.height,
                width: rect.width,
                height: rect.height
            )
        }
    }
}
