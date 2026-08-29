# ZaKo Input Signature Inspection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fail-closed, explicit input-signature verification gate to the ZaKo P→E authorization flow.

**Architecture:** AutogramKit owns the status-bearing inspection result and a small verification service. `QualifiedSigningProviding` exposes an explicit input inspection method with an unavailable default, while the engine bridge provides the real adapter. `ZakoSessionStore` owns the current result and session-token protection, and `AttestationPreflight` blocks every result except `valid`.

**Tech Stack:** Swift 6, Swift Package Manager, macOS 27, Swift Concurrency, XCTest, existing AutogramKit signing provider and ZaKo session store.

## Global Constraints

- Authorization proceeds only when input-signature verification state is `valid`.
- `invalid`, `unknown`, `unavailable`, and not-yet-inspected states block authorization.
- A successfully inspected document with no electronic signatures is `valid` with an empty signature list.
- Inspection failure MUST NOT be represented by an empty signature list.
- Existing non-mandate override MUST NOT bypass input-signature verification.
- Existing signing UI behavior outside ZaKo MUST remain unchanged.
- Do not claim independent production DSS, PAdES, XAdES, CAdES, certificate-chain, or qualified-timestamp validation.
- Keep comments and identifiers in English and end-user strings in Slovak.
- Never use em dashes.
- Skip formatters, linters, and project-wide suites during individual tasks. Run verification once at the end.

---

## File map

- Create `Autogram/Sources/AutogramKit/Signing/InputSignatureVerificationService.swift`: explicit result model, state aggregation, and provider-backed verification service.
- Modify `Autogram/Sources/AutogramKit/Signing/SigningProvider.swift`: add the status-bearing provider method with an unavailable default.
- Modify `Autogram/Sources/AutogramKit/Signing/JavaEngine/EngineBridgeSigningProvider.swift`: map engine inspection results and failures to the explicit result.
- Modify `Autogram/Sources/AutogramKit/Models/AttestationData.swift`: add the dedicated preflight error for blocked input-signature verification.
- Modify `Autogram/Sources/AutogramKit/Models/AttestationPreflight.swift`: require and evaluate the inspection result.
- Modify `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`: run inspection for the active source session, retain the result, and include it in every preflight path.
- Modify `Autogram/Sources/AutogramApp/Views/AuthorizeDoneViews.swift`: show explicit inspection state in the existing authorization readiness checklist.
- Create `Autogram/Tests/AutogramKitTests/InputSignatureVerificationTests.swift`: deterministic service, aggregation, preflight, and stale-result tests.
- Modify `Autogram/Tests/AutogramKitTests/AttestationValidatorTests.swift`: update existing preflight fixtures to pass a valid inspection result and preserve existing validation assertions.

## Interfaces

The implementation uses these public interfaces:

```swift
public struct InputSignatureInspectionResult: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case valid
        case invalid
        case unknown
        case unavailable
    }

    public let state: State
    public let signatures: [DocumentSignatureInfo]
    public let oldestQualifiedTimestamp: Date?
    public let detail: String

    public init(
        state: State,
        signatures: [DocumentSignatureInfo],
        oldestQualifiedTimestamp: Date?,
        detail: String
    )
    public static func completed(signatures: [DocumentSignatureInfo])
        -> InputSignatureInspectionResult
    public static func unavailable(detail: String)
        -> InputSignatureInspectionResult
}

public struct InputSignatureVerificationService: Sendable {
    public init(provider: any QualifiedSigningProviding)
    public func inspect(inputURL: URL) async -> InputSignatureInspectionResult
}

internal enum SessionResultGuard {
    static func accepts(resultFor: UUID, currentRecordID: UUID,
                        taskIsCancelled: Bool) -> Bool
}

public protocol QualifiedSigningProviding: Sendable {
    func inspectInputSignatures(in fileURL: URL) async -> InputSignatureInspectionResult
}
```

The existing `inspectSignatures(in:) -> [DocumentSignatureInfo]` API remains for the general signing UI. ZaKo uses only the status-bearing method.

---

### Task 1: Add failing inspection and gate tests

**Files:**
- Create: `Autogram/Tests/AutogramKitTests/InputSignatureVerificationTests.swift`
- Modify: `Autogram/Tests/AutogramKitTests/AttestationValidatorTests.swift`

**Interfaces:**
- Tests target `InputSignatureInspectionResult.completed(signatures:)`, `InputSignatureInspectionResult.unavailable(detail:)`, `InputSignatureVerificationService`, and `AttestationPreflight.evaluate` with an input inspection result.

- [ ] **Step 1: Write the failing aggregation tests**

Add tests with deterministic `DocumentSignatureInfo` values:

