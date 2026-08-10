# Native macOS Multi-Format Signing Design

Date: 2026-08-10

## Contract

Autogram macOS must:

- open and inspect supported ASiC containers without reporting a false `Ready` state;
- display embedded documents, existing signatures, covered documents, and timestamp information;
- create visible PAdES signatures whose appearance is cryptographically bound to the signature field;
- import visual signature artwork from transparent PNG or PDF;
- let the user place, resize, and freely rotate the appearance directly on a PDF page;
- batch-sign mixed PDF and ASiC selections without one file failure stopping the remaining files;
- expose reusable signing profiles through the app and Finder Quick Actions without Terminal UI;
- create standalone qualified timestamps without a card or signing certificate where DSS supports the selected format;
- preserve originals, existing signatures, secrets, and the Apple silicon only architecture;
- keep Java Autogram and European Commission DSS as the sole signing, validation, ASiC, and timestamp engine.

The contract is proven when each behavior above has the smallest reliable automated or live acceptance proof described in this document.

## Product Boundaries

- Minimum system: macOS 27.
- Architecture: ARM64 only.
- Native frontend: SwiftUI, AppKit, PDFKit, Finder Action Extension.
- Signing engine: Java Autogram with DSS 6.4 or a later explicitly adopted version.
- No cryptographic, eIDAS, trusted-list, ASiC, PAdES, XAdES, or CAdES implementation is ported to Swift.
- PAdES and ASiC outputs use Baseline T with a qualified timestamp when signing.
- A standalone timestamp does not create a personal signature.
- Original files are never overwritten.
- PINs and TSA credentials are never persisted outside macOS Keychain where persistence is explicitly configured for a custom TSA credential.

## Architecture Decision

Extend the existing SwiftUI application and Autogram/DSS engine through machine protocol v2.

Protocol v1 remains unchanged for current PDF automation. Protocol v2 provides multi-format inspection, signing, standalone timestamping, complete validation, visual appearance parameters, and reusable multi-request engine sessions.

Rejected alternatives:

- Separate scripts layered around protocol v1 would duplicate profile, error, and security behavior.
- Drawing the appearance into the PDF with PDFKit before signing would separate visual construction from the DSS signature field and duplicate coordinate handling.

## ASiC Inspection and Signing

### Root cause of the current failure

DSS ASiC analyzers require a `CertificateVerifier` before `getSignatures()` constructs their internal signature analyzers. The current structural inspection sets a verifier on individual signatures only after calling `getSignatures()`. PDF accepts that order, while ASiC throws a `NullPointerException` inside `DefaultDocumentAnalyzer.setCertificateVerifier`.

### Required behavior

The inspection service sets a local `CommonCertificateVerifier` on the document validator before reading ASiC signatures. This verifier is sufficient for fast structural and cryptographic inspection and does not load trusted lists.

Inspection returns:

- ASiC-S or ASiC-E container type;
- XAdES or CAdES signature family;
- embedded document names;
- signature identifiers, formats, signer display names, signing times, and cryptographic integrity;
- timestamp identifiers, production times, producers, and cryptographic integrity;
- the embedded documents covered by each signature.

Fast inspection does not claim legal validity or qualified status. Its user-facing state is `Cryptographically intact, complete validation not performed` when local integrity succeeds.

An existing ASiC container retains its container type and signature family when another signature is added. An ASiC with XAdES receives another XAdES signature. An ASiC with CAdES receives another CAdES signature. Existing signatures and documents remain unchanged.

When inspection fails, the file status is not `Ready`. The UI distinguishes a damaged container, an unsupported container type, and an analyzer failure with a safe recovery message.

## Input and Output Format Rules

- PDF defaults to PAdES.
- Existing ASiC is co-signed without changing its type or signature family.
- XML or another standalone binary input selected with an XAdES profile is placed in a new ASiC-E container.
- PDF is placed in ASiC-E with XAdES only when the user explicitly selects that profile.
- Visible signature appearances apply only to PDF.
- Output allocation follows the selected naming and destination policy and never overwrites a source or existing target.

