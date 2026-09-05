import XCTest
@testable import AutogramKit

final class CreateMLExporterTests: XCTestCase {
    func testAnnotationsUseCentrePixelCoordinatesWithTopLeftOrigin() {
        // Box occupies the bottom-right quadrant of a 1000x500 image.
        let entry = BankEntry(label: .kind(.officialStamp), documentSHA256: "d", pageIndex: 2,
                              box: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5),
                              featureVector: .init(values: []), detectorVersion: "t")
        let negative = BankEntry(label: .negative, documentSHA256: "d", pageIndex: 2,
                                 box: .init(x: 0.1, y: 0.8, width: 0.1, height: 0.1),
                                 featureVector: .init(values: []), detectorVersion: "t")
        let result = CreateMLExporter.annotations(for: [entry, negative], imageSizes: ["d-p2.png": CGSize(width: 1000, height: 500)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].image, "d-p2.png")
        XCTAssertEqual(result[0].annotations.count, 1, "Negatívy sa neexportujú ako boxy")
        let box = result[0].annotations[0]
        XCTAssertEqual(box.label, "officialStamp")
        XCTAssertEqual(box.coordinates.x, 750, accuracy: 1e-6)
        XCTAssertEqual(box.coordinates.y, 375, accuracy: 1e-6)
        XCTAssertEqual(box.coordinates.width, 500, accuracy: 1e-6)
        XCTAssertEqual(box.coordinates.height, 250, accuracy: 1e-6)
    }

    func testPagesWithOnlyNegativesStillAppearWithEmptyAnnotations() {
        let negative = BankEntry(label: .negative, documentSHA256: "d", pageIndex: 0,
                                 box: .init(x: 0.1, y: 0.8, width: 0.1, height: 0.1),
                                 featureVector: .init(values: []), detectorVersion: "t")
        let result = CreateMLExporter.annotations(for: [negative], imageSizes: ["d-p0.png": CGSize(width: 10, height: 10)])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].annotations.isEmpty)
    }

    func testAnnotationsJSONShapeMatchesCreateML() throws {
        let annotation = CreateMLImageAnnotation(image: "a.png", annotations: [
            .init(label: "initial", coordinates: .init(x: 1, y: 2, width: 3, height: 4))])
        let data = try JSONEncoder().encode([annotation])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(object[0]["image"] as? String, "a.png")
        let first = try XCTUnwrap((object[0]["annotations"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["label"] as? String, "initial")
        XCTAssertEqual((first["coordinates"] as? [String: Double])?["width"], 3)
    }
}
