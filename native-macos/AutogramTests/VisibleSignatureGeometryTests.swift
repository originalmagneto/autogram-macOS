import CoreGraphics
import Testing
@testable import Autogram

@Test func dssFieldConvertsCropBoxLocalPlacementForPageRotations() {
    let placement = VisibleSignaturePlacement(
        pageIndex: 1,
        pageRect: CGRect(x: 72, y: 144, width: 216, height: 108),
        rotationDegrees: 31
    )
    let cropBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let converter = PDFCoordinateConverter()
    let cases: [(rotation: Int, originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat)] = [
        (0, 72, 540, 216, 108),
        (90, 540, 324, 108, 216),
        (180, 324, 144, 216, 108),
        (270, 144, 72, 108, 216)
    ]

    for testCase in cases {
        let field = converter.dssField(
            placement,
            cropBox: cropBox,
            pageRotation: testCase.rotation
        )

        #expect(field.page == 2)
        #expect(field.originX == testCase.originX)
        #expect(field.originY == testCase.originY)
        #expect(field.width == testCase.width)
        #expect(field.height == testCase.height)
    }
}

@Test func rotatedPlacementGeometryAlignsVisualBoundsAndHitTesting() {
    let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
    let geometry = PDFPlacementGeometry(rect: rect, rotationDegrees: 90)
    let rotatedTopLeft = geometry.rotatedPoint(CGPoint(x: rect.minX, y: rect.minY))

    #expect(approximatelyEqual(rotatedTopLeft, CGPoint(x: 85, y: -5)))
    #expect(approximatelyEqual(geometry.visualBounds, CGRect(x: 35, y: -5, width: 50, height: 100)))
    #expect(approximatelyEqual(geometry.unrotatedPoint(rotatedTopLeft), CGPoint(x: rect.minX, y: rect.minY)))
    #expect(geometry.contains(geometry.rotatedPoint(CGPoint(x: 20, y: 30))))
    #expect(!geometry.contains(CGPoint(x: rect.minX, y: rect.minY)))
}

private func approximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
    approximatelyEqual(lhs.x, rhs.x) && approximatelyEqual(lhs.y, rhs.y)
}

private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    approximatelyEqual(lhs.origin, rhs.origin)
        && approximatelyEqual(lhs.width, rhs.width)
        && approximatelyEqual(lhs.height, rhs.height)
}

private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    abs(lhs - rhs) <= CGFloat.ulpOfOne.squareRoot()
}