```swift
func testCompletedInspectionWithNoSignaturesIsValid() {
    let result = InputSignatureInspectionResult.completed(signatures: [])
    XCTAssertEqual(result.state, .valid)
    XCTAssertTrue(result.signatures.isEmpty)
}

func testInvalidSignatureMakesInspectionInvalid() {
    let signature = DocumentSignatureInfo(id: "s1", signerDisplayName: "Test",
                                          state: .invalid)
    XCTAssertEqual(InputSignatureInspectionResult.completed(signatures: [signature]).state,
                   .invalid)
}

func testIndeterminateSignatureMakesInspectionUnknown() {
    let signature = DocumentSignatureInfo(id: "s1", signerDisplayName: "Test",
                                          state: .indeterminate)
    XCTAssertEqual(InputSignatureInspectionResult.completed(signatures: [signature]).state,
                   .unknown)
}

func testUnavailableInspectionPreservesFailureDetail() {
    let result = InputSignatureInspectionResult.unavailable(detail: "Verifier unavailable")
    XCTAssertEqual(result.state, .unavailable)
    XCTAssertEqual(result.detail, "Verifier unavailable")
}
```

- [ ] **Step 2: Write the failing preflight gate test**

Use otherwise valid `AttestationData` and confirmed security elements. Verify every non-valid state adds the dedicated input-signature validation error and that a valid inspection does not add it:

```swift
func testPreflightBlocksEveryNonValidInputSignatureState() {
    for state in [InputSignatureInspectionResult.State.invalid,
                  .unknown, .unavailable] {
        let inspection = InputSignatureInspectionResult(
            state: state, signatures: [], oldestQualifiedTimestamp: nil,
            detail: "blocked")
        let result = AttestationPreflight.evaluate(
            validData,
            securityElements: validElements,
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: true,
            inputSignatureInspection: inspection)
        XCTAssertTrue(result.errors.contains {
            if case .inputSignatureVerificationRequired(let actual) = $0 {
                return actual == state
            }
            return false
        })
    }
}
```

- [ ] **Step 3: Write the failing unavailable-provider service test**

Create a minimal provider test double that relies on the default status-bearing method and assert the service returns `.unavailable`, not `.valid` with zero signatures.

- [ ] **Step 4: Run the focused tests and verify the expected red failure**

Run:

```bash
cd Autogram
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter InputSignatureVerificationTests
```

Expected: compilation or test failures because the new result model, provider method, and preflight parameter do not exist yet. Do not proceed on a passing result.

---

### Task 2: Implement result model, aggregation, and service

**Files:**
- Create: `Autogram/Sources/AutogramKit/Signing/InputSignatureVerificationService.swift`
- Modify: `Autogram/Sources/AutogramKit/Signing/SigningProvider.swift`

**Interfaces:**
- Consumes existing `DocumentSignatureInfo` and `QualifiedSigningProviding`.
- Produces the public result and service interfaces from this plan.

- [ ] **Step 1: Add explicit result states and constructors**

Implement `InputSignatureInspectionResult` with a non-empty detail for unavailable results. `completed(signatures:)` computes state in this order: any `.invalid` maps to `.invalid`; otherwise any `.indeterminate` or `.unknown` maps to `.unknown`; otherwise `.valid`. Compute `oldestQualifiedTimestamp` as the minimum `signingTime` among signatures with state `.valid`, `hasQualifiedTimestamp == true`, and a non-nil signing time.

- [ ] **Step 2: Add status-bearing provider method**

Add this requirement to `QualifiedSigningProviding`:

```swift
func inspectInputSignatures(in fileURL: URL) async -> InputSignatureInspectionResult
```

Add a protocol extension default returning:

```swift
.unavailable(detail: "Overenie podpisov vstupného dokumentu nie je dostupné.")
```

Do not change the semantics of the existing list-returning method.

- [ ] **Step 3: Implement the provider-backed service**

`InputSignatureVerificationService.inspect(inputURL:)` checks that the standardized URL exists and is a regular file. Missing or unreadable input returns `.unavailable`. Otherwise it delegates to `provider.inspectInputSignatures(in:)`. The service does not convert an unavailable result to another state.

- [ ] **Step 4: Run the focused tests and verify green**

Run the implemented result and service tests individually so the not-yet-integrated preflight test does not obscure the model/service green state:

```bash
cd Autogram
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter InputSignatureVerificationTests/testCompletedInspectionWithNoSignaturesIsValid
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter InputSignatureVerificationTests/testUnavailableProviderReturnsUnavailable
```

Expected: the aggregation and default-provider tests pass. The preflight test remains intentionally red until Task 4.

---

