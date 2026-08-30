# ZaKo Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the current P2E ZaKo pilot into a production-gated application that emits only authority-backed form-pack and output artifacts, performs independent signature and timestamp validation, submits the exact signed record through a verified EZZK contract, and preserves a complete audit trail.

**Architecture:** Keep P2E as the only production scope. E2P and E2E remain separate future projects and may not reuse unverified P2E assumptions. Make each production stage consume immutable, content-addressed output from the preceding stage. Production enablement depends on verified authority artifacts, independent technical conformance evidence, real EZZK sandbox evidence, and explicit release approval. Demo, pilot, sandbox, and production are separate runtime modes and service capabilities.

**Tech Stack:** Swift 6, Swift Package Manager, macOS 27, SwiftUI, PDFKit, CoreGraphics, Foundation XML APIs, Security, CryptoTokenKit, bundled Java/DSS engine, RFC 3161 TSA, and only those ZaKo form, packaging, signature, output, and EZZK profiles that Phase 0 proves authoritative.

## Global Constraints

- P2E is the only planned production direction.
- The three supplied Markdown files are working requirements, not authority for PDF/A-1a, PDF/A-2b, PNG, XMLDataContainer, form versions, namespaces, XSD, XSLT, codelists, ASiC-E profile, signature profile, certificate policy, TSA policy, or EZZK behavior.
- A missing authoritative artifact or unresolved contract row is a blocker for every task that consumes it. It MUST NOT be replaced by an inferred constant, guessed endpoint, local fixture, or permissive fallback.
- PDF/A-1a is the safe production default described by the supplied working requirements, but it becomes production accepted only after the authoritative P2E format matrix and independent conformance evidence are recorded.
- PDF/A-2b MUST remain pilot-only unless an authoritative P2E format matrix explicitly accepts it.
- PNG MUST remain unavailable for production unless the authoritative P2E matrix confirms its exact page-count, content, MIME, packaging, signing, and warning rules.
- Any accepted alternative to the safe default MUST require the exact counsel-approved prior warning and explicit applicant acknowledgement required by the authority record. The acknowledgement MUST be a domain gate and an audit record, not only UI text.
- Official form versions, namespaces, XSD, XSLT, codelists, effective dates, and EZZK acceptance status MUST be stored as immutable versioned form-pack artifacts.
- No production conversion may use an `unverified`, `unknown`, `legacySwift`, expired, hash-mismatched, or mock form pack.
- The exact production signing and packaging objects MUST come from the confirmed authority record. Input PAdES, XAdES, and CAdES validation MUST remain separate from the selected P2E output authorization profile.
- A production conversion MUST use a validated mandate certificate and a validated qualified electronic timestamp according to confirmed certificate, TSA, signature, packaging, and EZZK contracts.
- An unavailable input-signature inspection MUST block production authorization. A completed inspection that proves no signatures are present is distinct from an unavailable inspection and follows the confirmed input-signature policy.
- AI MAY propose security elements. A human MUST review every non-empty page and explicitly confirm or reject every proposed element.
- Local marker checks MUST be labelled as preflight checks. They MUST NOT be presented as independent PDF/A, XML, signature, timestamp, ASiC-E, legal, or production conformance evidence.
- Demo, pilot, sandbox, and production modes MUST be distinct in configuration, UI, persistence, output naming, credentials, endpoint selection, and provider capability.
- Mock, demo, pilot, sandbox, and non-submitting transports MUST NOT satisfy a production provider capability check.
- No credentials, private keys, PINs, timestamp tokens, signed payloads, or API secrets may be committed or written to ordinary application logs.
- Comments, identifiers, and internal documentation MUST be in English. End-user strings MUST be in Slovak.
- Do not use em dashes in source, documentation, UI copy, or reports.
- Preserve the current `BuiltInVisionProvider.swift` work unless a narrowly scoped regression fix is required.
- Every implementation task MUST add or update a focused behavioral test before changing production code.
- Every phase ends with its stated exit gate. A green local test suite alone MUST NOT be treated as production, legal, interoperability, sandbox, or external conformance evidence.

## Model Allocation and Session Boundaries

- Session 1 uses Sol Medium only for independent plan review, requirement coverage verification, contradiction detection, and plan corrections.
- Session 1 MUST NOT modify production source code, create an implementation branch or worktree, or start any implementation task.
- When Session 1 finds Critical or Important defects, the corrected plan MUST receive a fresh second-pass Sol Medium verification of requirements, types, dependencies, exit gates, model allocation, and Session 1 prohibitions.
- Session 2 starts only after the corrected plan receives an approval verdict.
- Session 2 uses only fresh implementation and review subagents running on Luna high.
- Luna high subagents implement one plan task at a time in an isolated worktree and run the task-level review loop.
- The controller MUST NOT substitute a different model for implementation without explicit user approval.
- External authority artifacts that remain unavailable are blockers, not permission to invent a production contract.


## Current Baseline and Known Gaps

The current application already provides:

- A human review gate for non-empty pages and detected security elements.
- Fail-closed input signature states: `valid`, `invalid`, `unknown`, and `unavailable`.
- A P2E pipeline with SHA-256 fingerprinting, local evidence storage, ASiC-E packaging, and a pilot PDF/A-2b profile.
- A form-pack provenance model, but only an unverified legacy Swift pack is active.
- An EZZK abstraction with mock and unverified HTTP implementations.

The current application does not yet provide:

- An accepted production PDF/A-1a or PNG output profile.
- Official XSD/XSLT/codelist validation and rendering.
- Independent cryptographic validation of PAdES, XAdES, certificate chains, revocation, and QTS.
- A mandatory QTS gate and strict mandate-certificate gate.
- An EZZK request-signature and submission contract backed by sandbox evidence.
- Input-signature reports persisted into the attestation and evidence audit.
- Production E2P or E2E flows.

---

## Phase 0: Authority, Scope, and Release Modes

### Task 0.1: Create the authority register and evidence inventory

**Files:**
- Create: `Autogram/docs/zako/authority-register.md`
- Create: `Autogram/docs/zako/format-matrix.md`
- Create: `Autogram/docs/zako/form-version-matrix.md`
- Create: `Autogram/docs/zako/ezzk-protocol-contract.md`
- Reference: `docs/ZAKO_EXTERNAL_REQUIREMENTS_SPEC_2026-08-28.md`
- Reference: the three supplied Markdown specifications in `/Users/Magneto/Downloads`

**Interfaces:**
- Produces the versioned authority keys consumed by later tasks: `productionDirection`, `recordVersion`, `clauseVersion`, `namespace`, `pdfaProfile`, `pngEligibility`, `alternativeFormatNoticePolicy`, `recordXSD`, `clauseXSD`, `recordXSLT`, `clauseXSLT`, `codelistSet`, `packageProfile`, `inputSignaturePolicy`, `outputSignatureProfile`, `signedObjectContract`, `mandateCertificatePolicy`, `tsaPolicy`, `evidenceNumberValidityRule`, `submissionDeadlineRule`, `serverTimeRule`, `retryPolicy`, `idempotencyRule`, `registrationContract`, and `productionEndpoint`.

- [ ] Inventory every claim from all three supplied Markdown files. For each claim record the supplied-document path and hash, claimed source reference, retrieval date if known, effective interval, authority status, and the exact plan task that consumes it.
- [ ] Record the authoritative P2E format matrix, including PDF/A-1a, PDF/A-2b, PNG, page-count and graphic-only restrictions, OCR, tagging, Unicode, DPI, compression, MIME, packaging, and prior-warning requirements.
- [ ] Record the current, historical, and announced future record and clause versions separately. Include namespaces, eForm identifiers, effective intervals, EZZK acceptance intervals, and rules for historical validation.
- [ ] Record every official record XSD, clause XSD, record XSLT, clause XSLT, codelist artifact, namespace manifest, MIME type, packaging profile, signature profile, and signed-object rule with content hash.
- [ ] Record the EZZK transport contract: sandbox and production base URLs, endpoint paths, registration prerequisites, authentication, client certificate or token requirements, transport request signature, signed business object, number lifecycle, server-time source, response receipt, error codes, retry rules, permanent rejection rules, and idempotency semantics.
- [ ] Record evidence-number validity and record-submission deadline as separate rules with separate anchors, durations, server-time semantics, and terminal states. Do not collapse both supplied 24-hour claims into one deadline.
- [ ] Record input PAdES, XAdES, and CAdES inspection requirements separately from P2E output authorization. Include exact signed objects, certificate-chain, revocation, qualification, mandate, signature-policy, QTS, timestamp-token, and oldest-relevant-timestamp rules.
- [ ] Record the supplied XMLDataContainer claim as E2P-only and blocked until an authoritative E2P contract exists.
- [ ] Record the office-registration claims and supplied sandbox address as unverified until the authoritative registration and environment contract is obtained.
- [ ] Mark every unavailable authority item `blocked`. A row may become `verified` only from the named authority artifact, never from a local implementation or test.
- [ ] Add a decision log that resolves the alternative-format wording: PDF/A-1a remains the safe default; another format enters production only when authority permits it and the approved prior-warning policy is implemented and audited.

