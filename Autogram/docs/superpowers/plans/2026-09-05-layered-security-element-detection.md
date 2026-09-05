# Layered Security-Element Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the heuristic-only built-in detector with a layered on-device pipeline (multi-source candidates, feature-print kNN plus Foundation Model classification, review-driven learning, click-to-snap, evaluation harness) without touching `BuiltInVisionProvider` internals.

**Architecture:** `DetectionPipeline` keeps its public shape; its built-in stage becomes `LayeredDetectionProvider`, which runs three candidate sources per page, merges them, classifies each crop through a two-stage classifier, and emits pending `SecurityElement`s. `ExampleBank` persists confirmed and rejected crops as feature vectors and page renders, feeding both the kNN classifier and a Create ML export. `SegmentationSnapper` wraps Vision 27 iterative segmentation for the canvas.

**Tech Stack:** Swift 6, SwiftPM, XCTest, PDFKit, Vision (Swift API: `DetectContoursRequest`, `GenerateObjectnessBasedSaliencyImageRequest`, `GenerateImageFeaturePrintRequest`, `GenerateIterativeSegmentationRequest`), FoundationModels (`LanguageModelSession`, `@Generable`, `Attachment`).

**Spec:** `Autogram/docs/superpowers/specs/2026-09-05-layered-security-element-detection-design.md`

## Global Constraints

- Build and test only with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (Xcode 27.0). Command Line Tools alone fail on SwiftUI macros.
- All commands run from `/Users/magneto/Projects/Autogram-macOS/Autogram` (the SwiftPM root). Commit from the repo root `/Users/magneto/Projects/Autogram-macOS`.
- Platform floor stays `.macOS("27.0")` in `Package.swift`.
- Do not edit the internals of `Sources/AutogramKit/VisionAI/BuiltInVisionProvider.swift`. Wrapping it and calling its existing internal helpers (`render(page:targetWidth:)`, `visionExclusionBoxes(cgImage:)`, `VisionExclusions`) is allowed.
- English for identifiers, comments and docs; Slovak for user-facing strings.
- Never use em dashes in any text. Use hyphens, colons or parentheses.
- Keep `AGENTS.md` and `CLAUDE.md` byte-identical.
- No real scanned documents enter the repository. Fixtures come from `Tests/AutogramKitTests/TestPDFBuilder.swift`.
- Coordinate convention: app `NormalizedRect` is PDF bottom-origin (0...1). Vision's `NormalizedRect` is also lower-left origin; convert through pixel rects, never by assumption. Inside `AutogramKit`, the unqualified `NormalizedRect` is the app type; write `Vision.NormalizedRect` for Vision's.
- Test helper `awaitAsync` and `TestUncheckedSendable` already exist in `Tests/AutogramKitTests/SecurityElementsDetectorTests.swift` and `TestSendableBox.swift`.
- Commit message trailer: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## File Map

Create (all under `Sources/AutogramKit/VisionAI/` unless stated):
- `Candidates/DetectionCandidate.swift` - candidate value type and `CandidateSource` enum
- `Candidates/CandidateMerger.swift` - NMS, size gates, exclusion filtering
- `Candidates/CandidateSourcing.swift` - protocol plus `BuiltInCandidateSource`
- `Candidates/ContourCandidateSource.swift`
- `Candidates/SaliencyCandidateSource.swift`
- `Candidates/PageCrop.swift` - crop with margin, pixel/normalized conversions
- `Classification/ElementJudgement.swift` - judgement type, `ElementClassifying`, `ClassifierIdentity`
- `Classification/FeatureVector.swift` - `FeatureVector`, `FeaturePrintProviding`, `VisionFeaturePrintProvider`
- `Classification/FeaturePrintClassifier.swift`
- `Classification/FoundationModelClassifier.swift` - `FoundationJudging`, `FoundationJudgement`, live implementation
- `Classification/TwoStageClassifier.swift`
- `Learning/ExampleBank.swift` - `BankLabel`, `BankEntry`, `ExampleBank` actor, `ExampleBankStore`
- `Learning/ExampleBankRecorder.swift` - render, crop, embed, write on review decisions
- `Learning/CreateMLExporter.swift`
- `Segmentation/SegmentationSnapper.swift`
- `LayeredDetectionProvider.swift`
- `Evaluation/DetectionEvaluator.swift` - metrics (library code so it is testable)
- `Sources/vision-eval/main.swift` - CLI target
- Tests mirror these names under `Tests/AutogramKitTests/` and `Tests/AutogramAppTests/`.

Modify:
- `Sources/AutogramKit/Models/DomainModels.swift` - `detectionSource`
- `Sources/AutogramKit/VisionAI/SecurityElementsProviding.swift` - pipeline uses layered provider
- `Sources/AutogramKit/Support/AppSettings.swift` - two toggles
- `Sources/AutogramApp/ZakoSessionStore.swift` - pipeline build, bank recording, detector identifier, snapper
- `Sources/AutogramApp/Views/AnalysisCanvasView.swift` - click-to-snap, refine action
- `Sources/AutogramApp/Views/SettingsView.swift` - learning and dataset group
- `Package.swift` - `vision-eval` target
- `build_app.sh`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `AUTOGRAM_ZAKO_MODULE_SPEC.md`

---

### Task 1: Build environment and `detectionSource` field

**Files:**
- Modify: `build_app.sh:25`
- Modify: `AGENTS.md:7,31-32`, `CLAUDE.md:7,31-32`
- Modify: `Sources/AutogramKit/Models/DomainModels.swift:143-184`
- Test: `Tests/AutogramKitTests/SecurityElementDetectionSourceTests.swift`

**Interfaces:**
- Produces: `SecurityElement.detectionSource: String?` (default `nil`), new init parameter `detectionSource: String? = nil` appended last.

- [ ] **Step 1: Point tooling at Xcode 27**

In `build_app.sh` line 25 replace the default:

```bash
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
```

In both `AGENTS.md` and `CLAUDE.md`, line 7 becomes `- Swift 6.0+ / Xcode 27.0 toolchain (`/Applications/Xcode-beta.app`)` and lines 31-32 use `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"`. Verify with `diff AGENTS.md CLAUDE.md` (no output).

- [ ] **Step 2: Write the failing back-compat test**

```swift
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
```

- [ ] **Step 3: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter SecurityElementDetectionSourceTests`
Expected: compile error, `extra argument 'detectionSource'`.

- [ ] **Step 4: Add the field**

In `DomainModels.swift` inside `SecurityElement`:

```swift
    public var reviewState: SecurityElementReviewState
    /// Audit string naming the candidate sources and the deciding classifier,
    /// for example "builtIn+contour; kNN(n=12)". Nil for manual or legacy elements.
    public var detectionSource: String?

    private enum CodingKeys: String, CodingKey {
        case id, kind, pageIndex, boundingBox, confidence, verbalDescription,
             detectedByAI, reviewState, detectionSource
    }

    public init(id: UUID = UUID(), kind: Kind, pageIndex: Int,
                boundingBox: NormalizedRect, confidence: Double,
                verbalDescription: String = "", detectedByAI: Bool = true,
                reviewState: SecurityElementReviewState? = nil,
                detectionSource: String? = nil) {
        // existing assignments unchanged, then:
        self.detectionSource = detectionSource
    }
```

In `init(from decoder:)` add after `reviewState`:

```swift
        self.detectionSource = try container.decodeIfPresent(String.self, forKey: .detectionSource)
```

- [ ] **Step 5: Run the test and the whole suite**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`
Expected: all pass (the new file adds 2).

- [ ] **Step 6: Commit**

```bash
git add Autogram/build_app.sh AGENTS.md CLAUDE.md Autogram/Sources/AutogramKit/Models/DomainModels.swift Autogram/Tests/AutogramKitTests/SecurityElementDetectionSourceTests.swift
git commit -m "feat: add detectionSource to SecurityElement and target Xcode 27

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Candidate model, page crop, and merger

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Candidates/DetectionCandidate.swift`
- Create: `Sources/AutogramKit/VisionAI/Candidates/PageCrop.swift`
- Create: `Sources/AutogramKit/VisionAI/Candidates/CandidateMerger.swift`
- Test: `Tests/AutogramKitTests/CandidateMergerTests.swift`, `Tests/AutogramKitTests/PageCropTests.swift`

**Interfaces:**
- Produces:
  - `enum CandidateSource: String, Codable, Sendable, Hashable { case builtIn, contour, saliency }`
  - `struct DetectionCandidate: Sendable, Hashable { pageIndex: Int; box: NormalizedRect; sources: Set<CandidateSource>; kindHint: SecurityElement.Kind?; hintConfidence: Double? }`
  - `enum CandidateMerger { static func merge(_ candidates: [DetectionCandidate], exclusions: VisionExclusions, iouThreshold: Double = 0.5) -> [DetectionCandidate] }`
  - `enum PageCrop { static func pixelRect(for box: NormalizedRect, imageWidth: Int, imageHeight: Int, margin: Double = 0.12) -> CGRect; static func crop(_ image: CGImage, to box: NormalizedRect, margin: Double = 0.12) -> CGImage?; static func normalizedRect(fromPixelRect rect: CGRect, imageWidth: Int, imageHeight: Int) -> NormalizedRect }`

- [ ] **Step 1: Write failing tests**

`CandidateMergerTests.swift`:

```swift
import XCTest
@testable import AutogramKit

final class CandidateMergerTests: XCTestCase {
    private func cand(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                      source: CandidateSource, hint: SecurityElement.Kind? = nil,
                      conf: Double? = nil, page: Int = 0) -> DetectionCandidate {
        DetectionCandidate(pageIndex: page, box: .init(x: x, y: y, width: w, height: h),
                           sources: [source], kindHint: hint, hintConfidence: conf)
    }

    func testOverlappingCandidatesAreUnionedAndKeepStrongestHint() {
        let a = cand(0.10, 0.10, 0.20, 0.20, source: .builtIn, hint: .officialStamp, conf: 0.7)
        let b = cand(0.12, 0.12, 0.20, 0.20, source: .contour)
        let merged = CandidateMerger.merge([a, b], exclusions: .empty)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sources, [.builtIn, .contour])
        XCTAssertEqual(merged[0].kindHint, .officialStamp)
        XCTAssertEqual(merged[0].box.x, 0.10, accuracy: 1e-9)
        XCTAssertEqual(merged[0].box.width, 0.22, accuracy: 1e-9)
    }

    func testDifferentPagesNeverMerge() {
        let a = cand(0.1, 0.1, 0.2, 0.2, source: .builtIn, page: 0)
        let b = cand(0.1, 0.1, 0.2, 0.2, source: .contour, page: 1)
        XCTAssertEqual(CandidateMerger.merge([a, b], exclusions: .empty).count, 2)
    }

    func testTinyAndHugeBoxesAreDropped() {
        let tiny = cand(0.5, 0.5, 0.01, 0.01, source: .contour)      // area 1e-4 < 2e-4
        let huge = cand(0.0, 0.0, 0.6, 0.6, source: .saliency)       // area 0.36 > 0.25
        let ok = cand(0.2, 0.2, 0.1, 0.1, source: .contour)
        let merged = CandidateMerger.merge([tiny, huge, ok], exclusions: .empty)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].box.x, 0.2, accuracy: 1e-9)
    }

    func testExtremeAspectIsDropped() {
        let line = cand(0.1, 0.5, 0.5, 0.02, source: .contour) // aspect 25 > 18
        XCTAssertTrue(CandidateMerger.merge([line], exclusions: .empty).isEmpty)
    }

    func testCandidateOverlappingTextIsDropped() {
        var exclusions = VisionExclusions.empty
        exclusions.textBoxes = [.init(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        let onText = cand(0.1, 0.1, 0.3, 0.05, source: .contour)
        let clear = cand(0.6, 0.6, 0.1, 0.1, source: .contour)
        let merged = CandidateMerger.merge([onText, clear], exclusions: exclusions)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].box.x, 0.6, accuracy: 1e-9)
    }

    func testBuiltInHintSurvivesTextOverlapBecauseBuiltInAlreadyExcluded() {
        var exclusions = VisionExclusions.empty
        exclusions.textBoxes = [.init(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        let builtIn = cand(0.1, 0.1, 0.3, 0.05, source: .builtIn, hint: .handwrittenSignature, conf: 0.6)
        XCTAssertEqual(CandidateMerger.merge([builtIn], exclusions: exclusions).count, 1)
    }
}
```

`PageCropTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import AutogramKit

final class PageCropTests: XCTestCase {
    func testPixelRectFlipsToTopOriginAndAddsMargin() {
        // Box in bottom-origin normalized space: x 0.5, y 0.0, w 0.5, h 0.5 (bottom-right quadrant).
        let rect = PageCrop.pixelRect(for: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5),
                                      imageWidth: 200, imageHeight: 100, margin: 0.0)
        XCTAssertEqual(rect, CGRect(x: 100, y: 50, width: 100, height: 50))

        let padded = PageCrop.pixelRect(for: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5),
                                        imageWidth: 200, imageHeight: 100, margin: 0.1)
        XCTAssertEqual(padded.minX, 90, accuracy: 0.5)   // 10% of 100px width
        XCTAssertEqual(padded.maxX, 200, accuracy: 0.5)  // clamped to image
        XCTAssertEqual(padded.minY, 45, accuracy: 0.5)   // 10% of 50px height
        XCTAssertEqual(padded.maxY, 100, accuracy: 0.5)
    }

    func testNormalizedRectFromPixelRectRoundTrips() {
        let original = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let px = PageCrop.pixelRect(for: original, imageWidth: 400, imageHeight: 200, margin: 0)
        let back = PageCrop.normalizedRect(fromPixelRect: px, imageWidth: 400, imageHeight: 200)
        XCTAssertEqual(back.x, original.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, original.y, accuracy: 1e-9)
        XCTAssertEqual(back.width, original.width, accuracy: 1e-9)
        XCTAssertEqual(back.height, original.height, accuracy: 1e-9)
    }

    func testCropReturnsImageOfExpectedSize() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        let crop = try XCTUnwrap(PageCrop.crop(image, to: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5), margin: 0))
        XCTAssertEqual(crop.width, 100)
        XCTAssertEqual(crop.height, 50)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "CandidateMergerTests|PageCropTests"`
Expected: compile errors for missing types.

- [ ] **Step 3: Implement**

`DetectionCandidate.swift`:

```swift
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
```