### Task 3: Connect engine inspection to explicit results

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Signing/JavaEngine/EngineBridgeSigningProvider.swift`

**Interfaces:**
- Consumes `AutogramCLIEngine.inspect(files:)` and existing low-level `ExistingPDFSignature` states.
- Produces `inspectInputSignatures(in:)` for the engine bridge.

- [ ] **Step 1: Implement the engine bridge method**

Reuse the current engine inspection request and map each returned `DocumentSignatureInfo` through `InputSignatureInspectionResult.completed(signatures:)`. Catch inspection failures and return `.unavailable(detail:)`. Return `.unavailable` for a missing source file rather than `[]`.

- [ ] **Step 2: Preserve the existing general signing inspection method**

Keep `inspectSignatures(in:)` behavior and UI mapping unchanged. If code reuse is needed, extract only a focused private helper that does not alter its public result.

- [ ] **Step 3: Run the focused engine dispatch test**

Run:

```bash
cd Autogram
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter SigningProviderDispatchTests
```

Expected: PASS, with no live engine requirement. The explicit state aggregation is covered by `InputSignatureVerificationTests`; the real engine adapter is covered by the complete build and review because the production helper process is environment-gated.

---

### Task 4: Add the fail-closed ZaKo preflight gate

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Models/AttestationData.swift`
- Modify: `Autogram/Sources/AutogramKit/Models/AttestationPreflight.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- Modify: `Autogram/Tests/AutogramKitTests/AttestationValidatorTests.swift`
- Modify: `Autogram/Tests/AutogramKitTests/InputSignatureVerificationTests.swift`

**Interfaces:**
- Consumes `InputSignatureInspectionResult`.
- Produces a dedicated `AttestationValidationError.inputSignatureVerificationRequired(state:)` and a store-owned current inspection result.

- [ ] **Step 1: Add the preflight error and failing integration assertion**

Add:

```swift
case inputSignatureVerificationRequired(
    state: InputSignatureInspectionResult.State
)
```

Give it Slovak text identifying the blocking state. Update every existing `AttestationPreflight.evaluate` call site and fixture to pass an explicitly valid inspection result. Do not make the gate silently optional.

- [ ] **Step 2: Require valid inspection in preflight**

Add a required `inputSignatureInspection` argument to `AttestationPreflight.evaluate`. Append the dedicated error whenever `inputSignatureInspection.state != .valid`. Keep all existing review and attestation errors unchanged.

- [ ] **Step 3: Store and run the current inspection**

Add to `ZakoSessionStore`:

```swift
var inputSignatureInspection = InputSignatureInspectionResult.unavailable(
    detail: "Kontrola podpisov ešte neprebehla.")
```

Reset it in `resetSession`. In `runAnalysis`, capture `currentRecordID`, call `InputSignatureVerificationService(provider: signingProvider)`, and assign the result only when `SessionResultGuard.accepts(resultFor: currentRecordID, currentRecordID: self.currentRecordID, taskIsCancelled: Task.isCancelled)` is true. Recompute preflight after assignment. A new source session must invalidate the previous result before starting inspection.

- [ ] **Step 5: Add the stale-result regression test**

Test `SessionResultGuard.accepts` directly with two record IDs and both cancellation values. Verify a result for the old ID is rejected, a matching active result is accepted, and a cancelled task is rejected.

- [ ] **Step 6: Run focused preflight tests and verify green**

Run:

```bash
cd Autogram
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter 'AttestationValidatorTests|InputSignatureVerificationTests'
```

Expected: PASS.

---

### Task 5: Expose the blocking state in ZaKo UI

**Files:**
- Modify: `Autogram/Sources/AutogramApp/Views/AnalysisCanvasView.swift`
- Modify: `Autogram/Sources/AutogramApp/Views/AuthorizeDoneViews.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift` only if a presentation helper is required.

**Interfaces:**
- Consumes `store.inputSignatureInspection`.
- Produces visible Slovak state text and accessibility announcement. No button or override bypass.

- [ ] **Step 1: Add a UI contract assertion or inspect existing authorization checklist seam**

Place the status next to the existing authorization readiness checks. The UI must distinguish valid, invalid, unknown, and unavailable and explain that only valid permits authorization.

- [ ] **Step 2: Implement the state presentation**

Use existing project visual and accessibility patterns. Keep copy explicit:

- valid: `Vstupné podpisy overené`
- invalid: `Vstup obsahuje neplatný elektronický podpis`
- unknown: `Vstupné podpisy sa nepodarilo jednoznačne overiť`
- unavailable: `Overenie vstupných podpisov nie je dostupné`

Show the detail where available. Disable or leave the existing authorization action blocked through preflight rather than adding a UI-only guard.

- [ ] **Step 3: Verify the UI path by building the app target**

Run the focused build command from the repository instructions after implementation. The UI check must confirm that the status renders from the store property and that no stale result is shown after a new document is loaded.

---

### Task 6: Final verification and independent review

**Files:**
- All files changed by Tasks 1 through 5.
- Review output is external to source files unless a finding requires a targeted fix.

- [ ] **Step 1: Run the complete test suite**

Run:

```bash
cd Autogram
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test
```

Expected: all existing and new tests pass, with only pre-existing environment-gated skips.

- [ ] **Step 2: Build the app target**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh
```

Expected: successful app build.

- [ ] **Step 3: Request independent code review**

Review the complete diff against the approved design. Check especially:

- no empty-list failure fallback remains on the ZaKo path;
- every authorization path passes the same explicit result to preflight;
- stale tasks cannot overwrite a new source result;
- non-mandate override cannot bypass the signature gate;
- pilot PDF/A and unverified ZaKo or EZZK behavior are not presented as production contracts;
- the existing unfinished `BuiltInVisionProvider.swift` work is untouched.

- [ ] **Step 4: Resolve important review findings and rerun verification**

Fix only findings within this feature scope. Rerun the focused tests, complete suite, and app build after fixes.
