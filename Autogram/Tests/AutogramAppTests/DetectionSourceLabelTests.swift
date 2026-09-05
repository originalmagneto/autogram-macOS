import XCTest
@testable import AutogramApp

final class DetectionSourceLabelTests: XCTestCase {
    func testManualElementHasNoDetectionSource() {
        XCTAssertEqual(DetectionSourceLabel.slovak(nil), "Označené ručne")
    }

    func testHintOnlyHeuristicIsNamedAsAnEstimate() {
        XCTAssertEqual(DetectionSourceLabel.slovak("builtIn; builtInHint"),
                       "heuristika; iba odhad heuristiky")
    }

    func testNearestNeighbourCountIsSpelledOut() {
        XCTAssertEqual(DetectionSourceLabel.slovak("contour+saliency; kNN(n=7)"),
                       "kontúry+saliency; porovnanie s 7 príkladmi")
    }

    func testFoundationModelIsNamed() {
        XCTAssertEqual(DetectionSourceLabel.slovak("builtIn; fm"), "heuristika; on-device model")
    }
}