`PageCrop.swift`:

```swift
import Foundation
import CoreGraphics

/// Conversions between the app's bottom-origin normalized boxes and
/// top-origin pixel rects of a rendered page, plus cropping with margin.
public enum PageCrop {
    public static func pixelRect(for box: NormalizedRect, imageWidth: Int, imageHeight: Int,
                                 margin: Double = 0.12) -> CGRect {
        let w = Double(imageWidth), h = Double(imageHeight)
        let padX = box.width * margin, padY = box.height * margin
        let x0 = max(0, box.x - padX)
        let x1 = min(1, box.x + box.width + padX)
        let yBottom = max(0, box.y - padY)
        let yTop = min(1, box.y + box.height + padY)
        // Flip: pixel row 0 is the top of the page.
        let pxY = (1 - yTop) * h
        return CGRect(x: x0 * w, y: pxY, width: (x1 - x0) * w, height: (yTop - yBottom) * h)
    }

    public static func normalizedRect(fromPixelRect rect: CGRect, imageWidth: Int, imageHeight: Int) -> NormalizedRect {
        let w = Double(imageWidth), h = Double(imageHeight)
        let x = Double(rect.minX) / w
        let width = Double(rect.width) / w
        let height = Double(rect.height) / h
        let y = 1 - Double(rect.maxY) / h
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }

    public static func crop(_ image: CGImage, to box: NormalizedRect, margin: Double = 0.12) -> CGImage? {
        let rect = pixelRect(for: box, imageWidth: image.width, imageHeight: image.height, margin: margin)
            .integral
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return image.cropping(to: rect)
    }
}
```

`CandidateMerger.swift`:

```swift
import Foundation

public enum CandidateMerger {
    public static let minAreaRatio = 0.0002
    public static let maxAreaRatio = 0.25
    public static let maxAspect = 18.0
    public static let exclusionOverlap = 0.3

    public static func merge(_ candidates: [DetectionCandidate],
                             exclusions: VisionExclusions,
                             iouThreshold: Double = 0.5) -> [DetectionCandidate] {
        let gated = candidates.filter { passesGates($0, exclusions: exclusions) }
        var result: [DetectionCandidate] = []
        // Strongest hints first so the union keeps them.
        for candidate in gated.sorted(by: { ($0.hintConfidence ?? 0) > ($1.hintConfidence ?? 0) }) {
            if let index = result.firstIndex(where: {
                $0.pageIndex == candidate.pageIndex &&
                SecurityElementMerger.iou($0.box, candidate.box) > iouThreshold
            }) {
                result[index] = union(result[index], candidate)
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    static func passesGates(_ c: DetectionCandidate, exclusions: VisionExclusions) -> Bool {
        let area = c.box.width * c.box.height
        guard area >= minAreaRatio, area <= maxAreaRatio else { return false }
        guard c.box.width > 0, c.box.height > 0 else { return false }
        let aspect = max(c.box.width / c.box.height, c.box.height / c.box.width)
        guard aspect <= maxAspect else { return false }
        // Built-in candidates were already screened against OCR text by BuiltInVisionProvider.
        if c.sources == [.builtIn] { return true }
        return !exclusions.overlapsTextOrBarcode(c.box, threshold: exclusionOverlap)
    }

    static func union(_ a: DetectionCandidate, _ b: DetectionCandidate) -> DetectionCandidate {
        let x0 = min(a.box.x, b.box.x), y0 = min(a.box.y, b.box.y)
        let x1 = max(a.box.x + a.box.width, b.box.x + b.box.width)
        let y1 = max(a.box.y + a.box.height, b.box.y + b.box.height)
        let stronger = (a.hintConfidence ?? -1) >= (b.hintConfidence ?? -1) ? a : b
        return DetectionCandidate(pageIndex: a.pageIndex,
                                  box: .init(x: x0, y: y0, width: x1 - x0, height: y1 - y0),
                                  sources: a.sources.union(b.sources),
                                  kindHint: stronger.kindHint ?? a.kindHint ?? b.kindHint,
                                  hintConfidence: stronger.hintConfidence ?? a.hintConfidence ?? b.hintConfidence)
    }
}
```

`VisionExclusions` in `BuiltInVisionProvider.swift` is a nested internal `struct` inside `BuiltInVisionProvider`. Check with `grep -n "struct VisionExclusions" Sources/AutogramKit/VisionAI/BuiltInVisionProvider.swift`; if nested, reference it as `BuiltInVisionProvider.VisionExclusions` in the code above and add at the top of `CandidateMerger.swift`: `public typealias VisionExclusions = BuiltInVisionProvider.VisionExclusions`. Its `textBoxes` property must be settable from tests; it already is (`var textBoxes`). If the struct's access level is `private`, that would require editing the frozen file; it is not private (verified on 2026-09-05).

- [ ] **Step 4: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "CandidateMergerTests|PageCropTests"`
Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/Candidates Autogram/Tests/AutogramKitTests/CandidateMergerTests.swift Autogram/Tests/AutogramKitTests/PageCropTests.swift
git commit -m "feat: add detection candidate model, crop helpers and merger

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Candidate sources (built-in wrapper, contours, saliency)

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Candidates/CandidateSourcing.swift`
- Create: `Sources/AutogramKit/VisionAI/Candidates/ContourCandidateSource.swift`
- Create: `Sources/AutogramKit/VisionAI/Candidates/SaliencyCandidateSource.swift`
- Test: `Tests/AutogramKitTests/CandidateSourceTests.swift`

**Interfaces:**
- Consumes: `DetectionCandidate`, `CandidateSource`, `PageCrop.normalizedRect(fromPixelRect:imageWidth:imageHeight:)`, `BuiltInVisionProvider.render(page:targetWidth:)` (returns `RenderedPage` with `.cgImage` and `.pixels`).
- Produces:
  - `protocol CandidateSourcing: Sendable { var source: CandidateSource { get }; func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] }`
  - `struct BuiltInCandidateSource: Sendable { init(provider: BuiltInVisionProvider = .init()); func candidates(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> (candidates: [DetectionCandidate], passthrough: [SecurityElement]) }` (barcode elements are passthrough)
  - `struct ContourCandidateSource: CandidateSourcing`
  - `struct SaliencyCandidateSource: CandidateSourcing`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import PDFKit
@testable import AutogramKit

final class CandidateSourceTests: XCTestCase {
    private func renderedContractPage() throws -> CGImage {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let page = try XCTUnwrap(document.page(at: 0))
        return try XCTUnwrap(BuiltInVisionProvider.render(page: page, targetWidth: 760)?.cgImage)
    }

    func testBuiltInSourceConvertsElementsToHintedCandidatesAndPassesBarcodesThrough() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let analysis = PDFAnalysisEngine().analyze(document: document)
        let doc = TestUncheckedSendable(document)
        let result = awaitAsync {
            await BuiltInCandidateSource().candidates(in: doc.value, pageAnalyses: analysis.pageAnalyses)
        }
        XCTAssertFalse(result.candidates.isEmpty, "Vstavaný detektor má vrátiť aspoň jedného kandidáta")
        XCTAssertTrue(result.candidates.allSatisfy { $0.sources == [.builtIn] && $0.kindHint != nil })
        XCTAssertTrue(result.passthrough.allSatisfy { $0.kind == .other })
    }

    func testContourSourceFindsDrawnStampRegion() throws {
        let image = try renderedContractPage()
        let candidates = try awaitAsyncThrowing {
            try await ContourCandidateSource().candidates(pageImage: image, pageIndex: 0)
        }
        // typicalContractPDF draws a ring at the lower right; expect a candidate whose
        // centre lies in that quadrant.
        XCTAssertTrue(candidates.contains { $0.box.midX > 0.5 && $0.box.midY < 0.5 },
                      "Kontúry nenašli kandidáta v pravom dolnom kvadrante: \(candidates.map(\.box))")
        XCTAssertTrue(candidates.allSatisfy { $0.sources == [.contour] })
    }

    func testSaliencySourceReturnsOnlyValidNormalizedBoxes() throws {
        let image = try renderedContractPage()
        let candidates = try awaitAsyncThrowing {
            try await SaliencyCandidateSource().candidates(pageImage: image, pageIndex: 0)
        }
        for c in candidates {
            XCTAssertTrue((0...1).contains(c.box.x) && (0...1).contains(c.box.y))
            XCTAssertLessThanOrEqual(c.box.x + c.box.width, 1.0001)
            XCTAssertLessThanOrEqual(c.box.y + c.box.height, 1.0001)
            XCTAssertEqual(c.sources, [.saliency])
        }
    }
}

func awaitAsyncThrowing<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = TestSendableBox<Result<T, Error>>()
    let expectation = XCTestExpectation(description: "async")
    Task {
        do { box.value = .success(try await body()) } catch { box.value = .failure(error) }
        expectation.fulfill()
    }
    XCTWaiter().wait(for: [expectation], timeout: 60)
    return try box.value!.get()
}
```

Check `Tests/AutogramKitTests/TestSendableBox.swift` for the box type's actual name and property; adapt the helper to it (the existing `awaitAsync` in `SecurityElementsDetectorTests.swift` shows the pattern).

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter CandidateSourceTests`
Expected: compile errors for missing types.

- [ ] **Step 3: Implement**

`CandidateSourcing.swift`:

```swift
import Foundation
import CoreGraphics
import PDFKit

public protocol CandidateSourcing: Sendable {
    var source: CandidateSource { get }
    func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate]
}

/// Wraps the frozen heuristic detector. Its elements become hinted candidates;
/// barcode/QR elements are already reliable and pass through unchanged.
public struct BuiltInCandidateSource: Sendable {
    public let provider: BuiltInVisionProvider
    public init(provider: BuiltInVisionProvider = BuiltInVisionProvider()) { self.provider = provider }

    public func candidates(in document: PDFDocument,
                           pageAnalyses: [PageAnalysis]) async -> (candidates: [DetectionCandidate], passthrough: [SecurityElement]) {
        let elements = await provider.detect(in: document, pageAnalyses: pageAnalyses)
        var candidates: [DetectionCandidate] = []
        var passthrough: [SecurityElement] = []
        for element in elements {
            if element.kind == .other {
                passthrough.append(element)
            } else {
                candidates.append(DetectionCandidate(pageIndex: element.pageIndex, box: element.boundingBox,
                                                     sources: [.builtIn], kindHint: element.kind,
                                                     hintConfidence: element.confidence))
            }
        }
        return (candidates, passthrough)
    }
}
```

`ContourCandidateSource.swift`:

```swift
import Foundation
import CoreGraphics
import Vision

public struct ContourCandidateSource: CandidateSourcing {
    public var source: CandidateSource { .contour }
    public var contrastAdjustment: Float = 2.0
    public var maximumImageDimension = 760

    public init() {}

    public func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
        var request = DetectContoursRequest()
        request.contrastAdjustment = contrastAdjustment
        request.detectsDarkOnLight = true
        request.maximumImageDimension = maximumImageDimension
        let observation = try await request.perform(on: pageImage)
        let size = CGSize(width: pageImage.width, height: pageImage.height)
        var result: [DetectionCandidate] = []
        for contour in observation.topLevelContours {
            // normalizedPath is lower-left origin in 0...1; boundingBoxOfPath gives a
            // normalized rect we convert to pixels (top-origin) and back to the app type.
            let normalized = contour.normalizedPath.boundingBoxOfPath
            guard normalized.width > 0, normalized.height > 0 else { continue }
            let pixel = CGRect(x: normalized.minX * size.width,
                               y: (1 - normalized.maxY) * size.height,
                               width: normalized.width * size.width,
                               height: normalized.height * size.height)
            let box = PageCrop.normalizedRect(fromPixelRect: pixel,
                                              imageWidth: pageImage.width, imageHeight: pageImage.height)
            result.append(DetectionCandidate(pageIndex: pageIndex, box: box, sources: [.contour]))
        }
        return result
    }
}
```

`SaliencyCandidateSource.swift`:

```swift
import Foundation
import CoreGraphics
import Vision

public struct SaliencyCandidateSource: CandidateSourcing {
    public var source: CandidateSource { .saliency }
    public init() {}

    public func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
        let request = GenerateObjectnessBasedSaliencyImageRequest()
        let observation = try await request.perform(on: pageImage)
        let size = CGSize(width: pageImage.width, height: pageImage.height)
        return observation.salientObjects.map { object in
            let pixel = object.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            let box = PageCrop.normalizedRect(fromPixelRect: pixel,
                                              imageWidth: pageImage.width, imageHeight: pageImage.height)
            return DetectionCandidate(pageIndex: pageIndex, box: box, sources: [.saliency])
        }
    }
}
```

If `CoordinateOrigin` has no `.upperLeft` case (check with `grep -n -A4 "public enum CoordinateOrigin" <Vision swiftinterface>`), use `.lowerLeft` and flip manually: `pixel.origin.y = size.height - pixel.maxY`.

- [ ] **Step 4: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter CandidateSourceTests`
Expected: 3 pass. If the contour test fails because the ring is not a top-level contour, lower `contrastAdjustment` to 1.5 and re-run; record the final value in the file's doc comment.

- [ ] **Step 5: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/Candidates Autogram/Tests/AutogramKitTests/CandidateSourceTests.swift
git commit -m "feat: add built-in, contour and saliency candidate sources

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Feature vectors, example bank, kNN classifier

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Classification/ElementJudgement.swift`
- Create: `Sources/AutogramKit/VisionAI/Classification/FeatureVector.swift`
- Create: `Sources/AutogramKit/VisionAI/Learning/ExampleBank.swift`
- Create: `Sources/AutogramKit/VisionAI/Classification/FeaturePrintClassifier.swift`
- Test: `Tests/AutogramKitTests/ExampleBankTests.swift`, `Tests/AutogramKitTests/FeaturePrintClassifierTests.swift`

