# Learned security-element detector (step C)

Status: proposed, not started. Prepared 2026-09-25 after the review-learning fixes (`f6717b3f`, `c78f31bd`). Owner decisions of 2026-09-25 are folded in (see the end).

## Problem

The example bank only relabels boxes that the fixed candidate sources propose (built-in heuristics, contours, saliency). It never adds a box. On a new document the detector therefore keeps proposing the same wrongly shaped regions: a union of binding cord, wax seal and stamp, or fragments of a stamp. A reviewer's hand-drawn boxes teach nothing about *where* elements are. Steps A and B fixed the same document and the same crop. Step C is about new documents.

The Create ML export (`CreateMLExporter`) already writes complete page reviews in the object-detector format, with document-level `splits.json`. Nothing trains a model from it and nothing loads a model back.

## Goal

Chevron7 trains an object detector on the reviewer's own complete page reviews, on the Mac, and uses it as one more candidate source. Training never starts on its own: once there is enough data, the app offers it in a dedicated workflow that estimates the time, explains what will happen and starts it only on the reviewer's go-ahead. The detector only proposes: every box still goes through the kNN / Foundation Model classifier and the human review. A model becomes active only when it measurably beats the current detector on held-out pages.

Non-goals: shipping a pretrained model with the app, cloud training, replacing the classifier, and any change to what a reviewer must confirm.

## Feasibility (checked)

- `import CreateML` builds against the Xcode 27 SDK. `MLObjectDetector.train(trainingData: .directoryWithImagesAndJsonAnnotation(at:), annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center), parameters: .init(algorithm: .transferLearning(.objectPrint(revision: 1))))` typechecks and returns an `MLJob`, so training can run inside the app with progress and cancellation. The exporter's `annotations.json` already uses pixel units, a top-left origin and centre anchors.
- The app is not sandboxed, so training data and models can live next to the bank in `~/Library/Application Support/Chevron7/VisionBank/models/`.
- Not verified yet: training time and memory on real page counts, and whether Create ML accepts pages with empty annotation lists (reviewed pages without elements). Phase 0 answers both.

## Data reality

On 2026-09-25 the reviewer's bank held 77 crop decisions from two sample documents and only **one** complete page review. An object detector cannot learn from that. The feature must say so plainly and wait: a model is trained only when the data gate below is met. The practical consequence is that "Označiť stranu ako skontrolovanú" becomes the step that feeds learning, and the app says so openly (see "Education").

## Design

### Components (all in `Chevron7Kit/VisionAI/Learning/` unless noted)

1. **`DetectorTrainingReadiness`** (pure, tested) turns the bank into a readiness report: reviewed pages, distinct documents, boxes per label, pages new since the last training, which labels would be trained and which left out, and whether an offer is due. An offer is due when:
   - learning is on (`AppSettings.learnFromReviews`) and the reviewer has not turned offers off;
   - first training: at least 40 complete reviewed pages from at least 8 distinct documents;
   - later trainings: at least 20 new or changed complete page reviews since the last run;
   - the reviewer has not answered "Neskôr" in the last 7 days.
   A label is trained only with at least 15 boxes; below that it is left out of the model rather than trained on noise, and the report names it. All numbers are starting points, to be tuned in phase 0.
2. **`DetectorTrainingEstimate`** predicts the duration before the reviewer commits: the first time from the phase 0 throughput measured on Apple silicon (seconds per page and iteration), afterwards from this Mac's own last run, stored with the model. It is shown as a range ("približne 6 až 10 minút") and recalibrated after every run.
3. **`DetectorTrainer`** exports a fresh dataset with `CreateMLExporter`, builds the train set from the `train` partition only, runs `MLObjectDetector.train` with transfer learning, writes `models/candidate-<UUID>/Detector.mlmodel`, compiles it (`MLModel.compileModel(at:)`) and hands it to the evaluator. The export folder is deleted after the run. Cancellable through the `MLJob`.
4. **`DetectorPromotion`** scores the candidate against the currently active configuration on the `validation` and `test` partitions with `DetectionEvaluator.score` (IoU 0.4, the `vision-eval` default). The candidate is promoted only if mean recall across trained labels rises by at least 0.05 while precision does not drop by more than 0.02. Otherwise it is discarded and the reason is logged. The previous model is kept for one-click rollback.
5. **`LearnedCandidateSource: CandidateSourcing`** (new `CandidateSource.learned`) loads the active compiled model once per detection run and runs it through Vision (`VNCoreMLRequest`, recognized-object observations) on the already rendered page image. Each observation becomes a `DetectionCandidate` with `kindHint` from its top label and `hintConfidence` from its confidence. The boxes go through `CandidateMerger`, `CandidateQualityFilter` and `TwoStageClassifier` like any other candidate, so bank decisions (including exact-match rejections) still apply. `prioritized` should rank `.learned` candidates first for the Foundation Model budget.
6. **Training workflow (`Chevron7App`, see below)** owns the only way a training run starts.
7. **Audit**: `LayeredDetectionProvider.identifier` adds `learned(<model id>)` when the source is active, so `SecurityReviewStamp` records exactly which model proposed the boxes. The model id is the SHA-256 of the model's `Detector.mlmodel`.

### Training workflow

A separate window (`DetectorTrainingWindow`, a regular `Window` scene like Settings), never a sheet over a conversion in progress.

**When it is offered.** The readiness report is checked when a page review is saved. When an offer becomes due, the app does not interrupt: it shows a quiet banner on ZaKo's Done screen after the conversion ("Máte dosť skontrolovaných strán na natrénovanie vlastného detektora.") and a badge on the Learning card in Settings. Nothing appears during analysis, review, clause or authorization. The banner offers "Pozrieť" (opens the workflow), "Neskôr" (7 days) and "Nepripomínať" (turns offers off; the workflow stays reachable from Settings).

