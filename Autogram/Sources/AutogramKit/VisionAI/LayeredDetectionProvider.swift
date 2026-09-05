import Foundation
import CoreGraphics
import PDFKit

/// Layered on-device security element detector: built-in heuristics seed
/// candidates, contour and saliency sources add more, then a two-stage
/// classifier (kNN, optionally a Foundation Model fallback) decides the
/// final kind for each merged candidate.
public struct LayeredDetectionProvider: SecurityElementsProviding {
    public static let version = 1

    public let builtIn: BuiltInCandidateSource
    public let extraSources: [any CandidateSourcing]
    public let classifier: TwoStageClassifier
    public let renderTargetWidth: Int
    public let maxConcurrentPages: Int

    public init(builtIn: BuiltInCandidateSource = BuiltInCandidateSource(),
                extraSources: [any CandidateSourcing] = [ContourCandidateSource(), SaliencyCandidateSource()],
                classifier: TwoStageClassifier,
                renderTargetWidth: Int = 760,
                maxConcurrentPages: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)) {
        self.builtIn = builtIn
        self.extraSources = extraSources
        self.classifier = classifier
        self.renderTargetWidth = renderTargetWidth
        self.maxConcurrentPages = maxConcurrentPages
    }

    public static func makeDefault(bank: ExampleBank, useFoundationModel: Bool) -> LayeredDetectionProvider {
        let knn = FeaturePrintClassifier(bank: bank)
        let fm: (any ElementClassifying)? = useFoundationModel ? FoundationModelClassifier.makeIfAvailable() : nil
        return LayeredDetectionProvider(classifier: TwoStageClassifier(primary: knn, secondary: fm))
    }

    /// Versioned audit identifier listing active stages, stored in SecurityReviewStamp.
    public var identifier: String {
        var stages = ["builtIn"] + extraSources.map { $0.source.rawValue }
        stages = CandidateSource.allCases.map(\.rawValue).filter { stages.contains($0) }
        var parts = ["LayeredDetectionProvider/\(Self.version)", stages.joined(separator: "+"), "kNN"]
        if classifier.secondary != nil { parts.append("fm") }
        return parts.joined(separator: " ")
    }

    public var providerName: String { identifier }

    public func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement] {
        guard document.pageCount > 0 else { return [] }
        let builtInResult = await builtIn.candidates(in: document, pageAnalyses: pageAnalyses)
        let builtInByPage = Dictionary(grouping: builtInResult.candidates, by: \.pageIndex)

        var elements = builtInResult.passthrough
        let pageIndices = (0..<document.pageCount).filter { index in
            pageAnalyses.first(where: { $0.pageIndex == index })?.isEmpty == false
        }

        // Bounded concurrency: a sliding window of pages.
        var next = 0
        await withTaskGroup(of: [SecurityElement].self) { group in
            func enqueue() {
                guard next < pageIndices.count else { return }
                let pageIndex = pageIndices[next]
                next += 1
                let seeded = builtInByPage[pageIndex] ?? []
                guard let page = document.page(at: pageIndex) else { return }
                let box = PageBox(page: page)
                group.addTask { await self.detectOnPage(page: box.page, pageIndex: pageIndex, seeded: seeded) }
            }
            for _ in 0..<maxConcurrentPages { enqueue() }
            for await pageElements in group {
                elements.append(contentsOf: pageElements)
                enqueue()
            }
        }
        return elements
    }

    private func detectOnPage(page: PDFPage, pageIndex: Int, seeded: [DetectionCandidate]) async -> [SecurityElement] {
        guard let rendered = BuiltInVisionProvider.render(page: page, targetWidth: renderTargetWidth) else {
            return seeded.compactMap { hinted($0) }
        }
        let image = rendered.cgImage
        let exclusions = await BuiltInVisionProvider.visionExclusionBoxes(cgImage: image)

        var candidates = seeded
        for source in extraSources {
            if let found = try? await source.candidates(pageImage: image, pageIndex: pageIndex) {
                candidates.append(contentsOf: found)
            }
        }
        let merged = CandidateMerger.merge(candidates, exclusions: exclusions)

        var result: [SecurityElement] = []
        for candidate in merged {
            guard let crop = PageCrop.crop(image, to: candidate.box) else { continue }
            guard let judgement = await classifier.classify(crop: crop, hint: candidate.kindHint,
                                                            hintConfidence: candidate.hintConfidence),
                  let kind = judgement.kind else { continue }
            result.append(SecurityElement(
                kind: kind, pageIndex: pageIndex, boundingBox: candidate.box,
                confidence: judgement.confidence, verbalDescription: judgement.descriptionSK,
                detectedByAI: true, reviewState: .pending,
                detectionSource: Self.sourceString(candidate: candidate, judgement: judgement)))
        }
        return result
    }

    private func hinted(_ candidate: DetectionCandidate) -> SecurityElement? {
        guard let kind = candidate.kindHint else { return nil }
        return SecurityElement(kind: kind, pageIndex: candidate.pageIndex, boundingBox: candidate.box,
                               confidence: candidate.hintConfidence ?? 0.5, detectedByAI: true,
                               reviewState: .pending, detectionSource: "\(candidate.sourceLabel); builtInHint")
    }

    static func sourceString(candidate: DetectionCandidate, judgement: ElementJudgement) -> String {
        switch judgement.decidedBy {
        case .featurePrintKNN: return "\(candidate.sourceLabel); kNN(n=\(judgement.supportCount))"
        case .foundationModel: return "\(candidate.sourceLabel); fm"
        case .builtInHint: return "\(candidate.sourceLabel); builtInHint"
        }
    }
}

/// PDFPage is not Sendable; this wrapper carries it across the task group
/// closure boundary under Swift 6 strict concurrency. Safe because each page
/// is only ever touched by the single task it was handed to.
private struct PageBox: @unchecked Sendable {
    let page: PDFPage
}
