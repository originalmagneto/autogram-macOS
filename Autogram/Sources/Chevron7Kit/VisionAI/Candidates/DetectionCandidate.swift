import Foundation

public enum CandidateSource: String, Codable, Sendable, Hashable, CaseIterable {
    case builtIn, contour, saliency
}

/// A region that may contain a security element. Produced by candidate
/// sources, merged, then classified. Box uses the app's bottom-origin
/// normalized convention.
public struct DetectionCandidate: Sendable, Hashable {
    public var pageIndex: Int
    public var box: NormalizedRect
    public var sources: Set<CandidateSource>
    public var kindHint: SecurityElement.Kind?
    public var hintConfidence: Double?

    public init(pageIndex: Int, box: NormalizedRect, sources: Set<CandidateSource>,
                kindHint: SecurityElement.Kind? = nil, hintConfidence: Double? = nil) {
        self.pageIndex = pageIndex
        self.box = box
        self.sources = sources
        self.kindHint = kindHint
        self.hintConfidence = hintConfidence
    }

    public var sourceLabel: String {
        CandidateSource.allCases.filter { sources.contains($0) }.map(\.rawValue).joined(separator: "+")
    }
}
