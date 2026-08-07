# Existing Signatures, Token Defaults, and Timestamp Sources

Status: Approved in product review on 2026-08-07

## Summary

The native macOS Autogram application must show signatures already present in an opened PDF or ASiC-E container before the user adds another signature. It must discover the inserted eID or I.CA token and its eligible signing certificates, remember a default certificate separately for each known token, and automatically follow a renewed certificate for the same signer identity. It must also let the user choose a qualified timestamp source from the three configurations available in the existing Autogram application or configure an authenticated custom TSA service.

SwiftUI, AppKit, PDFKit, and native macOS security services own presentation and workflow. Autogram and DSS remain the only authority for document inspection, certificate interpretation, signing, timestamping, and eIDAS validation.

## Product Outcomes

1. A user can see every existing signature and its validation state before signing.
2. A user can add another signature without losing or obscuring existing signatures.
3. The application automatically detects a supported inserted token and eligible signing certificates.
4. The application automatically selects the user's saved default certificate for that specific token.
5. A renewed certificate for the same identity can replace the previous default without unnecessary setup.
6. The user can change or clear token-specific defaults in Settings.
7. Every successful signature contains a DSS-validated qualified timestamp from the selected TSA configuration.
8. Custom TSA credentials are stored only in macOS Keychain.

## Scope and Boundaries

This design covers:

- inspection of existing signatures in PDF and ASiC-E,
- adding a further signature to a supported PDF or ASiC-E document,
- automatic eID and I.CA token discovery,
- eligible certificate discovery and selection,
- token-specific certificate defaults,
- certificate renewal matching,
- predefined and custom qualified timestamp sources,
- optional custom TSA authentication,
- safe settings, diagnostics, and recovery behavior.

This design does not move cryptographic, PKCS#11, certificate qualification, ASiC, PAdES, XAdES, CAdES, timestamp, or trusted-list logic into Swift. It does not store a PIN. It does not promise that an arbitrary custom TSA is qualified merely because its URL is accepted.

## Document Inspection

### Supported Inputs

The native file intake layer recognizes content by format and validated structure, not only by filename extension. The first expanded scope supports:

- PDF documents, including PDFs with one or more PAdES signatures,
- ASiC-E containers supported by the existing Autogram and DSS engine, including containers with XAdES or CAdES signatures.

Malformed containers, misleading extensions, and unsupported ASiC variants must produce a clear non-destructive error. The source file is never modified in place.

### Inspection Timing

Inspection begins automatically when a file is opened. A file remains in an `inspecting` state until the helper returns a complete structured result. Signing is disabled while inspection is incomplete or while a blocking integrity error exists.

Inspection runs again:

- after a successful signature is produced,
- after the user replaces or reloads a document,
- when the user explicitly requests validation refresh,
- when trusted-list freshness requires a new qualification decision.

### Signature List

The inspector shows an explicit empty state when no signatures are present. For every existing signature it shows, when available:

- signer display name,
- signing time claimed by the signature,
- trusted timestamp production time,
- certificate issuer,
- certificate validity interval,
- signature format and baseline level,
- signer-certificate qualification,
- timestamp qualification,
- cryptographic validation result,
- document integrity result,
- revocation or indeterminate status,
- a concise reason and recovery action for warnings or failures.

The interface must distinguish these concepts:

- a signature can be cryptographically valid without a qualified signer certificate,
- a timestamp can be valid without being qualified,
- a qualified timestamp does not prove that the signer certificate is qualified,
- an indeterminate result is not shown as valid or invalid.

The primary list is concise. A disclosure view provides technical details and redacted certificate identifiers. Invalid, altered, or incompletely validated signatures are visually prominent without hiding the rest of the signature history.

### ASiC Presentation

For ASiC-E, the detail area shows:

- container type and validation status,
- contained documents with safe display names and media types,
- the signatures covering each contained document,
- a preview for content types that macOS can safely preview,
- a clear fallback for content that has no native preview.

The user must be able to understand which content a signature covers. Extracted content is never executed and is not silently written outside an application-controlled temporary directory.

### Adding Another Signature

Adding another signature creates a new output file and preserves all valid existing signatures and container contents. The helper determines the correct DSS signing path for the input format. Swift must not rebuild an ASiC archive or manipulate signature XML directly.

