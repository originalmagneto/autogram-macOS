# Learned detector implementation plan (phases 1-5)

**Spec:** `Chevron7/docs/superpowers/specs/2026-09-25-learned-detector-design.md` (thresholds approved 2026-09-25)
**Phase 0 findings:** `Chevron7/docs/superpowers/reviews/2026-09-25-learned-detector-phase0.md` (GO)
**Branch:** `feat/learned-detector` (worktree `Chevron7-learned-detector`; phase 0 commits already there: `VisionTrainSplit`, `vision-train`, findings)

**Goal:** the app trains an object detector on the reviewer's own complete page reviews, on the Mac, and uses it as one more candidate source that only proposes. Every box still flows through `CandidateMerger`, `CandidateQualityFilter`, `TwoStageClassifier` and the human review. Stop after each phase with a short Slovak summary and the real test numbers. Do not merge or push without the owner's explicit approval.

## Global constraints

- Toolchain Xcode 27; every build and test needs `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"`, run from `Chevron7/`.
- English for code, comments and docs; Slovak for user-facing strings; no em dashes anywhere.
- TDD: failing test first, see it fail for the right reason, then implement. Full suite (`swift test`) green before every phase summary; report both bundles plus the sum (Kit 579 + App 251 = 830 at plan time).
- Tests never touch `~/Library/Application Support/Chevron7` or `~/Library/Caches/Chevron7` (`RealStorageGuard` fails them; use `makeSettingsStore()` and temporary directories).
- Commit after each green task with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer. Never commit to `main`.
- Must not regress commits `f6717b3f`, `c78f31bd` (`ReviewLearningTests`, `ZakoReviewRecallTests` guard them).
- No suite test trains a real CreateML model (about 9 minutes fixed cost each; `vision-train` covers that path manually). Everything around it is tested with stubs and fixture files.
- Phase 0 spike traps to avoid: Combine `sink` closures must be `@Sendable` with `nonisolated(unsafe)` handoff; no `%s` with Swift strings in `String(format:)` (use `%@`).

## Phase 1: LearnedCandidateSource and vision-eval --model

- [ ] **Task 1.1: `CandidateSource.learned` case**
  `Chevron7/Sources/Chevron7Kit/VisionAI/Candidates/DetectionCandidate.swift`: add `learned` to the enum. Nothing else changes; `sourceLabel` and `prioritized` (hinted-first) pick it up automatically.
  Tests (`Chevron7/Tests/Chevron7KitTests/LearnedCandidateSourceTests.swift`): `testLearnedSourceLabelRenders` (sources `[.learned]` labels `"learned"`).
- [ ] **Task 1.2: `LearnedCandidateSource` with an injectable predictor**
  New `Chevron7/Sources/Chevron7Kit/VisionAI/Candidates/LearnedCandidateSource.swift` (in `Candidates/`, next to `ContourCandidateSource`, not `Learning/`: it implements `CandidateSourcing` and belongs with the other sources). Contents: `LearnedPrediction` (box in bottom-origin normalized coords, label string, confidence); `LearnedCandidateSource` (`source` `.learned`, `modelID`, `predict: @Sendable (CGImage) throws -> [LearnedPrediction]`); `candidates(pageImage:pageIndex:)` maps predictions through `VisionTrainSplit.kind(forTrainingLabel:)`, drops unknown labels, emits `DetectionCandidate(sources: [.learned], kindHint:, hintConfidence:)`. Same file: `LearnedModelLoader.load(at:)` (accepts a compiled `.mlmodelc` or a `.mlmodel` it compiles to a temp dir) and `coreMLPredictor(model: VNCoreMLModel)` production closure (per-call `VNCoreMLRequest`, Vision bounding boxes pass through as bottom-origin normalized rects).
  Tests (`LearnedCandidateSourceTests`): `testMapsLabelsToKindHints`, `testDropsUnknownLabels`, `testSourceIsLearned`, `testLoaderRejectsMissingPath`. No committed model binary: tests inject canned predictions.