**Interfaces:**
- Produces:
  - `enum ClassifierIdentity: String, Sendable { case featurePrintKNN, foundationModel, builtInHint }`
  - `struct ElementJudgement: Sendable, Equatable { kind: SecurityElement.Kind?; confidence: Double; margin: Double; descriptionSK: String; decidedBy: ClassifierIdentity; supportCount: Int }`
  - `protocol ElementClassifying: Sendable { func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement }`
  - `struct FeatureVector: Codable, Sendable, Equatable { values: [Float]; func distance(to:) -> Double }`
  - `protocol FeaturePrintProviding: Sendable { func featureVector(for image: CGImage) async throws -> FeatureVector }`
  - `struct VisionFeaturePrintProvider: FeaturePrintProviding`
  - `enum BankLabel: Codable, Hashable, Sendable { case kind(SecurityElement.Kind), negative }` with `exportLabel: String`
  - `struct BankEntry: Codable, Sendable, Identifiable`
  - `actor ExampleBank { init(directory: URL); func load() async throws; func entries() -> [BankEntry]; func add(_ entry: BankEntry) async throws; func remove(id: UUID) async throws; func removeAll() async throws; func count(for label: BankLabel) -> Int; var pagesDirectory: URL; var cropsDirectory: URL }`
  - `struct FeaturePrintClassifier: ElementClassifying { init(bank: ExampleBank, featurePrints: FeaturePrintProviding, k: Int = 5) }` plus `static func vote(query: FeatureVector, examples: [(FeatureVector, BankLabel)], k: Int) -> ElementJudgement`

- [ ] **Step 1: Write failing tests**

`ExampleBankTests.swift`:

```swift
import XCTest
@testable import AutogramKit

final class ExampleBankTests: XCTestCase {
    private func temporaryBank() throws -> ExampleBank {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bank-\(UUID().uuidString)", isDirectory: true)
        return ExampleBank(directory: dir)
    }

    private func entry(label: BankLabel, id: UUID = UUID()) -> BankEntry {
        BankEntry(id: id, label: label, documentSHA256: "abc", pageIndex: 0,
                  box: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                  featureVector: FeatureVector(values: [0, 1, 0]),
                  createdAt: Date(timeIntervalSince1970: 1_000), detectorVersion: "test")
    }

    func testAddPersistsAndReloads() throws {
        let bank = try temporaryBank()
        let id = UUID()
        try awaitAsyncThrowing { try await bank.add(self.entry(label: .kind(.officialStamp), id: id)) }
        let reloaded = ExampleBank(directory: awaitAsync { await bank.directory })
        try awaitAsyncThrowing { try await reloaded.load() }
        let entries = awaitAsync { await reloaded.entries() }
        XCTAssertEqual(entries.map(\.id), [id])
        XCTAssertEqual(entries.first?.label, .kind(.officialStamp))
        XCTAssertEqual(awaitAsync { await reloaded.count(for: .kind(.officialStamp)) }, 1)
    }

    func testRemoveAndRemoveAll() throws {
        let bank = try temporaryBank()
        let a = UUID(), b = UUID()
        try awaitAsyncThrowing {
            try await bank.add(self.entry(label: .negative, id: a))
            try await bank.add(self.entry(label: .negative, id: b))
            try await bank.remove(id: a)
        }
        XCTAssertEqual(awaitAsync { await bank.entries().map(\.id) }, [b])
        try awaitAsyncThrowing { try await bank.removeAll() }
        XCTAssertTrue(awaitAsync { await bank.entries() }.isEmpty)
    }

    func testBankLabelExportLabelsAreEnglishIdentifiers() {
        XCTAssertEqual(BankLabel.kind(.officialStamp).exportLabel, "officialStamp")
        XCTAssertEqual(BankLabel.kind(.handwrittenSignature).exportLabel, "handwrittenSignature")
        XCTAssertEqual(BankLabel.negative.exportLabel, "negative")
    }
}
```

`FeaturePrintClassifierTests.swift`:

```swift
import XCTest
@testable import AutogramKit

final class FeaturePrintClassifierTests: XCTestCase {
    private func v(_ a: Float, _ b: Float) -> FeatureVector { FeatureVector(values: [a, b]) }

    func testDistanceIsEuclidean() {
        XCTAssertEqual(v(0, 0).distance(to: v(3, 4)), 5, accuracy: 1e-9)
    }

    func testVoteReturnsNearestLabelWithMargin() {
        let examples: [(FeatureVector, BankLabel)] = [
            (v(1, 0), .kind(.officialStamp)), (v(1.1, 0), .kind(.officialStamp)), (v(0.9, 0), .kind(.officialStamp)),
            (v(0, 1), .kind(.handwrittenSignature)), (v(0, 1.1), .negative)
        ]
        let judgement = FeaturePrintClassifier.vote(query: v(1, 0.05), examples: examples, k: 5)
        XCTAssertEqual(judgement.kind, .officialStamp)
        XCTAssertEqual(judgement.decidedBy, .featurePrintKNN)
        XCTAssertGreaterThan(judgement.margin, 0.25)
        XCTAssertEqual(judgement.supportCount, 3)
    }

    func testNegativeWinnerYieldsNilKind() {
        let examples: [(FeatureVector, BankLabel)] = [(v(0, 0), .negative), (v(0.1, 0), .negative), (v(5, 5), .kind(.initial))]
        let judgement = FeaturePrintClassifier.vote(query: v(0, 0), examples: examples, k: 3)
        XCTAssertNil(judgement.kind)
        XCTAssertEqual(judgement.supportCount, 2)
    }

    func testEmptyBankYieldsZeroConfidence() {
        let judgement = FeaturePrintClassifier.vote(query: v(0, 0), examples: [], k: 5)
        XCTAssertNil(judgement.kind)
        XCTAssertEqual(judgement.confidence, 0)
        XCTAssertEqual(judgement.margin, 0)
        XCTAssertEqual(judgement.supportCount, 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "ExampleBankTests|FeaturePrintClassifierTests"`
Expected: compile errors.

- [ ] **Step 3: Implement**

`ElementJudgement.swift`:

```swift
import Foundation
import CoreGraphics

public enum ClassifierIdentity: String, Sendable, Codable {
    case featurePrintKNN, foundationModel, builtInHint
}

public struct ElementJudgement: Sendable, Equatable {
    /// Nil means "not a security element".
    public var kind: SecurityElement.Kind?
    public var confidence: Double
    /// Winner share minus runner-up share (kNN) or 0 for other classifiers.
    public var margin: Double
    public var descriptionSK: String
    public var decidedBy: ClassifierIdentity
    /// Number of bank examples backing the winning label (kNN only).
    public var supportCount: Int

    public init(kind: SecurityElement.Kind?, confidence: Double, margin: Double = 0,
                descriptionSK: String = "", decidedBy: ClassifierIdentity, supportCount: Int = 0) {
        self.kind = kind
        self.confidence = confidence
        self.margin = margin
        self.descriptionSK = descriptionSK
        self.decidedBy = decidedBy
        self.supportCount = supportCount
    }

    public static let unsure = ElementJudgement(kind: nil, confidence: 0, decidedBy: .featurePrintKNN)
}

public protocol ElementClassifying: Sendable {
    func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement
}
```

`FeatureVector.swift`:

```swift
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
        observation.data.withUnsafeBytes { raw in
            // Vision feature prints are Float32 arrays.
            let floats = raw.bindMemory(to: Float.self)
            for i in 0..<min(count, floats.count) { values[i] = floats[i] }
        }
        return FeatureVector(values: values)
    }
}
```

If `observation.elementType` is not `.float`, throw an error instead of reading Float32; check the `ElementType` cases in the Vision swiftinterface (`grep -n -A4 "public enum ElementType"`) and add `guard observation.elementType == .float else { throw FeatureVectorError.unsupportedElementType }` with a small `enum FeatureVectorError: Error { case unsupportedElementType }`.

`ExampleBank.swift`:

```swift
import Foundation

public enum BankLabel: Codable, Hashable, Sendable {
    case kind(SecurityElement.Kind)
    case negative

    public var exportLabel: String {
        switch self {
        case .negative: return "negative"
        case .kind(let kind):
            switch kind {
            case .handwrittenSignature: return "handwrittenSignature"
            case .officialStamp: return "officialStamp"
            case .embossedSeal: return "embossedSeal"
            case .initial: return "initial"
            case .other: return "other"
            }
        }
    }
}

public struct BankEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var label: BankLabel
    public var documentSHA256: String
    public var pageIndex: Int
    public var box: NormalizedRect
    public var featureVector: FeatureVector
    public var createdAt: Date
    public var detectorVersion: String

    public init(id: UUID = UUID(), label: BankLabel, documentSHA256: String, pageIndex: Int,
                box: NormalizedRect, featureVector: FeatureVector, createdAt: Date = Date(),
                detectorVersion: String) {
        self.id = id
        self.label = label
        self.documentSHA256 = documentSHA256
        self.pageIndex = pageIndex
        self.box = box
        self.featureVector = featureVector
        self.createdAt = createdAt
        self.detectorVersion = detectorVersion
    }

    public var pageImageFileName: String { "\(documentSHA256)-p\(pageIndex).png" }
    public var cropImageFileName: String { "\(id.uuidString).png" }
}

/// Local, on-device store of reviewed crops. JSON index plus PNG files.
public actor ExampleBank {
    public let directory: URL
    private var cache: [BankEntry] = []
    private var loaded = false

    public init(directory: URL) { self.directory = directory }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Autogram/VisionBank", isDirectory: true)
    }

    public var indexURL: URL { directory.appendingPathComponent("bank.json") }
    public var pagesDirectory: URL { directory.appendingPathComponent("pages", isDirectory: true) }
    public var cropsDirectory: URL { directory.appendingPathComponent("crops", isDirectory: true) }

    public func load() throws {
        try FileManager.default.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cropsDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode([BankEntry].self, from: data)
        } else {
            cache = []
        }
        loaded = true
    }

    private func ensureLoaded() throws {
        if !loaded { try load() }
    }

    public func entries() -> [BankEntry] {
        try? ensureLoaded()
        return cache
    }

    public func count(for label: BankLabel) -> Int {
        entries().filter { $0.label == label }.count
    }

    public func add(_ entry: BankEntry) throws {
        try ensureLoaded()
        cache.removeAll { $0.id == entry.id }
        cache.append(entry)
        try persist()
    }

    public func remove(id: UUID) throws {
        try ensureLoaded()
        cache.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: cropsDirectory.appendingPathComponent("\(id.uuidString).png"))
        try persist()
    }

    public func removeAll() throws {
        cache = []
        try? FileManager.default.removeItem(at: directory)
        loaded = false
        try load()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cache).write(to: indexURL, options: .atomic)
    }
}
```

`FeaturePrintClassifier.swift`:

```swift
import Foundation
import CoreGraphics

public struct FeaturePrintClassifier: ElementClassifying {
    public let bank: ExampleBank
    public let featurePrints: any FeaturePrintProviding
    public let k: Int

    public init(bank: ExampleBank, featurePrints: any FeaturePrintProviding = VisionFeaturePrintProvider(), k: Int = 5) {
        self.bank = bank
        self.featurePrints = featurePrints
        self.k = k
    }

    public func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
        let query = try await featurePrints.featureVector(for: crop)
        let examples = await bank.entries()
            .filter { $0.featureVector.values.count == query.values.count }
            .map { ($0.featureVector, $0.label) }
        return Self.vote(query: query, examples: examples, k: k)
    }

    /// Distance-weighted vote over the k nearest examples.
    public static func vote(query: FeatureVector, examples: [(FeatureVector, BankLabel)], k: Int) -> ElementJudgement {
        guard !examples.isEmpty else { return .unsure }
        let nearest = examples
            .map { (label: $0.1, distance: query.distance(to: $0.0)) }
            .sorted { $0.distance < $1.distance }
            .prefix(k)
        var weights: [BankLabel: Double] = [:]
        var counts: [BankLabel: Int] = [:]
        for item in nearest {
            let w = 1.0 / (item.distance + 0.05)
            weights[item.label, default: 0] += w
            counts[item.label, default: 0] += 1
        }
        let total = weights.values.reduce(0, +)
        let ranked = weights.sorted { $0.value > $1.value }
        let winner = ranked[0]
        let runnerUp = ranked.count > 1 ? ranked[1].value : 0
        let confidence = winner.value / total
        let margin = (winner.value - runnerUp) / total
        let kind: SecurityElement.Kind? = { if case .kind(let k) = winner.key { return k } else { return nil } }()
        return ElementJudgement(kind: kind, confidence: confidence, margin: margin,
                                descriptionSK: "", decidedBy: .featurePrintKNN,
                                supportCount: counts[winner.key] ?? 0)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "ExampleBankTests|FeaturePrintClassifierTests"`
Expected: 7 pass.

