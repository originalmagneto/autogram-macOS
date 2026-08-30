# P2E and EZZK Findings Register

Status: working technical record for Autogram P2E and CEZZK integration
Scope: official form sources, observed Podpisuj output, authenticated EZZK interface, and implementation boundaries

## Executive decisions

- Production target for the conversion clause is the official Slovensko.sk form dataset version 1.3.
- The Podpisuj artifact observed during reverse engineering is retained as a version 1.2 reference fixture only. It is not the production target.
- The current CEZZK conversion-record form remains version 1.0 until the official transition to record version 1.2 on 2027-01-01. Re-check the official source and dataset before changing this profile.
- Autogram must not claim production compatibility from the existing legacy Swift renderer. The new validator is structural and digest-based only, and is not a certificate trust-list validator or a VeraPDF conformance proof.
- EZZK authentication and submission must use the real authenticated service contract. No credentials, tokens, or guessed authorization flow are stored in the repository.
- Initial end-to-end integration must target the EZZK test environment before any production submission path is enabled.

## Official Slovensko.sk and MIRRI findings

### Clause form target: version 1.3

The official Slovensko.sk catalogue identifies the target form as:

- Form identifier: `50349287.ConversionCertificateOfPaperToElectronicDocument.sk`
- Form version: `1.3`
- Reference identifier: `http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3`
- Clause namespace: `http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3`
- Clause root: `ConversionCertificateOfPaperToElectronicDocument`
- Title: `Osvedčovacia doložka zaručenej konverzie z listinnej podoby do novovzniknutého elektronického dokumentu`
- Catalogue validity start shown by the official page: `01.12.2019`

Official sources:

- Metadata page: `https://formulare.slovensko.sk/_layouts/eFLCM/DetailVzoruEFormulara.aspx?vid=50349287.ConversionCertificateOfPaperToElectronicDocument.sk&vh=1&vl=3`
- Official artefact archive: `https://formulare.slovensko.sk/_layouts/eFLCM/GetEFormArtefact.aspx?ac=4&vid=50349287.ConversionCertificateOfPaperToElectronicDocument.sk&sid=&vh=1&vl=3`

The version 1.3 archive contains the official XML/XSD/XSLT artefacts, including `schema.xsd` and `data.xml`. The repository centralizes the URLs in `P2EConformanceProfile` so future dataset updates are explicit.

### CEZZK record transition

The official MIRRI CEZZK documentation states that new electronic record forms version 1.2 become effective on 2027-01-01. The current version 1.0 record forms remain in force until that date.

The currently published Slovensko.sk record dataset contains version 1.0:

- Dataset directory: `https://www.slovensko.sk/static/eform/dataset/50349287.ConversionRecordOfPaperToElectronicDocument.sk/`
- Current record namespace: `https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`
- Current record identifier: `http://data.gov.sk/doc/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`
- Record root: `ConversionRecord`
- Record XDCF version: `1.0`

The version 1.2 record profile is intentionally not guessed or enabled before the official effective date and dataset publication.

Official source:

- MIRRI CEZZK documentation: `https://mirri.gov.sk/sekcie/informatizacia/dokumenty/zakon-o-e-governmente/centralna-evidencia-zaznamov-o-vykonanej-zarucenej-konverzii/`

## Observed Podpisuj reference fixture

An authenticated Podpisuj transaction was inspected as a reference implementation. It used the same conversion domain but a different clause namespace and identifier:

- Clause namespace: `http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument/1.2`
- Clause identifier: `http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument/1.2`
- Clause version: `1.2`
- Record profile observed alongside it: record version `1.0`

This fixture is useful for regression and interoperability comparison. It must not replace the official v1.3 target profile. The v1.2 reference profile is named `P2EConformanceProfile.referenceV1_2`.

The authenticated Podpisuj account exposed historical P2E activity, including 133 P2E transactions and 266 consumed timestamps during the observed session. A known record `1563-260824-1` was displayed as authentic and valid. These values are observations from the authenticated interface, not a repository fixture or an EZZK production guarantee.