## Visible PAdES Appearance

### Asset library

The app stores visual signature assets in Application Support under stable identifiers.

- Transparent PNG is copied without flattening its alpha channel.
- PDF import lets the user select a page, crops to visible content, and renders a transparent appearance asset.
- User preferences store an asset identifier, never the original personal path.
- Missing or unreadable assets are detected during preflight.

### Default template

The default is the approved detailed certificate card. It contains:

- a `Digitally signed by` label;
- the imported handwritten or graphical signature;
- signer name from the selected certificate;
- certificate qualification when authoritative data is available;
- the selected PAdES profile;
- signing time;
- qualified timestamp status.

The appearance does not use the word `verified` unless complete trusted-list validation has occurred. A successful output may state that it contains a qualified timestamp because the output is published only after that requirement is proven.

### Direct page editor

The selected appearance is edited directly over the PDF page with:

- drag movement;
- corner resize handles;
- a rotation handle for arbitrary visual rotation;
- page selection;
- precise position, dimensions, and rotation in the inspector;
- snapping to page edges and centers;
- aspect-ratio preservation by default.

The editor stores geometry in the PDF page coordinate system. A single coordinate converter handles PDFKit view coordinates, page crop boxes, page rotation, and DSS top-left field coordinates.

For arbitrary rotation, the complete card is rendered into a transparent image at the required resolution. DSS places that image in the selected signature field. The field and appearance are created as part of the same PAdES signing operation.

## Signing Profiles

A named signing profile contains:

- output intent: automatic, PAdES, or ASiC with XAdES;
- required Baseline T level;
- timestamp source configuration identifier;
- remembered certificate preference for a detected signing token;
- visible appearance mode and asset identifier;
- saved PDF placement rule;
- output naming and destination policy;
- Finder Quick Action exposure preference.

PINs and TSA secrets are not profile fields. A remembered certificate is keyed by the detected token and certificate identity, not by a user-entered driver identifier.

## Batch Signing

A batch may contain PDF and ASiC files together. Before signing, the app builds a preflight plan showing for each file:

- input type and existing signature count;
- planned output type and profile;
- whether a visible PDF appearance will be used;
- output name and location;
- any condition that blocks processing.

Files are signed sequentially through one token session. The user enters the PIN once unless middleware requires another authentication. A per-file failure does not stop later files. Cancellation stops at the next safe boundary and keeps already completed outputs.

Progress uses truthful phases: inspection, credential discovery, preparation, signing, timestamp request, validation, and saving. The UI does not invent percentages or completion estimates.

## Finder Quick Actions

The primary integration is a native macOS Action Extension named `Sign with Autogram macOS`. It accepts one or more supported files from Finder and hands them to the containing application.

The extension does not perform cryptography and does not launch Terminal. It transfers only security-scoped file references, an opaque request identifier, and an optional profile identifier through an App Group request manifest. The main app displays a compact profile, certificate, and PIN flow when required.

Profiles may optionally be exposed as separate named Finder Quick Actions. Each generated action passes its stable profile identifier to the same app-owned flow. It contains no PIN, credential, personal absolute path, or signing implementation.

Both the main Action Extension and profile-specific actions use the same preflight, signing, output, and error rules as the full application.

## Standalone Qualified Timestamps

The app exposes `Add Timestamp` independently of personal signing. It requires no card, certificate, or PIN.

### PDF

DSS adds a standalone document timestamp in a new PDF revision. Existing signatures and timestamps remain intact. The timestamp is shown in the document inspector and does not require a visible page appearance.

### ASiC and standalone files

Standalone files may be placed into a new timestamped ASiC-E container. An existing ASiC is changed only when DSS can add the time assertion without changing the container type or breaking existing signatures. Unsupported combinations fail during preflight without modifying the source.

### Timestamp sources

