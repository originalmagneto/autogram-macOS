# P2E Conformance and EZZK Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic validation for the official P2E v1.3 clause target, retain a v1.2 Podpisuj reference profile, and expose separate EZZK protocol boundaries without inventing authentication.

**Architecture:** Add an official P2E v1.3 clause profile backed by the Slovensko.sk form catalogue, keep the observed Podpisuj v1.2 profile for regression fixtures, and keep the published CEZZK record at v1.0 until the announced v1.2 effective date. A conformance validator will reuse the existing ASiC ZIP and digest verifier, parse XMLDataContainer metadata, validate clause and record invariants, and compare both artifacts. Split the existing EZZK service contract into server-clock, evidence-number, and submission capabilities while preserving the existing HTTP and mock behavior.


The consolidated reverse-engineering and implementation record is maintained in `docs/P2E-EZZK-FINDINGS.md`. It contains the official source URLs, observed Podpisuj reference details, authenticated EZZK API contract, implementation boundaries, verification evidence, and update triggers.

**Tech Stack:** Swift 6, Foundation XMLDocument, CryptoKit SHA-256, XCTest, existing AutogramKit ASiC packager/verifier.

## Global Constraints

- The target clause profile is the official v1.3 dataset published by Slovensko.sk.
- The observed Podpisuj v1.2 profile remains available only for fixture validation.
- The CEZZK page announces record form v1.2 effective 2027-01-01. Recheck the official page and dataset before changing the record profile.
- Official source URLs are centralized in `P2EConformanceProfile` for update checks.
- Do not add guessed authentication or submission credentials.
- Do not modify the installed Podpisuj application.
- Existing `EZZKServicing`, `MockEZZKService`, and `HTTPSEZZKService` behavior remains source-compatible.
- New comments and interface text use English for code and Slovak for user-visible messages.
- No em dash characters in new files or text.

---

### Task 1: Add P2E profiles and source references

**Files:**
- Create: `Autogram/Sources/AutogramKit/Attestation/P2EConformanceProfile.swift`
- Test: `Autogram/Tests/AutogramKitTests/P2EConformanceTests.swift`

**Interfaces:**
- Produces `P2EConformanceProfile.targetV1_3` with the official clause v1.3 namespace and identifier.
- Produces `P2EConformanceProfile.referenceV1_2` for the observed Podpisuj fixture.
- Exposes official metadata, archive, and CEZZK documentation URLs for repeatable update checks.

- [ ] **Step 1: Define immutable profile constants**

Define a `public struct P2EConformanceProfile: Sendable, Equatable` with fields for XDCF namespace, clause namespace, clause identifier, clause root, record namespace, record root, clause XDCF version, record XDCF version, XDCF MIME type, PDF MIME type, PDF/A-2 code/name, SHA-256 code/name, and evidence URI prefix. Add `targetV1_3` from the official Slovensko.sk dataset and `referenceV1_2` from the authenticated Podpisuj transaction and fixture.

- [ ] **Step 2: Add profile and source assertions**

Add focused tests asserting both profiles and the exact official v1.3 metadata and archive URLs. This prevents silent drift to the legacy Autogram namespace and makes future dataset updates explicit.

---

### Task 2: Implement P2E conformance validator

**Files:**
- Create: `Autogram/Sources/AutogramKit/Attestation/P2EConformanceValidator.swift`
- Modify: `Autogram/Sources/AutogramKit/Evidence/ASiCEVerifier.swift` only if a narrowly scoped helper is required
- Test: `Autogram/Tests/AutogramKitTests/P2EConformanceTests.swift`

**Interfaces:**
- Consumes `P2EConformanceProfile`, `ASiCEContainerVerifier.readEntries`, and `ASiCEContainerVerifier.verify`.
- Produces:
  - `P2EConformanceValidator.Context(expectedPDFData:expectedEvidenceNumber:expectedConversionTime:)`
  - `P2EConformanceValidator.Result(isValid:issues:clause:record:)`
  - `P2EConformanceValidator.ArtifactResult(isValid:issues:entryNames:documentEntryName:xdcfEntryName:evidenceURI:fingerprintBase64:conversionTime:hasTimestamp:)`
  - `validate(clauseASiC:recordASiC:context:profile:)`