## Authenticated EZZK findings

### Portal and tenant

The authenticated EZZK portal was available at:

- Portal: `https://ezzk.iomo.sk/portal/ezzk/dashboard`
- API base: `https://ezzk.iomo.sk/api/zzkservice/v1`
- Logged-in organization shown by the portal: `Advokátska kancelária CHZ`
- Logged-in identifier shown by the portal: `000042249180`
- Portal build shown by the portal: `0.16.2`

The account-specific dashboard did not show usable unconsumed evidence numbers at the time of inspection. An authenticated `GET /ec` returned:

```json
{
  "availableEvidenceNumbers": [],
  "description": "Neboli nájdené žiadne nespotrebované evidenčné čísla"
}
```

This does not prove that the account can never generate numbers. It only records the state returned by the read-only request at inspection time.

### Discovered portal routes

The portal exposed these user-facing routes:

- `/portal/ezzk/evidence/request`
- `/portal/ezzk/evidence/consumed`
- `/portal/ezzk/conversion/perform`
- `/portal/ezzk/conversion/history`

### REST contract discovered from the authenticated portal bundle

The service JavaScript bundle exposed the following API contract:

| Method | Endpoint | Purpose | Repository status |
| --- | --- | --- | --- |
| `GET` | `/ec` | Read available evidence numbers | Read-only request performed |
| `POST` | `/ec` | Generate evidence numbers | Not called because it is consequential |
| `GET` | `/zzk/{evidenceNumber}` | Read a conversion record | Not called during this session |
| `GET` | `/zzk/{evidenceNumber}/original` | Read the original artefact | Not called during this session |
| `POST` | `/zzk` | Submit a conversion record | Not called because it is consequential |
| `GET` | `/ec/consumed` | Read consumed evidence numbers | Not called during this session |
| `GET` | `/zzk?...` | History/DataTables query | Default history request observed |

The conversion upload input accepts `.asice`. The Angular payload shape is:

```json
{
  "files": [
    {
      "fileName": "example.asice",
      "fileType": "application/vnd.etsi.asic-e+zip",
      "value": "<base64 file content>"
    }
  ]
}
```

The exact endpoint contract is now sufficient to design a typed transport, but not sufficient to authorize or submit automatically without an explicit authenticated session and a test-environment validation step.

### Authentication contract

The portal uses OAuth2 Bearer authentication through Keycloak:

- Issuer: `https://ezzk.iomo.sk/sso/auth/realms/ezzk`
- Client ID: `login-app`
- Redirect URI: `https://ezzk.iomo.sk/portal`

The repository must not embed tokens, client secrets, passwords, or copied browser session data. The intended native implementation is an interactive `ASWebAuthenticationSession` flow with secure token storage and refresh handling, followed by an EZZK REST client.

## Implementation now present in Autogram

### Conformance profiles

`P2EConformanceProfile.swift` defines:

- `targetV1_3` for the official clause namespace and identifier
- `referenceV1_2` for the observed Podpisuj fixture
- Current record version 1.0 for both profiles
- Official metadata, archive, and MIRRI documentation URLs
- Shared MIME, PDF/A-2, SHA-256, and evidence URI constants

### Structural validator

`P2EConformanceValidator.swift` validates the following without making unsupported trust claims:

- ASiC container validity through the existing verifier
- Required XDCF and PDF entries
- Official namespace, identifier, root, and XDCF version
- PDF/A-2 and `PDFA2` declarations
- SHA-256 method and Base64 digest of the embedded PDF
- Evidence URI and ISO-8601 conversion time
- Expected PDF data, evidence number, and conversion time when supplied
- Presence of `META-INF/signatures001.xml` and `SignatureTimeStamp`
- Rejection of demo signature markers
- Record artifact shape with one XDCF entry and no PDF entry
- Equality of evidence URI, fingerprint, and conversion time between clause and record
- Deterministic, sorted, deduplicated issue strings

