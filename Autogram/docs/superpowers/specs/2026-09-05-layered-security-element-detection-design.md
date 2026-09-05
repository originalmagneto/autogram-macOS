# Layered On-Device Security-Element Detection - Design

Date: 2026-09-05
Status: approved design, pending implementation plan
Scope: ZaKo analysis step - detection, classification, review-driven learning, click-to-snap, evaluation

## 1. Problem

The current built-in detector (`BuiltInVisionProvider`) is a set of HSV-mask and connected-component heuristics with Apple Vision used only for OCR and barcode exclusions. On real advokátske scans it mostly misses elements (stamps, signatures, embossed seals, initials). The detector has never been evaluated on real documents; the only fixtures are drawn programmatically. Apple Vision, VisionKit and Foundation Models offer no ready-made "stamp" or "signature" class, so there is nothing to switch on. A trained Create ML detector is the right long-term answer but needs a labelled dataset that does not exist.

## 2. Goals

1. Find more real elements (recall) without raising false positives.
2. Run entirely on device. No document content leaves the Mac unless the user has explicitly chosen an external LLM in Settings, as today.
3. Turn the advocate's normal confirm / reject work into a labelled dataset that can train a Create ML object detector later (phase C).
4. Make box placement faster in the review canvas.
5. Measure precision, recall and speed on real scans so every change is proven, not assumed.
6. Do not modify `BuiltInVisionProvider.swift` internals (frozen by `docs/superpowers/plans/2026-08-29-zako-production-readiness.md`).

Non-goals: Create ML training, new external LLM modes, EZZK work, changes to the attestation or authorization steps.

## 3. Platform facts (verified against the macOS 27 SDK on 2026-09-05)

- `FoundationModels`: `SystemLanguageModel.default.isAvailable` is true on the development Mac. `Attachment` / `ImageAttachment` accept `CGImage`, `CIImage`, `CVPixelBuffer` and file URLs. `@Generable` structured output works with image prompts. On-device context is about 4K tokens. The model does not return coordinates; it is a classifier and describer, not a detector.
- `Vision`: `GenerateIterativeSegmentationRequest` (new, `DownloadableAssetsRequest`, seed point, add / remove points), `GenerateObjectnessBasedSaliencyImageRequest`, `DetectContoursRequest`, `GenerateImageFeaturePrintRequest` with `FeaturePrintObservation.distance(to:)`, `CoreMLRequest`. No new document, handwriting or stamp request.
- `CreateML`: `MLObjectDetector` present (phase C).
- `CoreAI`: not usable from this project; out of scope.
- Build requires Xcode 27; Command Line Tools alone lack the SwiftUI macro plugin.

## 4. Architecture

`DetectionPipeline` remains the only entry point used by `ZakoSessionStore`. Its built-in stage is replaced by `LayeredDetectionProvider`, which conforms to `SecurityElementsProviding`. The external LLM merge stays as it is.

```
PDF page
  │ render (PDFKit, renderTargetWidth 760 as today, /Rotate respected)
  ▼
Candidate generation (per page, concurrent, bounded)
  ├ BuiltInCandidateSource     wraps BuiltInVisionProvider; keeps kind hint + confidence
  ├ ContourCandidateSource     DetectContoursRequest -> closed contour groups -> boxes
  └ SaliencyCandidateSource    GenerateObjectnessBasedSaliencyImageRequest -> salient boxes
  │  NMS merge by IoU; drop boxes overlapping OCR text / barcodes; size gates
  ▼
Classification (per candidate crop)
  ├ FeaturePrintClassifier     kNN over ExampleBank (positives and negatives)
  └ FoundationModelClassifier  on-device model, @Generable judgement, used when kNN is unsure
  │  TwoStageClassifier decides which answer is used and records it
  ▼
SecurityElement (kind, confidence, verbalDescription, detectedByAI = true,
                 reviewState = .pending, detectionSource)
```

All new code lives in `Sources/AutogramKit/VisionAI/` in subfolders `Candidates/`, `Classification/`, `Learning/`, `Segmentation/`, plus `Evaluation/` for the harness. `BuiltInVisionProvider.swift` is wrapped, not edited.

### 4.1 Degradation rules

- If contour or saliency requests fail, the candidate list is what `BuiltInVisionProvider` produced. Result is never worse than today.
- If the Foundation Model is unavailable and the bank is cold, candidates carry the built-in kind hint and confidence; candidates without a hint are dropped.
- If Vision segmentation assets are unavailable, the canvas keeps drag-to-draw only.
- Every failure is a non-fatal warning surfaced through the existing `analysisWarning` path.

## 5. Components

### 5.1 Candidate model

```swift
struct DetectionCandidate: Sendable, Hashable {
    var pageIndex: Int
    var box: NormalizedRect          // PDF bottom-origin, same convention as SecurityElement
    var sources: Set<CandidateSource> // .builtIn, .contour, .saliency
    var kindHint: SecurityElement.Kind?
    var hintConfidence: Double?
}
```

