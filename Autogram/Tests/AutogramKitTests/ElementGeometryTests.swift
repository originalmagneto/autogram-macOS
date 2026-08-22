import XCTest
@testable import AutogramKit

final class ElementGeometryTests: XCTestCase {
    func testClampedCenteredStaysInsidePage() {
        let centered = ElementGeometry.clampedCentered(center: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(centered.x, 0.5 - 0.13, accuracy: 0.0001)
        XCTAssertEqual(centered.y, 0.5 - 0.05, accuracy: 0.0001)

        let atEdge = ElementGeometry.clampedCentered(center: NormalizedPoint(x: 1.2, y: -0.3))
        XCTAssertEqual(atEdge.x, 1 - ElementGeometry.defaultPlacementSize.width, accuracy: 0.0001)
        XCTAssertEqual(atEdge.y, 0)
    }

    func testMovedClampsInsideBounds() {
        let box = NormalizedRect(x: 0.4, y: 0.4, width: 0.26, height: 0.10)
        let moved = ElementGeometry.moved(box, center: NormalizedPoint(x: 0.99, y: 0.02))
        XCTAssertLessThanOrEqual(moved.x + moved.width, 1.0001)
        XCTAssertGreaterThanOrEqual(moved.y, 0)
        XCTAssertEqual(moved.width, box.width)
        XCTAssertEqual(moved.height, box.height)
    }

    func testResizedHandlesOppositeDirections() {
        let downRight = ElementGeometry.resized(from: NormalizedPoint(x: 0.2, y: 0.2),
                                                to: NormalizedPoint(x: 0.6, y: 0.7))
        XCTAssertEqual(downRight.x, 0.2)
        XCTAssertEqual(downRight.y, 0.2)
        XCTAssertEqual(downRight.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(downRight.height, 0.5, accuracy: 0.0001)

        let upLeft = ElementGeometry.resized(from: NormalizedPoint(x: 0.6, y: 0.7),
                                             to: NormalizedPoint(x: 0.2, y: 0.2))
        XCTAssertEqual(upLeft.x, 0.2)
        XCTAssertEqual(upLeft.y, 0.2)
        XCTAssertEqual(upLeft.width, 0.4, accuracy: 0.0001)

        let tiny = ElementGeometry.resized(from: .zero, to: NormalizedPoint(x: 0.001, y: 0.001))
        XCTAssertGreaterThanOrEqual(tiny.width, ElementGeometry.minSize.width)
        XCTAssertGreaterThanOrEqual(tiny.height, ElementGeometry.minSize.height)
    }

    func testHitTestPicksSmallestContainingElement() {
        let bigID = UUID()
        let smallID = UUID()
        let otherPageID = UUID()

        let elements: [(id: UUID, pageIndex: Int, box: NormalizedRect)] = [
            (bigID, 0, NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)),
            (smallID, 0, NormalizedRect(x: 0.45, y: 0.45, width: 0.15, height: 0.12)),
            (otherPageID, 1, NormalizedRect(x: 0.45, y: 0.45, width: 0.15, height: 0.12))
        ]

        XCTAssertEqual(ElementGeometry.hitTest(elements: elements,
                                               point: NormalizedPoint(x: 0.5, y: 0.5),
                                               pageIndex: 0), smallID)
        XCTAssertNil(ElementGeometry.hitTest(elements: elements,
                                             point: NormalizedPoint(x: 0.05, y: 0.05),
                                             pageIndex: 0))
        XCTAssertEqual(ElementGeometry.hitTest(elements: elements,
                                               point: NormalizedPoint(x: 0.5, y: 0.5),
                                               pageIndex: 1), otherPageID)
    }

    func testResizeHandleZone() {
        let box = NormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.2)
        let inHandle = NormalizedPoint(x: box.x + box.width * 0.95,
                                       y: box.y + box.height * 0.95)
        let insideButNotHandle = NormalizedPoint(x: box.midX, y: box.midY)
        let outside = NormalizedPoint(x: 0.9, y: 0.9)

        XCTAssertTrue(ElementGeometry.isInResizeHandle(box, inHandle))
        XCTAssertFalse(ElementGeometry.isInResizeHandle(box, insideButNotHandle))
        XCTAssertFalse(ElementGeometry.isInResizeHandle(box, outside))
    }

    func testAspectFitterLetterboxMapping() {
        let fitter = ElementGeometry.AspectFitter(container: CGSize(width: 400, height: 800),
                                                  imageAspect: 595.0 / 842.0)
        let content = fitter.contentRect
        XCTAssertEqual(content.width, 400, accuracy: 0.01)
        XCTAssertEqual(content.height, 400 / (595.0 / 842.0), accuracy: 0.5)

        let topLeft = fitter.normalizedPoint(from: CGPoint(x: content.minX, y: content.minY))
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.001)

        let bottomRight = fitter.normalizedPoint(from: CGPoint(x: content.maxX, y: content.maxY))
        XCTAssertEqual(bottomRight.x, 1, accuracy: 0.001)
        XCTAssertEqual(bottomRight.y, 1, accuracy: 0.001)

        let viewRect = fitter.viewRect(for: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertEqual(viewRect.minX, content.midX - content.width * 0.25, accuracy: 0.01)
        XCTAssertEqual(viewRect.midY, content.midY, accuracy: 0.01)
    }
}
