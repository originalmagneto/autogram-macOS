import XCTest
@testable import Chevron7Kit

final class SecurityElementCatalogueTests: XCTestCase {
    func testGenericStampLocationUsesNeutralWording() {
        let element = SecurityElement(kind: .officialStamp, pageIndex: 0,
            boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), confidence: 1)
        XCTAssertTrue(element.locationDescription(pageSizePt: .zero).hasPrefix("Odtlačok pečiatky"))
    }

    func testGenericStampDoesNotClaimStateEmblem() {
        XCTAssertEqual(SecurityElement.Kind.officialStamp.codelist15Item.code, "pečiatka")
    }

    func testLegacyElementKeepsItsKindAndScanObservation() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","kind":"Úradná pečiatka","pageIndex":0,"boundingBox":{"x":0.1,"y":0.2,"width":0.3,"height":0.2},"confidence":0.9}"#
        let element = try JSONDecoder().decode(SecurityElement.self, from: Data(json.utf8))
        XCTAssertEqual(element.kind, .officialStamp)
        XCTAssertTrue(element.hasScanRegion)
        XCTAssertEqual(element.reviewState, .pending)
    }

    func testPhysicalCordCannotBecomeAnImageTrainingExample() throws {
        let element = SecurityElement(kind: .bindingCord, pageIndex: 0, boundingBox: .zero,
                                      confidence: 1, detectedByAI: false,
                                      observation: .physicalOriginal, originalLocation: "Na hrane zväzku")
        let decoded = try JSONDecoder().decode(SecurityElement.self, from: JSONEncoder().encode(element))
        XCTAssertFalse(decoded.hasScanRegion)
        XCTAssertNil(decoded.trainingKind)
        XCTAssertEqual(decoded.originalLocation, "Na hrane zväzku")
    }

    func testLegalCertificationDoesNotBecomeAVisualClass() {
        let element = SecurityElement(kind: .certifiedSignature, pageIndex: 0,
                                      boundingBox: .init(x: 0, y: 0, width: 0.2, height: 0.1), confidence: 1)
        XCTAssertEqual(element.trainingKind, .handwrittenSignature)
    }
}