- [ ] **Task 1.3: provider wiring and model audit id**
  `LayeredDetectionProvider.swift`: `makeDefault(bank:useFoundationModel:learnedSource: LearnedCandidateSource? = nil)` appends the source to `extraSources`; `identifier` appends `learned(<modelID>)` (full SHA-256 of `Detector.mlmodel`) when a learned source is active, so `SecurityReviewStamp` names the model.
  Tests (`LearnedCandidateSourceTests` or `LayeredDetectionProviderTests` if it exists): `testIdentifierNamesActiveModel`, `testIdentifierWithoutLearnedSourceUnchanged`.
- [ ] **Task 1.4: `vision-eval --model <path>`**
  `Chevron7/Sources/vision-eval/main.swift`: parse `--model`, load via `LearnedModelLoader`, pass into `makeDefault`. Manual verification (no commit): score the synthetic phase 0 dataset with the spike model (`/tmp/chevron7-phase0/main10/Detector.mlmodel`); expect the same numbers `vision-train --model` printed. Report the match in the phase summary.

## Phase 2: DetectorTrainer and DetectorPromotion

- [ ] **Task 2.1: train staging as a pure function**
  `Chevron7/Sources/Chevron7Kit/VisionAI/Learning/DetectorTrainer.swift`: `stageTrainDirectory(dataset: URL, trainImages: [String], trainAnnotations: [CreateMLImageAnnotation], to: URL)` copies images and writes the filtered `annotations.json` (the `vision-train` pattern, extracted so both use it; `vision-train` keeps its copy to stay a standalone spike).
  Tests (`DetectorTrainerTests`): `testStagingContainsOnlyTrainPartition`, `testStagingSkipsMissingImages` (or fails loudly: decide while writing the failing test; staged data must never silently drop pages).
- [ ] **Task 2.2: single-job guard with injected runner**
  Same file: `actor DetectorTrainingJob` with `run(_:)` executing one `@Sendable () async throws -> TrainedCandidate` closure at a time; a second concurrent start throws `busy`. `Task` cancellation is honoured at phase boundaries and cancels the `MLJob`. Production closure `trainProduction(bank:maxIterations:onProgress:)` holds the real path: `CreateMLExporter.export` to temp, stage, `MLObjectDetector.train` (`transferLearning(.objectPrint(revision: 1))`, explicit `maxIterations: 50`; phase 0 shows iterations are free, 50 is a representative budget), `@Sendable` sink plus semaphore handoff, write `models/candidate-<UUID>/Detector.mlmodel`, `MLModel.compileModel(at:)`, delete the export and staging folders. Thermal gate: refuse to start when `ProcessInfo.thermalState` is `.serious` or `.critical` (an `MLJob` has cancel but no suspend, so mid-run pressure cannot truly pause; on `.critical` during the run the job is cancelled and reported rather than promoted from a throttled run).
  Tests (`DetectorTrainerTests` with injected sleep/fail closures): `testSecondStartWhileRunningThrowsBusy`, `testCancellationAbortsRun`, `testFailingRunnerSurfacesError`.
- [ ] **Task 2.3: `LearnedModelScorer` shared by trainer and tools**
  New `Chevron7/Sources/Chevron7Kit/VisionAI/Learning/LearnedModelScorer.swift`: run a `VNCoreMLModel` over partition images and score with `DetectionEvaluator` at IoU 0.4 (extracted from the `vision-train` report path; `vision-train` keeps its copy).
  Tests (`LearnedModelScorerTests`): stub predictor over two fixture PNGs written to a temp dir, hand-computed TP/FP/FN asserted through `DetectionEvaluator.score`.