The validator deliberately does not prove:

- Qualified certificate trust
- Trust-list status
- OCSP or CRL status
- Long-term signature validity
- Full PDF/A conformance through VeraPDF
- Legal acceptance by CEZZK

### EZZK capability boundaries

`EZZKService.swift` now separates the service contract into:

- `EZZKServerClock`
- `EZZKEvidenceNumberProvider`
- `EZZKSubmissionTransport`
- `EZZKServicing`, which inherits all three and remains source-compatible

Existing mock numbering, HTTP behavior, and method signatures remain unchanged. The capability split is an architectural boundary only. No production endpoint, token flow, or submission side effect was added.

### Deliberate non-cutover

The existing legacy Swift form renderer and `FormPackRepository.currentLegacyUnverified` remain pilot-only. The new validator is not wired into the legacy generation path, because doing so would risk marking the existing output as official v1.3 compatible without an official renderer and end-to-end validation.

## Verification record

Executed in the worktree branch:

```text
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter P2EConformanceTests
```

Result: 7 tests passed, 0 failures.

```text
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test
```

Result: 146 tests passed, 3 skipped, 0 failures.

```text
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh
```

Result: successful build. App output:

`/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/.worktrees/zako-production-readiness/Autogram/.build/arm64-apple-macosx/debug/Autogram.app`

The build emitted existing unrelated warnings in `PDFPlacementOverlayView.swift` and test/support code. No current verification output reported a failure.

No EZZK evidence numbers were generated and no conversion was submitted. No installed Podpisuj application was modified.

## Open work and update triggers

1. Implement native OAuth2 login with `ASWebAuthenticationSession`, Keychain storage, refresh handling, cancellation, and logout.
2. Implement a typed EZZK REST transport against `/api/zzkservice/v1`.
3. Integrate only with `https://ezzk-test.iomo.sk` first and obtain a non-production test account or test credentials through the official operator.
4. Define the complete conversion submission model, including the signed clause ASiC, the separate signed record ASiC, and the exact server response/error mapping.
5. Obtain and inspect the full official v1.3 XSD/XSLT/data artefacts and implement an official-compatible clause renderer before production eligibility.
6. Add end-to-end test fixtures generated from official datasets and a test-environment submission smoke test that never runs against production by default.
7. Re-check the MIRRI documentation and Slovensko.sk dataset when record version 1.2 is announced or on 2027-01-01, whichever is required by the integration release process. Update `P2EConformanceProfile` and fixtures only from the official dataset.
8. Add a visible UI state that distinguishes pilot output, structurally validated output, and EZZK-accepted output.

## Repository references

- Plan: `docs/superpowers/plans/2026-08-29-p2e-conformance-and-ezzk-boundaries.md`
- Clause profile: `Sources/AutogramKit/Attestation/P2EConformanceProfile.swift`
- Validator: `Sources/AutogramKit/Attestation/P2EConformanceValidator.swift`
- EZZK boundaries: `Sources/AutogramKit/EZZK/EZZKService.swift`
- Conformance tests: `Tests/AutogramKitTests/P2EConformanceTests.swift`
- EZZK and packaging tests: `Tests/AutogramKitTests/EvidenceAndPackagingTests.swift`

## Task 6 integration and verification update (2026-08-30)

### Implemented and verified

