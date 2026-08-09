# Signing Feedback and Signature Inspector

Status: Approved in product review on 2026-08-09

## Contract

The native macOS application must make signing activity continuously visible, preserve and present the actual safe failure reason, and show existing signatures in a readable inspector layout. Re-signing an already signed PDF must preserve all previous signatures and either complete successfully or expose the exact recoverable failure.

## Existing Signatures

Existing signatures belong in the native right inspector, not below the PDF preview. The PDF remains the primary content and keeps the full detail height.

The inspector shows a compact summary followed by one disclosure row per signature. The summary states the signature count and whether all signatures are valid. Each row shows:

- signer display name,
- validation state with a system symbol and semantic color,
- signing date when available,
- a friendly PAdES format label,
- qualified timestamp state,
- covered documents when applicable.

Technical details stay collapsed by default. Empty, pending, and failed inspection states use native labels and progress indicators in the same section.

## Signing Activity

The right inspector shows an indeterminate native `ProgressView` whenever work is active but measurable progress is unavailable. It shows the current user-facing phase:

- Inspecting documents
- Reading the signing card
- Loading certificates
- Preparing signatures
- Signing documents
- Requesting a qualified timestamp
- Validating signed documents
- Saving signed documents

Batch completion uses determinate progress based only on completed or failed files. Animation uses system behavior and respects Reduce Motion automatically.

## Failure Presentation

Routine signing failures remain inline in the inspector. The application preserves structured machine-protocol failure messages. If the helper exits without a terminal event, the process runner returns a safe diagnostic based on the exit condition instead of discarding the captured failure context.

PIN values, TSA credentials, certificate private data, and unredacted document paths must never appear in diagnostics.

## Engine Boundary

SwiftUI owns presentation state only. Java Autogram and DSS continue to own signing, timestamping, preservation of prior signatures, and post-signing validation. Machine progress events provide phase identifiers. Swift maps those identifiers to user-facing text and does not infer cryptographic success from elapsed time.

## Acceptance Evidence

- A coordinator failure test proves an engine failure is thrown and retained.
- A process-runner integration test proves a nonterminal helper failure produces a safe useful reason.
- A focused native build proves the inspector and progress presentation compile.
- A live test with the supplied already signed PDF proves prior signatures remain present after adding another signature, or displays the exact failure that blocks completion.
