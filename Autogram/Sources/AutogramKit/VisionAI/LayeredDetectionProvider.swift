import Foundation
import CoreGraphics
import PDFKit
import os

/// A page rendered and OCRed exactly once, then shared by every detection stage.
///
/// Sending this across task boundaries is safe: `PixelMap` is a value type and
/// `CGImage` is immutable, so no task can observe another task's mutation. The
/// `@unchecked` conformance is only needed because `CGImage` predates `Sendable`.
struct PreparedPage: @unchecked Sendable {
    let pageIndex: Int
    let pixels: PixelMap
    let image: CGImage
    let exclusions: BuiltInVisionProvider.VisionExclusions
}

/// Per-run counters, useful for the evaluation harness and for surfacing
/// degraded stages in the UI.
public struct DetectionRunStats: Sendable, Equatable {
    public var foundationModelCalls: Int
    public var pagesProcessed: Int
    public var sourceFailures: [String]

    public init(foundationModelCalls: Int = 0, pagesProcessed: Int = 0, sourceFailures: [String] = []) {
        self.foundationModelCalls = foundationModelCalls
        self.pagesProcessed = pagesProcessed
        self.sourceFailures = sourceFailures
    }
}

/// Counts how often the secondary (Foundation Model) classifier was invoked
/// during one detection run. Created per run, so the count never leaks between runs.
final class CallCountingClassifier: ElementClassifying, @unchecked Sendable {
    private let wrapped: any ElementClassifying
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    init(wrapping wrapped: any ElementClassifying) { self.wrapped = wrapped }

    var count: Int { calls.withLock { $0 } }