After signing, the output is accepted only if:

1. the helper completed normally,
2. the output format is valid,
3. the previous signatures are still present,
4. the new signature is present and valid,
5. the requested qualified timestamp is present and validated,
6. the output passes the applicable DSS integrity checks.

## Token and Certificate Discovery

### Automatic Token Detection

The helper discovers supported eID and I.CA drivers and reports token presence as structured events. The UI never asks the user for a driver ID. Each discovered token is represented by a friendly provider name and a privacy-preserving stable token key.

The stable token key must:

- distinguish separate physical tokens when the middleware exposes sufficient stable information,
- avoid storing a raw card number, personal identifier, PIN, or private certificate data,
- be derived and hashed inside the helper before crossing the machine protocol,
- degrade safely to provider-level matching when a middleware cannot expose a stable token identity.

If exactly one supported token is present, it is selected automatically. If multiple tokens are present, the application asks the user to choose a friendly token entry and does not guess.

### Eligible Certificates

The helper enumerates certificates through the selected token. If the middleware requires authentication before enumeration, the application presents a native secure PIN sheet that explains why the PIN is needed.

The default picker includes only certificates that are eligible for document signing. Authentication-only, encryption-only, expired, not-yet-valid, or otherwise unusable certificates are excluded from automatic selection. A diagnostic detail may explain why a certificate was excluded.

Certificate presentation uses friendly fields such as signer name, issuer, purpose, qualification, and expiry date. Internal driver IDs and bare certificate serial numbers are not normal user settings.

### Default Certificate per Token

The application stores a separate default-certificate preference for each stable token key. The stored preference contains only public metadata needed for matching. It never contains a private key or PIN.

Selection order is:

1. exact saved certificate match on the detected token,
2. a safe renewed-certificate match for the same signer identity and signing purpose,
3. the only eligible certificate on the token,
4. an explicit user choice when multiple eligible certificates remain,
5. a blocking message when no eligible certificate exists.

When the user explicitly chooses a certificate, the UI offers a selected-by-default control labeled for the current token. The default can also be changed or cleared in Settings.

### Certificate Renewal

A renewed certificate may automatically replace the saved default when all of these conditions hold:

- it is on the same detected token,
- it represents the same signer identity using normalized certificate identity attributes,
- it has the same signing purpose and compatible qualification,
- it is currently valid,
- the previous default is expired, expiring, or no longer present,
- exactly one safe successor remains after filtering.

The application informs the user that the renewed certificate became the default. If more than one plausible successor exists, it asks the user and does not silently choose. Serial-number equality is not required for renewal matching.

### Settings Experience

Settings lists previously seen tokens using friendly provider and holder information. Each token row shows the current default certificate, issuer, qualification, and expiry date. Available actions are:

- Change Default, available when the token can be queried,
- Clear Default,
- Forget Token, which removes only local public preference metadata,
- Refresh Certificates.

Disconnected tokens remain visible as remembered devices but are clearly marked as unavailable. Settings must not expose a free-form driver ID or certificate serial field.

## Qualified Timestamp Sources

### Predefined Configurations

The Timestamp Source setting provides these choices with friendly labels:

1. `Automatic, recommended`, using Sectigo first and Belgium TSA as fallback,
2. `Sectigo Qualified TSA`,
3. `Belgium Qualified TSA`,
4. `Custom Provider`.

The underlying predefined endpoints initially match the existing Autogram configuration:

- `http://timestamp.sectigo.com/qualified`,
- `http://tsa.belgium.be/connect`.

Endpoint changes are application-managed configuration changes and require validation before release. The UI may show the current endpoint in a technical disclosure, but the normal picker uses provider names.

### Custom Provider

A custom provider configuration supports:

- one or more TSA URLs in ordered fallback sequence,
- optional username and password authentication,
- optional bearer or provider token authentication,
- a user-defined display name,
- a connection test that does not sign a user document,
- removal and credential replacement.

Non-secret configuration is stored in application preferences. Passwords and tokens are stored as Keychain items scoped to the application and provider configuration. Secrets must not appear in preferences, process arguments, environment variables, logs, diagnostics, crash reports, or machine-protocol events.