- [ ] **Step 5: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/Classification Autogram/Sources/AutogramKit/VisionAI/Learning Autogram/Tests/AutogramKitTests/ExampleBankTests.swift Autogram/Tests/AutogramKitTests/FeaturePrintClassifierTests.swift
git commit -m "feat: add feature vectors, example bank and kNN classifier

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Foundation Model classifier

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Classification/FoundationModelClassifier.swift`
- Test: `Tests/AutogramKitTests/FoundationModelClassifierTests.swift`

**Interfaces:**
- Consumes: `ElementJudgement`, `ElementClassifying`, `ClassifierIdentity.foundationModel`.
- Produces:
  - `struct FoundationJudgement: Sendable, Equatable { isSecurityElement: Bool; kind: FoundationJudgementKind; descriptionSK: String; confidence: Double }`
  - `enum FoundationJudgementKind: String, Sendable, CaseIterable { case stamp, signature, embossedSeal, initial, other, none }` with `var securityKind: SecurityElement.Kind?`
  - `protocol FoundationJudging: Sendable { func judge(crop: CGImage, hint: SecurityElement.Kind?) async throws -> FoundationJudgement }`
  - `struct FoundationModelClassifier: ElementClassifying { init(judge: FoundationJudging, timeoutSeconds: Double = 8); static func makeIfAvailable(timeoutSeconds: Double = 8) -> FoundationModelClassifier?; static func map(_ judgement: FoundationJudgement) -> ElementJudgement }`
  - `actor SystemFoundationJudge: FoundationJudging` (live implementation, one `LanguageModelSession`)

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import CoreGraphics
@testable import AutogramKit

final class FoundationModelClassifierTests: XCTestCase {
    private struct FakeJudge: FoundationJudging {
        let result: FoundationJudgement
        let delay: Double
        func judge(crop: CGImage, hint: SecurityElement.Kind?) async throws -> FoundationJudgement {
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            return result
        }
    }

    private func blankImage() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(ctx.makeImage())
    }

    func testMapsStampJudgementToOfficialStamp() {
        let judgement = FoundationModelClassifier.map(
            FoundationJudgement(isSecurityElement: true, kind: .stamp, descriptionSK: "Okrúhla modrá pečiatka.", confidence: 0.8))
        XCTAssertEqual(judgement.kind, .officialStamp)
        XCTAssertEqual(judgement.confidence, 0.8, accuracy: 1e-9)
        XCTAssertEqual(judgement.descriptionSK, "Okrúhla modrá pečiatka.")
        XCTAssertEqual(judgement.decidedBy, .foundationModel)
    }

    func testNotASecurityElementYieldsNilKindRegardlessOfKindField() {
        let judgement = FoundationModelClassifier.map(
            FoundationJudgement(isSecurityElement: false, kind: .stamp, descriptionSK: "", confidence: 0.9))
        XCTAssertNil(judgement.kind)
    }

    func testTimeoutYieldsUnsureJudgement() throws {
        let classifier = FoundationModelClassifier(
            judge: FakeJudge(result: .init(isSecurityElement: true, kind: .signature, descriptionSK: "", confidence: 1), delay: 2),
            timeoutSeconds: 0.1)
        let image = try blankImage()
        let judgement = try awaitAsyncThrowing { try await classifier.classify(crop: image, hint: nil) }
        XCTAssertNil(judgement.kind)
        XCTAssertEqual(judgement.confidence, 0)
        XCTAssertEqual(judgement.decidedBy, .foundationModel)
    }

    func testLiveModelSeparatesRingFromPlainTextIfAvailable() throws {
        guard let classifier = FoundationModelClassifier.makeIfAvailable() else {
            throw XCTSkip("On-device Foundation Model nie je dostupný")
        }
        let document = try XCTUnwrap(PDFKit.PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let page = try XCTUnwrap(document.page(at: 0))
        let rendered = try XCTUnwrap(BuiltInVisionProvider.render(page: page, targetWidth: 760))
        // The ring in typicalContractPDF sits in the lower-right quadrant; text is upper-left.
        let ring = try XCTUnwrap(PageCrop.crop(rendered.cgImage, to: .init(x: 0.55, y: 0.05, width: 0.4, height: 0.35)))
        let text = try XCTUnwrap(PageCrop.crop(rendered.cgImage, to: .init(x: 0.05, y: 0.70, width: 0.5, height: 0.2)))
        let ringJudgement = try awaitAsyncThrowing { try await classifier.classify(crop: ring, hint: nil) }
        let textJudgement = try awaitAsyncThrowing { try await classifier.classify(crop: text, hint: nil) }
        XCTAssertNotNil(ringJudgement.kind, "Kruh má byť rozpoznaný ako prvok")
        XCTAssertNil(textJudgement.kind, "Bežný text nesmie byť prvok")
    }
}
```

Add `import PDFKit` at the top of the test file.

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter FoundationModelClassifierTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

```swift
import Foundation
import CoreGraphics
import FoundationModels

public enum FoundationJudgementKind: String, Sendable, CaseIterable, Codable {
    case stamp, signature, embossedSeal, initial, other, none

    public var securityKind: SecurityElement.Kind? {
        switch self {
        case .stamp: return .officialStamp
        case .signature: return .handwrittenSignature
        case .embossedSeal: return .embossedSeal
        case .initial: return .initial
        case .other: return .other
        case .none: return nil
        }
    }
}

public struct FoundationJudgement: Sendable, Equatable {
    public var isSecurityElement: Bool
    public var kind: FoundationJudgementKind
    public var descriptionSK: String
    public var confidence: Double

    public init(isSecurityElement: Bool, kind: FoundationJudgementKind, descriptionSK: String, confidence: Double) {
        self.isSecurityElement = isSecurityElement
        self.kind = kind
        self.descriptionSK = descriptionSK
        self.confidence = confidence
    }
}

public protocol FoundationJudging: Sendable {
    func judge(crop: CGImage, hint: SecurityElement.Kind?) async throws -> FoundationJudgement
}

/// Structured output type for the on-device model.
@Generable(description: "Judgement whether a crop of a scanned legal document shows a physical security element")
struct GeneratedJudgement {
    @Guide(description: "true only if a stamp, handwritten signature, embossed seal or handwritten initial is physically visible in the image")
    var isSecurityElement: Bool
    @Guide(description: "one of: stamp, signature, embossedSeal, initial, other, none", .anyOf(FoundationJudgementKind.allCases.map(\.rawValue)))
    var kind: String
    @Guide(description: "one short Slovak sentence describing the visible element, empty if none")
    var descriptionSK: String
    @Guide(description: "confidence between 0 and 1", .range(0.0...1.0))
    var confidence: Double
}

/// Live judge. One session per instance; calls are serialised by the actor.
public actor SystemFoundationJudge: FoundationJudging {
    private let session: LanguageModelSession

    public init() {
        session = LanguageModelSession(instructions: """
        You inspect small crops of scanned Slovak legal documents. Decide only from what is \
        physically visible in the image. Never infer an element from context, expected placement, \
        or surrounding text. A stamp is an inked impression (often round, blue or red, with text or \
        a coat of arms). A signature is handwritten cursive ink. An embossed seal is a colourless \
        relief impression. An initial is a short handwritten mark. Printed text, logos, lines, tables \
        and photographs are not security elements. Answer in the requested structure. \
        descriptionSK must be Slovak.
        """)
    }

    public func judge(crop: CGImage, hint: SecurityElement.Kind?) async throws -> FoundationJudgement {
        let hintText = hint.map { "A heuristic detector suggested this may be: \($0.rawValue). Verify visually." } ?? ""
        let response = try await session.respond(generating: GeneratedJudgement.self,
                                                 options: GenerationOptions(temperature: 0)) {
            "Is a physical security element visible in this crop? \(hintText)"
            Attachment(crop)
        }
        let content = response.content
        return FoundationJudgement(isSecurityElement: content.isSecurityElement,
                                   kind: FoundationJudgementKind(rawValue: content.kind) ?? .none,
                                   descriptionSK: content.descriptionSK,
                                   confidence: min(max(content.confidence, 0), 1))
    }
}

public struct FoundationModelClassifier: ElementClassifying {
    public let judge: any FoundationJudging
    public let timeoutSeconds: Double

    public init(judge: any FoundationJudging, timeoutSeconds: Double = 8) {
        self.judge = judge
        self.timeoutSeconds = timeoutSeconds
    }

    public static func makeIfAvailable(timeoutSeconds: Double = 8) -> FoundationModelClassifier? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        return FoundationModelClassifier(judge: SystemFoundationJudge(), timeoutSeconds: timeoutSeconds)
    }

    public func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
        let judge = self.judge
        let timeout = timeoutSeconds
        let crop = crop
        return try await withThrowingTaskGroup(of: ElementJudgement?.self) { group in
            group.addTask { Self.map(try await judge.judge(crop: crop, hint: hint)) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first ?? ElementJudgement(kind: nil, confidence: 0, decidedBy: .foundationModel)
        }
    }

    public static func map(_ judgement: FoundationJudgement) -> ElementJudgement {
        let kind = judgement.isSecurityElement ? judgement.kind.securityKind : nil
        return ElementJudgement(kind: kind, confidence: judgement.confidence, margin: 0,
                                descriptionSK: judgement.descriptionSK, decidedBy: .foundationModel)
    }
}
```

`CGImage` is not `Sendable`; the task group closure captures it. If the compiler rejects the capture, wrap it: `let box = UncheckedSendableImage(crop)` where `struct UncheckedSendableImage: @unchecked Sendable { let image: CGImage }` is declared privately in this file, and pass `box.image` inside the tasks.

If `@Generable` refuses `.anyOf` on a `String` property alongside a `description` label, drop the `.anyOf` guide and keep the description; the `FoundationJudgementKind(rawValue:) ?? .none` fallback already tolerates free text.

- [ ] **Step 4: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter FoundationModelClassifierTests`
Expected: 3 pass, the live test passes or is skipped. If the live test fails on the text crop being judged as an element, tighten the instructions sentence about printed text and re-run once; if it still fails, mark the live test `XCTExpectFailure("model calibration")` and note it in the commit body.

- [ ] **Step 5: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/Classification/FoundationModelClassifier.swift Autogram/Tests/AutogramKitTests/FoundationModelClassifierTests.swift
git commit -m "feat: add on-device Foundation Model crop classifier

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Two-stage classifier

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Classification/TwoStageClassifier.swift`
- Test: `Tests/AutogramKitTests/TwoStageClassifierTests.swift`

**Interfaces:**
- Consumes: `ElementClassifying`, `ElementJudgement`.
- Produces: `struct TwoStageClassifier: ElementClassifying { init(primary: ElementClassifying, secondary: ElementClassifying?, minimumSupport: Int = 3, minimumMargin: Double = 0.25); func classify(crop:hint:) }` and `static func decide(primary: ElementJudgement, secondary: ElementJudgement?, hint: SecurityElement.Kind?, hintConfidence: Double?, minimumSupport: Int, minimumMargin: Double) -> ElementJudgement?` (nil = discard candidate). Also `func classify(crop: CGImage, hint: SecurityElement.Kind?, hintConfidence: Double?) async -> ElementJudgement?` used by the provider.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import AutogramKit

final class TwoStageClassifierTests: XCTestCase {
    private func knn(_ kind: SecurityElement.Kind?, conf: Double, margin: Double, support: Int) -> ElementJudgement {
        ElementJudgement(kind: kind, confidence: conf, margin: margin, decidedBy: .featurePrintKNN, supportCount: support)
    }
    private func fm(_ kind: SecurityElement.Kind?, conf: Double, desc: String = "") -> ElementJudgement {
        ElementJudgement(kind: kind, confidence: conf, descriptionSK: desc, decidedBy: .foundationModel)
    }

    func testConfidentKNNWins() {
        let result = TwoStageClassifier.decide(primary: knn(.officialStamp, conf: 0.8, margin: 0.6, support: 5),
                                               secondary: fm(.handwrittenSignature, conf: 0.9),
                                               hint: nil, hintConfidence: nil, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .officialStamp)
        XCTAssertEqual(result?.decidedBy, .featurePrintKNN)
    }

    func testWeakKNNDefersToFoundationModelAndBlendsWhenAgreeing() {
        let result = TwoStageClassifier.decide(primary: knn(.officialStamp, conf: 0.5, margin: 0.1, support: 4),
                                               secondary: fm(.officialStamp, conf: 0.9, desc: "Pečiatka."),
                                               hint: nil, hintConfidence: nil, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .officialStamp)
        XCTAssertEqual(result?.decidedBy, .foundationModel)
        XCTAssertEqual(result!.confidence, 0.6 * 0.9 + 0.4 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(result?.descriptionSK, "Pečiatka.")
    }

    func testLowSupportDefersEvenWithHighMargin() {
        let result = TwoStageClassifier.decide(primary: knn(.initial, conf: 1, margin: 1, support: 1),
                                               secondary: fm(.handwrittenSignature, conf: 0.7),
                                               hint: nil, hintConfidence: nil, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .handwrittenSignature)
        XCTAssertEqual(result!.confidence, 0.7, accuracy: 1e-9)
    }

    func testFoundationModelNegativeDiscardsCandidate() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: fm(nil, conf: 0.9),
                                               hint: .officialStamp, hintConfidence: 0.7, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }

    func testNoSecondaryFallsBackToHint() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: nil,
                                               hint: .handwrittenSignature, hintConfidence: 0.66, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .handwrittenSignature)
        XCTAssertEqual(result!.confidence, 0.66, accuracy: 1e-9)
        XCTAssertEqual(result?.decidedBy, .builtInHint)
    }

    func testNoSecondaryAndNoHintDiscards() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: nil, hint: nil, hintConfidence: nil,
                                               minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }

    func testConfidentKNNNegativeDiscardsEvenWithHint() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0.9, margin: 0.8, support: 6),
                                               secondary: nil, hint: .officialStamp, hintConfidence: 0.9,
                                               minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter TwoStageClassifierTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

```swift
import Foundation
import CoreGraphics

/// kNN first; Foundation Model when kNN is unsure; built-in hint as last resort.
public struct TwoStageClassifier: Sendable {
    public let primary: any ElementClassifying
    public let secondary: (any ElementClassifying)?
    public let minimumSupport: Int
    public let minimumMargin: Double

    public init(primary: any ElementClassifying, secondary: (any ElementClassifying)?,
                minimumSupport: Int = 3, minimumMargin: Double = 0.25) {
        self.primary = primary
        self.secondary = secondary
        self.minimumSupport = minimumSupport
        self.minimumMargin = minimumMargin
    }

    /// Returns nil when the candidate should be discarded.
    public func classify(crop: CGImage, hint: SecurityElement.Kind?, hintConfidence: Double?) async -> ElementJudgement? {
        let primaryJudgement = (try? await primary.classify(crop: crop, hint: hint)) ?? .unsure
        var secondaryJudgement: ElementJudgement? = nil
        if !Self.isConfident(primaryJudgement, minimumSupport: minimumSupport, minimumMargin: minimumMargin),
           let secondary {
            secondaryJudgement = try? await secondary.classify(crop: crop, hint: hint)
        }
        return Self.decide(primary: primaryJudgement, secondary: secondaryJudgement, hint: hint,
                           hintConfidence: hintConfidence, minimumSupport: minimumSupport, minimumMargin: minimumMargin)
    }

    static func isConfident(_ j: ElementJudgement, minimumSupport: Int, minimumMargin: Double) -> Bool {
        j.supportCount >= minimumSupport && j.margin >= minimumMargin
    }

    public static func decide(primary: ElementJudgement, secondary: ElementJudgement?,
                              hint: SecurityElement.Kind?, hintConfidence: Double?,
                              minimumSupport: Int, minimumMargin: Double) -> ElementJudgement? {
        if isConfident(primary, minimumSupport: minimumSupport, minimumMargin: minimumMargin) {
            return primary.kind == nil ? nil : primary
        }
        if let secondary {
            guard let kind = secondary.kind else { return nil }
            var result = secondary
            if primary.kind == kind {
                result.confidence = 0.6 * secondary.confidence + 0.4 * primary.confidence
            }
            result.kind = kind
            return result
        }
        if let hint {
            return ElementJudgement(kind: hint, confidence: hintConfidence ?? 0.5, decidedBy: .builtInHint)
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter TwoStageClassifierTests`
Expected: 7 pass.

