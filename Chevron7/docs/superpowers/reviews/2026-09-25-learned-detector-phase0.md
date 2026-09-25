# Phase 0 findings: on-device detector training (2026-09-25)

## Verdict: GO (at the time boundary on this machine, not over it)

Three runs on 34 train pages (2, 10 and 50 iterations) all took 531 to 569 s
wall time with 0.8 to 0.9 GB peak RSS on the Mac Studio below. Training time
is a fixed cost per page (feature extraction and setup, about 16 s/page):
the iteration budget changes nothing measurable across a 25x range, so a
representative 50-iteration training is established at about 9.5 minutes.
Extrapolated first training (40 pages): about 11 minutes on this M1 Max,
less on newer Apple silicon. Memory is a non-issue. Create ML accepts
reviewed pages with empty annotation lists without any error.

## Hardware

- Mac Studio (Mac13,1), Apple M1 Max, 32 GB RAM, macOS 27.0 (26A428), Xcode 27.
- On mains power, only a terminal and an editor besides the training process.
- This is the slower end of what the target offices have: a newer Mac Studio
  trains the same job faster, an older MacBook Air slower. The first in-app
  time estimate must say so.

## Dataset (synthetic: timing and memory only)

- 44 pages in 13 documents: train 34 (2 empty), validation 5 (1 empty),
  test 5 (1 empty). Page PNGs 1200x1800, the same size the exporter writes.
- All 40 annotated pages are affine and contrast variants of ONE really
  reviewed page (Ukazkova_zapisnica.pdf: 6 boxes, 5 labels: bindingCord,
  handwrittenSignature x2, officialStamp, initial, waxSeal). The train split
  holds 192 boxes (32 annotated pages of 6); the whole synthetic set 240.
  The 4 empty pages are variants of the second sample with `annotations: []`.
- Variants: rotation +-3 deg, scale 0.96-1.04, shift +-20 px, contrast and
  brightness +-8 percent, deterministic seed. Boxes transformed through
  corners plus axis-aligned clipping; a check script confirmed every box
  inside the image and none degenerate.
- Accuracy numbers from this set say NOTHING about real documents: the model
  saw the same content 40 times. Only wall time and peak RSS are reported
  as findings.

## Measured

Algorithm `transferLearning(objectPrint(revision: 1))`, 1200x1800 pages:

| run | pages (train) | iterations | wall time | s/page | s/page/iter | peak RSS | model file |
|-----|---------------|------------|-----------|--------|-------------|----------|------------|
| smoke | 34 | 2 | 569 s | 16.7 | 8.4 | 0.8 GB | 7.1 MB |
| main | 34 | 10 | 531 s | 15.6 | 1.6 | 0.9 GB | 7.1 MB |
| representative | 34 | 50 | 563 s | 16.6 | 0.3 | 0.8 GB | 7.1 MB |

- Compile plus scoring of 10 held-out pages: about 4 s.
- Cost model: fixed about 16 s/page on this M1 Max, marginal cost per
  iteration below noise from 2 to 50 iterations. Cost scales with pages, not
  iterations: a bank grown to 100 pages retrains in about 25 minutes here,
  so the estimate range must be recomputed from the page count, not fixed.
- Extrapolated first training (40 pages): about 40/34 x 550 s = about 650 s,
  roughly 10 to 11 minutes on this M1 Max. Proposed first estimate for the
  workflow: "približne 8 až 15 minút" (this machine plus margin for real
  data spread and slower or faster Macs; recomputed from the page count and
  recalibrated after the first run on the reviewer's own Mac, per the spec).

## Empty pages

- Create ML parsed and trained on a train split containing 2 pages with
  `annotations: []` with no error and no warning; validation and test splits
  with 1 empty page each scored normally.
- Whether empty pages help or hurt the model cannot be told from synthetic
  data. The exporter keeps including them (a reviewed empty page is the only
  way the model learns "nothing here"), and promotion on held-out documents
  will reject a model they damage.

## Accuracy (illustrative only, synthetic data)

- The 2-iteration model spams boxes (161 predictions on 5 validation pages),
  precision near zero. Expected from an untrained model.
- The 10-iteration model memorised the repeated stamp (officialStamp recall
  1.00 on copies of the same page) and misses the rest. The 50-iteration
  model predicts far fewer boxes (24 on validation) with the same recall
  pattern. Training converges toward restraint; on what, only real data
  can say. All of this proves the score pipeline discriminates; it proves
  nothing about real documents.
- Scoring runs through the compiled model over Vision (`VNCoreMLRequest`)
  and `DetectionEvaluator` at IoU 0.4, the same path phase 1 will use.

## Tool issues found and fixed (not Create ML)

1. A Combine `sink` writing to MainActor-isolated top-level vars traps with
   SIGTRAP (`_dispatch_assert_queue_fail`). Fix: `@Sendable` closures plus
   `nonisolated(unsafe)` handoff behind a semaphore.
2. `String(format: "%-22s", swiftString)` traps in `strlen`. Fix: `%@`.
   Lesson for phase 2: no `%s` with Swift strings in `DetectorTrainer` logs.

## Proposed thresholds (spec starting points, kept)

- First training: 40 complete reviewed pages from 8 distinct documents.
  Measured scale (34 pages) matches; document diversity (8) is NOT validated
  by this spike (all synthetic pages share one source) and stays a judgment
  call until real multi-office data exists.
- Label trained only with at least 15 boxes. Not validated either (synthetic
  labels have 40 to 80 boxes); kept as a noise guard, to be tuned after the
  first real trainings.
- Retraining offer after 20 new or changed complete page reviews. A retrain
  on the same scale costs the same about 10 minutes; as the bank grows past
  the gate, cost grows about 16 s/page on this machine, which the estimate
  range must reflect (see above).
- Promotion rule unchanged: recall up by at least 0.05, precision down by at
  most 0.02, on held-out documents.

## What phase 0 did not answer

- Real accuracy on real held-out documents (needs real reviewed pages,
  months away at the current 1 complete review).
- Exact per-Mac first estimate (recalibrates itself after the first run).
- Thermal throttling and battery behaviour (phase 3 workflow concern).

## Spike artefacts

- `vision-train` target (`Chevron7/Sources/vision-train/`): trains the train
  split, compiles, scores validation and test. `--model` rescores without
  retraining. Kept in the branch for phase 1 fixture work.
- `VisionTrainSplit` (`Chevron7Kit/VisionAI/Learning/`) plus
  `VisionTrainSplitTests`: partition helpers shared with the future trainer.
- Synthetic dataset builder: throwaway PIL script in scratch (not committed);
  method described above. The 44-page dataset itself is not committed.
- Owner bank untouched: the spike only READ the reviewed page and two page
  PNGs; all output went to `/tmp/chevron7-phase0/`.
