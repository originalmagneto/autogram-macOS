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
