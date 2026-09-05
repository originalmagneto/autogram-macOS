import Foundation
import CoreGraphics

public struct LabelMetrics: Codable, Equatable, Sendable {
    public var truePositives: Int
    public var falsePositives: Int
    public var falseNegatives: Int
    public init(truePositives: Int, falsePositives: Int, falseNegatives: Int) {
        self.truePositives = truePositives; self.falsePositives = falsePositives; self.falseNegatives = falseNegatives
    }
    public var precision: Double { truePositives + falsePositives == 0 ? 0 : Double(truePositives) / Double(truePositives + falsePositives) }
    public var recall: Double { truePositives + falseNegatives == 0 ? 0 : Double(truePositives) / Double(truePositives + falseNegatives) }
    public var f1: Double { precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall) }
}

public struct EvaluationMetrics: Codable, Equatable, Sendable {
    public var perLabel: [String: LabelMetrics]
    public var meanMillisecondsPerPage: Double
    public var pages: Int
    /// Foundation Model invocations during the run. Zero for providers that do not report stats.
    public var foundationModelCalls: Int = 0
    public init(perLabel: [String: LabelMetrics], meanMillisecondsPerPage: Double, pages: Int,
                foundationModelCalls: Int = 0) {
        self.perLabel = perLabel; self.meanMillisecondsPerPage = meanMillisecondsPerPage; self.pages = pages
        self.foundationModelCalls = foundationModelCalls
    }
}

public enum DetectionEvaluator {
    public static func label(for kind: SecurityElement.Kind) -> String { BankLabel.kind(kind).exportLabel }

    /// Greedy one-to-one matching per page and label at the IoU threshold.
    public static func score(predicted: [SecurityElement], truth: [CreateMLImageAnnotation],
                             imageSizes: [String: CGSize], pageOrder: [String], iouThreshold: Double) -> [String: LabelMetrics] {
        var result: [String: LabelMetrics] = [:]
        func bump(_ label: String, _ update: (inout LabelMetrics) -> Void) {
            var m = result[label] ?? LabelMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 0)
            update(&m)
            result[label] = m
        }
        for (pageIndex, image) in pageOrder.enumerated() {
            guard let size = imageSizes[image] else { continue }
            let truthBoxes = (truth.first { $0.image == image }?.annotations ?? []).map { box -> (String, NormalizedRect) in
                let rect = CGRect(x: box.coordinates.x - box.coordinates.width / 2,
                                  y: box.coordinates.y - box.coordinates.height / 2,
                                  width: box.coordinates.width, height: box.coordinates.height)
                return (box.label, PageCrop.normalizedRect(fromPixelRect: rect, imageWidth: Int(size.width), imageHeight: Int(size.height)))
            }
            var unmatchedTruth = truthBoxes
            for element in predicted where element.pageIndex == pageIndex {
                let label = self.label(for: element.kind)
                if let index = unmatchedTruth.firstIndex(where: { $0.0 == label && SecurityElementMerger.iou($0.1, element.boundingBox) >= iouThreshold }) {
                    unmatchedTruth.remove(at: index)
                    bump(label) { $0.truePositives += 1 }
                } else {
                    bump(label) { $0.falsePositives += 1 }
                }
            }
            for (label, _) in unmatchedTruth { bump(label) { $0.falseNegatives += 1 } }
        }
        return result
    }
}