**Acceptance:**
- Every requirement from the three supplied files maps to a task, an evidence gate, or an explicit future-project entry.
- Every later external dependency has a named authority row, artifact hash, source, effective interval, and status.
- No task that consumes a `blocked`, `unverified`, expired, or missing authority row is eligible to start.
- The authority register distinguishes working requirement, verified authority, independent technical conformance evidence, sandbox evidence, and release approval.

### Task 0.2: Add explicit demo, pilot, sandbox, and production runtime modes

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Support/AppSettings.swift`
- Modify: `Autogram/Sources/AutogramApp/AppSettingsStore.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/SettingsView.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Test: `Autogram/Tests/AutogramKitTests/RuntimeModeTests.swift`

**Prerequisites:**
- Task 0.1 defines the verified sandbox and production endpoint identities and provider capability rules.

**Interfaces:**
```swift
public enum ZaKoRuntimeMode: String, Codable, CaseIterable, Hashable, Sendable {
    case demo
    case pilot
    case sandbox
    case production
}

public enum EZZKProviderCapability: String, Codable, Hashable, Sendable {
    case mock
    case pilot
    case sandbox
    case production
}
public enum ZaKoFormPackPolicy: String, Codable, Hashable, Sendable {
    case allowUnverifiedNonProduction
    case requireVerifiedSandbox
    case requireVerifiedProduction
}


public struct ZaKoRuntimePolicy: Sendable, Equatable {
    public let mode: ZaKoRuntimeMode
    public let formPackSelectionPolicy: ZaKoFormPackPolicy
    public let permittedGatewayCapability: EZZKProviderCapability
    public let requiresAuthorityVerifiedArtifacts: Bool
    public let permitsProductionStatus: Bool

    public static func policy(for mode: ZaKoRuntimeMode) -> Self
}
```

- [ ] Write failing tests proving production rejects unverified or expired form packs, mock, pilot, sandbox, and non-submitting EZZK providers, pilot output profiles, optional QTS, non-mandate identities, and arbitrary endpoint overrides.
- [ ] Write failing tests proving demo, pilot, and sandbox modes cannot use production credentials, call the production endpoint, create a production status, or emit production-looking evidence.
- [ ] Implement one closed `policy(for:)` mapping. Do not expose a public initializer that can construct contradictory mode and capability combinations.
- [ ] Store sandbox and production endpoints as separate typed configurations bound to authority-register IDs and hashes, not one user-editable URL string.
- [ ] Make the selected mode and provider capability visible in Settings and in every output and evidence record.
- [ ] Prevent changing mode, endpoint identity, form pack, or provider capability during an active conversion session.
- [ ] Remove every fallback from a failed production provider to mock, pilot, sandbox, local-clock, legacy form-pack, or local-validator behavior.

**Acceptance:**
- A production session cannot be constructed with mock, pilot, sandbox, non-submitting, unverified, expired, or user-substituted services or artifacts.
- UI copy clearly distinguishes demo, pilot, sandbox, and production.
- Runtime mode, provider capability, endpoint authority ID, and configuration hash are persisted in audit records.
- A sandbox acceptance receipt cannot be represented as a production submission receipt.

**Commit:** `feat(zako): add explicit runtime modes and production policy`

### Task 0.3: Add content-addressed evidence artifact primitives

**Files:**
- Create: `Autogram/Sources/AutogramKit/Evidence/VerificationArtifactReference.swift`
- Test: `Autogram/Tests/AutogramKitTests/VerificationArtifactReferenceTests.swift`

**Interfaces:**
```swift
public struct VerificationArtifactReference: Codable, Hashable, Sendable {
    public let kind: Kind
    public let relativePath: String
    public let sha256Hex: String
    public let byteCount: Int
    public let createdAt: Date

    public enum Kind: String, Codable, Hashable, Sendable {
        case authoritySnapshot
        case formPackProvenanceReport
        case inputSignatureReport
        case certificateReport
        case timestampToken
        case timestampReport
        case pdfaPreflightReport
        case pdfaConformanceReport
        case xmlValidationReport
        case formRenderReport
        case packageValidationReport
        case ezzkRequest
        case ezzkResponse
        case ezzkTransportSignatureReport
        case humanReviewAudit
    }
}
```

- [ ] Validate normalized relative paths, byte count, lowercase SHA-256, and file bytes when a reference is created or loaded.
- [ ] Reject absolute paths, parent traversal, symlink escape, missing files, byte-count mismatch, and hash mismatch.
- [ ] Keep artifact kind separate from evidence status. A valid local hash does not make the artifact authoritative, independent, sandbox-accepted, legally valid, or production-approved.

**Acceptance:**
- Every later report interface can reference immutable bytes without redefining this type.
- Reference integrity proves only identity and local integrity, not the validity of the referenced report.

### Phase 0 exit gate

- The authority register, format matrix, form-version matrix, signature and packaging contract, and EZZK contract exist and classify every required row.
- Every Phase 1 through Phase 7 prerequisite names only `verified` authority rows. Any remaining required `blocked` row blocks Session 2 work that consumes it.
- Production mode is fail-closed and cannot silently fall back to mock, demo, pilot, sandbox, local-clock, or marker-only services.
- Counsel and product owner approve the scope statement: production P2E only; E2P and E2E remain separate future projects.

---

## Phase 1: Official Form Packs and XML Contract

### Task 1.1: Replace legacy-only form selection with immutable official form packs

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Attestation/FormPack.swift`
- Create: `Autogram/Sources/AutogramKit/Attestation/FormPackArtifactStore.swift`
- Create: `Autogram/Sources/AutogramKit/Attestation/OfficialFormPackRepository.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Test: `Autogram/Tests/AutogramKitTests/FormPackTests.swift`

**Prerequisites:**
- Verified Phase 0 rows for the P2E record and clause versions, namespaces, eForm identifiers, XSD, XSLT, codelists, effective intervals, packaging profile, output profile, and EZZK acceptance.

**Interfaces:**
```swift
public enum FormPackVerificationState: String, Codable, Hashable, Sendable {
    case unverified
    case verified
}

public enum FormPackAcceptanceState: String, Codable, Hashable, Sendable {
    case unknown
    case pilotOnly
    case sandboxAccepted
    case productionAccepted
    case rejected
}

public enum FormPackRenderer: String, Codable, Hashable, Sendable {
    case legacySwift
    case xslt
}

public enum FormPackArtifactKind: String, Codable, Hashable, Sendable {
    case recordXSD
    case clauseXSD
    case recordXSLT
    case clauseXSLT
    case codelist
    case namespaceManifest
    case packagingManifest
}

public struct FormPackArtifact: Codable, Hashable, Sendable {
    public let kind: FormPackArtifactKind
    public let identifier: String
    public let resourceName: String
    public let sha256Hex: String
    public let byteCount: Int
    public let authorityRecordID: String
}

public struct ConversionFormPack: Codable, Hashable, Identifiable, Sendable {
    public let manifestVersion: Int
    public let id: String
    public let direction: ConversionDirection
    public let recordVersion: String
    public let clauseVersion: String
    public let namespace: String
    public let eFormIdentifier: String
    public let effectiveFrom: Date
    public let effectiveUntil: Date?
    public let verificationState: FormPackVerificationState
    public let acceptanceState: FormPackAcceptanceState
    public let renderer: FormPackRenderer
    public let artifacts: [FormPackArtifact]
    public let outputProfile: ConversionOutputProfile
    public let newDocumentFormatItem: ZakoCodelistItem
    public let fingerprintMethodItem: ZakoCodelistItem
}

public protocol OfficialFormPackProviding: Sendable {
    func productionPack(for direction: ConversionDirection, at serverTime: Date) throws -> ConversionFormPack
    func validationPack(id: String) throws -> ConversionFormPack
}
```

- [ ] Migrate `FormPackVerificationState`, `FormPackAcceptanceState`, `FormPackRenderer`, and `ConversionFormPack` to the exact interfaces above. Map legacy `.accepted` records to a non-production state unless verified evidence explicitly supports `productionAccepted`.
- [ ] Migrate the existing `ConversionFormPack` without dropping `manifestVersion`, `verificationState`, `acceptanceState`, `renderer`, output-profile mapping, or codelist mappings.
- [ ] Bundle only artifacts whose exact bytes and hashes match verified Phase 0 authority rows. If any required bytes are unavailable, keep the task blocked and do not create a substitute fixture.
- [ ] Verify every bundled artifact hash and authority-record binding at load time.
- [ ] Reject missing roles, duplicate identifiers, expired generation packs, overlapping effective intervals, hash mismatches, `legacySwift` production renderers, and acceptance not confirmed for EZZK.
- [ ] Keep historical packs selectable only through `validationPack(id:)`. Never select an expired pack for new production generation.
- [ ] Remove the implicit `currentLegacyUnverified` selection from every production caller.
- [ ] Require an explicit pack in `AttestationClauseGenerator.generateXML(input:formPack:)` and remove the source-compatible legacy overload after all callers migrate.
- [ ] Return a pack provenance report containing id, versions, namespace, artifact authority IDs and hashes, effective interval, verification state, acceptance state, and renderer.

