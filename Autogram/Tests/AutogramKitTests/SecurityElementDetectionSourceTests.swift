import XCTest
@testable import AutogramKit

final class SecurityElementDetectionSourceTests: XCTestCase {
    func testDecodingLegacyElementWithoutDetectionSourceYieldsNil() throws {
        let json = """
        {"id":"9C4E1A4B-4C3F-4C58-8C6A-2F1E7B6E9F10","kind":"Úradná pečiatka","pageIndex":0,
         "boundingBox":{"x":0.1,"y":0.1,"width":0.2,"height":0.2},"confidence":0.8,
         "verbalDescription":"","detectedByAI":true,"reviewState":"pending"}
        """.data(using: .utf8)!
        let element = try JSONDecoder().decode(SecurityElement.self, from: json)
        XCTAssertNil(element.detectionSource)
    }

    func testDetectionSourceRoundTrips() throws {
        let element = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .init(x: 0, y: 0, width: 0.1, height: 0.1),
                                      confidence: 0.9, detectionSource: "builtIn+contour; kNN(n=12)")
        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(SecurityElement.self, from: data)
        XCTAssertEqual(decoded.detectionSource, "builtIn+contour; kNN(n=12)")
    }
}