The helper receives a secret only for the duration of a timestamp request through the protected process input channel. The secret is cleared from Swift workflow state after use. Diagnostics may report that authentication was configured or rejected, but never include its value.

### Qualification and Failure Policy

The product requirement remains a qualified electronic timestamp. Selecting a predefined or custom URL is not proof of qualification.

Every produced output must be validated by DSS against applicable and sufficiently fresh trusted-list data. The output succeeds only when the new timestamp is valid and its qualification is `QTSA`. The application fails closed when:

- every configured TSA endpoint is unavailable,
- authentication is rejected,
- a TSA response is malformed,
- the timestamp is invalid,
- the timestamp is valid but not qualified,
- qualification is indeterminate because trusted-list data is unavailable or too stale.

Fallback moves only to the next endpoint in the selected configuration. It never silently changes to a different saved provider. Error messages distinguish network, authentication, server refusal, non-qualified timestamp, and trusted-list failures.

## Machine Protocol Additions

The machine protocol must gain structured operations and events for:

- document format detection,
- PDF and ASiC-E signature inspection,
- signature and timestamp validation details,
- token insertion, removal, and stable token key,
- eligible certificate discovery,
- public certificate identity metadata suitable for default matching,
- signing PDF or supported ASiC-E while preserving prior signatures,
- selected TSA configuration and ordered endpoints,
- ephemeral custom TSA authentication,
- post-signing validation proving `QTSA` qualification.

Secrets are request-only fields, are never echoed, and are redacted before any diagnostic serialization. Protocol additions must remain versioned and must not break the existing PDF machine-signing request without an explicit protocol-version change.

## Security and Privacy

- PINs are never persisted.
- Custom TSA credentials live only in Keychain.
- Raw card numbers and personal identifiers are not preference keys.
- Certificate defaults use public metadata and a privacy-preserving token key.
- Client filenames and paths are redacted from shareable diagnostics.
- ASiC contents are treated as untrusted input.
- Extracted files are not executed and are cleaned after preview or inspection.
- Swift does not load PKCS#11 libraries.
- Java Autogram and DSS remain the validation authority.

## Recovery Behavior

The user receives a specific action for common failures:

- insert or reconnect the expected token,
- unlock the token and retry the PIN,
- choose among multiple tokens or certificates,
- choose a new default when renewal matching is ambiguous,
- refresh trusted lists,
- test or repair custom TSA authentication,
- switch to another explicitly selected TSA configuration,
- reveal redacted technical details for support.

No failure may overwrite the source document or present a partially produced output as successfully signed.

## Acceptance Criteria

- Opening an unsigned PDF shows an explicit no-signatures state.
- Opening a signed PDF lists every existing signature and its distinct validation properties.
- Opening a supported ASiC-E lists contained documents and every signature covering them.
- A further signature can be added without removing existing valid signatures.
- Inserting one supported token selects it automatically.
- Inserting multiple supported tokens requires an explicit token choice.
- An exact per-token default certificate is selected automatically.
- A unique safe renewed certificate becomes the default and the user is informed.
- Ambiguous renewal requires an explicit choice.
- Settings can change, clear, and forget token-specific defaults without exposing internal IDs.
- Automatic TSA mode uses Sectigo and then Belgium TSA in order.
- Either predefined provider can be selected individually.
- A custom provider accepts ordered URLs and optional Keychain-backed authentication.
- A successful output always contains a DSS-validated `QTSA` timestamp.
- A valid but non-qualified custom timestamp causes the operation to fail.
- No PIN, TSA credential, private key data, raw card identifier, or client path appears in diagnostics.

## Implementation Workstreams

The implementation should proceed as three independently reviewable workstreams:

1. PDF and ASiC-E inspection, signature presentation, and co-signing validation.
2. Token-aware certificate discovery, per-token defaults, and renewal matching.
3. Timestamp source settings, Keychain credentials, helper transport, and QTSA enforcement.

The workstreams share typed domain models and versioned machine-protocol contracts. They should not be merged into one large implementation task. Automated coverage should focus on deterministic model, protocol, and security boundaries. Physical-token and live-TSA behavior belongs in a small manual hardware acceptance matrix rather than a large collection of fragile UI tests.