**Acceptance:**
- Production P2E selection returns exactly one verified, `productionAccepted`, effective pack for EZZK server time.
- A legacy, unverified, unknown, rejected, expired, incomplete, or hash-mismatched pack cannot pass production policy.
- Historical fixtures remain readable for evidence verification and cannot be selected for new generation.
- Missing official artifact bytes leave this task blocked rather than producing a locally invented pack.

### Task 1.2: Implement official XSD validation and XSLT rendering

**Files:**
- Create: `Autogram/Sources/AutogramKit/Attestation/OfficialFormValidator.swift`
- Create: `Autogram/Sources/AutogramKit/Attestation/OfficialFormRenderer.swift`
- Modify: `Autogram/Sources/AutogramKit/Attestation/AttestationXMLValidator.swift`
- Modify: `Autogram/Sources/AutogramKit/Attestation/AttestationClauseGenerator.swift`
- Test: `Autogram/Tests/AutogramKitTests/OfficialFormValidationTests.swift`
- Test fixtures: `Autogram/Tests/Fixtures/ZaKo/FormPacks/<pack-id>/`

**Prerequisites:**
- Task 1.1 provides a verified pack containing separate record and clause schema and stylesheet roles.

**Interfaces:**
```swift
public struct FormArtifactValidationResult: Sendable, Equatable {
    public let artifactKind: FormPackArtifactKind
    public let artifactSHA256Hex: String
    public let inputSHA256Hex: String
    public let isValid: Bool
    public let issues: [String]
}

public struct OfficialFormValidationReport: Sendable, Equatable {
    public let isValid: Bool
    public let validatorName: String
    public let validatorVersion: String
    public let formPackID: String
    public let results: [FormArtifactValidationResult]
}

public struct OfficialFormRenderResult: Sendable, Equatable {
    public let renderedData: Data
    public let sourceXMLSHA256Hex: String
    public let stylesheetSHA256Hex: String
    public let renderedSHA256Hex: String
}

public protocol OfficialFormValidating: Sendable {
    func validate(recordXML: Data,
                  clauseXML: Data,
                  formPack: ConversionFormPack) async throws -> OfficialFormValidationReport
}

public protocol OfficialFormRendering: Sendable {
    func renderClause(xml: Data,
                      formPack: ConversionFormPack) async throws -> OfficialFormRenderResult
    func renderRecord(xml: Data,
                      formPack: ConversionFormPack) async throws -> OfficialFormRenderResult
}
```

- [ ] Write failing tests for valid record and clause XML, wrong namespace, wrong version, unknown codelist value, missing required field, invalid fingerprint, wrong stylesheet role, and artifact hash mismatch.
- [ ] Implement XSD validation through the verified engine adapter using the exact record and clause schemas. Do not infer XSD validity from `XMLDocument` parsing.
- [ ] Implement record and clause XSLT rendering from the exact stylesheets selected by artifact role in the pack.
- [ ] Preserve the existing structural validator only as a separately named diagnostic preflight layer.
- [ ] Make generation and authorization fail if the official validator or renderer is unavailable in production mode.
- [ ] Include validator identity, validator version, exact input hashes, schema and stylesheet hashes, report hash, and render hashes in the evidence audit.

**Acceptance:**
- A syntactically valid but XSD-invalid record or clause is rejected.
- XML generated with a different namespace, version, or codelist is rejected.
- Record and clause renderings are produced by the selected official stylesheets and all source, stylesheet, and output hashes are recorded.
- Local parsing or marker checks cannot set `OfficialFormValidationReport.isValid`.

**Commit:** `feat(zako): validate official form packs and render clauses`

### Task 1.3: Correct codelists and output format values

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Attestation/ZakoCodelists.swift`
- Modify: `Autogram/Sources/AutogramKit/Attestation/AttestationClauseGenerator.swift`
- Modify: `Autogram/Sources/AutogramKit/Models/AttestationData.swift`
- Test: `Autogram/Tests/AutogramKitTests/AttestationXMLTests.swift`

- [ ] Load the accepted P2E format item and all dependent values from the verified codelist artifact. Do not replace `PDFA2` with another hardcoded guess.
- [ ] Map the selected `ConversionOutputProfile` to the exact codelist item identifier and code, not to a display label.
- [ ] Reject missing, expired, unverified, duplicated, or display-only codelist values.
- [ ] Add tests for authority-backed PDF/A-1a, authority-backed PNG when permitted, rejected PDF/A-2b production selection, and a changed codelist hash.
- [ ] Ensure the same accepted format code and codelist artifact hash appear in the output metadata, clause XML, record XML, form-pack stamp, and evidence record.

**Acceptance:**
- No production XML contains `PDF/A-2`, `PDFA2`, `PDF/A-1a`, or a PNG code unless that exact value comes from the effective verified codelist artifact.
- Format-code or codelist-hash mismatch is caught before signing.

---

## Phase 2: PDF/A-1a, PNG, and Output Artifact Validation

### Task 2.1: Implement the accepted production output profiles

**Files:**
- Modify: `Autogram/Sources/AutogramKit/PDFA/ConversionOutputProfile.swift`
- Modify: `Autogram/Sources/AutogramKit/PDFA/PDFAConverter.swift`
- Modify: `Autogram/Sources/AutogramKit/PDFA/ImageToPDFConverter.swift`
- Modify: `Autogram/Sources/AutogramKit/PDFA/EmbeddedFileService.swift`
- Test: `Autogram/Tests/AutogramKitTests/PDFAProfileTests.swift`

**Prerequisites:**
- Verified Phase 0 format-matrix, alternative-warning, MIME, packaging, and conformance-validator rows.
- Task 1.3 provides the accepted output-format codelist mapping.

**Interfaces:**
```swift
public enum OutputProfileAcceptanceState: String, Codable, Hashable, Sendable {
    case pilotOnly
    case sandboxAccepted
    case productionAccepted
    case unavailable
}

public enum ApplicantNoticePolicy: String, Codable, Hashable, Sendable {
    case none
    case priorExplicitAcknowledgement
}

public struct ConversionOutputProfile: Codable, Hashable, Identifiable, Sendable {
    public enum Container: String, Codable, Hashable, Sendable {
        case pdf
        case png
    }

    public let id: String
    public let label: String
    public let container: Container
    public let pdfaPart: Int?
    public let pdfaConformance: String?
    public let requiresTaggedStructure: Bool
    public let requiresUnicodeMapping: Bool
    public let requiresOCRTextLayer: Bool
    public let minimumRasterDPI: Int?
    public let maximumRasterDPI: Int?
    public let requiresLosslessRasterCompression: Bool
    public let maximumPageCount: Int?
    public let requiresGraphicOnlyContent: Bool
    public let noticePolicy: ApplicantNoticePolicy
    public let noticeTextAuthorityID: String?
    public let authorityRecordID: String
    public let externalConformanceEvidenceID: String?
    public let acceptanceState: OutputProfileAcceptanceState
}
```

- [ ] Migrate every caller from `ConversionOutputProfile.VerificationState` to `OutputProfileAcceptanceState`, remove the old state and implicit defaults in the same task, and map existing profiles to non-production states.
- [ ] Write failing tests proving proposed PDF/A-1a, PNG, PDF/A-2b, or another format cannot become production accepted from a local flag or local validator result.
- [ ] Implement PDF/A-1a generation only after its authority row is verified. Enforce embedded fonts, Unicode mapping, tagged structure, XMP metadata, output intent, and the exact OCR and association rules in that row.
- [ ] Implement PNG only after its exact authority scenario is verified. Enforce page count, graphic-only, MIME, compression, packaging, signing, and prior-warning rules.
- [ ] Treat 200 to 300 DPI and lossless compression as authority-controlled raster policy inputs, not as proof of PDF/A or legal conformance.
- [ ] Keep PDF/A-2b explicitly pilot-only unless the verified P2E matrix changes that status.
- [ ] Pass the selected profile, authority record, codelist mapping, and notice policy into clause generation, record generation, preflight, and evidence.
- [ ] Remove the converter restriction that treats the pilot profile as the only implemented profile only after an authority-backed profile passes independent conformance.

**Acceptance:**
- Each declared production profile has verified authority evidence, a reproducible output fixture, and an independent technical conformance report bound to the exact output hash.
- Unsupported, unverified, locally self-accepted, or expired profiles fail before conversion.
- A profile requiring prior warning cannot start conversion without the exact acknowledged warning record.

### Task 2.2: Add OCR, tagged-structure, and independent output verification

**Files:**
- Create: `Autogram/Sources/AutogramKit/PDFA/PDFAConformanceReport.swift`
- Modify: `Autogram/Sources/AutogramKit/PDFA/PDFAValidator.swift`
- Modify: `Autogram/Sources/AutogramKit/PDFA/PDFAConverter.swift`
- Test: `Autogram/Tests/AutogramKitTests/PDFAConformanceTests.swift`

**Prerequisites:**
- Task 2.1 provides an authority-backed profile and names the approved independent validator.

**Interfaces:**
```swift
public enum OutputValidationEvidenceKind: String, Codable, Equatable, Sendable {
    case localPreflight
    case independentConformance
}

