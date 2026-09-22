# Batch signature validation optimization

## Goal

Keep full signature validation for signed input documents while removing avoidable per-document latency. Preserve offline signing behavior when trust or revocation services are unavailable.

## Approved behavior

- The batch preflight waits for the full validation attempt to finish before enabling signing.
- `TOTAL_PASSED` maps to `Overené`.
- `INVALID` maps to `Neplatné alebo konfliktné` and blocks only that document.
- `INDETERMINATE` maps to `Neznáme` and does not block signing.
- Trust-list, CRL, OCSP, timeout, or other validation-service failures map to `Neznáme` with an explicit detail and do not block signing.
- Missing, unreadable, or malformed input files remain blocked. An unavailable validation result for an otherwise readable input is informational and does not block signing.
- A validation failure must never be downgraded from `INVALID` to `Neznáme`.

## Architecture

### Batch provider API

Add a bulk input-signature inspection operation to `QualifiedSigningProviding`. The default implementation preserves compatibility by inspecting URLs through the existing single-document operation. The Java engine provider overrides it and submits one `VALIDATE` request containing all documents.

The bulk result is keyed by canonical URL. Missing result entries become unavailable results with an explicit detail, so the batch cannot silently omit a document.

### Java engine

Use the existing persistent `MachineSessionProcess` and V2 `VALIDATE` operation. This keeps one helper process alive and lets the bundled DSS engine reuse its trust-list cache. Do not perform a separate validation request for each document.

The bridge continues to map DSS signature fields, including signer, format, signing time, qualified timestamp, cryptographic integrity, indication, sub-indication, and validation reason.

### Batch store

During preflight:

1. Load all readable PDF documents.
2. Resolve the signing identity.
3. Submit one bulk validation request for all loaded documents.
4. Publish each returned input signature state and detail to its `BatchItem`.
5. Mark only `INVALID`, unavailable input files, and structural input failures as failed.
6. Leave `UNKNOWN` and validation-service-unavailable items pending and allow the batch to reach the ready state.

The existing preflight generation guard remains authoritative. Results from a cancelled or superseded preflight must not mutate the current batch.

### User interface

Show progress while the bulk validation is running, using the existing preflight phase and a localized progress message. Keep the signing action disabled until the request finishes. Display the final input signature state and detail per document. Do not present `UNKNOWN` as verified.

## Error handling

- Validation-service failures are informational and preserve signing availability.
- A malformed or missing response for a loaded document is represented as unavailable or unknown according to the provider result, with detail.
- Cancellation stops publication of stale results and preserves the cancelled batch state.
- The helper session remains persistent. No new cache directory or per-document helper process is introduced.

## Tests

Add coverage for:

- the Java provider issuing one bulk `VALIDATE` request for multiple files,
- preserving result-to-document mapping when the engine returns results out of order,
- missing bulk result entries becoming explicit unavailable results,
- allowing indeterminate and service-unavailable results while blocking invalid input,
- cancellation and generation guards for bulk validation,
- existing per-document PAdES and shared ASiC-E signing behavior remaining unchanged.

Run focused validation and batch tests, then the complete Swift test suite and application build/install.