**Steps.**
1. *Čo sa stane*: what training does and does not do, in plain Slovak: the detector learns from the reviewer's own checked pages, only on this Mac, nothing leaves the computer, it will only ever suggest boxes and every box still needs confirmation. Shows the readiness report: pages, documents, per-kind counts, kinds that will be trained and kinds left out for lack of examples ("Slepotlač: 3 príklady, potrebných 15").
2. *Odhad a pokyny*: the time estimate and instructions: keep the Mac on power, Chevron7 may stay open in the background and conversions can continue, closing the app cancels the run and nothing is lost, the Mac may be slower meanwhile. Button "Spustiť trénovanie".
3. *Priebeh*: phases (príprava dát, trénovanie, overenie na dokumentoch, ktoré model nevidel) with the `MLJob` progress and remaining time, "Zrušiť". Runs at utility priority and pauses on thermal pressure (`ProcessInfo.thermalState`); on battery it asks before continuing. Never started in `--web-signing` accessory mode; at most one run at a time.
4. *Výsledok*: old versus new on held-out documents in words and numbers ("Nový detektor našiel 78 % prvkov, doterajší 61 %; nesprávnych návrhov o 1 % viac"), then either "Používať nový detektor" (default when promotion rules pass) or the explanation why the previous one stays. A notification (`UNUserNotificationCenter`) tells the reviewer when a run finishes while the window is closed.

**Settings (Learning card).** Offers on or off, readiness progress ("Skontrolované strany: 12 z 40 pre prvé trénovanie"), the active model with its date and measured gain, "Otvoriť trénovanie…" (always available; with too little data it explains what is missing instead of starting), "Vrátiť predchádzajúci detektor". Deleting the bank also deletes all models.

### Education

The reviewer should understand that careful review pays off, and the app should show it working. Copy is educational first; the website repeats it only once the feature ships (PRODUCT.md rule).

- **Review step**: under "Označiť stranu ako skontrolovanú" a one-line hint while learning is on: "Každá skontrolovaná strana učí Chevron7 rozpoznávať vaše dokumenty." A first-use popover explains the three layers once: the same crop is remembered right away, the same document brings back the review, and enough checked pages train a detector for new documents.
- **Settings Learning card**: the readiness progress bar as a visible goal, plus a short "Ako sa Chevron7 učí" explainer with the three layers.
- **Done screen**: after a conversion with a newly reviewed page, a quiet line "Strana pribudla do učenia (12 z 40)". Nothing louder until an offer is due.
- **After a successful training**: the result screen and later the findings list name the learned detector as a source ("váš detektor"), so the reviewer sees the effect in daily work.
- **Website (after release)**: a section on the app learning the office's own documents on the device, with no data leaving the Mac and every suggestion still confirmed by the advocate.

### Data flow

```
page review saved (reviewed-pages.json)
  -> DetectorTrainingReadiness (offer due?)
  -> banner on the Done screen / badge in Settings
  -> training workflow: report -> estimate and instructions -> reviewer starts it
  -> DetectorTrainer (export train split -> MLObjectDetector.train -> compile)
  -> DetectorPromotion (score on validation + test vs active) -> result screen
  -> models/active -> LearnedCandidateSource in the next detection run
```

## Phases

0. **Spike (half a day)**: a `vision-train` executable next to `vision-eval` that trains from an exported dataset and prints time, memory and per-label metrics. Run it on the sample documents and on a synthetic set of at least 40 pages to set the gate numbers and check empty-annotation pages. Stop here if training a useful model takes more than about 10 minutes on the Mac Studio.
1. `LearnedCandidateSource` with a model loaded from a path; tests with a tiny fixture model trained in the spike; `vision-eval --model <path>`.
2. `DetectorTrainer` and `DetectorPromotion` with tests on a fixture dataset (promotion rules, rollback, cancellation, no writes outside the bank directory: `RealStorageGuard` applies).
3. Readiness report, estimate, training workflow window, Done-screen banner and Settings card.
4. Education copy in the review step, Settings and Done screen; Slovak copy reviewed by the owner.
5. Documentation: `security-element-training.md`, CLAUDE.md / AGENTS.md, and website claims only once shipped (PRODUCT.md rule).

## Risks

- **Too little data** for months in real use. Mitigated by the gate and the status line; the feature does nothing until it can help.
- **Overfitting to one office's documents** (the same letterhead, stamp and binding). Document-level splits keep the evaluation honest; promotion requires a gain on unseen documents.
- **Legal record**: the model only proposes. Every box still needs confirmation, and the stamp names the model, so a later audit can tell which detector suggested what.
- **Resource use**: training runs only after the reviewer starts it, one run at a time, at utility priority, paused on thermal pressure and confirmed again on battery.
- **Estimate wrong on the first run**: the range comes from phase 0 hardware, not this Mac. The first result recalibrates it, and the workflow says the first estimate is rough.

## Owner decisions (2026-09-25)

1. No automatic training in the first release.
2. Training is a separate workflow: once enough documents are reviewed, the app asks whether to train, estimates the time, gives instructions and starts it on the reviewer's go-ahead.
3. The app tells the reviewer that marking pages reviewed teaches the detector, with an educational and marketing tone.

## Still open

- The thresholds (40 pages, 8 documents, 15 boxes per kind, 20 new pages for retraining) until phase 0 measures real training.
- Final Slovak wording of the education copy.
