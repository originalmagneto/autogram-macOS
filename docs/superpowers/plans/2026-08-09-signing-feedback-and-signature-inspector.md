# Signing Feedback and Signature Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make re-signing failures diagnosable, display continuous signing activity, and move existing signatures into a readable native inspector section.

**Architecture:** `WorkspaceModel` exposes one presentation phase and one safe workflow error. `SigningCoordinator` preserves thrown engine failures, while `CLIProcessRunner` classifies helper exits without exposing secrets. `SigningInspector` owns signature history and activity presentation so `PDFDetailView` remains a full-height document preview.

**Tech Stack:** macOS 27, Swift 6, SwiftUI, AppKit, PDFKit, Observation, Java 25, Autogram machine protocol, Swift Testing

## Global Constraints

- Apply the MSW necessity test to every change and test.
- Deployment target remains macOS 27.0 and architecture remains ARM64 only.
- Java Autogram and DSS remain the signing and validation authority.
- Existing signatures must be preserved when adding a new signature.
- Qualified timestamps remain mandatory.
- Never expose PINs, TSA credentials, private certificate data, or unredacted document paths.
- Use native system controls and respect Reduce Motion.
- Do not use em dash characters.

---

## Locked File Map

- `native-macos/Autogram/Core/Models/SigningModels.swift`: user-facing workflow phase and safe signing failure values.
- `native-macos/Autogram/Features/Workspace/SigningCoordinator.swift`: signing state transitions and failure propagation.
- `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`: observable phase and inline failure state.
- `native-macos/Autogram/Infrastructure/CLI/CLIProcessRunner.swift`: helper termination classification.
- `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`: machine progress event mapping.
- `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`: document preview only.
- `native-macos/Autogram/Features/Signing/SigningInspector.swift`: activity, failure, and signature history presentation.
- `native-macos/AutogramTests/SigningCoordinatorTests.swift`: exact coordinator failure proof.
- `native-macos/AutogramIntegrationTests/CLIProcessRunnerTests.swift`: safe helper-exit proof.

### Task 1: Preserve Safe Failure Reasons

**Files:**
- Modify: `native-macos/Autogram/Features/Workspace/SigningCoordinator.swift`
- Modify: `native-macos/Autogram/Infrastructure/CLI/CLIProcessRunner.swift`
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Test: `native-macos/AutogramTests/SigningCoordinatorTests.swift`
- Test: `native-macos/AutogramIntegrationTests/CLIProcessRunnerTests.swift`

**Interfaces:**
- Produces: a thrown `SigningFailure` for every terminal coordinator failure.
- Produces: a `CLIProcessFailure.helperExited(status:diagnostic:)` whose diagnostic is sanitized and optional.
- Produces: `WorkspaceModel.signingError: String?` for inline presentation.

- [ ] **Step 1: Keep the existing coordinator failure test as the contract test**

The existing `completeFailurePreservesTheEngineReason` test already requires `beginSigning` to throw the exact engine failure. Do not add a duplicate.

- [ ] **Step 2: Run the focused coordinator test and confirm the current failure**

Run:

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test -only-testing:AutogramTests/completeFailurePreservesTheEngineReason
```

Expected before the fix: the test fails because `beginSigning` returns after setting `.failed`.

- [ ] **Step 3: Throw the normalized failure after storing coordinator state**

Use one normalized value:

```swift
let failure = asSigningFailure(error)
state = .failed(failure)
throw failure
```

- [ ] **Step 4: Add one process-runner test for an abnormal helper exit**

Extend the existing fake helper fixture with one mode that writes a known non-secret diagnostic and exits without a terminal event. Assert that the localized error contains a safe classified reason and does not expose an absolute source path.

- [ ] **Step 5: Preserve the safe error in `WorkspaceModel`**

Add `private(set) var signingError: String?`, clear it when a new credential or signing flow starts, and set it from the thrown `LocalizedError` in `sign`.

- [ ] **Step 6: Run only the two focused test targets**

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test -only-testing:AutogramTests/completeFailurePreservesTheEngineReason -only-testing:AutogramIntegrationTests/CLIProcessRunnerTests
```

Expected: both proofs pass.

### Task 2: Expose Continuous Workflow Activity

**Files:**
- Modify: `native-macos/Autogram/Core/Models/SigningModels.swift`
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Modify: `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`
- Modify: `native-macos/Autogram/Features/Signing/SigningInspector.swift`

**Interfaces:**
- Produces: `SigningActivityPhase?` on `WorkspaceModel`.
- Consumes: existing model state before helper events and machine `file.progress` phase values after helper launch.

- [ ] **Step 1: Add the smallest user-facing phase model**

Define an enum whose cases map to the approved phase labels. Do not add timing estimates or synthetic percentages.

- [ ] **Step 2: Set phase state at existing workflow boundaries**

Set phases when inspection starts, certificate discovery starts, signing preparation starts, and signing finishes. Clear the phase on completion, cancellation, or failure.

- [ ] **Step 3: Map existing `file.progress` phase payloads when present**

Decode only known safe phase identifiers. Ignore unknown phase values so protocol evolution cannot break signing.

- [ ] **Step 4: Present native progress in the inspector**

Use an indeterminate `ProgressView` for the active phase and retain the existing determinate batch progress only when completed-file counts are available. Keep progress inline and nonmodal.

- [ ] **Step 5: Build the native app**

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' build
```

Expected: build succeeds without new warnings in changed files.

### Task 3: Move Signature History into the Inspector

**Files:**
- Modify: `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`
- Modify: `native-macos/Autogram/Features/Signing/SigningInspector.swift`

**Interfaces:**
- Consumes: the selected `PDFItem.inspection` already held by `WorkspaceModel`.
- Produces: a native `Section("Existing Signatures")` in `SigningInspector`.

- [ ] **Step 1: Remove the signature list below the PDF preview**

Keep `PDFDetailView` responsible only for PDF preview or ASiC content preview and the navigation title.

- [ ] **Step 2: Add the signature summary to the right inspector**

Show count and aggregate validation state. Use system symbols and semantic styles for valid, invalid, and indeterminate states.

- [ ] **Step 3: Add one disclosure row per signature**

The collapsed row contains signer and validation. Expanded content contains date, friendly format, qualified timestamp state, and covered document names.

- [ ] **Step 4: Build and run focused existing tests**

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' build
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test -only-testing:AutogramTests/SigningCoordinatorTests -only-testing:AutogramIntegrationTests/CLIProcessRunnerTests
```

Expected: build and focused tests pass.

### Task 4: Live Acceptance

**Files:**
- No source changes unless the live result proves an accepted contract claim is still unmet.

- [ ] **Step 1: Build and ad-hoc sign the test application**

Use the existing native build script and project entitlements.

- [ ] **Step 2: Open the supplied already signed PDF**

Use `/Users/Magneto/Downloads/Jesenna-ponuka-2026_signed_signed.pdf` and confirm both existing signatures appear in the inspector before signing.

- [ ] **Step 3: Add one signature with I.CA SecureStore**

Expected: the output contains the two prior signatures plus the new signature and required qualified timestamp. If signing cannot complete, the inspector must display the exact safe failure and current phase instead of a generic dialog.

- [ ] **Step 4: Halt and report**

Report only the contract outcome, proof, and any rejected claims required by MSW.