public struct PDFAConformanceReport: Codable, Sendable, Equatable {
    public let profileID: String
    public let inputSHA256Hex: String
    public let evidenceKind: OutputValidationEvidenceKind
    public let validatorName: String
    public let validatorVersion: String
    public let executedAt: Date
    public let isValid: Bool
    public let issues: [String]
}
```

- [ ] Write fixtures for vector text, raster scan, mixed text and graphics, rotated pages, mixed page sizes, and pages with no OCR text.
- [ ] Implement deterministic OCR and reading-order/tag construction only to the extent required by the verified output profile.
- [ ] Verify tagged structure, Unicode mapping, embedded fonts, output intent, prohibited features, and profile-specific OCR rules through the approved independent validator, not raw byte markers.
- [ ] Rename the existing local validator result to `PDFAPreflightReport` and mark it `localPreflight`. It may diagnose likely failures but cannot create a `productionAccepted` profile or satisfy a release gate.
- [ ] Validate the final PDF bytes after XML association and normalization. If the confirmed output contract signs the PDF itself, validate again after signing.
- [ ] Bind the independent report to the exact final PDF hash and persist validator identity, version, execution date, report hash, and evidence kind.

**Acceptance:**
- A PDF with correct XMP markers but missing required structure is rejected by independent validation.
- A PDF with invalid Unicode mapping is rejected when the accepted profile requires Unicode mapping.
- OCR absence or presence is evaluated against the verified profile rule, not a hardcoded assumption.
- Every production output hash has an `independentConformance` report from the approved validator. A local preflight report cannot satisfy this criterion.

### Phase 2 exit gate

- The selected P2E output profile has verified authority status and a verified codelist mapping.
- Representative PDF/A-1a or PNG fixtures, only as accepted by the authority matrix, pass approved independent technical validation.
- The exact final output bytes are bound to the independent report and remain unchanged before packaging.
- No production output is generated under a pilot, sandbox-only, unavailable, locally self-accepted, or expired profile.

---

## Phase 3: Input Signature, Certificate, Timestamp, and Package Validation

### Task 3.1: Build an independent input signature verifier

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Signing/InputSignatureVerificationService.swift`
- Create: `Autogram/Sources/AutogramKit/Signing/SignatureValidationReport.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/JavaEngine/EngineBridgeSigningProvider.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/SigningProvider.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/KeychainXAdESSigningProvider.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Test: `Autogram/Tests/AutogramKitTests/InputSignatureVerificationTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/SignatureValidationTests.swift`

**Prerequisites:**
- Verified Phase 0 input-signature policy defining supported formats, trust sources, revocation semantics, qualification rules, timestamp requirements, and the meaning of an unsigned input.

**Interfaces:**
```swift
public enum ValidationConclusion: String, Codable, Hashable, Sendable {
    case valid
    case invalid
    case indeterminate
    case unavailable
}

public enum SignatureFormat: String, Codable, Hashable, Sendable {
    case pades
    case xades
    case cades
    case unknown
}

public enum RevocationStatus: String, Codable, Hashable, Sendable {
    case good
    case revoked
    case indeterminate
    case notChecked
}

public struct SignedObjectReference: Codable, Sendable, Equatable {
    public let identifier: String
    public let digestAlgorithm: String
    public let digestHex: String
    public let resolvedArtifactSHA256Hex: String?
    public let digestMatches: Bool
}

public struct ValidatedTimestamp: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let conclusion: ValidationConclusion
    public let genTime: Date?
    public let tokenSHA256Hex: String?
    public let isQualified: Bool?
    public let messageImprintMatches: Bool?
    public let coveredObject: SignedObjectReference?
}

public struct ValidatedSignature: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let format: SignatureFormat
    public let signerDisplayName: String
    public let signingTime: Date?
    public let conclusion: ValidationConclusion
    public let signatureValueValid: Bool?
    public let certificateFingerprintSHA256Hex: String?
    public let chainConclusion: ValidationConclusion
    public let revocationStatus: RevocationStatus
    public let qualifiedStatus: ValidationConclusion
    public let signedObjects: [SignedObjectReference]
    public let timestamps: [ValidatedTimestamp]
    public let issues: [String]
}

public struct SignatureValidationReport: Codable, Sendable, Equatable {
    public let conclusion: ValidationConclusion
    public let inspectionCompleted: Bool
    public let noSignaturesPresent: Bool
    public let signatures: [ValidatedSignature]
    public let oldestRelevantQualifiedTimestamp: Date?
    public let validatorName: String
    public let validatorVersion: String
    public let validatedInputSHA256Hex: String
}
```

- [ ] Write failing tests for valid and invalid PAdES, XAdES, and CAdES; invalid signature value; digest-only evidence; broken chain; revoked certificate; indeterminate revocation; malformed timestamp; timestamp over the wrong object; unsupported format; completed unsigned inspection; and unavailable inspection.
- [ ] Use the verified engine or an approved independent DSS-equivalent validator for signature value, signed-object, chain, revocation, qualification, and timestamp validation.
- [ ] Distinguish `invalid`, `indeterminate`, and `unavailable`. Never convert unavailable trust or revocation evidence into `valid`.
- [ ] Treat `inspectionCompleted == true && noSignaturesPresent == true` according to the confirmed input policy. Do not treat it as an unavailable inspection.
- [ ] Compute `oldestRelevantQualifiedTimestamp` only from independently valid, qualified timestamp tokens that cover the exact relevant signed object under the confirmed policy. Never substitute claimed signing time.
- [ ] Persist a bounded, content-addressed report artifact rather than embedding unbounded validator output in the UI model.
- [ ] Migrate all callers from `InputSignatureInspectionResult` to `SignatureValidationReport`, then remove the compatibility projection in the same task.

**Acceptance:**
- A valid digest without a valid cryptographic signature value and resolved signed object is not accepted.
- A signature with unavailable trust or revocation status is `indeterminate` or `unavailable`, never `valid`.
- The report binds the validator and exact input hash and distinguishes no signatures from failed inspection.

### Task 3.2: Enforce an authority-backed mandate certificate policy

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Signing/SigningProvider.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/JavaEngine/EngineBridgeSigningProvider.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/KeychainXAdESSigningProvider.swift`
- Create: `Autogram/Sources/AutogramKit/Signing/MandateCertificatePolicy.swift`
- Test: `Autogram/Tests/AutogramKitTests/MandateCertificatePolicyTests.swift`

**Prerequisites:**
- Verified Phase 0 certificate policy, mandate identifiers, trust anchors, revocation method, qualification rule, and private-key proof rule.

**Interfaces:**
```swift
public struct MandateCertificatePolicy: Sendable, Equatable {
    public let authorityRecordID: String
    public let acceptedCertificatePolicies: Set<String>
    public let acceptedMandateOIDs: Set<String>
    public let requireQualifiedStatus: Bool
    public let requirePrivateKey: Bool
}

public struct CertificateValidationReport: Sendable, Equatable {
    public let conclusion: ValidationConclusion
    public let certificateFingerprintSHA256Hex: String
    public let matchedCertificatePolicy: String?
    public let matchedMandateOIDs: Set<String>
    public let qualifiedStatus: ValidationConclusion
    public let chainConclusion: ValidationConclusion
    public let revocationStatus: RevocationStatus
    public let privateKeyPossessionProven: Bool
    public let validatorName: String
    public let validatorVersion: String
    public let issues: [String]
}
```

- [ ] Encode only certificate-policy identifiers, mandate OIDs, trust anchors, and revocation rules from the verified authority row.
- [ ] Replace issuer and subject string heuristics with certificate extension and policy validation.
- [ ] Validate certificate validity interval, key usage, extended key usage, policy OIDs, mandate attributes, chain, revocation, qualified status, and private-key possession.
- [ ] Remove the production non-mandate override path. Keep any override only in demo or pilot mode and prevent its use with sandbox or production credentials and outputs.
- [ ] Revalidate immediately before signing and bind the report to the certificate actually used.
- [ ] Ensure the used certificate matches the identity shown, advocate recorded in the clause, and fingerprint stored in the audit.

**Acceptance:**
- Production signing cannot proceed with an unverified policy, wrong mandate, non-qualified certificate, expired certificate, revoked or indeterminate certificate, broken chain, or unavailable private key.
- The report identifies the exact authority policy, matching OIDs, validator, and certificate fingerprint.

### Task 3.3: Make QTS mandatory and validate the exact timestamp token

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Signing/RFC3161TimestampClient.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/XAdESSigner.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/KeychainXAdESSigningProvider.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/AuthorizeDoneViews.swift`
- Test: `Autogram/Tests/AutogramKitTests/TimestampClientTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/QualifiedTimestampPolicyTests.swift`

**Prerequisites:**
- Verified Phase 0 TSA policy, output signature profile, timestamp placement, exact covered-object rule, and server-time rule.
- Task 3.2 provides the validated signing certificate report.

**Interfaces:**
```swift
public struct TrustedServerTime: Codable, Sendable, Equatable {
    public let value: Date
    public let observedAt: Date
    public let sourceAuthorityID: String
    public let responseArtifact: VerificationArtifactReference
}