- [ ] **Step 1: Write failing valid-artifact test**

Build an in-memory ASiC-E with `mimetype`, one XDCF entry, one PDF entry, manifest, and `META-INF/signatures001.xml`. The XDCF must contain the exact XMLDataContainer namespace, clause namespace, identifier, `Version="1.2"`, `PDF/A-2`, `PDFA2`, `SHA-256`, a valid evidence URI, and a SHA-256 base64 fingerprint of the embedded PDF. Assert the validator accepts the clause artifact and records the embedded PDF name, fingerprint, evidence URI, conversion date, and timestamp marker.

- [ ] **Step 2: Write failing rejection tests**

Add tests for wrong clause namespace, wrong XDCF identifier or version, missing XDCF, missing PDF, incorrect embedded PDF fingerprint, wrong fingerprint method, missing timestamp marker, and a demo signature marker. Assert each result is invalid and includes a stable issue string.

- [ ] **Step 3: Implement XMLDataContainer parsing**

Parse the root with external entities disabled. Require `XMLDataContainer` in the XDCF namespace, one `XMLData` element, exact identifier and version, and a nested clause root in the profile namespace. Use local-name child lookup so prefixed XML remains supported.

- [ ] **Step 4: Implement clause artifact checks**

Reuse `ASiCEContainerVerifier.verify`, require a valid ASiC result, require `META-INF/signatures001.xml`, require exactly one XDCF and one PDF data entry, reject demo signatures, validate manifest media types, validate `NewDocumentInfo`, `PDFA2`, `PDF/A-2`, `SHA-256`, evidence URI, ISO-8601 conversion time, and the SHA-256 base64 digest of the embedded PDF. If context supplies expected PDF data, compare its digest. If context supplies expected evidence or conversion time, compare them.

- [ ] **Step 5: Implement record artifact checks and cross-artifact comparison**

When a record container is supplied, require a valid signed ASiC containing exactly one XDCF data entry and no PDF data entry. Require the legacy record root and record version. Extract evidence URI, fingerprint, and conversion time from the record and compare them with the clause artifact. Require a `SignatureTimeStamp` marker in both artifacts.

- [ ] **Step 6: Return deterministic issues**

Sort and deduplicate issue strings. Never throw for malformed user input. Return a complete invalid result with the parser or container issue. Keep this validator structural and digest-based. Do not claim cryptographic certificate validation or VeraPDF conformance.

- [ ] **Step 7: Run focused tests**

Run `DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter P2EConformanceTests` and expect all focused tests to pass.

---

### Task 3: Add typed EZZK capability boundaries

**Files:**
- Modify: `Autogram/Sources/AutogramKit/EZZK/EZZKService.swift:69-73`
- Test: `Autogram/Tests/AutogramKitTests/EvidenceAndPackagingTests.swift`

**Interfaces:**
- Produces `EZZKServerClock`, `EZZKEvidenceNumberProvider`, and `EZZKSubmissionTransport` protocols.
- `EZZKServicing` inherits all three protocols and remains source-compatible.

- [ ] **Step 1: Add protocol conformance test**

Add a compile-time and runtime test that assigns `MockEZZKService` to each capability protocol, requests one evidence number, submits an envelope through the submission capability, and reads server time through the clock capability.

- [ ] **Step 2: Split the protocol declaration**

Define the three single-purpose protocols and make `EZZKServicing` inherit from them. Leave method signatures unchanged. Do not change HTTP paths, authentication payloads, or mock numbering behavior.

- [ ] **Step 3: Verify existing service behavior**

Run the focused evidence tests and confirm sequential mock numbers and submitted records remain unchanged.

---

### Task 4: Full verification and cleanup

**Files:**
- Modify: only files changed by Tasks 1 through 3

- [ ] **Step 1: Run complete test suite**

Run `DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test` and require zero failures.

- [ ] **Step 2: Run application build**

Run `DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh` and require a successful app build.

- [ ] **Step 3: Review the diff for scope**

Confirm no production endpoint was added, no installed application was modified, no legacy caller was broken, and no placeholders or em dashes were introduced.
