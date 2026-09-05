import Foundation
import CoreGraphics
import Vision

public struct FeatureVector: Codable, Sendable, Equatable {
    public var values: [Float]
    public init(values: [Float]) { self.values = values }

    public func distance(to other: FeatureVector) -> Double {
        precondition(values.count == other.values.count, "feature vector length mismatch")
        var sum: Double = 0
        for i in values.indices {
            let d = Double(values[i]) - Double(other.values[i])
            sum += d * d
        }
        return sum.squareRoot()
    }
}

public enum FeatureVectorError: Error {
    case unsupportedElementType
}

public protocol FeaturePrintProviding: Sendable {
    func featureVector(for image: CGImage) async throws -> FeatureVector
}

public struct VisionFeaturePrintProvider: FeaturePrintProviding {
    public init() {}

    public func featureVector(for image: CGImage) async throws -> FeatureVector {
        let request = GenerateImageFeaturePrintRequest()
        let observation = try await request.perform(on: image)
        let count = observation.elementCount
        var values = [Float](repeating: 0, count: count)
        if observation.elementType == .double {
            observation.data.withUnsafeBytes { raw in
                let doubles = raw.bindMemory(to: Double.self)
                for i in 0..<min(count, doubles.count) { values[i] = Float(doubles[i]) }
            }
        } else {
            observation.data.withUnsafeBytes { raw in
                // Vision feature prints are Float32 arrays by default.
                let floats = raw.bindMemory(to: Float.self)
                for i in 0..<min(count, floats.count) { values[i] = floats[i] }
            }
        }
        return FeatureVector(values: values)
    }
}