`CandidateMerger.merge(_:)` performs NMS: candidates with IoU > 0.5 are unioned into one, keeping all sources and the strongest hint. Size gates: box area between 0.0002 and 0.25 of the page; aspect between 1/18 and 18. Candidates overlapping OCR text lines or barcodes by more than 0.3 are dropped, reusing `VisionExclusions` from the built-in provider (made internal-accessible; no behaviour change).

### 5.2 Candidate sources

- `BuiltInCandidateSource`: calls `BuiltInVisionProvider.detect` once per document and converts each element into a candidate with `kindHint` and `hintConfidence`. Barcode elements pass through unchanged as `.other` (they are already reliable).
- `ContourCandidateSource`: `DetectContoursRequest` with `contrastAdjustment` 2.0, `detectsDarkOnLight` true, `maximumImageDimension` 760. Top-level contours whose bounding box passes the size gates become candidates. Nested contours are folded into their parent.
- `SaliencyCandidateSource`: `GenerateObjectnessBasedSaliencyImageRequest`; each `salientObjects` rect passing size gates becomes a candidate.

All three run inside a `TaskGroup` per page; pages are processed with at most `ProcessInfo.activeProcessorCount / 2` in flight.

### 5.3 Classification

```swift
struct ElementJudgement: Sendable {
    var kind: SecurityElement.Kind?   // nil = not a security element
    var confidence: Double            // 0...1
    var descriptionSK: String
    var decidedBy: ClassifierIdentity // .featurePrintKNN, .foundationModel, .builtInHint
}

protocol ElementClassifying: Sendable {
    func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement
}
```

Crops are taken from the page render with a 12 % margin around the candidate box, clamped to the page.

- `FeaturePrintClassifier`: computes the crop's feature print, takes the k = 5 nearest bank examples, votes with weight `1 / (distance + 0.05)`. Labels are the five kinds plus `negative`. `confidence` = winning share of the total weight; `margin` = winner minus runner-up. Feature print computation sits behind `FeaturePrintProviding` so tests inject vectors.
- `FoundationModelClassifier`: one `LanguageModelSession` per analysis run, instructions fixed in code (Slovak security-element definitions, "judge only what is physically visible in the image, do not infer from context"), prompt = `Attachment(crop)` plus the hint as optional context. Output type:

```swift
@Generable struct FoundationJudgement {
    @Guide(description: "true only if a stamp, signature, embossed seal or initial is visible")
    var isSecurityElement: Bool
    var kind: JudgementKind          // stamp, signature, embossedSeal, initial, other, none
    @Guide(description: "one short Slovak sentence describing the visible element")
    var descriptionSK: String
    @Guide(.range(0...1)) var confidence: Double
}
```

The classifier is constructed only if `SystemLanguageModel.default.isAvailable`. Calls are serialised through one session; a per-crop timeout of 8 s yields "unsure", not an error. Both the Foundation Model call and the session sit behind `FoundationJudging` so tests use a fake.

- `TwoStageClassifier`: rule in order
  1. If the bank has at least 3 examples of the kNN winner's label and margin >= 0.25, use the kNN result.
  2. Else if the Foundation Model classifier exists, use its result; combine confidence as `0.6 * fm + 0.4 * knn` when both agree, else the FM value.
  3. Else fall back to the candidate's built-in hint; candidates without a hint are discarded.

`detectionSource` on the emitted element records the candidate sources and the deciding classifier, for example `"builtIn+contour; kNN(n=41)"`.

### 5.4 Domain model change

`SecurityElement` gains `public var detectionSource: String?`. It is decoded with `decodeIfPresent`, so existing sessions, registers and evidence rows keep loading. `SecurityReviewStamp.detectorIdentifier` is set to `LayeredDetectionProvider.identifier`, a versioned string such as `"LayeredDetectionProvider/1 builtIn+contour+saliency kNN fm"` reflecting which stages were active in that run.

### 5.5 ExampleBank (learning and dataset)

Location: `~/Library/Application Support/Autogram/VisionBank/`.

```
VisionBank/
  bank.json                 // [BankEntry]
  pages/<docSHA256>-p<N>.png   // full page render, 1200 px wide, written once per page
  crops/<entryUUID>.png     // crop with margin, for inspection and re-embedding
```

```swift
struct BankEntry: Codable, Sendable {
    var id: UUID
    var label: BankLabel              // .kind(SecurityElement.Kind) or .negative
    var documentSHA256: String
    var pageIndex: Int
    var box: NormalizedRect           // final, user-adjusted box
    var featurePrint: Data            // Codable FeaturePrintObservation
    var createdAt: Date
    var detectorVersion: String
}
```

Writes happen in `ZakoSessionStore.updateReviewState` and on manual add: `.confirmed` writes a positive entry with the element's current kind and box; `.rejected` writes a negative entry. Returning an element to review removes its entry. Writes are best-effort and off the main actor; failures surface once as a warning and never block review.

Settings (new "Učenie a dataset" group under AI):
- "Učiť sa z potvrdených a odmietnutých prvkov" toggle, default on.
- Counter: entries per label.
- "Exportovať dataset pre Create ML…" - writes a folder with `annotations.json` in Create ML object-detection format (`[{"image": "...", "annotations": [{"label": "...", "coordinates": {"x","y","width","height"}}]}]`, pixel coordinates, centre-based as Create ML expects) plus copies of the page images. Negatives are exported as images without annotations.
- "Vymazať lokálny dataset…" with confirmation.
- Privacy note text: the dataset stays on this Mac, contains page renders of documents whose elements you confirmed, and is never uploaded.