- [ ] **Step 5: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/Classification/TwoStageClassifier.swift Autogram/Tests/AutogramKitTests/TwoStageClassifierTests.swift
git commit -m "feat: add two-stage classifier decision rule

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: LayeredDetectionProvider and pipeline integration

**Files:**
- Create: `Sources/AutogramKit/VisionAI/LayeredDetectionProvider.swift`
- Modify: `Sources/AutogramKit/VisionAI/SecurityElementsProviding.swift:9-31`
- Test: `Tests/AutogramKitTests/LayeredDetectionProviderTests.swift`

**Interfaces:**
- Consumes: `BuiltInCandidateSource`, `CandidateSourcing`, `CandidateMerger`, `PageCrop`, `TwoStageClassifier`, `BuiltInVisionProvider.render(page:targetWidth:)`, `BuiltInVisionProvider.visionExclusionBoxes(cgImage:)`.
- Produces:
  - `struct LayeredDetectionProvider: SecurityElementsProviding { init(builtIn: BuiltInCandidateSource = .init(), extraSources: [any CandidateSourcing] = [ContourCandidateSource(), SaliencyCandidateSource()], classifier: TwoStageClassifier, renderTargetWidth: Int = 760, maxConcurrentPages: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)); var identifier: String }`
  - `DetectionPipeline.init(builtin: any SecurityElementsProviding, llmProvider: (any SecurityElementsProviding)? = nil)`; `DetectionPipeline.builtin` type becomes `any SecurityElementsProviding`.
  - `static func makeDefault(bank: ExampleBank, useFoundationModel: Bool) -> LayeredDetectionProvider`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import PDFKit
import CoreGraphics
@testable import AutogramKit

final class LayeredDetectionProviderTests: XCTestCase {
    private struct FixedSource: CandidateSourcing {
        let source: CandidateSource
        let boxes: [NormalizedRect]
        let fails: Bool
        func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
            if fails { throw NSError(domain: "test", code: 1) }
            return boxes.map { DetectionCandidate(pageIndex: pageIndex, box: $0, sources: [source]) }
        }
    }
    private struct FixedClassifier: ElementClassifying {
        let judgement: ElementJudgement
        func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement { judgement }
    }

    private func contract() throws -> (PDFDocument, [PageAnalysis]) {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        return (document, PDFAnalysisEngine().analyze(document: document).pageAnalyses)
    }

    func testEmitsPendingAIElementsWithDetectionSource() throws {
        let (document, analyses) = try contract()
        let classifier = TwoStageClassifier(
            primary: FixedClassifier(judgement: .init(kind: .officialStamp, confidence: 0.9, margin: 0.9,
                                                      descriptionSK: "Pečiatka.", decidedBy: .featurePrintKNN, supportCount: 10)),
            secondary: nil)
        let provider = LayeredDetectionProvider(
            extraSources: [FixedSource(source: .contour, boxes: [.init(x: 0.6, y: 0.1, width: 0.2, height: 0.2)], fails: false)],
            classifier: classifier)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analyses) }
        let stamps = elements.filter { $0.kind == .officialStamp }
        XCTAssertFalse(stamps.isEmpty)
        for stamp in stamps {
            XCTAssertTrue(stamp.detectedByAI)
            XCTAssertEqual(stamp.reviewState, .pending)
            XCTAssertEqual(stamp.verbalDescription, "Pečiatka.")
            let source = try XCTUnwrap(stamp.detectionSource)
            XCTAssertTrue(source.contains("kNN"), source)
        }
    }

    func testFailingSourceDoesNotLoseBuiltInCandidates() throws {
        let (document, analyses) = try contract()
        let classifier = TwoStageClassifier(primary: FixedClassifier(judgement: .unsure), secondary: nil)
        let provider = LayeredDetectionProvider(
            extraSources: [FixedSource(source: .saliency, boxes: [], fails: true)],
            classifier: classifier)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analyses) }
        // With an unsure kNN and no FM, hints from the built-in provider survive.
        XCTAssertTrue(elements.contains { $0.kind == .officialStamp || $0.kind == .handwrittenSignature },
                      "Vstavané nálezy musia prežiť zlyhanie zdroja: \(elements.map(\.kind))")
        XCTAssertTrue(elements.filter { $0.kind != .other }.allSatisfy { $0.detectionSource?.contains("builtInHint") == true })
    }

    func testNegativeClassificationDropsCandidates() throws {
        let (document, analyses) = try contract()
        let classifier = TwoStageClassifier(
            primary: FixedClassifier(judgement: .init(kind: nil, confidence: 0.95, margin: 0.9, decidedBy: .featurePrintKNN, supportCount: 9)),
            secondary: nil)
        let provider = LayeredDetectionProvider(extraSources: [], classifier: classifier)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analyses) }
        XCTAssertTrue(elements.allSatisfy { $0.kind == .other }, "Len barcode passthrough smie zostať")
    }

    func testIdentifierListsActiveStages() {
        let classifier = TwoStageClassifier(primary: FixedClassifier(judgement: .unsure),
                                            secondary: FixedClassifier(judgement: .unsure))
        let provider = LayeredDetectionProvider(classifier: classifier)
        XCTAssertEqual(provider.identifier, "LayeredDetectionProvider/1 builtIn+contour+saliency kNN fm")
        let noFM = LayeredDetectionProvider(extraSources: [], classifier: TwoStageClassifier(primary: FixedClassifier(judgement: .unsure), secondary: nil))
        XCTAssertEqual(noFM.identifier, "LayeredDetectionProvider/1 builtIn kNN")
    }

    func testDetectionPipelineAcceptsLayeredProvider() throws {
        let (document, analyses) = try contract()
        let provider = LayeredDetectionProvider(extraSources: [], classifier: TwoStageClassifier(primary: FixedClassifier(judgement: .unsure), secondary: nil))
        let pipeline = DetectionPipeline(builtin: provider)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await pipeline.detect(in: doc.value, pageAnalyses: analyses) }
        XCTAssertFalse(elements.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter LayeredDetectionProviderTests`
Expected: compile errors.

- [ ] **Step 3: Implement the provider**

```swift
import Foundation
import CoreGraphics
import PDFKit

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
                group.addTask { await self.detectOnPage(page: page, pageIndex: pageIndex, seeded: seeded) }
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
```

`PDFPage` and `PDFDocument` are not `Sendable`; the existing code base passes them through `UncheckedSendable` wrappers (`Sources/AutogramApp/ConcurrencySupport.swift` and the test `TestUncheckedSendable`). Inside `AutogramKit` add, at the bottom of this file, `private struct PageBox: @unchecked Sendable { let page: PDFPage }` and capture `PageBox(page: page)` in the task group closure if the compiler complains.

- [ ] **Step 4: Generalise `DetectionPipeline`**

In `SecurityElementsProviding.swift` replace lines 9-17:

```swift
public struct DetectionPipeline: SecurityElementsProviding {
    public let builtin: any SecurityElementsProviding
    public let llmProvider: (any SecurityElementsProviding)?

    public init(builtin: any SecurityElementsProviding = BuiltInVisionProvider(),
                llmProvider: (any SecurityElementsProviding)? = nil) {
        self.builtin = builtin
        self.llmProvider = llmProvider
    }
```

Then run `grep -rn "pipeline.builtin\|\.builtin\b" Sources Tests` and fix any call site that relied on the concrete `BuiltInVisionProvider` type (expected: none besides `detectWithStatus` in `LLMVisionProviders.swift`, which only calls `detect`).

- [ ] **Step 5: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "LayeredDetectionProviderTests|SecurityElementsDetectorTests|LLMVisionParserTests"`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/LayeredDetectionProvider.swift Autogram/Sources/AutogramKit/VisionAI/SecurityElementsProviding.swift Autogram/Tests/AutogramKitTests/LayeredDetectionProviderTests.swift
git commit -m "feat: add layered detection provider and generalise pipeline

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Bank recorder and Create ML exporter

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Learning/ExampleBankRecorder.swift`
- Create: `Sources/AutogramKit/VisionAI/Learning/CreateMLExporter.swift`
- Test: `Tests/AutogramKitTests/ExampleBankRecorderTests.swift`, `Tests/AutogramKitTests/CreateMLExporterTests.swift`

**Interfaces:**
- Consumes: `ExampleBank`, `BankEntry`, `BankLabel`, `FeaturePrintProviding`, `PageCrop`, `BuiltInVisionProvider.render(page:targetWidth:)`, `AttestationClauseGenerator.sha256Hex(of:)`.
- Produces:
  - `struct ExampleBankRecorder: Sendable { init(bank: ExampleBank, featurePrints: FeaturePrintProviding = VisionFeaturePrintProvider(), pageRenderWidth: Int = 1200, detectorVersion: String); func record(document: PDFDocument, documentData: Data, element: SecurityElement, label: BankLabel) async throws; func forget(elementID: UUID) async throws }` - entry id equals the element id so decisions can be reverted.
  - `enum CreateMLExporter { static func export(bank: ExampleBank, to folder: URL) async throws -> URL; static func annotations(for entries: [BankEntry], imageSizes: [String: CGSize]) -> [CreateMLImageAnnotation] }`
  - `struct CreateMLImageAnnotation: Codable, Equatable { image: String; annotations: [CreateMLBox] }`, `struct CreateMLBox: Codable, Equatable { label: String; coordinates: CreateMLCoordinates }`, `struct CreateMLCoordinates: Codable, Equatable { x: Double; y: Double; width: Double; height: Double }` (pixel units, centre point, top-left image origin).

- [ ] **Step 1: Write failing tests**

`ExampleBankRecorderTests.swift`:

```swift
import XCTest
import PDFKit
@testable import AutogramKit

final class ExampleBankRecorderTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { FeatureVector(values: [1, 2, 3]) }
    }

    func testRecordWritesEntryPageAndCrop() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let data = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let element = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.9)
        let recorder = ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: "test/1")
        let doc = TestUncheckedSendable(document)
        try awaitAsyncThrowing { try await recorder.record(document: doc.value, documentData: data, element: element, label: .kind(.officialStamp)) }

        let entries = awaitAsync { await bank.entries() }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, element.id)
        XCTAssertEqual(entries[0].label, .kind(.officialStamp))
        XCTAssertEqual(entries[0].documentSHA256, AttestationClauseGenerator.sha256Hex(of: data))
        XCTAssertEqual(entries[0].featureVector.values, [1, 2, 3])
        let pages = awaitAsync { await bank.pagesDirectory }
        let crops = awaitAsync { await bank.cropsDirectory }
        XCTAssertTrue(FileManager.default.fileExists(atPath: pages.appendingPathComponent(entries[0].pageImageFileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: crops.appendingPathComponent(entries[0].cropImageFileName).path))
    }

    func testForgetRemovesEntry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let data = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let element = SecurityElement(kind: .initial, pageIndex: 0,
                                      boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1), confidence: 1)
        let recorder = ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: "test/1")
        let doc = TestUncheckedSendable(document)
        try awaitAsyncThrowing {
            try await recorder.record(document: doc.value, documentData: data, element: element, label: .negative)
            try await recorder.forget(elementID: element.id)
        }
        XCTAssertTrue(awaitAsync { await bank.entries() }.isEmpty)
    }
}
```

`CreateMLExporterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "ExampleBankRecorderTests|CreateMLExporterTests"`
Expected: compile errors.

- [ ] **Step 3: Implement the recorder**

```swift
import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Turns a review decision into a bank entry: renders the page once,
/// crops the element, embeds it, and persists everything.
public struct ExampleBankRecorder: Sendable {
    public let bank: ExampleBank
    public let featurePrints: any FeaturePrintProviding
    public let pageRenderWidth: Int
    public let detectorVersion: String

    public init(bank: ExampleBank, featurePrints: any FeaturePrintProviding = VisionFeaturePrintProvider(),
                pageRenderWidth: Int = 1200, detectorVersion: String) {
        self.bank = bank
        self.featurePrints = featurePrints
        self.pageRenderWidth = pageRenderWidth
        self.detectorVersion = detectorVersion
    }

    public func record(document: PDFDocument, documentData: Data, element: SecurityElement, label: BankLabel) async throws {
        guard let page = document.page(at: element.pageIndex),
              let rendered = BuiltInVisionProvider.render(page: page, targetWidth: pageRenderWidth) else {
            throw RecorderError.renderFailed
        }
        let image = rendered.cgImage
        guard let crop = PageCrop.crop(image, to: element.boundingBox) else { throw RecorderError.cropFailed }
        let vector = try await featurePrints.featureVector(for: crop)
        let entry = BankEntry(id: element.id, label: label,
                              documentSHA256: AttestationClauseGenerator.sha256Hex(of: documentData),
                              pageIndex: element.pageIndex, box: element.boundingBox,
                              featureVector: vector, detectorVersion: detectorVersion)
        try await bank.load()
        let pageURL = await bank.pagesDirectory.appendingPathComponent(entry.pageImageFileName)
        if !FileManager.default.fileExists(atPath: pageURL.path) {
            try Self.writePNG(image, to: pageURL)
        }
        try Self.writePNG(crop, to: await bank.cropsDirectory.appendingPathComponent(entry.cropImageFileName))
        try await bank.add(entry)
    }

    public func forget(elementID: UUID) async throws {
        try await bank.remove(id: elementID)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RecorderError.writeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RecorderError.writeFailed }
    }

    public enum RecorderError: Error { case renderFailed, cropFailed, writeFailed }
}
```

- [ ] **Step 4: Implement the exporter**

```swift
import Foundation
import CoreGraphics
import ImageIO

public struct CreateMLCoordinates: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct CreateMLBox: Codable, Equatable, Sendable {
    public var label: String
    public var coordinates: CreateMLCoordinates
    public init(label: String, coordinates: CreateMLCoordinates) { self.label = label; self.coordinates = coordinates }
}

public struct CreateMLImageAnnotation: Codable, Equatable, Sendable {
    public var image: String
    public var annotations: [CreateMLBox]
    public init(image: String, annotations: [CreateMLBox]) { self.image = image; self.annotations = annotations }
}