- [ ] **Task 2.4: `DetectorPromotion` decision (pure)**
  New `Chevron7/Sources/Chevron7Kit/VisionAI/Learning/DetectorPromotion.swift`: `decide(candidate:active:trainedLabels:) -> .promote(recallGain:precisionDelta:) / .keep(reason:)` implementing the spec rule (mean recall across trained labels up by at least 0.05, precision down by at most 0.02).
  Tests (`DetectorPromotionTests`): `testPromoteOnRecallGain`, `testKeepWhenPrecisionDropsTooMuch`, `testKeepWhenRecallGainTooSmall`, `testKeepWhenNoTrainedLabels`.
- [ ] **Task 2.5: `ModelRegistry` with rollback**
  Same file or `Learning/ModelRegistry.swift`: root at `<bank>/models/`; `promote(candidateURL:metadata:)` moves `active` to `previous` and the candidate to `active`; `rollback()` swaps back; `activeModelID()` returns the SHA-256 of `active/Detector.mlmodel`; metadata JSON (id, date, recall gain, precision delta, seconds per page, pages, iterations) feeds the Settings card and the estimate recalibration. Deleting the bank directory deletes models with it (nothing extra to implement; assert in test with a temp bank dir).
  Tests (`DetectorPromotionTests` or `ModelRegistryTests`): `testPromoteKeepsPreviousForRollback`, `testRollbackRestoresPrevious`, `testActiveIDIsSHA256OfModel`.
- [ ] **Task 2.6: manual end-to-end training proof**
  No commit: point a debug build at a COPY of a rich bank (or the synthetic set) and run one real in-app-style training through `trainProduction` plus promotion scoring; report wall time and peak RSS in the phase summary to confirm the app path matches the spike.

## Phase 3: readiness, estimate, workflow window, Done banner, Settings card

- [ ] **Task 3.1: `DetectorTrainingReadiness` (pure)**
  New `Chevron7/Sources/Chevron7Kit/VisionAI/Learning/DetectorTrainingReadiness.swift`: `report(reviewedPages:documents:boxesPerLabel:newSinceLastTraining:learnOn:offersEnabled:snoozedUntil:)` returns pages, documents, per-label counts, trained vs left-out labels (`>= 15` boxes) and `offerDue` (40 pages / 8 documents first run, 20 new reviews later, 7-day "Neskôr", offers off, learning off). Run state (`lastRunAt`, `secondsPerPage`, `snoozedUntil`) lives in `<bank>/models/training-state.json` (new `TrainingState` Codable plus round-trip test); the offers on/off switch is a new `AppSettings.detectorTrainingOffersEnabled` key (default true, following the `learnFromReviews` Codable pattern).
  Tests (`DetectorTrainingReadinessTests`): `testOfferDueAtGate` (40/8), `testNoOfferBelowGate` (39 pages, 7 documents), `testLabelLeftOutBelow15Boxes`, `testRetrainingNeeds20NewReviews`, `testSnoozeSuppressesOfferFor7Days`, `testOffersOffSuppressesOffer`, `testTrainingStateRoundTrip`.
- [ ] **Task 3.2: `DetectorTrainingEstimate` (pure)**
  New `Chevron7/Sources/Chevron7Kit/VisionAI/Learning/DetectorTrainingEstimate.swift`: first estimate from page count at 16 s/page (phase 0 M1 Max), later from stored `secondsPerPage`; renders a Slovak range ("približne 8 až 15 minút").
  Tests (`DetectorTrainingEstimateTests`): `testFirstEstimateFor40Pages`, `testRecalibratedEstimateUsesLastRun`, exact-string assertions.