Supported source choices remain:

- Automatic, using the configured qualified provider fallback order;
- Sectigo Qualified TSA;
- Belgium Qualified TSA;
- a custom provider with one or more endpoints and optional Basic or Bearer authentication.

Custom credentials are stored only in macOS Keychain. Endpoint configuration alone never proves qualification.

After signing or standalone timestamping, DSS performs the required trusted-list validation. The result is published only when the required qualified timestamp is present and qualified. TSA, network, trusted-list, and qualification failures leave the original untouched and produce distinct safe errors.

## Engine Lifecycle and Protocol v2

The app supervises one long-lived ARM64 Java engine process per application session. The process:

- accepts multiple JSON Lines requests;
- performs fast local inspection without waiting for trusted lists;
- initializes and refreshes trusted-list state in the background once;
- serializes token operations;
- emits request-scoped progress and terminal events;
- restarts safely after an unexpected exit without retaining secrets.

Protocol v2 operations are:

- `CAPABILITIES`;
- `INSPECT`;
- `CERTIFICATES`;
- `SIGN`;
- `TIMESTAMP`;
- `VALIDATE`.

Every request has a protocol version, opaque request identifier, operation, and typed payload. Every accepted request emits exactly one terminal completion or failure event. Per-file failures do not turn a successfully processed batch request into an ambiguous process failure.

The signing request carries stable file identifiers, source and reserved target references, format intent, profile level, timestamp source, certificate identity, and optional visible appearance geometry. Secret values travel only through standard input, are never logged, and are cleared after consumption in both Swift and Java.

## UI State and Error Handling

File states are distinct: loaded, inspecting, ready, unsupported, inspection failed, signing, signed, and signing failed.

Errors are classified as:

- damaged or unsupported input;
- card or middleware unavailable;
- incorrect PIN;
- timestamp provider unavailable;
- returned timestamp not qualified;
- trusted-list validation unavailable or failed;
- output collision or write failure;
- internal engine failure.

The UI exposes a safe reason and a recovery action. It never displays secrets, internal stack traces, or unredacted personal paths.

Outputs are written to reserved temporary files. The app validates format, preservation of existing signature identifiers, the new signature or timestamp, and the required qualification before atomically moving the file to its final destination.

## Minimal Proof

Claims receive only the smallest proof required by the contract:

- an ASiC fixture proves that inspection returns documents and signatures without the missing-verifier exception;
- one visible-signature fixture proves selected page bounds and a valid resulting PAdES signature;
- one mixed batch fixture proves that a failed item does not prevent a later item from completing;
- standalone timestamp fixtures prove preservation of prior signatures and presence of the required timestamp for supported PDF and ASiC paths;
- protocol boundary tests prove that PIN and TSA credentials are absent from arguments, environment, logs, diagnostics, and persisted profiles;
- live acceptance on the target Mac proves I.CA SecureStore, real certificate selection, one mixed batch, Finder handoff, and qualified TSA behavior.

Existing proofs are reused. No duplicate test, broad matrix, screenshot suite, or unrelated refactor is admitted without a contract claim that would otherwise remain unproven.

## Delivery Order

1. Fix ASiC inspection and misleading file status.
2. Define protocol v2 and the long-lived engine boundary.
3. Add multi-format signing and mixed batch preflight.
4. Add standalone qualified timestamping.
5. Add visual signature asset storage, rendering, and direct page placement.
6. Add signing profiles and the native Finder Action Extension.
7. Add optional profile-specific Finder Quick Actions.
8. Complete live I.CA and TSA acceptance.

Each item is a separate implementation slice and commit. A later slice does not block shipping an earlier completed slice.

## Authoritative References

- European Commission DSS documentation: https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/doc/dss-documentation.html
- European Commission DSS 6.4 API: https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/apidocs/index-all.html
- Apple Finder Action Extensions: https://developer.apple.com/documentation/appkit/add-functionality-to-finder-with-action-extensions

