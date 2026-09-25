# Handoff prompt: learned security-element detector (step C)

Prompt for the agent that implements step C. Paste everything below the line as its first message. Spec: `Chevron7/docs/superpowers/specs/2026-09-25-learned-detector-design.md`. The implementation plan does not exist yet: the agent writes it after phase 0 and the owner's approval.

---

You are implementing "step C" of Chevron7: a security-element detector that the app trains on the reviewer's own page reviews. Chevron7 is a native macOS SwiftUI app for Slovak qualified signatures and guaranteed conversion (ZaKo). Repository: /Users/Magneto/PROJECTS/Chevron7 (GitHub originalmagneto/chevron7), base branch main at b5b705ba or later.

## Read first, completely

1. `CLAUDE.md` in the repo root (`AGENTS.md` is an identical copy). Its rules bind you. In particular: never use em dashes in any text; keep CLAUDE.md and AGENTS.md in sync; English for code, comments and docs; Slovak for user-facing strings; Xcode 27 at /Applications/Xcode.app only (prefix every build and test with `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"`); tests must never touch `~/Library/Application Support/Chevron7` or `~/Library/Caches/Chevron7` (`RealStorageGuard` fails them, use `makeSettingsStore()` and temporary directories).
2. The spec, your source of truth: `Chevron7/docs/superpowers/specs/2026-09-25-learned-detector-design.md`. The "Owner decisions (2026-09-25)" section is final: no automatic training; training starts only from a separate workflow the reviewer opens and confirms, after the app offers it once enough pages are reviewed, with a time estimate and instructions; the app teaches the reviewer (educational, marketing tone) that marking pages reviewed ("Označiť stranu ako skontrolovanú") feeds learning.
3. `Chevron7/docs/security-element-training.md`: how the example bank, `reviewed-pages.json`, the Create ML export and the recent learning fixes work.
4. The code you will build on, in `Chevron7/Sources/Chevron7Kit/VisionAI/`: `LayeredDetectionProvider.swift`, `Candidates/` (`CandidateSourcing`, `DetectionCandidate`, `CandidateMerger`, `CandidateQualityFilter`), `Classification/` (`TwoStageClassifier`, `FeaturePrintClassifier`), `Learning/` (`ExampleBank`, `ExampleBankRecorder`, `CreateMLExporter`, `ReviewedPageRecall`), `Evaluation/DetectionEvaluator.swift`; the `vision-eval` target (`Sources/vision-eval`); the app side in `Sources/Chevron7App`: `ZakoSessionStore.swift`, `Views/AnalysisCanvasView.swift` (review step), `Views/SettingsView.swift` (`LearningDatasetCard`), `Views/AuthorizeDoneViews.swift` (Done screen), `DetectionSourceLabel.swift`.

## Context you cannot derive from the code

- Recent fixes you must not regress (commits `f6717b3f`, `c78f31bd`): the recorder embeds crops at the detector render width (760 px); an exact bank match (feature print distance <= 0.05) decides alone; reopening a document recalls its complete page reviews; re-running the AI never deletes bank entries. `ReviewLearningTests` and `ZakoReviewRecallTests` guard this.
- Checked on 2026-09-25: this compiles against the Xcode 27 SDK: `MLObjectDetector.train(trainingData: .directoryWithImagesAndJsonAnnotation(at:), annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center), parameters: .init(algorithm: .transferLearning(.objectPrint(revision: 1))))` returns an `MLJob`. The feature extractor case is `objectPrint`, not `scenePrint`. `CreateMLExporter` already writes pixel units, top-left origin, centre anchors. The app is not sandboxed.
- Data reality: the owner's real bank has 77 crop decisions from two sample documents and only one complete page review. Sample PDFs: `.impeccable/zako/Ukazkova_listina.pdf` and `.impeccable/zako/Ukazkova_zapisnica.pdf`. Never write to the owner's real bank. For phase 0 you may read it, or better, a copy in your scratch directory.

## How to work

- Work in a git worktree on a new branch (for example `feat/learned-detector`). Commit in small steps, messages ending with your co-author line. Do NOT merge to main or push without the owner's explicit approval: every feat/fix commit pushed to main triggers a public GitHub release (`.github/workflows/release.yml`).
- Test-driven: write the failing test first, see it fail for the right reason, then implement. Before claiming anything works, run the full suite (`swift test` from `Chevron7/`) and report the real numbers.
- Stop and ask the owner when the spec is silent or wrong, rather than guessing. Ask in Slovak; the owner is Marián (they/them in English text).

## Phase 0: spike, then stop

Goal: measure whether in-app training is practical and set the thresholds.

1. Add an executable target `vision-train` next to `vision-eval`: it takes an exported dataset folder (`CreateMLExporter` output with `annotations.json` and `splits.json`), trains on the train partition with `MLObjectDetector.train`, compiles the model, scores it on validation and test with `DetectionEvaluator` (IoU 0.4), and prints wall time, peak memory, iterations and per-label precision and recall.
2. Build a dataset large enough to measure time and memory: at least 40 pages. With two real documents you will need augmented pages (render the sample PDFs with shifts, scale, small rotation and contrast changes, transforming the boxes accordingly), clearly marked as synthetic. Say plainly that accuracy numbers from this set are not meaningful; only timing and memory are.
3. Check whether Create ML accepts reviewed pages with an empty annotation list.
4. Write the findings to `Chevron7/docs/superpowers/reviews/<date>-learned-detector-phase0.md`: hardware, dataset size, training time per page and iteration, memory, empty-page behaviour, and proposed values for the thresholds in the spec (40 pages, 8 documents, 15 boxes per kind, 20 new pages for retraining) and for the first time estimate.
5. STOP. Report to the owner in Slovak: the numbers, a go or no-go recommendation (the spec says stop if a useful model takes more than about 10 minutes on the Mac Studio), and the proposed thresholds. Wait for approval.

## After approval

- Update the spec with the approved thresholds, then write the implementation plan to `Chevron7/docs/superpowers/plans/<date>-learned-detector.md` (bite-sized TDD tasks, exact files, test names), following the spec's phases 1 to 5: `LearnedCandidateSource` and `vision-eval --model`; `DetectorTrainer` and `DetectorPromotion`; readiness report, estimate, training workflow window, Done-screen banner, Settings card; education copy; documentation.
- Show the plan to the owner before implementing it. Then implement phase by phase, stopping after each phase with a short Slovak summary and the test results.
- Before merging: all tests green, CLAUDE.md and AGENTS.md updated identically (the VisionAI and Learning bullets), `docs/security-element-training.md` updated, `Chevron7/scripts/check-rename-boundary.sh` passing, and the Slovak copy reviewed by the owner. Website claims only after the feature ships (`PRODUCT.md`).

## Non-negotiables from the spec

- The learned detector only proposes candidates. Every box still goes through `CandidateMerger`, `CandidateQualityFilter` and `TwoStageClassifier` (so bank rejections still apply) and through the human review.
- A new model becomes active only if it beats the active one on held-out documents (recall up by at least 0.05, precision down by at most 0.02). Keep the previous model for rollback.
- Nothing leaves the Mac. Training never runs in `--web-signing` accessory mode, runs one job at a time at utility priority, pauses on thermal pressure and asks again on battery.
- `LayeredDetectionProvider.identifier` names the active model (`learned(<sha256>)`) so `SecurityReviewStamp` records which detector suggested the boxes.