public struct QualifiedTimestampReport: Codable, Sendable, Equatable {
    public let conclusion: ValidationConclusion
    public let genTime: Date?
    public let tokenSHA256Hex: String?
    public let tsaCertificateFingerprintSHA256Hex: String?
    public let messageImprintMatches: Bool?
    public let tsaChainConclusion: ValidationConclusion
    public let tsaRevocationStatus: RevocationStatus
    public let qualifiedStatus: ValidationConclusion
    public let coveredObject: SignedObjectReference?
    public let trustedServerTime: TrustedServerTime
    public let validatorName: String
    public let validatorVersion: String
    public let issues: [String]
}
```

- [ ] Write failing tests proving production cannot disable QTS and cannot accept an absent, malformed, unqualified, revoked, indeterminate, wrong-policy, wrong-imprint, wrong-object, or time-inconsistent token.
- [ ] Validate HTTP status, CMS token parsing, message imprint, TSA certificate chain, revocation, qualification, policy, nonce if required, and `genTime`.
- [ ] Verify the token covers the exact signed value or signed object required by the verified P2E output signature profile. Do not modify `PAdESSigner` for ZaKo unless that output profile is separately authority-approved.
- [ ] Compare `genTime` to the verified EZZK server-time and conversion-time rules without falling back to the local clock.
- [ ] Store the token through a content-addressed restricted artifact reference and bind its hash to the report.
- [ ] Keep the QTS toggle only in demo or pilot mode. Production shows a read-only requirement.

**Acceptance:**
- Every production authorization has a validated qualified timestamp report bound to the exact token and covered object.
- A missing, invalid, indeterminate, unavailable, or wrong-object QTS blocks progression and produces a precise validation issue.

### Task 3.4: Build and independently validate the final P2E package

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Evidence/ASiCEVerifier.swift`
- Modify: `Autogram/Sources/AutogramKit/Evidence/ASiCEPackager.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/XAdESSigner.swift`
- Test: `Autogram/Tests/AutogramKitTests/EvidenceAndPackagingTests.swift`

**Prerequisites:**
- Verified Phase 0 package profile, MIME rules, signature profile, signed-object contract, and timestamp placement.
- Tasks 2.2, 3.2, and 3.3 provide validated output, certificate, and QTS evidence.

**Interfaces:**
```swift
public struct PackageValidationReport: Codable, Sendable, Equatable {
    public let conclusion: ValidationConclusion
    public let packagingProfileID: String
    public let containerSHA256Hex: String
    public let signedObjects: [SignedObjectReference]
    public let signatureReport: SignatureValidationReport
    public let timestampReport: QualifiedTimestampReport
    public let validatorName: String
    public let validatorVersion: String
    public let issues: [String]
}
```

- [ ] Write failing tests for every package invariant in the verified profile, including missing or extra signature artifacts, invalid signature value, missing certificate, missing timestamp, wrong signed object, digest mismatch, manifest mismatch, MIME mismatch, duplicate name, absolute path, and parent traversal.
- [ ] Package only the exact output, clause, record, signature, and metadata objects required by the verified P2E profile. Do not assume the current ASiC-E shape is authoritative.
- [ ] Verify every resolved signed-object reference and digest, the cryptographic signature value, signing certificate, chain, revocation, qualified status, signature policy, signed properties, and QTS token.
- [ ] Bind the final package report to the exact container hash and the already validated output, clause, and record hashes.
- [ ] Reject a structurally valid but unsigned, partially signed, marker-only, or locally self-validated container.

**Acceptance:**
- The final package matches the authority-backed profile and passes the approved independent signature and package validator.
- No unsigned, partially signed, wrong-object, or tampered package can be marked valid.
- Input PAdES, XAdES, and CAdES reports remain distinct from the output package authorization report.

**Commit:** `feat(zako): validate signatures timestamps and final package`

### Phase 3 exit gate

- Input-signature inspection is complete and fail-closed under the verified input policy.
- The mandate certificate, output signature, QTS token, every signed object, and the final package pass approved independent validation.
- The oldest relevant qualified timestamp is derived only from valid qualified tokens over relevant input objects.
- No production signing or packaging assumption remains supported only by a working note, local marker, demo signer, or guessed profile.

---

## Phase 4: Audit Model and Human Review Evidence

### Task 4.1: Extend the evidence model with complete provenance

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Evidence/LocalEvidenceStore.swift`
- Modify: `Autogram/Sources/AutogramKit/Models/DomainModels.swift`
- Test: `Autogram/Tests/AutogramKitTests/EvidenceAuditTests.swift`

**Prerequisites:**
- Task 0.3 provides `VerificationArtifactReference`.
- Tasks 1.2 through 3.4 define the report artifacts and hashes that evidence records reference.

**Interfaces:**
```swift
public enum ZaKoProductionStage: String, Codable, Hashable, Sendable {
    case intakeFrozen
    case numberReserved
    case artifactsGenerated
    case artifactsValidated
    case signed
    case timestampValidated
    case packageValidated
    case auditPersisted
    case submissionPending
    case submitted
    case permanentlyRejected
    case evidenceExported
}

public struct EvidenceAuditEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let stage: ZaKoProductionStage
    public let occurredAt: Date
    public let inputArtifactSHA256Hexes: [String]
    public let outputArtifactSHA256Hexes: [String]
    public let evidence: [VerificationArtifactReference]
}
```

- [ ] Add runtime mode, provider capability, endpoint configuration hash, authority snapshot, form-pack stamp, output-profile stamp, input-signature report, oldest relevant qualified timestamp, certificate report, QTS token and report, PDF/A preflight and conformance reports, XML report, form-render report, package report, and EZZK request and response references.
- [ ] Add source-origin confirmation, detector provider and version, reviewer identity, review timestamp, page decisions, element decisions, physical-sheet decision, paper-size decisions, alternative-format notice acknowledgement, and override reason.
- [ ] Add separate `serverTimeObservedAt`, `conversionTime`, `evidenceNumberIssuedAt`, `evidenceNumberExpiresAt`, `submissionWindowStartedAt`, `submissionDueAt`, `signedAt`, `submissionAttemptedAt`, `submittedAt`, and `permanentlyRejectedAt` fields. Do not derive both EZZK deadlines from one timestamp.
- [ ] Append immutable stage events that bind each stage input hash, output hash, report reference, and time. Status projections may change, but prior events and artifacts may not be rewritten.
- [ ] Version the Codable model and provide explicit migration for existing pilot records. Migrated records remain pilot and do not acquire production evidence by default.
- [ ] Store sensitive report files with restrictive permissions and content hashes.
- [ ] Never persist PINs, passwords, private keys, raw authentication headers, reusable bearer tokens, or unredacted credential payloads.

**Acceptance:**
- One evidence record is traceable by hashes from frozen input through generation, validation, authorization, timestamp, packaging, EZZK submission, response, and export.
- Separate number-validity and submission-deadline timestamps are preserved exactly as returned or derived under the verified contract.
- Existing pilot records decode without being falsely upgraded to sandbox or production.

### Task 4.2: Persist input-signature evidence and oldest relevant QTS

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Attestation/AttestationClauseGenerator.swift`
- Modify: `Autogram/Sources/AutogramKit/Attestation/AttestationXMLValidator.swift`
- Modify: `Autogram/Sources/AutogramKit/Models/AttestationData.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Test: `Autogram/Tests/AutogramKitTests/InputSignatureAuditTests.swift`

**Prerequisites:**
- Task 3.1 provides `SignatureValidationReport`.
- Verified form-pack mappings identify any official fields for foreign-signature status and timestamp provenance.

- [ ] Map foreign-signature status and oldest-relevant-qualified-timestamp values only to fields defined by the verified record and clause schemas.
- [ ] Do not invent an XML extension for a report reference. When no official form field exists, retain the content-addressed report only in the evidence package.
- [ ] Persist the input signature report, exact inspected input hash, `noSignaturesPresent`, every signature conclusion, timestamp-token evidence, and `oldestRelevantQualifiedTimestamp`.
- [ ] Reject production generation when inspection is unavailable or when the report conclusion does not satisfy the verified input policy.
- [ ] Ensure each recorded fingerprint names its artifact and byte boundary: frozen input, generated output, record XML, clause XML, signed package, or EZZK submitted object.
- [ ] Add an audit-package manifest linking all artifacts and reports by SHA-256.

**Acceptance:**
- The final evidence package contains independently verifiable input-signature and timestamp evidence for the exact frozen input.
- XML contains only fields and values accepted by the selected official form pack.
- The oldest timestamp in XML and audit, when required, equals the earliest valid qualified token over a relevant input object and never a claimed signing time.

### Task 4.3: Preserve operator facts, document analysis, and human review gates

**Files:**
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/AnalysisCanvasView.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/AttestationFormView.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/AuthorizeDoneViews.swift`
- Modify: `Autogram/Sources/AutogramKit/Models/DomainModels.swift`
- Test: `Autogram/Tests/AutogramKitTests/AttestationValidatorTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/AccessibilityContractTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/ProductionMessagingTests.swift`

