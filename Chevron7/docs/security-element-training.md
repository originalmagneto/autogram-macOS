# Security-element training data

## Two independent records

`bank.json` contains individual crop decisions and feature vectors for local example matching. A collection of accepted and rejected crops does not prove that every object on a page was reviewed.

`reviewed-pages.json` stores complete page snapshots separately. Older banks remain readable, but their pages become eligible for detector export only after an explicit complete review. A snapshot contains document SHA-256, page index, canonical visual boxes, review time and detector version. Empty reviewed pages have an empty box list and a real rendered page image.

The caller must pass every element belonging to the page to `ExampleBankRecorder.recordReviewedPage(document:documentData:pageIndex:elements:)`. Pending decisions, elements from another page, unsupported confirmed visible kinds and invalid confirmed scan boxes prevent the snapshot from being saved. A confirmed physical-original observation also excludes the whole page: without a scan box, omitting it could mislabel a visible object as background. The recorder invalidates any previous snapshot before rejecting the page and never fabricates a positive crop. A rejected candidate is background, never an object rectangle.

Finish queued crop recording before saving a complete page. Crop additions, replacements and removals invalidate affected page snapshots. The application must also call `ExampleBank.invalidateReviewedPage(documentSHA256:pageIndex:)` on review or annotation edits, including edits without a stored crop. For a non-rejected physical observation, exclude and invalidate both its original page and its explicitly referenced output page, including references to another page. A new complete review is eligible only when every visible object has a supported scan box.

## How a review reaches the next detection

The detector renders pages at `LayeredDetectionProvider.defaultRenderTargetWidth` (760 px). `ExampleBankRecorder` embeds each crop from a render at that same width (`featureRenderWidth`), while the stored page and crop PNGs stay at 1200 px for export. The widths must match: a feature print of the same box taken from a 1200 px render lies 0.2 to 0.55 away from the 760 px one, as far as two different elements. Entries recorded before this change keep their 1200 px vectors and only vote.

`FeaturePrintClassifier.vote` treats a bank example within `exactMatchDistance` (0.05) as an earlier review of the very same crop. When every such example agrees, that decision is final (`ElementJudgement.isExactMatch`, source `kNN(exact)`), so one rejection keeps a suggestion from coming back and one correction relabels it, however few examples back it and whatever the on-device model says. Conflicting exact matches fall back to the ordinary vote, which still needs three agreeing neighbours. The bank has no distance cutoff for unknown crops: on the reviewer's bank of September 2026, crops of one kind from different documents (up to 1.16) were as far apart as crops of different kinds (5th percentile 0.95), so no threshold separated them.

Crop decisions only relabel boxes the candidate sources propose; they never add a box. Opening a document whose page has a complete snapshot in `reviewed-pages.json` (same SHA-256) replaces detection on that page with the reviewer's boxes (`ReviewedPageRecall`, source `reviewedPage`), each a pending suggestion because every conversion needs its own review; with learning off nothing is recalled. "Znova analyzovať AI" always detects afresh. Replacing the suggestions after an analysis is not a reviewer's edit: it neither removes bank entries nor invalidates stored page reviews.

## Visual labels

Supported visual training labels come from `SecurityElement.Kind.visualKind` and `trainingLabel`: `handwrittenSignature`, `officialStamp`, `embossedSeal`, `initial`, `bindingCord`, `securityTape`, `waxSeal`, `watermark`, `securityPattern`, `opticallyVariable`, `securityFoil` and `lamination`. A certified signature uses the `handwrittenSignature` image class; a round official stamp uses `officialStamp`. Certification and physical binding assessments remain human observations. `other` and `permanentBinding` have no visual training class. A confirmed unsupported visible object excludes its whole page from detector export so it cannot silently become background. Exportable labels do not imply that the current automatic detector proposes every class.

The crop recorder removes an earlier positive crop when its element becomes physical-only or unsupported. Rejected candidates with valid scan regions remain negative examples for crop matching. Because any change to an element removes its crop from the bank, the review step locks a rejected element: `ZakoSessionStore` refuses to move, resize, refine, duplicate, re-page, re-kind, re-describe or delete it, and the canvas never hit-tests it. Only returning it to review ("Vrátiť na kontrolu") forgets the negative. Deleting a pending AI suggestion rejects it instead, so a detector mistake always becomes a negative example; only hand-drawn elements and AI findings already confirmed are deleted, and a deleted element leaves no example behind. A real element with a skewed box should be moved and confirmed (a positive with corrected geometry), not rejected.

## Export

Every export creates a new `dataset-<UUID>` subfolder and returns its `annotations.json`. Only complete snapshots with readable page PNG files are copied. Annotation coordinates use pixel centres and a top-left image origin. Reviewed empty pages are included with `annotations: []`.

`splits.json` groups image names by source document SHA-256 and assigns each document to `train`, `validation` or `test`. The assignment hashes document identity into ten buckets: eight for training, one for validation and one for testing. All pages from a document keep the same assignment across exports. These proportions are approximate, and small datasets can have an empty partition. Use this manifest to construct separate training, validation and test inputs; Create ML does not automatically consume this custom manifest.

The manifest prevents identical document identities from crossing partitions. Copies with different PDF bytes, related documents and near-duplicate scans still require a human dataset audit. Review the exported images and labels before training. Exporting data neither trains a model nor establishes detection accuracy. Report evaluation results only after testing a trained model against real held-out scans.

## Original page review

A confirmed element makes its original page nonempty for review and record numbering, even if low-ink analysis classified the scan as blank. Returning or rejecting the last confirmed finding restores that automatic classification. Physical observations still exclude both referenced pages from training.

## Learned detector (step C)

Once enough complete reviews exist (40 pages from 8 documents first, 20 new
reviews later, 15 boxes per label; see the phase 0 findings in
`docs/superpowers/reviews/2026-09-25-learned-detector-phase0.md`), the
reviewer may start training from the dedicated workflow window. Training runs
once at a time at utility priority, never in `--web-signing` accessory mode,
refuses to start on serious thermal pressure and cancels on critical pressure.
Cost is fixed per page (about 16 s on the M1 Max Mac Studio); the iteration
budget (50) changes nothing measurable.

`DetectorTrainer` exports a fresh dataset, stages the `train` split
(`VisionTrainSplit`), trains with transfer learning (`objectPrint`), and
writes `models/candidate-<UUID>/Detector.mlmodel` plus its compiled form.
`DetectorPromotion` scores the candidate and the active model on the
`validation` and `test` partitions (`LearnedModelScorer`, `DetectionEvaluator`
at IoU 0.4) and promotes only on a mean recall gain of at least 0.05 with a
precision drop of at most 0.02 across trained labels. `ModelRegistry` keeps
`active/` and `previous/` under `<bank>/models/` with metadata (SHA-256 id,
date, measured gain, seconds per page); rollback swaps them back. Deleting
the bank deletes the models.

`LearnedCandidateSource` (source `learned`) runs the active compiled model
over the rendered page and proposes hinted candidates. They flow through
`CandidateMerger`, `CandidateQualityFilter` and `TwoStageClassifier` like any
other candidate, so bank rejections still apply, and every box still needs
human confirmation. `LayeredDetectionProvider.identifier` appends
`learned(<model id>)`, so `SecurityReviewStamp` records which model proposed
the boxes. Readiness, estimate and offer state live in
`models/training-state.json` (`TrainingState`); the offers switch is
`AppSettings.detectorTrainingOffersEnabled`.