### 5.6 Click-to-snap

`SegmentationSnapper` (behind `SegmentationSnapping` for tests):

```swift
func snap(pageImage: CGImage, seed: NormalizedPoint) async throws -> NormalizedRect
func refine(pageImage: CGImage, box: NormalizedRect) async throws -> NormalizedRect
```

`snap` builds `GenerateIterativeSegmentationRequest(seed:)`, performs it, takes the mask's bounding rect, converts to bottom-origin normalized coordinates, and pads by 4 %. `refine` seeds from the box centre and adds the four inset corners as included points. If `assetStatus` is not ready, the snapper calls `downloadAssets(progress:)` once, reporting progress through a published property; while downloading or if the download fails, snapping is disabled and drag remains.

Canvas changes (`AnalysisCanvasView`):
- In an element mode (Pečiatka, Podpis, Pečať, Parafa), a click without drag snaps and creates the element; drag still draws manually.
- Element row and context menu gain "Spresniť rámec" which calls `refine` on the selected element.
- A small status chip shows "Sťahujem model výberu…" during asset download.

### 5.7 Evaluation harness

New executable target `vision-eval` (depends on `AutogramKit`), not bundled in the app.

```
swift run vision-eval <dataset-folder> [--builtin-only] [--no-fm] [--iou 0.4] [--json]
```

Input is the same folder format as the dataset export (page images plus `annotations.json`). It runs `LayeredDetectionProvider` over each page image and prints per-kind precision, recall, F1 at the given IoU, plus mean ms per page and count of FM calls. `--builtin-only` runs the wrapped provider alone so the delta of the new layers is visible. `--json` emits machine-readable output for tracking across commits.

Real scans stay outside the repository. The repository keeps only synthetic fixtures from `TestPDFBuilder`.

### 5.8 Settings

- `AppSettings` gains `useFoundationModelClassifier: Bool` (default true), `learnFromReviews: Bool` (default true). Both are honoured by `ZakoSessionStore.buildPipeline`.
- `AIMode` is unchanged. The layered detector is always the built-in stage; external LLM modes still merge as secondary.
- Settings shows the on-device model availability state using the existing readiness pattern.

## 6. Data flow summary

1. `runAnalysis()` builds `LayeredDetectionProvider` from settings and the shared `ExampleBank`.
2. Provider renders pages, generates and merges candidates, classifies, emits pending elements.
3. Advocate reviews in the canvas (drag, click-to-snap, refine, confirm, reject).
4. Each confirm / reject writes a bank entry; the next analysis run uses the grown bank.
5. Dataset export produces Create ML input for phase C.

## 7. Error handling

- Vision request errors: caught per source, logged, source skipped for that page.
- Foundation Model unavailable at construction: classifier omitted; UI shows availability in Settings.
- Foundation Model call failure or timeout: judgement "unsure", stage falls through.
- Bank read failure: bank treated as empty for this run; warning shown once.
- Bank write failure: warning shown once, review continues.
- Segmentation asset download failure: snapping disabled, drag remains, warning shown once.

## 8. Testing

Unit (deterministic, no ML):
- `CandidateMergerTests`: NMS union, size gates, text and barcode exclusion.
- `FeaturePrintClassifierTests`: voting with injected vectors, margin, cold bank.
- `TwoStageClassifierTests`: each rule branch, confidence combination.
- `ExampleBankTests`: round trip, confirm / reject / return-to-review, export format with pixel coordinate conversion.
- `SegmentationSnapperTests`: mask to normalized rect conversion, padding, clamping (mask injected).
- `DomainModels` back-compat: decoding an element without `detectionSource`.
- `LayeredDetectionProviderTests`: with fake sources and classifiers, verifies degradation rules and `detectorIdentifier` string.

Live (skip when unavailable):
- Foundation Model classifier on a drawn stamp and on plain text, asserting the boolean only.
- Contour and saliency sources on `TestPDFBuilder.typicalContractPDF()` produce at least one candidate near the drawn ring.

Existing `SecurityElementsDetectorTests` keep passing because the wrapped provider is unchanged.

## 9. Documentation to update

- `README.md` AI Vision section and `docs/diagrams/ai-vision.svg` caption.
- `AGENTS.md` and `CLAUDE.md` in sync: architecture line for detection, Xcode 27 path in build instructions, new `vision-eval` target.
- `AUTOGRAM_ZAKO_MODULE_SPEC.md` lines 186-192 and 268-280 corrected to describe the implemented pipeline rather than the earlier CoreML aspiration, with phase C stated as the follow-up.
- This spec and the implementation plan.

## 10. Phase C hand-off

When the bank holds at least a few hundred positives per common kind, export the dataset, train `MLObjectDetector`, and add a `CoreMLCandidateSource` running through `CoreMLRequest`. The candidate and classifier protocols are designed so that step adds a source without changing the pipeline shape.
