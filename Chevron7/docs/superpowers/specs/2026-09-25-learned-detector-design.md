# Learned security-element detector (step C)

Status: proposed, not started. Prepared 2026-09-25 after the review-learning fixes (`f6717b3f`, `c78f31bd`).

## Problem

The example bank only relabels boxes that the fixed candidate sources propose (built-in heuristics, contours, saliency). It never adds a box. On a new document the detector therefore keeps proposing the same wrongly shaped regions: a union of binding cord, wax seal and stamp, or fragments of a stamp. A reviewer's hand-drawn boxes teach nothing about *where* elements are. Steps A and B fixed the same document and the same crop. Step C is about new documents.

The Create ML export (`CreateMLExporter`) already writes complete page reviews in the object-detector format, with document-level `splits.json`. Nothing trains a model from it and nothing loads a model back.

## Goal

Chevron7 trains an object detector on the reviewer's own complete page reviews, on the Mac, in the background, and uses it as one more candidate source. The detector only proposes: every box still goes through the kNN / Foundation Model classifier and the human review. A model becomes active only when it measurably beats the current detector on held-out pages.

Non-goals: shipping a pretrained model with the app, cloud training, replacing the classifier, and any change to what a reviewer must confirm.

## Feasibility (checked)

- `import CreateML` builds against the Xcode 27 SDK. `MLObjectDetector.train(trainingData: .directoryWithImagesAndJsonAnnotation(at:), annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center), parameters: .init(algorithm: .transferLearning(.objectPrint(revision: 1))))` typechecks and returns an `MLJob`, so training can run inside the app with progress and cancellation. The exporter's `annotations.json` already uses pixel units, a top-left origin and centre anchors.
- The app is not sandboxed, so training data and models can live next to the bank in `~/Library/Application Support/Chevron7/VisionBank/models/`.
- Not verified yet: training time and memory on real page counts, and whether Create ML accepts pages with empty annotation lists (reviewed pages without elements). Phase 0 answers both.

## Data reality

On 2026-09-25 the reviewer's bank held 77 crop decisions from two sample documents and only **one** complete page review. An object detector cannot learn from that. The feature must say so plainly and wait: a model is trained only when the data gate below is met. The practical consequence is that "Označiť stranu ako skontrolovanú" becomes the step that feeds learning, and the UI should say that.

## Design

### Components (all in `Chevron7Kit/VisionAI/Learning/` unless noted)

1. **`DetectorTrainingGate`** decides whether a training run is due:
   - learning on (`AppSettings.learnFromReviews`) and the new setting `trainDetectorAutomatically` on;
   - at least 40 complete reviewed pages from at least 8 distinct documents, and at least 15 boxes per label that is to be trained (labels below the threshold are left out of the model rather than trained on noise);
   - at least 10 new or changed complete page reviews since the last run;
   - the last run is more than 24 hours old.
   All numbers are starting points, to be tuned in phase 0.
2. **`DetectorTrainer`** exports a fresh dataset with `CreateMLExporter`, builds the train set from the `train` partition only, runs `MLObjectDetector.train` with transfer learning, writes `models/candidate-<UUID>/Detector.mlmodel`, compiles it (`MLModel.compileModel(at:)`) and hands it to the evaluator. The export folder is deleted after the run. Cancellable through the `MLJob`.
3. **`DetectorPromotion`** scores the candidate against the currently active configuration on the `validation` and `test` partitions with `DetectionEvaluator.score` (IoU 0.4, the `vision-eval` default). The candidate is promoted only if mean recall across trained labels rises by at least 0.05 while precision does not drop by more than 0.02. Otherwise it is discarded and the reason is logged. The previous model is kept for one-click rollback.
4. **`LearnedCandidateSource: CandidateSourcing`** (new `CandidateSource.learned`) loads the active compiled model once per detection run and runs it through Vision (`VNCoreMLRequest`, recognized-object observations) on the already rendered page image. Each observation becomes a `DetectionCandidate` with `kindHint` from its top label and `hintConfidence` from its confidence. The boxes go through `CandidateMerger`, `CandidateQualityFilter` and `TwoStageClassifier` like any other candidate, so bank decisions (including exact-match rejections) still apply. `prioritized` should rank `.learned` candidates first for the Foundation Model budget.
5. **Scheduling (`Chevron7App`)**: a low-priority task started after the ZaKo flow finishes a conversion or a page review changes. It is never started in `--web-signing` accessory mode, pauses on battery power or thermal pressure (`ProcessInfo.thermalState`), and runs at most one job at a time.
6. **Audit**: `LayeredDetectionProvider.identifier` adds `learned(<model id>)` when the source is active, so `SecurityReviewStamp` records exactly which model proposed the boxes. The model id is the SHA-256 of the model's `Detector.mlmodel`.

### Settings (Learning card)

- Toggle "Automaticky trénovať detektor z mojich kontrol" (default off in the first release, on once phase 0 numbers are known).
- Status line: "Skontrolované strany: N z 40 potrebných", last training time and result ("Nový model aktivovaný: zachytí 78 % prvkov namiesto 61 %" or "Model nebol lepší, ponechaný predchádzajúci").
- Buttons "Trénovať teraz" (ignores the 10-new-pages and 24-hour rules, not the data gate) and "Vrátiť predchádzajúci model".
- Deleting the bank also deletes all models.

### Data flow

```
page review saved (reviewed-pages.json)
  -> DetectorTrainingGate (enough new data?)
  -> DetectorTrainer (export train split -> MLObjectDetector.train -> compile)
  -> DetectorPromotion (score on validation + test vs active)
  -> models/active -> LearnedCandidateSource in the next detection run
```

## Phases

0. **Spike (half a day)**: a `vision-train` executable next to `vision-eval` that trains from an exported dataset and prints time, memory and per-label metrics. Run it on the sample documents and on a synthetic set of at least 40 pages to set the gate numbers and check empty-annotation pages. Stop here if training a useful model takes more than about 10 minutes on the Mac Studio.
1. `LearnedCandidateSource` with a model loaded from a path; tests with a tiny fixture model trained in the spike; `vision-eval --model <path>`.
2. `DetectorTrainer` and `DetectorPromotion` with tests on a fixture dataset (promotion rules, rollback, cancellation, no writes outside the bank directory: `RealStorageGuard` applies).
3. Gate, scheduling and Settings UI.
4. Documentation: `security-element-training.md`, CLAUDE.md / AGENTS.md, and website claims only once shipped (PRODUCT.md rule).

## Risks

- **Too little data** for months in real use. Mitigated by the gate and the status line; the feature does nothing until it can help.
- **Overfitting to one office's documents** (the same letterhead, stamp and binding). Document-level splits keep the evaluation honest; promotion requires a gain on unseen documents.
- **Legal record**: the model only proposes. Every box still needs confirmation, and the stamp names the model, so a later audit can tell which detector suggested what.
- **Resource use**: training is capped to one background job, paused on battery and thermal pressure.

## Open questions for the owner

1. Default of the training toggle in the first release: off (recommended until phase 0 numbers exist) or on?
2. Are 40 reviewed pages from 8 documents an acceptable wait before anything happens?
3. Should the Settings status nudge the reviewer to mark pages reviewed ("Označiť stranu ako skontrolovanú" feeds learning), or stay silent?