- [ ] Require an audited operator confirmation that the paper input is an original or officially certified copy, using counsel-approved text, operator identity, and timestamp.
- [ ] Keep physical sheet count and its simplex, duplex, or manual method separate from PDF page count and non-empty page count.
- [ ] Require an explicit reviewed paper-size classification for every non-empty page. Block unknown sizes and test mixed-size documents.
- [ ] Require an explicit page decision for every non-empty page, including a positive "no additional security element" decision.
- [ ] Require explicit confirmation, rejection, or corrected classification for every AI-proposed and manually added security element.
- [ ] Invalidate the page review when page bytes, crop, rotation, paper size, sheet method, element location, element type, or description changes.
- [ ] If the selected output profile requires prior warning, record the exact authority-approved text ID, text hash, applicant acknowledgement, operator identity, and acknowledgement time before conversion starts.
- [ ] Show review completion, reviewer identity, source-origin confirmation, sheet method, paper-size decisions, alternative-format acknowledgement, and decision timestamp in the authorization summary.
- [ ] Keep AI provider and model metadata in the audit, while ensuring AI output never becomes an accepted decision automatically.
- [ ] Add VoiceOver labels and keyboard access for every review state and blocked reason.

**Acceptance:**
- Any changed source fact, page, sheet method, paper size, warning acknowledgement, or security element reopens the required review.
- A stale, incomplete, AI-only, or UI-only review cannot satisfy production preflight.
- The working specifications' source, page, sheet, format-warning, and human-review requirements have explicit audit evidence.

**Commit:** `feat(zako): persist complete conversion audit and review evidence`

### Phase 4 exit gate

- Every operator fact, human decision, validator report, and artifact transition has immutable, content-addressed audit evidence.
- Input-signature evidence and oldest relevant QTS are present in official XML only where the verified schema permits and are always present in the evidence package when applicable.
- Historical and pilot records remain distinguishable from new production records.

---

## Phase 5: EZZK Gateway, Number Validity, and Submission Deadline

### Task 5.1: Implement the confirmed EZZK protocol adapter

**Files:**
- Modify: `Autogram/Sources/AutogramKit/EZZK/EZZKService.swift`
- Create: `Autogram/Sources/AutogramKit/EZZK/EZZKGateway.swift`
- Create: `Autogram/Sources/AutogramKit/EZZK/EZZKProtocolModels.swift`
- Test: `Autogram/Tests/AutogramKitTests/EZZKGatewayTests.swift`

**Prerequisites:**
- Verified Phase 0 EZZK sandbox and production endpoints, registration prerequisites, authentication, transport request-signature, signed business object, server-time, response, idempotency, retry, and rejection contracts.

**Interfaces:**
```swift
public protocol EZZKGateway: Sendable {
    var capability: EZZKProviderCapability { get }
    var configurationSHA256Hex: String { get }
    func serverTime() async throws -> TrustedServerTime
    func reserveEvidenceNumber(for request: EvidenceNumberRequest) async throws -> EvidenceNumberReservation
    func submit(_ submission: EZZKSubmission) async throws -> EZZKSubmissionResult
}

public struct EvidenceNumberRequest: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let count: Int
    public let direction: ConversionDirection
    public let formPackID: String
}

public enum EvidenceNumberLifecycleState: String, Codable, Equatable, Sendable {
    case reserved
    case boundToRecord
    case consumed
    case expired
    case rejected
}

public struct EvidenceNumberReservation: Codable, Sendable, Equatable {
    public let number: String
    public let reservationID: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let state: EvidenceNumberLifecycleState
    public let responseArtifact: VerificationArtifactReference
}

public struct EZZKSubmissionWindow: Codable, Sendable, Equatable {
    public let startedAt: Date
    public let dueAt: Date
    public let anchorAuthorityID: String
}

public struct EZZKSubmission: Codable, Sendable, Equatable {
    public let idempotencyKey: String
    public let evidenceNumber: String
    public let formPackID: String
    public let signedRecord: Data
    public let signedRecordSHA256Hex: String
    public let signedObject: SignedObjectReference
    public let submissionWindow: EZZKSubmissionWindow
}

public enum EZZKSubmissionDisposition: String, Codable, Equatable, Sendable {
    case accepted
    case retryableFailure
    case permanentRejection
    case indeterminate
}

public struct EZZKSubmissionResult: Codable, Sendable, Equatable {
    public let disposition: EZZKSubmissionDisposition
    public let serverRecordID: String?
    public let serverCode: String?
    public let serverTime: Date?
    public let responseArtifact: VerificationArtifactReference
    public let transportSignatureReport: VerificationArtifactReference?
}
```

- [ ] Implement only the verified protocol. Do not guess endpoint names, JSON or SOAP shapes, authentication fields, transport signatures, or signed business objects.
- [ ] Migrate all callers from `EZZKServicing` to `EZZKGateway`, remove `HTTPSEZZKService` as a production path, and retain `MockEZZKService` only with `.mock` capability for demo and tests.
- [ ] Separate transport, authentication, transport request signing, business-object signing, response parsing, and failure disposition.
- [ ] Bind sandbox and production configurations to separate provider capabilities, authority IDs, endpoint allowlists, credentials, and configuration hashes.
- [ ] Use only the confirmed authentication mechanism. Never place a password in an ad hoc payload.
- [ ] Submit the exact signed record object required by EZZK and bind its byte hash and signature reference to the request and audit.
- [ ] Redact credentials, reusable tokens, authentication headers, and signed payload bytes from logs.
- [ ] Inject transport and clock only into unit-test adapters. Neither injection may allow a test adapter to claim production capability.

**Acceptance:**
- Offline contract fixtures verify exact request bytes, transport signature, authentication metadata, response parsing, and error mapping.
- A real sandbox run returns a captured, redacted allocation response and submission response for the exact signed record hash.
- An unconfigured, mismatched, mock, pilot, sandbox, or non-submitting gateway fails production preflight before number allocation or artifact generation.

### Task 5.2: Implement separate evidence-number and submission deadlines

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Evidence/LocalEvidenceStore.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/AttestationFormView.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/EvidenceDashboardView.swift`
- Test: `Autogram/Tests/AutogramKitTests/EvidenceNumberLifecycleTests.swift`

**Prerequisites:**
- Task 5.1 provides verified server time and reservation responses.
- Phase 0 separately verifies the number-validity and submission-deadline rules.

- [ ] Persist reservation ID, request ID, issued time, expiry time, lifecycle state, response hash, submission-window anchor, submission due time, and server-time evidence.
- [ ] Allocate the evidence number at the exact point required by the verified contract and before any operation the contract defines as conversion start.
- [ ] Calculate number expiry and record-submission due time from their separate verified anchors. Do not use `Date()` or one shared hardcoded 24-hour interval.
- [ ] Refuse binding, signing, or submission with an expired, consumed, rejected, or wrong-session reservation according to the verified lifecycle.
- [ ] Add separate warnings and terminal states for number expiry and submission deadline.
- [ ] Prevent concurrent sessions from binding or consuming the same reservation through an atomic store operation.

**Acceptance:**
- Tests independently cover number reservation, binding, consumption, expiry, duplicate use, wrong-session use, server-clock skew, submission-window start, submission deadline, timeout, and restart recovery.
- The UI never conflates an expired number, overdue submission, retryable queue entry, permanent rejection, or accepted record.

### Task 5.3: Implement contract-defined idempotency, retry, and rejection

**Files:**
- Modify: `Autogram/Sources/AutogramKit/EZZK/EZZKGateway.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/EvidenceDashboardView.swift`
- Test: `Autogram/Tests/AutogramKitTests/EZZKSubmissionTests.swift`

**Prerequisites:**
- Verified Phase 0 idempotency, retry, duplicate-query, response-code, and permanent-rejection rules.

- [ ] Construct or obtain the idempotency key exactly as the verified contract requires. Do not invent a fingerprint formula when the contract owns the key.
- [ ] Classify timeout, network, HTTP, SOAP, schema, authentication, signature, expired-number, duplicate, and server responses only according to the verified contract.
- [ ] Treat ambiguous outcomes as `indeterminate` until the confirmed query or reconciliation operation proves acceptance or retry safety.
- [ ] Store every attempt number, request hash, idempotency key, server code, response artifact, disposition, and next permitted action.
- [ ] Keep `queuedForSubmission` only for contract-confirmed retryable outcomes.
- [ ] Use a terminal permanent-rejection state until a new user action and contract rule permits a new record.
- [ ] Apply bounded retry only where the verified idempotency or reconciliation contract proves that duplicate EZZK records cannot be created.

**Acceptance:**
- Sandbox evidence proves replay or reconciliation of the same submission cannot create a second EZZK record.
- A permanent rejection never re-enters retry automatically.
- An indeterminate response never becomes accepted or retryable by local assumption.

**Commit:** `feat(zako): integrate verified idempotent EZZK gateway`

### Phase 5 exit gate

- Real sandbox evidence proves server time, number reservation, exact signed submission, separate number-validity and submission-deadline handling, duplicate reconciliation, timeout, permanent rejection, and safe retry behavior.
- The production endpoint, registration state, credentials, request-signature profile, and provider capability are verified and required for production mode.
- Request and response evidence proves the submitted bytes equal the exact independently validated signed record required by EZZK.

---

## Phase 6: Pipeline Cutover and Production UX

### Task 6.1: Make the production stage order explicit and fail-closed

**Files:**
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Modify: `Autogram/Sources/AutogramKit/Models/AttestationPreflight.swift`
- Create: `Autogram/Sources/AutogramKit/Models/ZaKoProductionPreflight.swift`
- Test: `Autogram/Tests/AutogramKitTests/ZaKoProductionPreflightTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/ConversionPipelineIntegrationTests.swift`

**Prerequisites:**
- Phases 0 through 5 have passed their exit gates.

**Interfaces:**
```swift
public struct ZaKoProductionGate: Sendable, Equatable {
    public let targetStage: ZaKoProductionStage
    public let errors: [ZaKoProductionValidationError]
    public var isSatisfied: Bool { errors.isEmpty }
}