- `EZZKEnvironment` remains fixed-authority: sandbox is `https://ezzk-test.iomo.sk`, production is `https://ezzk.iomo.sk`, and the app's production authority gate is closed.
- `EZZKSessionController` owns OAuth-backed session state. The default OAuth configuration has no native callback, so login remains unavailable until the operator registers and supplies a confirmed native redirect URI and callback scheme.
- `SettingsView` presents only fixed environment identities, OAuth session controls, and migration contact metadata. It does not present an EZZK password login, arbitrary EZZK endpoint input, OAuth token values, or a mock fallback after OAuth failure.
- `EZZKClient` uses the fixed sandbox API host by environment, Bearer tokens from the dedicated EZZK token store, authenticated server `Date` values, bounded retries for read-only requests only, and a non-retrying consequential POST.
- Consequential submit decoding requires a non-empty `EZZKSubmissionReceipt.receipt`. A 2xx response with an unknown body is rejected as `invalidResponse`, and transport timeout remains an uncertainty rather than a submission.
- Focused receipt tests now prove that a confirmed receipt does not mutate a local evidence row by itself, that an unknown successful response leaves a signed row non-submitted, and that a submit timeout leaves a signed row non-submitted.
- The legacy exported `HTTPSEZZKService` and `EZZKCredentials` types remain only for source compatibility. No application wiring selects them; `AppSettingsStore` does not construct a password-authenticated service. Legacy password storage is read only to prevent an old credentialed installation from entering demo mode and is not used for OAuth or REST requests.
- Demo-only `MockEZZKService` behavior is retained. Explicit demo submit calls remain local-only and leave the evidence row pending; dashboard success feedback identifies the local preparation rather than CEZZK acceptance.
- `URLSessionEZZKHTTPTransport` uses a redirect-denying delegate, so Bearer headers and refresh-token POST bodies are never forwarded across HTTP redirects. The client also validates final API and issuer response authorities.
- Conversion preflight no longer requests evidence numbers automatically. Evidence-number generation remains an explicit Settings action or explicit user action from the conversion form.
- `AppSettingsStore` distinguishes empty, present, and unavailable OAuth token storage. Keychain errors fail closed and cannot classify an installation as demo or expose the mock service.
- Demo is visible as `Demo (lokálne)` with no sandbox or production URL presented as the active service. Demo submission calls remain local and leave rows pending.
- Validated OIDC discovery now carries its token endpoint in `EZZKTokenSet`; refresh uses that endpoint and rejects missing or untrusted endpoints instead of reconstructing a path.

### Exact verification

```text
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKHTTPClientTests
```

Result: 21 tests passed, 0 failures.

```text
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test
```

Result: 187 tests executed, 3 skipped, 0 failures.

```text
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh
```

Result: successful debug build at `Autogram/.build/arm64-apple-macosx/debug/Autogram.app`. Existing warnings remain in unrelated app and signing support code.

The app was launched from the built bundle. Screen capture produced no usable app surface in this session, so interactive Settings verification was not feasible. Source and build evidence confirm the sandbox default, closed production gate, callback-gated login, no EZZK password-login controls, and disabled signed ASiC-E submission control.

### Blockers and uncertainty

- **Native callback blocker:** the operator has not supplied a registered native redirect URI and callback scheme. The observed web redirect is explicitly rejected, so login remains blocked closed.
- **Sandbox account blocker:** no non-production EZZK test account or credentials were available for an authenticated sandbox smoke test. No evidence-number request or conversion POST was made.
- **Unconfirmed POST receipt schema:** the portal bundle confirms the `.asice` `files` payload and `POST /api/zzkservice/v1/zzk`, but the authoritative success body and complete error mapping were not confirmed from an operator-backed sandbox transaction. The client therefore accepts only the typed non-empty `receipt` shape as a narrow defensive boundary and does not claim interoperability.
- **Local evidence integration gap:** the current app workflow does not produce and validate the separate signed record ASiC required for EZZK submission, and `EZZKClient` is not yet adapted to `EZZKServicing.submit(ConversionRecordEnvelope)`. The Settings ASiC submission control remains disabled. The app-target test boundary also prevents a direct XCTest of `EZZKSessionController.logout()` preserving rows; `LocalEvidenceStore` persists independently and existing persistence coverage remains green.
- **Demo status limitation:** the demo mock is still called for compatibility, but both the dashboard and conversion workflow now leave demo rows pending instead of assigning `.submitted`. It is not evidence of CEZZK acceptance; dashboard feedback labels the outcome as demo-local.

Production readiness is not claimed.