/// Writes the bank in the Create ML object-detector folder format:
/// <folder>/annotations.json plus one PNG per page.
public enum CreateMLExporter {
    public static func export(bank: ExampleBank, to folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await bank.load()
        let entries = await bank.entries()
        let pagesDirectory = await bank.pagesDirectory
        var sizes: [String: CGSize] = [:]
        for name in Set(entries.map(\.pageImageFileName)) {
            let source = pagesDirectory.appendingPathComponent(name)
            guard let size = imageSize(at: source) else { continue }
            sizes[name] = size
            let destination = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
        let annotations = self.annotations(for: entries, imageSizes: sizes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = folder.appendingPathComponent("annotations.json")
        try encoder.encode(annotations).write(to: url, options: .atomic)
        return url
    }

    public static func annotations(for entries: [BankEntry], imageSizes: [String: CGSize]) -> [CreateMLImageAnnotation] {
        let grouped = Dictionary(grouping: entries, by: \.pageImageFileName)
        return grouped.keys.sorted().compactMap { image in
            guard let size = imageSizes[image], let group = grouped[image] else { return nil }
            let boxes: [CreateMLBox] = group.compactMap { entry in
                guard case .kind = entry.label else { return nil }
                let rect = PageCrop.pixelRect(for: entry.box, imageWidth: Int(size.width), imageHeight: Int(size.height), margin: 0)
                return CreateMLBox(label: entry.label.exportLabel,
                                   coordinates: .init(x: rect.midX, y: rect.midY, width: rect.width, height: rect.height))
            }
            return CreateMLImageAnnotation(image: image, annotations: boxes)
        }
    }

    static func imageSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        return CGSize(width: w, height: h)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "ExampleBankRecorderTests|CreateMLExporterTests"`
Expected: 5 pass.

- [ ] **Step 6: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/Learning Autogram/Tests/AutogramKitTests/ExampleBankRecorderTests.swift Autogram/Tests/AutogramKitTests/CreateMLExporterTests.swift
git commit -m "feat: record review decisions into the example bank and export for Create ML

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Settings toggles and session store wiring

**Files:**
- Modify: `Sources/AutogramKit/Support/AppSettings.swift` (fields, `CodingKeys`, `init`, `init(from:)`, `encode`)
- Modify: `Sources/AutogramApp/ZakoSessionStore.swift` (`buildPipeline`, `runAnalysis`, `updateReviewState`, `securityReviewStamp`, `loadDocument`, new bank plumbing)
- Test: `Tests/AutogramKitTests/AppSettingsLearningTests.swift`, `Tests/AutogramAppTests/ZakoBankRecordingTests.swift`

**Interfaces:**
- Consumes: `LayeredDetectionProvider.makeDefault(bank:useFoundationModel:)`, `LayeredDetectionProvider.identifier`, `ExampleBank`, `ExampleBankRecorder`, `BankLabel`, `DetectionPipeline(builtin:llmProvider:)`.
- Produces:
  - `AppSettings.useFoundationModelClassifier: Bool` (default `true`), `AppSettings.learnFromReviews: Bool` (default `true`), both as trailing `init` parameters.
  - `ZakoSessionStore.exampleBank: ExampleBank` (injected, default `ExampleBank(directory: ExampleBank.defaultDirectory)`), `ZakoSessionStore.bankRecorderFactory: (ExampleBank, String) -> ExampleBankRecorder` (injectable for tests), `ZakoSessionStore.documentData: Data?`, `ZakoSessionStore.detectorIdentifier: String`.
  - `static func buildPipeline(settings: AppSettings, bank: ExampleBank) -> DetectionPipeline` (old signature removed; update `ZakoAIVisionReadinessTests` if it called it).

- [ ] **Step 1: Write failing tests**

`AppSettingsLearningTests.swift`:

```swift
import XCTest
@testable import AutogramKit

final class AppSettingsLearningTests: XCTestCase {
    func testDefaultsAreOn() {
        let settings = AppSettings()
        XCTAssertTrue(settings.useFoundationModelClassifier)
        XCTAssertTrue(settings.learnFromReviews)
    }

    func testLegacyJSONWithoutNewKeysDecodesToDefaults() throws {
        let json = #"{"aiMode":"Interný (on-device Vision)"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(settings.useFoundationModelClassifier)
        XCTAssertTrue(settings.learnFromReviews)
    }

    func testTogglesRoundTrip() throws {
        var settings = AppSettings()
        settings.useFoundationModelClassifier = false
        settings.learnFromReviews = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.useFoundationModelClassifier)
        XCTAssertFalse(decoded.learnFromReviews)
    }
}
```

`ZakoBankRecordingTests.swift` (app target, `@MainActor`, follows `ZakoAIVisionReadinessTests` style):

```swift
import XCTest
import PDFKit
import AutogramKit
@testable import AutogramApp

@MainActor
final class ZakoBankRecordingTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { FeatureVector(values: [0.5]) }
    }

    private func makeStore(learn: Bool) throws -> (ZakoSessionStore, ExampleBank) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zako-bank-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let settingsStore = AppSettingsStore()
        settingsStore.settings.learnFromReviews = learn
        let store = ZakoSessionStore(settingsStore: settingsStore, exampleBank: bank)
        store.bankRecorderFactory = { bank, version in
            ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: version)
        }
        let data = TestPDFBuilderApp.typicalContractPDF()
        store.document = try XCTUnwrap(PDFDocument(data: data))
        store.documentData = data
        store.analysis = PDFAnalysisEngine().analyze(document: store.document!)
        return (store, bank)
    }

    func testConfirmAndRejectWriteBankEntriesAndReturnRemovesThem() async throws {
        let (store, bank) = try makeStore(learn: true)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        let noise = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                    boundingBox: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.05), confidence: 0.5)
        store.securityElements = [stamp, noise]

        store.confirmSecurityElement(id: stamp.id)
        store.rejectSecurityElement(id: noise.id)
        await store.waitForBankWrites()

        let entries = await bank.entries()
        XCTAssertEqual(Set(entries.map(\.id)), [stamp.id, noise.id])
        XCTAssertEqual(entries.first { $0.id == stamp.id }?.label, .kind(.officialStamp))
        XCTAssertEqual(entries.first { $0.id == noise.id }?.label, .negative)

        store.returnSecurityElementToReview(id: stamp.id)
        await store.waitForBankWrites()
        XCTAssertEqual(await bank.entries().map(\.id), [noise.id])
    }

    func testLearningOffWritesNothing() async throws {
        let (store, bank) = try makeStore(learn: false)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        store.securityElements = [stamp]
        store.confirmSecurityElement(id: stamp.id)
        await store.waitForBankWrites()
        XCTAssertTrue(await bank.entries().isEmpty)
    }

    func testReviewStampCarriesDetectorIdentifier() throws {
        let (store, _) = try makeStore(learn: true)
        XCTAssertTrue(store.securityReviewStamp.detectorIdentifier.hasPrefix("LayeredDetectionProvider/"))
    }
}
```

`TestPDFBuilderApp` does not exist in the app test target. Copy `Tests/AutogramKitTests/TestPDFBuilder.swift` to `Tests/AutogramAppTests/TestPDFBuilderApp.swift`, rename the enum to `TestPDFBuilderApp`, and keep only `build(pages:)`, `ring`, `polyline`, `text`, `filledCircle` and `typicalContractPDF()`. (SwiftPM test targets cannot share sources; duplication is the accepted pattern here.)

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter "AppSettingsLearningTests|ZakoBankRecordingTests"`
Expected: compile errors.

- [ ] **Step 3: Add the settings fields**

In `AppSettings.swift`:
- After `public var retainRecentDocuments: Bool` add:

```swift
    /// Use the on-device Foundation Model to classify uncertain candidates.
    public var useFoundationModelClassifier: Bool
    /// Record confirmed and rejected elements into the local example bank.
    public var learnFromReviews: Bool
```

- `CodingKeys`: append `case useFoundationModelClassifier, learnFromReviews`.
- `init(...)`: append parameters `useFoundationModelClassifier: Bool = true, learnFromReviews: Bool = true` and assignments.
- `init(from:)`: append

```swift
        self.useFoundationModelClassifier = try container.decodeIfPresent(Bool.self, forKey: .useFoundationModelClassifier) ?? true
        self.learnFromReviews = try container.decodeIfPresent(Bool.self, forKey: .learnFromReviews) ?? true
```

- `encode(to:)`: append the two `encode` calls.

- [ ] **Step 4: Wire the session store**

In `ZakoSessionStore.swift`:

1. Properties (near `var document: PDFDocument?`):

```swift
    var documentData: Data?
    let exampleBank: ExampleBank
    var bankRecorderFactory: (ExampleBank, String) -> ExampleBankRecorder = { bank, version in
        ExampleBankRecorder(bank: bank, detectorVersion: version)
    }
    private(set) var detectorIdentifier: String = LayeredDetectionProvider(
        classifier: TwoStageClassifier(primary: NoOpClassifier(), secondary: nil)).identifier
    private var bankWriteTasks: [UUID: Task<Void, Never>] = [:]
    private var bankWarningShown = false
```

Add at file bottom:

```swift
/// Placeholder used only to compute the default identifier before the first analysis.
private struct NoOpClassifier: ElementClassifying {
    func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement { .unsure }
}
```

2. `init` gains `exampleBank: ExampleBank = ExampleBank(directory: ExampleBank.defaultDirectory)` as the last parameter and assigns `self.exampleBank = exampleBank`. Update `AutogramApp.swift:23` only if the compiler requires it (default keeps it compiling).

3. Replace `static func buildPipeline(settings:)` signature with `static func buildPipeline(settings: AppSettings, bank: ExampleBank) -> DetectionPipeline` and the final line with:

```swift
        let layered = LayeredDetectionProvider.makeDefault(bank: bank, useFoundationModel: settings.useFoundationModelClassifier)
        return DetectionPipeline(builtin: layered, llmProvider: llmProvider)
```

4. In `runAnalysis()` replace `let pipeline = Self.buildPipeline(settings: selectedSettings)` with:

```swift
        let pipeline = Self.buildPipeline(settings: selectedSettings, bank: exampleBank)
        if let layered = pipeline.builtin as? LayeredDetectionProvider {
            detectorIdentifier = layered.identifier
        }
```

5. In `loadDocument(at:)`, after `self.document = document`, add `self.documentData = (try? Data(contentsOf: url)).flatMap { url.pathExtension.lowercased() == "asice" ? ASiCEContainerVerifier.extractPDFData($0) : $0 }`. In `resetSession(keepingProfile:)` add `documentData = nil` next to wherever `document = nil` is set.

6. `securityReviewStamp`: pass `detectorIdentifier: detectorIdentifier` to the `SecurityReviewStamp` initializer.

7. Replace `updateReviewState`:

```swift
    private func updateReviewState(id: UUID, state: SecurityElementReviewState) {
        guard let index = securityElements.firstIndex(where: { $0.id == id }) else { return }
        securityElements[index].reviewState = state
        touchReview()
        recomputePreflight()
        recordReviewDecision(securityElements[index], state: state)
    }

    private func recordReviewDecision(_ element: SecurityElement, state: SecurityElementReviewState) {
        guard settings.learnFromReviews, let document, let documentData else { return }
        let recorder = bankRecorderFactory(exampleBank, detectorIdentifier)
        let doc = UncheckedSendable(document)
        bankWriteTasks[element.id]?.cancel()
        bankWriteTasks[element.id] = Task.detached(priority: .utility) { [recorder, doc, documentData, element] in
            do {
                switch state {
                case .confirmed:
                    try await recorder.record(document: doc.value, documentData: documentData,
                                              element: element, label: .kind(element.kind))
                case .rejected:
                    try await recorder.record(document: doc.value, documentData: documentData,
                                              element: element, label: .negative)
                case .pending:
                    try await recorder.forget(elementID: element.id)
                }
            } catch {
                await MainActor.run { self.showBankWarningOnce(error) }
            }
        }
    }

    private func showBankWarningOnce(_ error: Error) {
        guard !bankWarningShown else { return }
        bankWarningShown = true
        analysisWarning = "Lokálny dataset sa nepodarilo aktualizovať (\(error.localizedDescription)). Kontrola pokračuje."
    }

    /// Test hook: wait for outstanding bank writes.
    func waitForBankWrites() async {
        for task in bankWriteTasks.values { await task.value }
        bankWriteTasks = [:]
    }
```

`UncheckedSendable` exists in `Sources/AutogramApp/ConcurrencySupport.swift`. If `Task.detached` rejects capturing `self` for `showBankWarningOnce`, capture `[weak self]` and guard.

8. Grep for other callers of `buildPipeline(settings:` (tests) and update them to pass `bank: ExampleBank(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))`.

- [ ] **Step 5: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`
Expected: whole suite passes.

- [ ] **Step 6: Commit**

```bash
git add Autogram/Sources/AutogramKit/Support/AppSettings.swift Autogram/Sources/AutogramApp/ZakoSessionStore.swift Autogram/Tests/AutogramKitTests/AppSettingsLearningTests.swift Autogram/Tests/AutogramAppTests/ZakoBankRecordingTests.swift Autogram/Tests/AutogramAppTests/TestPDFBuilderApp.swift
git commit -m "feat: wire layered detector, learning toggles and bank recording into ZaKo session

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Settings UI - learning and dataset group

**Files:**
- Modify: `Sources/AutogramApp/Views/SettingsView.swift` (insert a new glass card after the prompt card that ends at the `.onAppear { ... }` block near line 363)
- Modify: `Sources/AutogramApp/AppSettingsStore.swift` (expose `exampleBank`)
- Test: `Tests/AutogramAppTests/SettingsLearningCardTests.swift`

**Interfaces:**
- Consumes: `AppSettings.useFoundationModelClassifier`, `AppSettings.learnFromReviews`, `ExampleBank.count(for:)`, `ExampleBank.removeAll()`, `CreateMLExporter.export(bank:to:)`, `FoundationModels.SystemLanguageModel.default.isAvailable`.
- Produces: `AppSettingsStore.exampleBank: ExampleBank` (single shared instance also passed to `ZakoSessionStore` in `AutogramApp.swift`), `struct LearningDatasetCard: View` with `init(settingsStore: AppSettingsStore, bank: ExampleBank)`, and a pure helper `enum LearningCardText { static func summary(counts: [BankLabel: Int]) -> String }`.

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import AutogramKit
@testable import AutogramApp

final class SettingsLearningCardTests: XCTestCase {
    func testSummaryListsCountsPerLabelInSlovak() {
        let text = LearningCardText.summary(counts: [
            .kind(.officialStamp): 12, .kind(.handwrittenSignature): 7, .negative: 3])
        XCTAssertEqual(text, "Pečiatky: 12 · Podpisy: 7 · Slepotlač: 0 · Parafy: 0 · Iné: 0 · Zamietnuté: 3")
    }