    func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
        calls.withLock { $0 += 1 }
        return try await wrapped.classify(crop: crop, hint: hint)
    }
}

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

    /// Upper bound on candidates per page that may reach the Foundation Model.
    /// Candidates beyond it are decided by kNN with the built-in hint as fallback.
    public var foundationModelBudgetPerPage: Int = 12

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
        await detectWithStats(in: document, pageAnalyses: pageAnalyses).elements
    }

    public func detectWithStats(in document: PDFDocument,
                                pageAnalyses: [PageAnalysis]) async -> (elements: [SecurityElement], stats: DetectionRunStats) {
        guard document.pageCount > 0 else { return ([], DetectionRunStats()) }

        // One sequential render pass. PDFKit is not thread safe, so every page is
        // rasterized and OCRed on this task before any concurrent work starts, and
        // the result is shared by the built-in heuristics and the extra sources.
        var prepared: [PreparedPage] = []
        for pageIndex in 0..<document.pageCount {
            guard let analysis = pageAnalyses.first(where: { $0.pageIndex == pageIndex }),
                  !analysis.isEmpty,
                  let page = document.page(at: pageIndex),
                  let rendered = BuiltInVisionProvider.render(page: page, targetWidth: renderTargetWidth) else { continue }
            let exclusions = await BuiltInVisionProvider.visionExclusionBoxes(cgImage: rendered.cgImage)
            prepared.append(PreparedPage(pageIndex: pageIndex, pixels: rendered.pixels,
                                         image: rendered.cgImage, exclusions: exclusions))
        }

        // Snapshot the example bank once per run so every page votes against the
        // same set of examples even if the user confirms elements while it runs.
        let counting = classifier.secondary.map { CallCountingClassifier(wrapping: $0) }
        let runClassifier = TwoStageClassifier(primary: await Self.snapshot(of: classifier.primary),
                                               secondary: counting,
                                               minimumSupport: classifier.minimumSupport,
                                               minimumMargin: classifier.minimumMargin)

        var elements: [SecurityElement] = []
        var sourceFailures: [String] = []
        var next = 0
        await withTaskGroup(of: PageResult.self) { group in
            // Enqueue keeps the sliding window full: it advances until a task was
            // actually added or the array ran out, so no page can consume a slot
            // without producing a result.
            func enqueue() {
                while next < prepared.count {
                    let page = prepared[next]
                    next += 1
                    group.addTask { await self.detectOnPage(page, classifier: runClassifier) }
                    return
                }
            }
            for _ in 0..<maxConcurrentPages { enqueue() }
            for await pageResult in group {
                elements.append(contentsOf: pageResult.elements)
                sourceFailures.append(contentsOf: pageResult.sourceFailures)
                enqueue()
            }
        }

        let stats = DetectionRunStats(foundationModelCalls: counting?.count ?? 0,
                                      pagesProcessed: prepared.count,
                                      sourceFailures: sourceFailures)
        return (elements, stats)
    }

    private struct PageResult: Sendable {
        var elements: [SecurityElement]
        var sourceFailures: [String]
    }

    private func detectOnPage(_ page: PreparedPage, classifier runClassifier: TwoStageClassifier) async -> PageResult {
        let builtInResult = builtIn.candidates(on: page)
        var candidates = builtInResult.candidates
        var sourceFailures: [String] = []
        for source in extraSources {
            do {
                candidates.append(contentsOf: try await source.candidates(pageImage: page.image, pageIndex: page.pageIndex))
            } catch {
                sourceFailures.append("\(source.source.rawValue): \(error.localizedDescription)")
            }
        }
        let merged = Self.prioritized(CandidateMerger.merge(candidates, exclusions: page.exclusions))

        // Candidates without a secondary classifier cannot reach the Foundation Model.
        let withoutFoundationModel = TwoStageClassifier(primary: runClassifier.primary, secondary: nil,
                                                        minimumSupport: runClassifier.minimumSupport,
                                                        minimumMargin: runClassifier.minimumMargin)

        var result = builtInResult.passthrough
        for (rank, candidate) in merged.enumerated() {
            guard let crop = PageCrop.crop(page.image, to: candidate.box) else { continue }
            let effective = rank < foundationModelBudgetPerPage ? runClassifier : withoutFoundationModel
            guard let judgement = await effective.classify(crop: crop, hint: candidate.kindHint,
                                                           hintConfidence: candidate.hintConfidence),
                  let kind = judgement.kind else { continue }
            // For a hint-only decision `descriptionSK` is empty on purpose: no
            // judgement produced a verbal description, and inventing one would
            // put unreviewed text in front of the notary.
            result.append(SecurityElement(
                kind: kind, pageIndex: page.pageIndex, boundingBox: candidate.box,
                confidence: judgement.confidence, verbalDescription: judgement.descriptionSK,
                detectedByAI: true, reviewState: .pending,
                detectionSource: Self.sourceString(candidate: candidate, judgement: judgement)))
        }
        return PageResult(elements: result, sourceFailures: sourceFailures)
    }

    /// Foundation Model budget order: hinted candidates first, then the ones more
    /// sources agreed on, then the larger regions.
    static func prioritized(_ candidates: [DetectionCandidate]) -> [DetectionCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsHinted = lhs.kindHint != nil
            let rhsHinted = rhs.kindHint != nil
            if lhsHinted != rhsHinted { return lhsHinted }
            if lhs.sources.count != rhs.sources.count { return lhs.sources.count > rhs.sources.count }
            return lhs.box.width * lhs.box.height > rhs.box.width * rhs.box.height
        }
    }

    /// Returns an examples-backed copy of a kNN classifier; any other classifier
    /// is returned unchanged.
    static func snapshot(of primary: any ElementClassifying) async -> any ElementClassifying {
        guard let knn = primary as? FeaturePrintClassifier else { return primary }
        return await knn.snapshot()
    }

    static func sourceString(candidate: DetectionCandidate, judgement: ElementJudgement) -> String {
        switch judgement.decidedBy {
        case .featurePrintKNN: return "\(candidate.sourceLabel); kNN(n=\(judgement.supportCount))"
        case .foundationModel: return "\(candidate.sourceLabel); fm"
        case .builtInHint: return "\(candidate.sourceLabel); builtInHint"
        }
    }
}
