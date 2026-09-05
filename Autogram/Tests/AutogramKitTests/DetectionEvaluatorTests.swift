import XCTest
@testable import AutogramKit

final class DetectionEvaluatorTests: XCTestCase {
    func testMatchesByIoUPerLabel() {
        let truth = [CreateMLImageAnnotation(image: "p0.png", annotations: [
            .init(label: "officialStamp", coordinates: .init(x: 750, y: 375, width: 500, height: 250)),
            .init(label: "handwrittenSignature", coordinates: .init(x: 100, y: 50, width: 100, height: 20))])]
        let predicted = [
            SecurityElement(kind: .officialStamp, pageIndex: 0, boundingBox: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5), confidence: 1),
            SecurityElement(kind: .initial, pageIndex: 0, boundingBox: .init(x: 0.0, y: 0.9, width: 0.05, height: 0.05), confidence: 1)]
        let metrics = DetectionEvaluator.score(predicted: predicted, truth: truth,
                                               imageSizes: ["p0.png": CGSize(width: 1000, height: 500)],
                                               pageOrder: ["p0.png"], iouThreshold: 0.4)
        XCTAssertEqual(metrics["officialStamp"], LabelMetrics(truePositives: 1, falsePositives: 0, falseNegatives: 0))
        XCTAssertEqual(metrics["handwrittenSignature"], LabelMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 1))
        XCTAssertEqual(metrics["initial"], LabelMetrics(truePositives: 0, falsePositives: 1, falseNegatives: 0))
    }

    func testPrecisionRecallF1() {
        let m = LabelMetrics(truePositives: 3, falsePositives: 1, falseNegatives: 2)
        XCTAssertEqual(m.precision, 0.75, accuracy: 1e-9)
        XCTAssertEqual(m.recall, 0.6, accuracy: 1e-9)
        XCTAssertEqual(m.f1, 2 * 0.75 * 0.6 / 1.35, accuracy: 1e-9)
        XCTAssertEqual(LabelMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 0).f1, 0)
    }
}