    func testEmptySummary() {
        XCTAssertEqual(LearningCardText.summary(counts: [:]),
                       "Pečiatky: 0 · Podpisy: 0 · Slepotlač: 0 · Parafy: 0 · Iné: 0 · Zamietnuté: 0")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter SettingsLearningCardTests`
Expected: compile error.

- [ ] **Step 3: Implement**

In `AppSettingsStore.swift` add `let exampleBank = ExampleBank(directory: ExampleBank.defaultDirectory)` and in `AutogramApp.swift` change the store creation to `ZakoSessionStore(settingsStore: settings, exampleBank: settings.exampleBank)`.

Append to `SettingsView.swift`:

```swift
enum LearningCardText {
    static func summary(counts: [BankLabel: Int]) -> String {
        func n(_ label: BankLabel) -> Int { counts[label] ?? 0 }
        return "Pečiatky: \(n(.kind(.officialStamp))) · Podpisy: \(n(.kind(.handwrittenSignature))) · " +
               "Slepotlač: \(n(.kind(.embossedSeal))) · Parafy: \(n(.kind(.initial))) · " +
               "Iné: \(n(.kind(.other))) · Zamietnuté: \(n(.negative))"
    }
}

struct LearningDatasetCard: View {
    @Bindable var settingsStore: AppSettingsStore
    let bank: ExampleBank
    @State private var counts: [BankLabel: Int] = [:]
    @State private var exportMessage: String?
    @State private var showDeleteConfirmation = false
    private let modelAvailable = SystemLanguageModel.default.isAvailable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Učenie a lokálny dataset").font(.headline)

            Toggle("Klasifikovať neisté nálezy on-device modelom (Apple Intelligence)",
                   isOn: $settingsStore.settings.useFoundationModelClassifier)
                .disabled(!modelAvailable)
            Text(modelAvailable
                 ? "Model beží výhradne na tomto Macu. Bez neho rozhoduje iba porovnanie s potvrdenými príkladmi."
                 : "On-device model nie je na tomto Macu dostupný. Zapnite Apple Intelligence v Systémových nastaveniach.")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("Učiť sa z potvrdených a odmietnutých prvkov", isOn: $settingsStore.settings.learnFromReviews)
            Text(LearningCardText.summary(counts: counts))
                .font(.caption.monospacedDigit())
            Text("Dataset zostáva na tomto Macu. Obsahuje náhľady strán dokumentov, ktorých prvky ste potvrdili alebo odmietli. Nikdy sa neodosiela.")
                .font(.caption2).foregroundStyle(.secondary)

            HStack {
                Button("Exportovať dataset pre Create ML…") { exportDataset() }
                Button("Vymazať lokálny dataset…", role: .destructive) { showDeleteConfirmation = true }
                Spacer()
            }
            .controlSize(.small)
            if let exportMessage {
                Text(exportMessage).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .glassCard(cornerRadius: 14, padding: 16)
        .task { await refreshCounts() }
        .confirmationDialog("Vymazať všetky uložené príklady?", isPresented: $showDeleteConfirmation) {
            Button("Vymazať", role: .destructive) {
                Task { try? await bank.removeAll(); await refreshCounts() }
            }
            Button("Zrušiť", role: .cancel) {}
        }
    }

    private func refreshCounts() async {
        let entries = await bank.entries()
        counts = Dictionary(grouping: entries, by: \.label).mapValues(\.count)
    }

    private func exportDataset() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Exportovať"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            do {
                let url = try await CreateMLExporter.export(bank: bank, to: folder)
                exportMessage = "Export hotový: \(url.path)"
            } catch {
                exportMessage = "Export zlyhal: \(error.localizedDescription)"
            }
        }
    }
}
```

Add `import FoundationModels` and `import AppKit` at the top of `SettingsView.swift` if missing. Insert `LearningDatasetCard(settingsStore: settingsStore, bank: settingsStore.exampleBank)` directly after the prompt card's `.onAppear { ... }` block inside the same `VStack`.

- [ ] **Step 4: Build, run tests, and check the card visually**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter SettingsLearningCardTests` (expected 2 pass), then `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./build_app.sh` and open `.build/arm64-apple-macosx/debug/Autogram.app`, Settings, AI section: the card shows both toggles, the counter line, both buttons.

- [ ] **Step 5: Commit**

```bash
git add Autogram/Sources/AutogramApp/Views/SettingsView.swift Autogram/Sources/AutogramApp/AppSettingsStore.swift Autogram/Sources/AutogramApp/AutogramApp.swift Autogram/Tests/AutogramAppTests/SettingsLearningCardTests.swift
git commit -m "feat: add learning and dataset settings card

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Segmentation snapper and click-to-snap canvas

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Segmentation/SegmentationSnapper.swift`
- Modify: `Sources/AutogramApp/ZakoSessionStore.swift` (snapper state, `snapElement`, `refineElement`)
- Modify: `Sources/AutogramApp/Views/AnalysisCanvasView.swift:786-835` (drag end handling), `ElementRow` (refine button), status chip
- Test: `Tests/AutogramKitTests/SegmentationSnapperTests.swift`

**Interfaces:**
- Consumes: `PageCrop.normalizedRect(fromPixelRect:imageWidth:imageHeight:)`, `BuiltInVisionProvider.render(page:targetWidth:)`, `Vision.GenerateIterativeSegmentationRequest`.
- Produces:
  - `protocol SegmentationSnapping: Sendable { func snap(pageImage: CGImage, seed: NormalizedPoint) async throws -> NormalizedRect; func refine(pageImage: CGImage, box: NormalizedRect) async throws -> NormalizedRect; func ensureAssets(progress: @Sendable @escaping (Double) -> Void) async throws }`
  - `struct SegmentationSnapper: SegmentationSnapping` (live), plus pure `static func boundingRect(ofMask mask: [Bool], width: Int, height: Int, padding: Double = 0.04) -> NormalizedRect?` and `static func mask(from pixelBuffer: CVReadOnlyPixelBuffer, threshold: Float = 0.5) -> (mask: [Bool], width: Int, height: Int)`.
  - `enum SnapperError: Error { case assetsUnavailable, emptyMask }`
  - `ZakoSessionStore.snapper: any SegmentationSnapping`, `ZakoSessionStore.snapAssetProgress: Double?` (nil when idle or ready), `ZakoSessionStore.snapUnavailableReason: String?`, `func snapElement(kind:at:) async -> UUID?`, `func refineElement(id:) async`.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import AutogramKit