- [ ] **Task 3.3: training workflow window**
  New `Chevron7/Sources/Chevron7App/Views/DetectorTrainingWindow.swift` plus `Window("Trénovanie detektora", id: DetectorTrainingWindow.id)` next to the Settings window in `Chevron7/Sources/Chevron7App/Chevron7App.swift:115` (and an opener like `OpenSettingsButton`). Four steps per spec (report, estimate plus instructions, progress with cancel, result with promote-or-keep explanation); view model drives `DetectorTrainingJob`, `LearnedModelScorer`, `DetectorPromotion` and `ModelRegistry`; `UNUserNotificationCenter` ping when the window is closed at finish. Guards: refuse to start in `--web-signing` accessory mode (`AppLaunchMode.current`, following `EZZKStatusChecker.shouldRun`); Low Power Mode asks again before continuing; thermal gate lives in the trainer. Verified by build plus manual smoke on a bank copy; no committed UI snapshot tests.
- [ ] **Task 3.4: Done-screen banner**
  `Chevron7/Sources/Chevron7App/Views/AuthorizeDoneViews.swift`: after a conversion, when a freshly computed readiness report says an offer is due, show the quiet banner with "Pozrieť" (opens the workflow window), "Neskôr" (7-day snooze in training state), "Nepripomínať" (turns the AppSettings switch off). Readiness is computed on appear from the bank (JSON read, async); nothing appears during analysis, review, clause or authorization.
- [ ] **Task 3.5: Settings Learning card**
  `LearningDatasetCard` in `Chevron7/Sources/Chevron7App/Views/SettingsView.swift:1278`: readiness progress ("Skontrolované strany: 12 z 40 pre prvé trénovanie"), active model with date and measured gain, "Otvoriť trénovanie…" (always available; explains what is missing when below gate), "Vrátiť predchádzajúci detektor" (registry rollback), offers on/off toggle. Manual smoke in the phase summary.

## Phase 4: education copy (Slovak, owner reviews before merge)

- [ ] **Task 4.1: review step, Settings, Done screen, findings naming**
  One-line hint under "Označiť stranu ako skontrolovanú" in `AnalysisCanvasView.swift` (visible while learning is on); first-use popover explaining the three layers (crop remembered, document recalled, detector trained); "Ako sa Chevron7 učí" explainer in the Learning card; quiet Done line "Strana pribudla do učenia (12 z 40)" after a conversion with a newly reviewed page; `DetectionSourceLabel.slovak` maps `"learned"` to "váš detektor" (test `testLearnedDetectorIsNamed` in `Chevron7/Tests/Chevron7AppTests/DetectionSourceLabelTests.swift`, following the existing cases). Final wording goes to the owner for review as its own commit; nothing merges before approval.

## Phase 5: documentation and merge gate

- [ ] **Task 5.1: docs and repo rules**
  `Chevron7/docs/security-element-training.md`: learned-detector section (training set construction from complete reviews, empty pages, splits, promotion rule, model registry layout, audit id). `CLAUDE.md` and `AGENTS.md` updated identically (VisionAI bullet: learned source; Learning bullet: trainer, promotion, registry, readiness). Run `Chevron7/scripts/check-rename-boundary.sh` (new files carry no product name; the script must pass). No website changes (`PRODUCT.md`: claims only after the feature ships). Final full suite plus the merge-gate checklist from the handoff (all green, docs done, Slovak copy approved) in the summary; merge only on explicit owner approval.

## Out of scope

Pretrained model shipped with the app; cloud training; replacing the kNN / Foundation Model classifier; any change to what a reviewer must confirm; true mid-run training suspend (CreateML `MLJob` has cancel only); website claims before release; per-account locks or throughput work (single job at a time is the design).

## Open questions for the owner (answer at plan review, blocking details not the direction)

1. `LearnedCandidateSource` in `Candidates/` next to the other sources instead of the spec's `Learning/`: placement only, behaviour identical. Veto to move it.
2. Thermal pressure: gate the start plus cancel-and-report on `.critical` mid-run (a true pause does not exist in CreateML). Accept, or keep runs fully manual-guarded?
3. In-app training budget: explicit `maxIterations: 50` (phase 0: iterations are free, 50 is representative). Accept, or prefer the CreateML default?
4. No fixture model binary committed; tests use the stub predictor and `vision-eval --model` is verified manually with a spike model. Accept?