public enum ZaKoProductionValidationError: Error, Sendable, Equatable {
    case wrongRuntimeOrProviderCapability
    case externalAuthorityBlocked(String)
    case formPackNotEligible
    case outputProfileNotEligible
    case sourceOriginNotConfirmed
    case sheetCountNotConfirmed
    case paperSizeNotConfirmed
    case alternativeFormatNoticeNotAcknowledged
    case pagesNotReviewed
    case securityElementsNotReviewed
    case inputSignatureInspectionNotValid
    case trustedServerTimeUnavailable
    case evidenceNumberUnavailable
    case evidenceNumberExpired
    case mandateCertificateNotValid
    case officialXMLValidationFailed
    case independentOutputValidationFailed
    case signatureValidationFailed
    case qualifiedTimestampValidationFailed
    case packageValidationFailed
    case auditPersistenceFailed
    case submissionDeadlineExpired
    case ezzkNotConfigured
}
```

- [ ] Implement and test this exact state order: freeze input; independently inspect input signatures; complete source, page, sheet, paper-size, security-element, and warning decisions; obtain trusted server time; reserve and bind an evidence number; generate output, record XML, and clause XML in memory; validate output and XML; render official views; sign the exact contract objects; obtain and validate QTS; build and independently validate the final package; atomically persist signed evidence; submit the exact signed EZZK record; persist the response; export evidence only as a separate requested operation.
- [ ] Keep generation, validation, signing, timestamp validation, package validation, EZZK submission, audit persistence, and evidence export as separate stage transitions with typed inputs and immutable output hashes.
- [ ] Write negative integration tests that attempt to skip, reorder, repeat, or feed stale bytes into every stage.
- [ ] Keep UI button state as a convenience only. `ZaKoProductionGate` and stage transitions are authoritative.
- [ ] Recompute the applicable gate after every input, review, identity, authority artifact, form-pack, profile, trusted-time, reservation, endpoint, and runtime-mode change.
- [ ] Recheck authority status and exact artifact hashes immediately before signing and immediately before EZZK submission.
- [ ] Ensure stale async results cannot replace any state or artifact in a new session.
- [ ] Keep generated bytes in memory or restricted temporary storage until validation completes. Atomically persist the independently validated signed evidence before network submission.
- [ ] If EZZK submission fails, preserve signed evidence and the attempt record, but never report it as submitted.

**Acceptance:**
- No stage can consume bytes or evidence from a non-preceding, stale, failed, or different-session stage.
- No production-looking artifact is persisted before the required generation and validation gates pass.
- No EZZK submission occurs before exact-object signature, QTS, package, and audit-persistence gates pass.
- Export never mutates conversion, signature, timestamp, submission, or audit state.

### Task 6.2: Correct production UI and legal-status messaging

**Files:**
- Modify: `Autogram/Sources/AutogramApp/Views/AttestationFormView.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/AuthorizeDoneViews.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/EvidenceDashboardView.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/SettingsView.swift`
- Test: `Autogram/Tests/AutogramKitTests/AccessibilityContractTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/ProductionMessagingTests.swift`

- [ ] Show the exact selected output profile, form-pack versions, runtime mode, provider capability, endpoint authority ID, current stage, and each validator evidence kind.
- [ ] Replace generic `PDF/A` labels with the exact profile only when an authority-backed profile is actually selected.
- [ ] Present any required alternative-format warning before conversion and show the exact acknowledgement evidence in the authorization summary.
- [ ] Show QTS and mandate certificate as production requirements, not optional preferences.
- [ ] Do not claim production legal effect, authority acceptance, independent conformance, or EZZK acceptance for demo, pilot, sandbox, local-preflight, or unverified evidence.
- [ ] Show number expiry and submission deadline separately, including trusted server time, retryable state, indeterminate outcome, permanent rejection reason, and accepted server receipt.
- [ ] Keep all stage status, evidence kind, warning, and blocked reasons accessible through VoiceOver and keyboard navigation.

**Acceptance:**
- A user can identify the exact blocked stage, authority row, artifact, evidence kind, or EZZK state.
- Demo, pilot, sandbox, and production screens and evidence statuses cannot be mistaken for one another.
- UI text cannot convert a local test, local preflight, sandbox receipt, or working specification into a production claim.

### Task 6.3: Produce a complete exportable evidence package

**Files:**
- Create: `Autogram/Sources/AutogramKit/Evidence/EvidencePackageExporter.swift`
- Modify: `Autogram/Sources/AutogramKit/Evidence/LocalEvidenceStore.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/EvidenceDashboardView.swift`
- Test: `Autogram/Tests/AutogramKitTests/EvidencePackageExporterTests.swift`

**Interfaces:**
```swift
public enum EvidencePackageEntryKind: String, Codable, Equatable, Sendable {
    case authoritySnapshot
    case frozenInput
    case generatedOutput
    case recordXML
    case clauseXML
    case officialRendering
    case signedPackage
    case validatorReport
    case timestampToken
    case ezzkRequest
    case ezzkResponse
    case humanReviewAudit
    case stageAudit
}

public struct EvidencePackageManifest: Codable, Sendable, Equatable {
    public let recordID: UUID
    public let entries: [EvidencePackageEntry]
    public let manifestSHA256Hex: String
}

