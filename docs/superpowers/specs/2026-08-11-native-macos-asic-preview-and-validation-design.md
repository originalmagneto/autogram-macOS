# Native macOS ASiC Preview and Complete Validation Design

Date: 2026-08-11

## Contract

Autogram macOS must:

- show an embedded PDF from an ASiC container inside the main document area after one click;
- leave the source ASiC container unchanged while previewing it;
- first report fast structural and cryptographic inspection, then replace it with a complete DSS validation result when available;
- distinguish valid, invalid, and indeterminate results and expose the specific validation reason;
- let the user retry complete validation when required evidence was unavailable.

The contract is proven by one ASiC fixture with an embedded PDF and one signed ASiC fixture whose complete DSS report is decoded into an explicit user-facing state and reason.

## Chosen Approach

Extend machine protocol v2 instead of extracting ZIP entries in Swift or sending documents to an external validation service.

The Java Autogram engine remains responsible for ASiC parsing, safe document extraction, DSS validation, trusted lists, certificate paths, OCSP, CRL, and timestamp qualification. SwiftUI and PDFKit remain responsible only for presentation.

Rejected alternatives:

- Direct ZIP handling in Swift would duplicate ASiC container rules and create a second document extraction path.
- Keeping cryptographic inspection only would continue presenting every machine inspection as indeterminate and would not answer whether a signature is trusted.
- Sending documents to the European Commission demonstration service would disclose document contents outside the Mac and rely on a service not intended as a production validator.

## ASiC Content Preview

The existing ASiC contents list becomes interactive. Selecting an embedded PDF asks the supervised Java engine to extract that named signed document from the already selected container. The response carries the document bytes through the machine protocol with its media type and display name.

The native app writes the response to an app-managed temporary location and displays it with the existing PDFKit preview. A Back to ASiC Contents control returns to the container list. Closing the document or app removes the temporary preview. Previewing never writes into, replaces, or re-signs the ASiC source.

The engine accepts only an entry returned by its own prior inspection result. It uses the DSS ASiC extractor rather than a general ZIP path. Unsupported embedded content remains visible in the list without an internal preview action.

## Validation Data Flow

Opening a signed PDF or ASiC starts two distinct stages:

1. Fast inspection reads structure, signatures, covered documents, timestamps, and cryptographic integrity without waiting for online evidence.
2. Complete validation runs through the existing shared `SignatureValidator`, which uses the EU List of Trusted Lists, national trusted lists, certificate-chain construction, OCSP, CRL, and DSS timestamp qualification.

The fast result must not claim legal validity. Its label is `Checking trust status` while complete validation is active.

The complete result replaces the provisional state with:

- `Valid` when the DSS validation policy passes;
- `Invalid` when DSS returns a failed validation indication;
- `Validation incomplete` when DSS returns an indeterminate indication.

An indeterminate result includes the most useful safe DSS sub-indication or constraint message, such as unavailable revocation information or an incomplete certificate path. The UI does not convert cryptographic integrity alone into a valid result.

## Refresh and Caching

The supervised engine initializes its trusted-list source once and reuses the existing DSS file cache. Validation may therefore use cached trusted lists while refreshing external evidence according to DSS configuration.

`Verify Again` starts a new complete validation for the selected document. It is available for indeterminate results and validation failures. A retry can produce a different authoritative result when trusted lists, OCSP, CRL, or intermediate certificates have become available. The app does not imply that an indeterminate result will change automatically merely with the passage of time.

## UI Behavior

The ASiC contents screen shows embedded files as native rows. A PDF row has a preview affordance and opens in the same central area with one click. The sidebar and signature inspector remain associated with the ASiC container, not the temporary extracted file.

The signature card shows progress while complete validation runs. Its final status uses green for valid, red for invalid, and orange for incomplete validation. Expanding the card shows the signer, signing time, format, timestamp status, covered documents, and validation reason already returned by DSS.

## Error Handling

- A failed embedded preview leaves the ASiC container and its inspection result available.
- A network or trusted-list failure produces `Validation incomplete`, not `Invalid`.
- A cryptographic or policy failure produces `Invalid` with the DSS reason.
- No raw stack trace, secret, or personal absolute path is shown or persisted.
- Cancellation or document removal discards pending preview and validation responses by request identifier.

## Minimal Proof

- One Java test proves that an inspected ASiC PDF entry can be extracted by its inspected identity and that an unknown entry is rejected.
- One Swift test proves that selecting the embedded PDF changes the central content to PDF preview and Back returns to the ASiC list.
- One Java test proves that machine inspection uses complete DSS reports rather than a hard-coded indeterminate indication.
- One decoder or model test proves valid, invalid, and indeterminate mappings with a reason.
- One live check on the target Mac proves that the supplied ASiC opens its embedded PDF and that complete validation reaches a final explained state when network evidence is available.

Existing fixtures and tests are extended where possible. No duplicate matrix, broad refactor, or unrelated UI work is part of this contract.