final class SegmentationSnapperTests: XCTestCase {
    func testBoundingRectOfMaskFlipsToBottomOriginAndPads() {
        // 10x10 mask, filled rows 6..7 (top-origin), cols 2..3.
        var mask = [Bool](repeating: false, count: 100)
        for y in 6...7 { for x in 2...3 { mask[y * 10 + x] = true } }
        let rect = try! XCTUnwrap(SegmentationSnapper.boundingRect(ofMask: mask, width: 10, height: 10, padding: 0))
        XCTAssertEqual(rect.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.2, accuracy: 1e-9)
        // rows 6..7 from the top means bottom-origin y from 0.2 to 0.4
        XCTAssertEqual(rect.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.2, accuracy: 1e-9)

        let padded = try! XCTUnwrap(SegmentationSnapper.boundingRect(ofMask: mask, width: 10, height: 10, padding: 0.5))
        XCTAssertEqual(padded.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(padded.width, 0.4, accuracy: 1e-9)
    }

    func testEmptyMaskYieldsNil() {
        XCTAssertNil(SegmentationSnapper.boundingRect(ofMask: [Bool](repeating: false, count: 4), width: 2, height: 2))
    }

    func testPaddingIsClampedToImage() {
        var mask = [Bool](repeating: false, count: 4)
        mask[0] = true // top-left pixel
        let rect = try! XCTUnwrap(SegmentationSnapper.boundingRect(ofMask: mask, width: 2, height: 2, padding: 2))
        XCTAssertEqual(rect.x, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.y + rect.height, 1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(rect.x + rect.width, 1)
        XCTAssertGreaterThanOrEqual(rect.y, 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter SegmentationSnapperTests`
Expected: compile errors.

- [ ] **Step 3: Implement the snapper**

```swift
import Foundation
import CoreGraphics
import CoreVideo
import Vision

public enum SnapperError: Error { case assetsUnavailable, emptyMask }

public protocol SegmentationSnapping: Sendable {
    func ensureAssets(progress: @Sendable @escaping (Double) -> Void) async throws
    func snap(pageImage: CGImage, seed: NormalizedPoint) async throws -> NormalizedRect
    func refine(pageImage: CGImage, box: NormalizedRect) async throws -> NormalizedRect
}

/// Wraps Vision 27 iterative segmentation. Coordinates in and out use the
/// app's bottom-origin normalized convention.
public struct SegmentationSnapper: SegmentationSnapping {
    public var padding: Double = 0.04
    public init() {}

    public func ensureAssets(progress: @Sendable @escaping (Double) -> Void) async throws {
        let request = GenerateIterativeSegmentationRequest(seedPoint: Vision.NormalizedPoint(x: 0.5, y: 0.5))
        switch await request.assetStatus {
        case .ready: return
        default:
            let root = Progress(totalUnitCount: 100)
            let observer = root.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            defer { observer.invalidate() }
            try await request.downloadAssets(progress: root.makeChild(withPendingUnitCount: 100))
            if case .ready = await request.assetStatus { return }
            throw SnapperError.assetsUnavailable
        }
    }

    public func snap(pageImage: CGImage, seed: NormalizedPoint) async throws -> NormalizedRect {
        // Vision seed points are lower-left origin, same as the app.
        let request = GenerateIterativeSegmentationRequest(seedPoint: Vision.NormalizedPoint(x: seed.x, y: seed.y))
        return try await perform(request, on: pageImage)
    }

    public func refine(pageImage: CGImage, box: NormalizedRect) async throws -> NormalizedRect {
        let request = GenerateIterativeSegmentationRequest(seedBox: Vision.NormalizedRect(
            x: box.x, y: box.y, width: box.width, height: box.height))
        return try await perform(request, on: pageImage)
    }

    private func perform(_ request: GenerateIterativeSegmentationRequest, on image: CGImage) async throws -> NormalizedRect {
        guard case .ready = await request.assetStatus else { throw SnapperError.assetsUnavailable }
        let observation = try await request.perform(on: image)
        let (mask, width, height) = Self.mask(from: observation.pixelBuffer)
        guard let rect = Self.boundingRect(ofMask: mask, width: width, height: height, padding: padding) else {
            throw SnapperError.emptyMask
        }
        return rect
    }

    public static func mask(from pixelBuffer: CVReadOnlyPixelBuffer, threshold: Float = 0.5) -> (mask: [Bool], width: Int, height: Int) {
        let width = pixelBuffer.width, height = pixelBuffer.height
        var mask = [Bool](repeating: false, count: width * height)
        pixelBuffer.withUnsafeBuffer { buffer in
            // Vision masks are single-channel; support the two common formats.
            let bytesPerRow = pixelBuffer.bytesPerRow
            let isFloat = pixelBuffer.pixelFormat == kCVPixelFormatType_OneComponent32Float
            for y in 0..<height {
                let row = buffer.baseAddress!.advanced(by: y * bytesPerRow)
                for x in 0..<width {
                    let value: Float = isFloat
                        ? row.load(fromByteOffset: x * 4, as: Float.self)
                        : Float(row.load(fromByteOffset: x, as: UInt8.self)) / 255
                    mask[y * width + x] = value >= threshold
                }
            }
        }
        return (mask, width, height)
    }

    public static func boundingRect(ofMask mask: [Bool], width: Int, height: Int, padding: Double = 0.04) -> NormalizedRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let pixel = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let base = PageCrop.normalizedRect(fromPixelRect: pixel, imageWidth: width, imageHeight: height)
        let padX = base.width * padding, padY = base.height * padding
        let x0 = max(0, base.x - padX), y0 = max(0, base.y - padY)
        let x1 = min(1, base.x + base.width + padX), y1 = min(1, base.y + base.height + padY)
        return NormalizedRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
```

The exact `CVReadOnlyPixelBuffer` accessor names (`width`, `height`, `bytesPerRow`, `pixelFormat`, `withUnsafeBuffer`) must be verified against the SDK: `grep -n "struct CVReadOnlyPixelBuffer" -A40 /Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreVideo.framework/Modules/CoreVideo.swiftmodule/arm64e-apple-macos.swiftinterface`. If the type exposes only the C-style `CVPixelBuffer`, use `CVPixelBufferLockBaseAddress` / `CVPixelBufferGetBaseAddress` / `CVPixelBufferGetBytesPerRow` / `CVPixelBufferGetPixelFormatType` instead. Alternatively use `observation.cgImage` and read pixels through `PixelMap(cgImage:)` with `luminance(x:y:) > 0.5`; that path is already in the code base and needs no new CoreVideo calls. Prefer the `PixelMap` path if any doubt.

- [ ] **Step 4: Session store additions**

```swift
    var snapper: any SegmentationSnapping = SegmentationSnapper()
    var snapAssetProgress: Double?
    var snapUnavailableReason: String?
    private var snapAssetsReady = false

    private func ensureSnapAssets() async -> Bool {
        if snapAssetsReady { return true }
        snapAssetProgress = 0
        defer { snapAssetProgress = nil }
        do {
            try await snapper.ensureAssets { fraction in
                Task { @MainActor in self.snapAssetProgress = fraction }
            }
            snapAssetsReady = true
            snapUnavailableReason = nil
            return true
        } catch {
            snapUnavailableReason = "Presný výber prvku nie je dostupný (model sa nepodarilo stiahnuť). Rámec nakreslite ručne."
            return false
        }
    }

    private func renderedPage(_ pageIndex: Int) -> CGImage? {
        guard let document, let page = document.page(at: pageIndex) else { return nil }
        return BuiltInVisionProvider.render(page: page, targetWidth: 1200)?.cgImage
    }

    /// Click without drag in an element mode: segment at the point and create the element.
    func snapElement(kind: SecurityElement.Kind, at point: NormalizedPoint) async -> UUID? {
        let pageIndex = previewPageIndex
        guard await ensureSnapAssets(), let image = renderedPage(pageIndex) else { return nil }
        let box = UncheckedSendableImage(image)
        guard let rect = try? await snapper.snap(pageImage: box.image, seed: point) else { return nil }
        addSecurityElement(kind: kind, pageIndex: pageIndex, rect: rect)
        return selectedElementID
    }

    func refineElement(id: UUID) async {
        guard let element = securityElements.first(where: { $0.id == id }),
              await ensureSnapAssets(), let image = renderedPage(element.pageIndex) else { return }
        let box = UncheckedSendableImage(image)
        guard let rect = try? await snapper.refine(pageImage: box.image, box: element.boundingBox) else { return }
        updateElementBoundingBox(id: id, boundingBox: rect)
    }
```

Add `struct UncheckedSendableImage: @unchecked Sendable { let image: CGImage; init(_ image: CGImage) { self.image = image } }` to `ConcurrencySupport.swift`.

- [ ] **Step 5: Canvas changes**

In `ElementOverlay.dragGesture` replace `.onEnded { _ in interaction = nil }` with:

```swift
            .onEnded { value in
                defer { interaction = nil }
                guard let current = interaction, !current.moved,
                      case .resizing(let id, _) = current.kind,
                      let tool = store.activeTool,
                      store.securityElements.first(where: { $0.id == id })?.detectedByAI == false else { return }
                // A click without movement in an element mode: replace the placeholder with a snapped element.
                let point = mapper.normalizedPoint(from: value.location)
                store.removeSecurityElement(id: id)
                Task { @MainActor in
                    if await store.snapElement(kind: tool, at: point) == nil {
                        store.undoDelete()
                    }
                }
            }
```

In `ElementRow` add `let onRefine: () -> Void` after `onDuplicate`, and next to the duplicate button add:

```swift
                Button {
                    onRefine()
                } label: {
                    Label("Spresniť rámec", systemImage: "wand.and.stars")
                }
                .help("Prispôsobí rámec skutočnému obrysu prvku (Apple Vision).")
```

At the `ElementRow(` call site add `onRefine: { Task { await store.refineElement(id: element.id) } },` after `onDuplicate`.

Below the markup toolbar in `AnalysisCanvasView` add:

```swift
            if let progress = store.snapAssetProgress {
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("Sťahujem model výberu…").font(.caption2)
                }
                .padding(6)
                .background(.regularMaterial, in: Capsule())
            } else if let reason = store.snapUnavailableReason {
                Text(reason).font(.caption2).foregroundStyle(.secondary)
            }
```

- [ ] **Step 6: Run tests and verify manually**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test` (all pass), then `./build_app.sh`, open a PDF in ZaKo, pick Pečiatka, click once on a stamp: a box appears around it after the one-time download; "Spresniť rámec" tightens a hand-drawn box.

- [ ] **Step 7: Commit**

```bash
git add Autogram/Sources/AutogramKit/VisionAI/Segmentation Autogram/Sources/AutogramApp/ZakoSessionStore.swift Autogram/Sources/AutogramApp/ConcurrencySupport.swift Autogram/Sources/AutogramApp/Views/AnalysisCanvasView.swift Autogram/Tests/AutogramKitTests/SegmentationSnapperTests.swift
git commit -m "feat: click-to-snap and refine element boxes with Vision segmentation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Evaluation harness

**Files:**
- Create: `Sources/AutogramKit/VisionAI/Evaluation/DetectionEvaluator.swift`
- Create: `Sources/vision-eval/main.swift`
- Modify: `Package.swift`
- Test: `Tests/AutogramKitTests/DetectionEvaluatorTests.swift`

**Interfaces:**
- Consumes: `CreateMLImageAnnotation`, `BankLabel.exportLabel`, `SecurityElementMerger.iou`, `LayeredDetectionProvider`, `DetectionPipeline`, `PDFAnalysisEngine`.
- Produces:
  - `struct EvaluationMetrics: Codable, Equatable { perLabel: [String: LabelMetrics]; meanMillisecondsPerPage: Double; pages: Int }`, `struct LabelMetrics: Codable, Equatable { truePositives: Int; falsePositives: Int; falseNegatives: Int; var precision: Double; var recall: Double; var f1: Double }`
  - `enum DetectionEvaluator { static func score(predicted: [SecurityElement], truth: [CreateMLImageAnnotation], imageSizes: [String: CGSize], pageOrder: [String], iouThreshold: Double) -> [String: LabelMetrics]; static func label(for kind: SecurityElement.Kind) -> String }`

- [ ] **Step 1: Write failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter DetectionEvaluatorTests`
Expected: compile errors.

- [ ] **Step 3: Implement evaluator**

```swift
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
    public init(perLabel: [String: LabelMetrics], meanMillisecondsPerPage: Double, pages: Int) {
        self.perLabel = perLabel; self.meanMillisecondsPerPage = meanMillisecondsPerPage; self.pages = pages
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
```

- [ ] **Step 4: CLI target**

`Package.swift`: add to `targets`:

```swift
        .executableTarget(
            name: "vision-eval",
            dependencies: ["AutogramKit"]
        ),
```

`Sources/vision-eval/main.swift`:

```swift
import Foundation
import AppKit
import PDFKit
import AutogramKit

// Usage: vision-eval <dataset-folder> [--builtin-only] [--no-fm] [--iou 0.4] [--json]
var args = Array(CommandLine.arguments.dropFirst())
guard let folderPath = args.first else {
    FileHandle.standardError.write("usage: vision-eval <dataset-folder> [--builtin-only] [--no-fm] [--iou 0.4] [--json]\n".data(using: .utf8)!)
    exit(2)
}
args.removeFirst()
let builtinOnly = args.contains("--builtin-only")
let useFM = !args.contains("--no-fm")
let json = args.contains("--json")
var iou = 0.4
if let i = args.firstIndex(of: "--iou"), i + 1 < args.count, let v = Double(args[i + 1]) { iou = v }

let folder = URL(fileURLWithPath: folderPath)
let annotationsURL = folder.appendingPathComponent("annotations.json")
let truth = try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: annotationsURL))
let pageOrder = truth.map(\.image)

// Build one PDF page per image so the provider sees the same input as the app.
let document = PDFDocument()
var sizes: [String: CGSize] = [:]
for (index, name) in pageOrder.enumerated() {
    guard let image = NSImage(contentsOf: folder.appendingPathComponent(name)),
          let page = PDFPage(image: image) else { fatalError("cannot load \(name)") }
    sizes[name] = image.size
    document.insert(page, at: index)
}

let bank = ExampleBank(directory: ExampleBank.defaultDirectory)
let provider: any SecurityElementsProviding = builtinOnly
    ? BuiltInVisionProvider()
    : LayeredDetectionProvider.makeDefault(bank: bank, useFoundationModel: useFM)
let analyses = PDFAnalysisEngine().analyze(document: document).pageAnalyses

let semaphore = DispatchSemaphore(value: 0)
var predicted: [SecurityElement] = []
let start = Date()
Task {
    predicted = await provider.detect(in: document, pageAnalyses: analyses)
    semaphore.signal()
}
semaphore.wait()
let elapsed = Date().timeIntervalSince(start) * 1000

let perLabel = DetectionEvaluator.score(predicted: predicted, truth: truth, imageSizes: sizes, pageOrder: pageOrder, iouThreshold: iou)
let metrics = EvaluationMetrics(perLabel: perLabel, meanMillisecondsPerPage: elapsed / Double(max(pageOrder.count, 1)), pages: pageOrder.count)

if json {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(metrics), as: UTF8.self))
} else {
    print("provider: \(provider.providerName)")
    print(String(format: "pages: %d   mean ms/page: %.0f", metrics.pages, metrics.meanMillisecondsPerPage))
    print(String(format: "%-22@ %5@ %5@ %5@ %7@ %7@ %7@", "label", "TP", "FP", "FN", "P", "R", "F1"))
    for (label, m) in perLabel.sorted(by: { $0.key < $1.key }) {
        print(String(format: "%-22@ %5d %5d %5d %7.2f %7.2f %7.2f", label, m.truePositives, m.falsePositives, m.falseNegatives, m.precision, m.recall, m.f1))
    }
}
```

`PDFPage(image:)` yields a page whose media box matches the image points; `sizes[name]` must be pixel size, so replace `image.size` with the pixel size read through `CGImageSourceCreateWithURL` (reuse `CreateMLExporter.imageSize(at:)`; make it `public static`).

- [ ] **Step 5: Run tests and smoke the CLI**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter DetectionEvaluatorTests` (2 pass). Then create a smoke dataset: in the app, confirm two elements on any document, export the dataset from Settings to `~/AutogramEval`, and run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run vision-eval ~/AutogramEval` and `... --builtin-only`. Both must print a table.

- [ ] **Step 6: Commit**

```bash
git add Autogram/Package.swift Autogram/Sources/vision-eval Autogram/Sources/AutogramKit/VisionAI/Evaluation Autogram/Sources/AutogramKit/VisionAI/Learning/CreateMLExporter.swift Autogram/Tests/AutogramKitTests/DetectionEvaluatorTests.swift
git commit -m "feat: add vision-eval harness with per-label precision and recall

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: Documentation

**Files:**
- Modify: `README.md` (lines 36, 75-81, 114-116)
- Modify: `AGENTS.md:11-13` and `CLAUDE.md:11-13`
- Modify: `AUTOGRAM_ZAKO_MODULE_SPEC.md:186-192, 268-280, 315`
- Modify: `Autogram/docs/superpowers/plans/2026-08-29-zako-production-readiness.md:32` (note that the freeze on `BuiltInVisionProvider` remains and the wrapper is the extension point)

- [ ] **Step 1: README**

Line 36 becomes: `- **AI Vision:** vrstvená on-device detekcia (vstavané heuristiky + Apple Vision kontúry a saliency), klasifikácia porovnaním s potvrdenými príkladmi a on-device Apple modelom, klik-na-prvok cez Vision segmentáciu; voliteľne oMLX, Ollama a OpenAI-compatible endpointy.`

Replace the paragraph at line 79 with:

`AI Vision je vrstvená: kandidáti z vstavaných heuristík, Apple Vision kontúr a saliency sa zlúčia a každý výrez klasifikuje porovnanie s lokálne uloženými potvrdenými príkladmi (feature print kNN); neisté prípady posúdi on-device Apple model. Každé potvrdenie alebo odmietnutie v kontrole ukladá výrez do lokálneho datasetu, ktorý sa dá exportovať pre Create ML. Bezpečnostné prvky je možné označiť ručne alebo kliknutím (Vision segmentácia), upraviť ich rámec a potvrdiť alebo odmietnuť každý nález. Manuálna kontrola zostáva povinnou poistkou.`

Line 116 caption: add one sentence: `Kandidáti z troch zdrojov sa zlučujú a klasifikujú dvojstupňovo (kNN nad lokálnym datasetom, potom on-device model).`

Add under a suitable developer section: `- \`swift run vision-eval <dataset>\` vyhodnotí presnosť a rýchlosť detekcie na exportovanom datasete (mimo repozitára).`

- [ ] **Step 2: AGENTS.md and CLAUDE.md**

Replace lines 11-13 with:

```
- PDFKit, CoreGraphics, Apple Vision and FoundationModels for document analysis and security element detection
  - `LayeredDetectionProvider` (VisionAI/): candidates from `BuiltInVisionProvider` (frozen), `DetectContoursRequest`, objectness saliency; merged by `CandidateMerger`; classified by `TwoStageClassifier` (`FeaturePrintClassifier` kNN over `ExampleBank`, then on-device `FoundationModelClassifier`)
  - `ExampleBank` at `~/Library/Application Support/Autogram/VisionBank` records confirm/reject decisions; `CreateMLExporter` writes Create ML object-detector datasets; `vision-eval` target scores precision/recall
  - `SegmentationSnapper` wraps `GenerateIterativeSegmentationRequest` for click-to-snap boxes in `AnalysisCanvasView`
  - Local LLM vision providers: oMLX (Apple Silicon MLX, `localhost:8000/v1`) and Ollama (`localhost:11434`), plus OpenAI-compatible cloud APIs with keys in Keychain
  - AI provider selection in Settings uses provider cards (`SettingsView.aiProviderRow`); config panel renders under the chosen mode; `LearningDatasetCard` holds the learning toggles and dataset export
```

Run `diff AGENTS.md CLAUDE.md` (no output).

- [ ] **Step 3: ZaKo module spec**

At lines 186-192 replace the Hough/CoreML bullet with: `Implementované: vrstvená detekcia (heuristiky + Vision kontúry + saliency), kNN nad lokálnym datasetom, on-device Foundation Model klasifikácia neistých výrezov. Fáza C (plán): Create ML `MLObjectDetector` natrénovaný z exportovaného datasetu, pripojený ako ďalší zdroj kandidátov cez `CoreMLRequest`.` At 268-280 rename `CoreML` to `Vision + FoundationModels (+ CoreML vo fáze C)`. At 315 keep F3 but reference this spec.

- [ ] **Step 4: Commit**

```bash
git add README.md AGENTS.md CLAUDE.md AUTOGRAM_ZAKO_MODULE_SPEC.md Autogram/docs/superpowers/plans/2026-08-29-zako-production-readiness.md
git commit -m "docs: describe layered detection, learning dataset and vision-eval

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review notes

- Spec coverage: 4 architecture (T7), 4.1 degradation (T7 tests), 5.1-5.2 candidates (T2-T3), 5.3 classification (T4-T6), 5.4 domain (T1, T9 identifier), 5.5 bank and settings (T4, T8, T9, T10), 5.6 snap (T11), 5.7 harness (T12), 5.8 settings (T9-T10), 7 errors (T7, T9, T11), 8 tests (each task), 9 docs (T13), 10 phase C (T13 spec text).
- Type consistency checked: `ElementJudgement(kind:confidence:margin:descriptionSK:decidedBy:supportCount:)`, `TwoStageClassifier.classify(crop:hint:hintConfidence:)` returns optional, `LayeredDetectionProvider.identifier` format `"LayeredDetectionProvider/1 builtIn+contour+saliency kNN fm"`, `BankLabel.exportLabel`, `PageCrop` helpers, `ExampleBank` actor methods.
- Open SDK-shape risks are called out inline with a fallback in T3 (`CoordinateOrigin`), T4 (`ElementType`), T5 (`@Generable` guides, `CGImage` capture), T7 (`PDFPage` sendability), T11 (`CVReadOnlyPixelBuffer` accessors, `PixelMap` fallback).