public struct EvidencePackageEntry: Codable, Sendable, Equatable {
    public let relativePath: String
    public let kind: EvidencePackageEntryKind
    public let sha256Hex: String
    public let byteCount: Int
}
```

- [ ] Export the authority snapshot; frozen-input fingerprint; final PDF or PNG; record and clause XML; official renderings; final signed package; form, output, signature, certificate, QTS, and package reports; timestamp token; EZZK request and response; human review; deadline evidence; and immutable stage audit.
- [ ] Generate a canonical manifest with deterministic ordering, normalized relative paths, byte counts, and SHA-256 for every entry.
- [ ] Exclude credentials, PINs, private keys, raw authentication headers, reusable tokens, and unredacted secrets.
- [ ] Verify the exported package by re-reading every entry, rejecting path traversal or duplicates, and recomputing each entry and manifest hash.
- [ ] Make export available for signed, queued, indeterminate, permanently rejected, and submitted records without mutating their state.

**Acceptance:**
- An exported package can be technically inspected without the application database and preserves evidence-kind distinctions.
- The manifest detects addition, removal, replacement, reordering, or path substitution.
- Export cannot be represented as independent validation or legal approval.

**Commit:** `feat(zako): cut over production pipeline and evidence export`

### Phase 6 exit gate

- Production authorization is domain-gated and independent of UI state.
- Generation, validation, signing, timestamp, package validation, EZZK submission, audit persistence, and export have separate typed stages and immutable hash handoffs.
- UI accurately distinguishes demo, pilot, sandbox, and production and separates both EZZK deadlines.
- A complete evidence package can be exported and locally integrity-verified without claiming external conformance.

---

## Phase 7: External Conformance and Release Qualification

### Task 7.1: Build the external validation and interoperability fixture set

**Files:**
- Create: `Autogram/Tests/Fixtures/ZaKo/Production/`
- Create: `Autogram/docs/zako/external-validation-report.md`
- Create: `Autogram/docs/zako/release-checklist.md`

**Prerequisites:**
- Phases 0 through 6 have passed their exit gates.

- [ ] Include representative scans with official stamps, handwritten signatures, embossed seals, QR codes, OCR text, tables, mixed page sizes, rotations, blank pages, false-positive candidates, and unknown paper-size negatives.
- [ ] Include completed unsigned input inspection plus valid, invalid, revoked, indeterminate, unavailable, wrong-object, and malformed PAdES, XAdES, and CAdES cases under the verified input policy.
- [ ] Include valid, expired, revoked, indeterminate, unqualified, wrong-imprint, wrong-object, and malformed timestamp tokens.
- [ ] Include vector, raster, OCR, mixed-content, tagged-structure, Unicode, and negative outputs for each authority-accepted production profile. Do not label PDF/A-1a or PNG production fixtures unless their authority rows are verified.
- [ ] Include current production form-pack, historical-validation pack, wrong-effective-date, wrong-namespace, wrong-XSD, wrong-XSLT, changed-codelist, and changed-artifact-hash fixtures.
- [ ] Include valid and invalid final-package fixtures for every exact signed-object and MIME invariant in the accepted package profile.
- [ ] Include redacted real EZZK sandbox server-time, number-allocation, submission, duplicate reconciliation, retryable, indeterminate, and permanent-rejection captures.
- [ ] Record validator or sandbox identity, version or environment, command or request ID, exact input and output hashes, date, result, evidence kind, and report hash for every fixture.

### Task 7.2: Run focused, integration, sandbox, and external verification

**Commands:**
```bash
cd "/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram"
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh
```

- [ ] Run each task's focused behavioral tests, including negative fail-closed cases.
- [ ] Run the full Swift test suite after each phase and the packaged application build at release qualification.
- [ ] Run offline integration tests for every typed stage handoff, stale-result rejection, atomic audit write, restart recovery, and export integrity.
- [ ] Run the app in sandbox mode through the complete P2E flow with real sandbox server time, number allocation, signed submission, and server receipt.
- [ ] Prove production configuration rejects mock, demo, pilot, sandbox, and non-submitting transports. Do not exercise a dry-run transport inside production mode.
- [ ] Perform only a contract-permitted production connectivity or authentication readiness check that cannot allocate a number or submit a record, if the authoritative contract provides such an operation.
- [ ] Verify exact final artifacts with the approved independent output, XML/XSD, signature, timestamp, and package validators. Store their raw reports as content-addressed evidence.
- [ ] Reconcile every external report input hash with the final evidence package and EZZK submitted-object hash.
- [ ] Exercise VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency, and at least three window sizes.
- [ ] Confirm `BuiltInVisionProvider.swift` has no unrelated changes.
- [ ] Review all compiler warnings and either fix in scope or record them as release blockers with owners.

**Acceptance:**
- All focused and full local tests pass and the packaged build succeeds.
- Local results are labelled only as local test or preflight evidence.
- Independent validator reports are attached for the exact released form, output, signature, timestamp, and package hashes.
- Real sandbox request and response evidence proves the complete EZZK lifecycle and exact submitted-object hash.
- Production capability checks reject every test, mock, pilot, sandbox, and non-submitting provider.
- No unresolved Critical or Important review finding or external authority blocker remains.

### Task 7.3: Release approval and production enablement

**Files:**
- Modify: `Autogram/docs/zako/release-checklist.md`
- Modify: `Autogram/docs/zako/authority-register.md`
- Modify: `Autogram/Sources/AutogramKit/Support/AppSettings.swift`

- [ ] Require explicit approval for the working-requirement coverage matrix; authority snapshot; form-pack and codelist hashes; output-profile and alternative-warning policy; validator identities and versions; output signature and package profiles; exact signed objects; mandate and TSA policies; EZZK contract and production endpoint; separate number-validity and submission-deadline rules; sandbox evidence; and release artifact hashes.
- [ ] Enable production mode only when every Phase 0 through Phase 7 exit gate is checked and no required authority row is blocked, unverified, expired, or missing.
- [ ] Keep production enablement behind a versioned configuration flag disabled by default in development and test builds.
- [ ] Make the production flag reject configuration-hash drift and require a new release approval after any authority artifact, validator, endpoint, certificate policy, TSA policy, package profile, or warning-text change.
- [ ] Document rollback to sandbox mode without deleting, rewriting, or reclassifying evidence records.
- [ ] Record the first production release version and all component and evidence hashes in the authority register.

**Acceptance:**
- Production enablement is reproducible from authority artifacts, independent reports, real sandbox evidence, and the release checklist.
- No local test, local validator, working note, or UI flag can enable production.
- Rollback does not convert submitted, rejected, indeterminate, queued, pilot, or sandbox records into another status.

**Commit:** `chore(zako): qualify production release and enable approved profile`

---

## Separate Post-Production Scope: E2P and E2E

Do not expand the P2E production gate to cover these directions by reusing hardcoded P2E assumptions, artifacts, signatures, packaging rules, or EZZK mappings.

### E2P requirements

- Treat the supplied XMLDataContainer statement only as an unverified working requirement.
- Obtain authoritative E2P record and clause form packs, output format, XMLDataContainer profile if applicable, codelists, packaging profile, EZZK mapping, and acceptance evidence.
- Define the exact signed objects, output signature profile, QTS coverage, rendering, and print-conversion evidence.
- Add a separate session store or direction-specific typed pipeline.
- Add E2P-specific fixtures, XSD/XSLT validation, signature validation, EZZK sandbox tests, audit, evidence export, and independent conformance.

### E2E requirements

- Obtain authoritative E2E record and clause form packs, output format, packaging profile, EZZK mapping, and acceptance evidence.
- Define how the original electronic document, its signatures, the converted output, and the new clause are linked.
- Preserve and validate input signatures under the E2E-specific contract.
- Define the accepted output format, exact signed objects, QTS coverage, and package validation.
- Add a separate typed pipeline and independent end-to-end conformance evidence before exposing E2E in any production UI.

### Batch and scanner capabilities

- Treat batch conversion, scanner/ImageCapture integration, and background EZZK submission as separate projects.
- Each capability requires its own authority impact review, concurrency, cancellation, idempotency, audit, deadline, sandbox, and conformance tests.

---

## Recommended Implementation Order

1. Phase 0 authority register and runtime modes.
2. Phase 1 official form packs, codelists, XSD validation, and XSLT rendering.
3. Phase 2 authority-accepted P2E output and independent artifact validation.
4. Phase 3 input signatures, mandate certificate, QTS, exact signed objects, and final package.
5. Phase 4 immutable audit, input-signature evidence, source facts, and human review.
6. Phase 5 confirmed EZZK gateway, separate deadlines, idempotency, retry, and rejection.
7. Phase 6 typed pipeline cutover, production UX, and evidence export.
8. Phase 7 focused tests, integration tests, real sandbox evidence, external conformance, and release qualification.
9. Only after P2E release approval: separate E2P and E2E projects.

## Non-Negotiable Production Exit Criteria

- [ ] Every claim from the three supplied files maps to a plan task, blocker, evidence gate, or separate future project.
- [ ] No required authority row is blocked, unverified, expired, missing, or supported only by a working specification.
- [ ] The P2E format matrix and exact codelist values are verified and approved.
- [ ] The accepted P2E form pack contains verified record and clause versions, namespaces, XSD, XSLT, codelists, effective intervals, EZZK acceptance, and hashes.
- [ ] PDF/A-1a, PNG, or any alternative is enabled only under the verified matrix. Required tagging, Unicode, OCR, DPI, compression, MIME, packaging, and prior-warning rules are enforced.
- [ ] Any required alternative-format warning is acknowledged before conversion and preserved with text hash, applicant acknowledgement, operator identity, and time.
- [ ] Final output and XML pass approved independent validation bound to their exact hashes. Local marker or parsing checks remain preflight only.
- [ ] Input PAdES, XAdES, and CAdES are independently validated under the verified policy, including exact signed objects, chain, revocation, qualification, and timestamp evidence.
- [ ] A completed no-signature inspection is distinguished from an unavailable inspection.
- [ ] The mandate certificate, private-key possession, output signature, certificate chain, revocation, qualified status, signature policy, QTS token, timestamp imprint, and exact covered object are independently validated.
- [ ] The final package profile, MIME, signature value, signed properties, and every signed-object reference are authority-backed and independently validated.
- [ ] Source origin, physical sheets, page counts, paper sizes, every non-empty page, and every proposed or manual security element have explicit human decisions.
- [ ] Input signature report, oldest relevant qualified timestamp, validator references, authority snapshot, warning acknowledgement, and human review audit are persisted.
- [ ] Real EZZK sandbox evidence proves authentication, transport request signature, server time, number reservation, exact signed submission, server receipt, idempotency or reconciliation, safe retry, indeterminate handling, and permanent rejection.
- [ ] Evidence-number validity and record-submission deadline have separate verified anchors, times, warnings, and terminal states.
- [ ] Production mode cannot use mock, demo, pilot, sandbox, non-submitting, arbitrary-endpoint, unverified-pack, pilot-profile, local-validator, or non-mandate overrides.
- [ ] Generation, validation, signing, timestamp, package validation, EZZK submission, audit, and export remain separate typed stages with immutable hash handoffs.
- [ ] The complete evidence package can be exported and integrity-verified without being misrepresented as independent conformance or legal approval.
- [ ] Independent conformance reports, real sandbox evidence, counsel approvals, product approval, and release approval are attached to the release checklist.
