# Security-element training data

## Two independent records

`bank.json` contains individual crop decisions and feature vectors for local example matching. A collection of accepted and rejected crops does not prove that every object on a page was reviewed.

`reviewed-pages.json` stores complete page snapshots separately. Older banks remain readable, but their pages become eligible for detector export only after an explicit complete review. A snapshot contains document SHA-256, page index, canonical visual boxes, review time and detector version. Empty reviewed pages have an empty box list and a real rendered page image.

The caller must pass every element belonging to the page to `ExampleBankRecorder.recordReviewedPage(document:documentData:pageIndex:elements:)`. Pending decisions, elements from another page, unsupported confirmed visible kinds and invalid confirmed scan boxes prevent the snapshot from being saved. A confirmed physical-original observation also excludes the whole page: without a scan box, omitting it could mislabel a visible object as background. The recorder invalidates any previous snapshot before rejecting the page and never fabricates a positive crop. A rejected candidate is background, never an object rectangle.

Finish queued crop recording before saving a complete page. Crop additions, replacements and removals invalidate affected page snapshots. The application must also call `ExampleBank.invalidateReviewedPage(documentSHA256:pageIndex:)` on review or annotation edits, including edits without a stored crop. For a non-rejected physical observation, exclude and invalidate both its original page and its explicitly referenced output page, including references to another page. A new complete review is eligible only when every visible object has a supported scan box.

## Visual labels

Supported visual training labels come from `SecurityElement.Kind.visualKind` and `trainingLabel`: `handwrittenSignature`, `officialStamp`, `embossedSeal`, `initial`, `bindingCord`, `securityTape`, `waxSeal`, `watermark`, `securityPattern`, `opticallyVariable`, `securityFoil` and `lamination`. A certified signature uses the `handwrittenSignature` image class; a round official stamp uses `officialStamp`. Certification and physical binding assessments remain human observations. `other` and `permanentBinding` have no visual training class. A confirmed unsupported visible object excludes its whole page from detector export so it cannot silently become background. Exportable labels do not imply that the current automatic detector proposes every class.

The crop recorder removes an earlier positive crop when its element becomes physical-only or unsupported. Rejected candidates with valid scan regions remain negative examples for crop matching.

## Export

Every export creates a new `dataset-<UUID>` subfolder and returns its `annotations.json`. Only complete snapshots with readable page PNG files are copied. Annotation coordinates use pixel centres and a top-left image origin. Reviewed empty pages are included with `annotations: []`.

`splits.json` groups image names by source document SHA-256 and assigns each document to `train`, `validation` or `test`. The assignment hashes document identity into ten buckets: eight for training, one for validation and one for testing. All pages from a document keep the same assignment across exports. These proportions are approximate, and small datasets can have an empty partition. Use this manifest to construct separate training, validation and test inputs; Create ML does not automatically consume this custom manifest.

The manifest prevents identical document identities from crossing partitions. Copies with different PDF bytes, related documents and near-duplicate scans still require a human dataset audit. Review the exported images and labels before training. Exporting data neither trains a model nor establishes detection accuracy. Report evaluation results only after testing a trained model against real held-out scans.

## Original page review

A confirmed element makes its original page nonempty for review and record numbering, even if low-ink analysis classified the scan as blank. Returning or rejecting the last confirmed finding restores that automatic classification. Physical observations still exclude both referenced pages from training.
