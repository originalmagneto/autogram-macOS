# macOS 27 UX Preflight, Accessibility, and Native Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Autogram to a macOS 27-first native surface and make the ZaKo workflow truthful, keyboard-accessible, and safe for legal preflight decisions.

**Architecture:** Keep the current SwiftUI/AppKit application structure, but establish one shared `AutogramAppModel` for settings and session ownership so the main window and native Settings scene use the same state. Replace hand-painted navigation glass with standard macOS 27 components, keep custom glass only for small functional groups, and expose a dedicated preflight model that drives both inline form validation and the authorization checklist. Preserve the existing PDF/A, signing, evidence, and detection engines; change only when and how their state is surfaced.

**Tech Stack:** Swift 6, SwiftUI, AppKit, PDFKit, Observation, Swift Package Manager, XCTest, macOS 27 SDK.

## Global Constraints

- Target macOS 27 only in `Package.swift` and the generated app bundle.
- Use standard SwiftUI/AppKit controls before custom drawing; use `.glassEffect` and `GlassEffectContainer` only for small custom functional groups.
- All high-stakes actions must expose truthful state, actionable errors, and a keyboard path.
- Legal preflight must run before server-time/network and cryptographic work.
- Existing PDF/A, EZZK, Keychain, signing, and evidence behavior remains intact unless required to surface the preflight state.
- Keep Slovak user-facing copy and English source comments.
- Do not use Unicode emoji in UI copy or source comments.
- Run focused tests after each task and the packaged app build once after all tasks. Skip formatters, linters, and unrelated refactors.

---

### Task 1: Establish the macOS 27 native visual and window baseline

**Files:**
- Modify: `Autogram/Package.swift:4-8`
- Modify: `Autogram/build_app.sh:13,52-53`
- Modify: `Autogram/Sources/AutogramApp/AutogramApp.swift:3-15`
- Modify: `Autogram/Sources/AutogramApp/Theme/DesignSystem.swift:5-44,46-63,160-226`
- Modify: `Autogram/Sources/AutogramApp/Views/RootView.swift:39-159`
- Modify: `Autogram/Sources/AutogramApp/Views/AnalysisCanvasView.swift:163-225,343-381`
- Create: `Autogram/Tests/AutogramKitTests/MacOS27UXContractTests.swift`

**Interfaces:**
- Produces a macOS 27-only package target and generated bundle with `LSMinimumSystemVersion` `27.0`.
- Produces `AutogramAppModel` owned by `AutogramApp` and injected into `RootView`, `SettingsView`, `SigningSessionStore`, and `ZakoSessionStore` without changing their public engine APIs.
- Produces native menu commands for Open, Add Files, Show/Hide Sidebar, and Settings using the existing action closures.

- [ ] **Step 1: Write the failing platform contract tests**

Add tests that inspect only deterministic project contracts exposed by small pure helpers:

```swift
func testMacOS27DeploymentContract() throws {
    let package = try String(contentsOf: packageURL, encoding: .utf8)
    XCTAssertTrue(package.contains(".macOS(\"27.0\")"))
}

func testEvidenceStatusDoesNotDependOnTimerOnly() {
    XCTAssertTrue(EvidenceRecord.submissionDeadlineInterval == 24 * 3600)
}
```

The first test must fail against the current `.macOS("26.0")` declaration. Keep the test narrow and do not test source text for visual behavior.

- [ ] **Step 2: Run the contract test and verify the expected failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter MacOS27UXContractTests
```

Expected: the deployment contract fails because the package still declares macOS 26.0.

- [ ] **Step 3: Update the deployment and bundle floor**

Change `Package.swift` to `.macOS("27.0")`. Change `build_app.sh` so both `LSMinimumSystemVersion` and the package build use 27.0. Do not change signing identity or bundle identifiers.

- [ ] **Step 4: Introduce shared app state without changing engine behavior**

Create an `@MainActor @Observable final class AutogramAppModel` containing the existing `AppSettingsStore`, `SigningSessionStore`, and `ZakoSessionStore` initialization currently in `RootView.init()`. Make `AutogramApp` own the model with `@State`, inject it into `RootView`, and add a `Settings` scene that presents `SettingsView` against the same `AppSettingsStore`. Remove the Settings workflow row from the main workflow sidebar and expose `SettingsLink` plus a `⌘,` command instead.

- [ ] **Step 5: Replace custom navigation glass with macOS 27 hierarchy**

Keep `NavigationSplitView` and `Table`, but remove custom `.background(.bar)` treatments from navigation/action containers where the system already supplies the glass layer. Refactor `liquidGlass` so it uses a single native `.glassEffect(.regular, in: .rect(cornerRadius: ...))` on custom functional groups. Do not apply glass to every nested card. Keep content containers plain or use semantic system materials only where the content needs separation.

Move `markupToolbar`, page navigation, and sheet-count actions into toolbar or inspector groups. Keep no more than three groups and retain the primary action on the trailing edge. Keep the document canvas as the content layer.

- [ ] **Step 6: Add macOS 27 menu commands and labels**

Add `Commands` for:

```swift
CommandGroup(after: .newItem) {
    Button("Otvoriť súbor…", action: openDocument)
        .keyboardShortcut("o", modifiers: .command)
    Button("Pridať súbory…", action: addFiles)
        .keyboardShortcut("o", modifiers: [.command, .shift])
}

CommandGroup(after: .sidebar) {
    Button("Zobraziť alebo skryť sidebar", action: toggleSidebar)
        .keyboardShortcut("s", modifiers: [.command, .control])
}
```

Use text labels for all commands because macOS 27 hides many menu item images by default. Do not rely on SF Symbols as the only command meaning.

- [ ] **Step 7: Add macOS 27 layout contract tests and run them**

Test the pure layout constants or helper values that replace the current fixed-width assumptions. The test must assert that the inspector can collapse and that the root minimum is not a sum of all preferred columns. Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter MacOS27UXContractTests
```

Expected: PASS.

- [ ] **Step 8: Build the package product**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh
```

Expected: `Autogram.app` is created with a macOS 27 minimum version.

---

### Task 2: Implement truthful ZaKo legal preflight

**Files:**
- Modify: `Autogram/Sources/AutogramKit/Models/AttestationData.swift:30-151`
- Create: `Autogram/Sources/AutogramKit/Models/AttestationPreflight.swift`
- Modify: `Autogram/Sources/AutogramApp/ZakoSessionStore.swift:24-43,117-169,318-453,505-532`
- Modify: `Autogram/Sources/AutogramApp/Views/AttestationFormView.swift:9-197,253-278`
- Modify: `Autogram/Sources/AutogramApp/Views/AuthorizeDoneViews.swift:8-215,273-351`
- Modify: `Autogram/Sources/AutogramApp/Views/ZakoFlowViews.swift:60-74`
- Create: `Autogram/Tests/AutogramKitTests/AttestationValidatorTests.swift`

**Interfaces:**
- Adds `AttestationData.originConfirmed: Bool`, decoding absent legacy values as `false`.
- Adds `AttestationValidationError.originNotConfirmed` with the Slovak error text `Potvrďte, že vstupný dokument je originál alebo úradne osvedčená kópia.`
- Adds `AttestationPreflight.Result` with deterministic readiness checks for local validation, origin confirmation, document names, sheet count, evidence number, and identity selection.
- Adds `ZakoSessionStore.preflightErrors`, `ZakoSessionStore.isPreflightComplete`, and `ZakoSessionStore.preparePreflight() async`.
- Adds `ZakoSessionStore.evidenceNumberError: String?` so evidence-number failures are rendered next to the evidence control instead of being hidden in `lastError`.
- Adds explicit `ZakoSessionStore.isAuthorizing` rather than deriving in-flight state from a display string.

- [ ] **Step 1: Write failing validator tests**

Add tests for the new legal gate:

```swift
func testValidationRequiresOriginConfirmation() {
    var data = validAttestationData()
    data.originConfirmed = false

    let errors = AttestationValidator.validate(data, securityElements: validElements, qualifiedTimestampTime: nil)

    XCTAssertTrue(errors.contains(.originNotConfirmed))
}

func testValidationPassesWhenOriginIsConfirmed() {
    var data = validAttestationData()
    data.originConfirmed = true

    let errors = AttestationValidator.validate(data, securityElements: validElements, qualifiedTimestampTime: nil)

    XCTAssertFalse(errors.contains(.originNotConfirmed))
}
```

The first test must fail before the new model field and validator rule exist.

- [ ] **Step 2: Run validator tests and verify the expected failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter AttestationValidatorTests
```

Expected: the new origin-confirmation test fails for the missing validator rule.

- [ ] **Step 3: Add the origin confirmation to the model and validator**
Add `originConfirmed` to `AttestationData` after `originalDocumentTypeLabel` and add it to `CodingKeys`. Decode it with `decodeIfPresent(Bool.self, forKey: .originConfirmed) ?? false` to preserve existing saved templates. Add `originNotConfirmed` to `AttestationValidationError` and append it before the other field checks when the flag is false.

- [ ] **Step 4: Add explicit preflight state to the store**

Create a pure `AttestationPreflight` helper in AutogramKit so the legal readiness rules are testable without importing the executable app target:

```swift
public enum AttestationPreflight {
    public struct Result: Equatable, Sendable {
        public let errors: [AttestationValidationError]
        public let hasSelectedIdentity: Bool
        public let mandateRequirementSatisfied: Bool
        public var isComplete: Bool {
            errors.isEmpty && hasSelectedIdentity && mandateRequirementSatisfied
        }
    }

    public static func evaluate(
        _ data: AttestationData,
        securityElements: [SecurityElement],
        hasSelectedIdentity: Bool,
        mandateRequirementSatisfied: Bool
    ) -> Result {
        Result(
            errors: AttestationValidator.validate(
                data,
                securityElements: securityElements,
                qualifiedTimestampTime: nil),
            hasSelectedIdentity: hasSelectedIdentity,
            mandateRequirementSatisfied: mandateRequirementSatisfied)
    }
}
```

`ZakoSessionStore` owns:

```swift
var preflightErrors: [AttestationValidationError] = []
var evidenceNumberError: String?
var isAuthorizing = false

var isPreflightComplete: Bool {
    AttestationPreflight.evaluate(
        attestation,
        securityElements: securityElements,
        hasSelectedIdentity: selectedIdentityID != nil,
        mandateRequirementSatisfied: mandateRequirementSatisfied
    ).isComplete && preflightErrors.isEmpty
}

func preparePreflight() async {
    evidenceNumberError = nil
    if attestation.evidenceNumber?.trimmingCharacters(in: .whitespaces).isEmpty != false {
        await fetchEvidenceNumber()
    }
    preflightErrors = AttestationPreflight.evaluate(
        attestation,
        securityElements: securityElements,
        hasSelectedIdentity: selectedIdentityID != nil,
        mandateRequirementSatisfied: mandateRequirementSatisfied
    ).errors
}
```

`fetchEvidenceNumber()` must set `evidenceNumberError` on failure, clear it on success, and never hide the error only in `lastError`.

- [ ] **Step 5: Test that invalid local preflight stops server-time work**

Add a focused test for `AttestationPreflight.evaluate` with an invalid attestation and assert that `isComplete` is false. In `authorizeAndSign()`, call `preparePreflight()` before any server-time request; the sequence must be observable through the existing state transitions and the pure preflight result.

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter AttestationValidatorTests
```

Expected before the implementation change: the origin gate test fails and the pure preflight result is not complete.

- [ ] **Step 6: Move local preflight before server time and guard re-entry**

At the start of `authorizeAndSign()`:

```swift
guard !isAuthorizing else { return }
isAuthorizing = true
defer {
    isAuthorizing = false
    analysisProgressText = ""
}

await preparePreflight()
guard isPreflightComplete else { return }

analysisProgressText = "Zisťujem dôveryhodný čas…"
let conversionTime = try await ezzkService.serverTime()
```

Do not request server time, convert PDF/A, or touch the signing provider until local preflight passes. Preserve the existing PDF/A, XML, signing, local evidence, and CEZZK submission sequence after the gate.

- [ ] **Step 7: Make evidence number acquisition automatic and visible**

When the attestation step becomes active, call `preparePreflight()` once for the current document. Keep a visible `ProgressView` while requesting the number, show `evidenceNumberError` beside the control, and provide a `Znova získať číslo` retry action. Remove the manual-only mental model from the primary flow while retaining retry.

- [ ] **Step 8: Add live inline validation and origin attestation**

In `AttestationFormView`, add a legally explicit `Toggle`:

```swift
Toggle("Potvrdzujem, že vstupný dokument je originál alebo úradne osvedčená kópia.",
       isOn: $store.attestation.originConfirmed)
```

Render field-level error text under the affected field. Recompute `preflightErrors` as fields change. Do not use a global error list as the only recovery path. Show `evidenceNumberError` in the evidence section.

- [ ] **Step 9: Make Continue and Authorize honest**

Disable `Pokračovať na autorizáciu` while evidence-number acquisition is active or when the form has unresolved preflight errors. Keep an explicit `Skontrolovať údaje` action if the user needs to see all errors. In `AuthorizeView`, use the `isAuthorizing` flag for progress and disable state, not `analysisProgressText.isEmpty`.

The checklist must include origin confirmation, evidence number, selected identity, mandate state, QTS state, sheet count, security elements, and document names. A check must mean the corresponding condition is actually true.

- [ ] **Step 10: Fix completion truthfulness and test it**

When CEZZK submission fails, keep the signed-file result but show a queued state with deadline and retry action. Do not use the unconditional success headline. Add tests for submitted and queued outcome labels in `AccessibilityContractTests`. Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter AttestationValidatorTests
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter AccessibilityContractTests
```

Expected: PASS with local preflight before server time, visible evidence-number errors, re-entry protection, and truthful queued completion state.

---

### Task 3: Make document review and native surfaces keyboard and VoiceOver complete

**Files:**
- Modify: `Autogram/Sources/AutogramApp/Views/RootView.swift:52-106`
- Modify: `Autogram/Sources/AutogramApp/Views/AnalysisCanvasView.swift:119-225,227-317,383-447,500-706`
- Modify: `Autogram/Sources/AutogramApp/Views/AuthorizeDoneViews.swift:139-260`
- Modify: `Autogram/Sources/AutogramApp/Views/EvidenceDashboardView.swift:20-142,397-455`
- Modify: `Autogram/Sources/AutogramApp/Views/SettingsView.swift:1-49,286-618`
- Modify: `Autogram/Sources/AutogramApp/Theme/DesignSystem.swift:64-101,271-318`
- Modify: `Autogram/Sources/AutogramApp/SigningSessionStore.swift:150-180,400-430`
- Modify: `Autogram/Sources/AutogramKit/EngineBridge/Signing/VisibleAppearanceInspector.swift:70-175`
- Modify: `Autogram/Sources/AutogramKit/EngineBridge/PDF/PDFPlacementOverlayView.swift:150-182`
- Create: `Autogram/Sources/AutogramKit/Models/UXLabels.swift`
- Create: `Autogram/Tests/AutogramKitTests/AccessibilityContractTests.swift`

**Interfaces:**
- Queue rows, identity rows, element rows, and icon-only actions become focusable controls with explicit accessibility labels and values.
- `UXLabels.confidenceLabel(for:) -> String` returns a numeric, non-color confidence label.
- `UXLabels.evidenceStatusLabel(for:) -> String` returns a textual pending/overdue/submitted state.
- `ElementRow` renders a real description editor and calls the existing `onDescriptionChange` callback.
- `AnalysisCanvasView` exposes selected-element keyboard movement and resize through visible inspector controls as well as mouse dragging.
- Evidence table selection remains selection; detail opens through Return, double-click, or an explicit action.
- Destructive queue, element, TSA, profile, and artwork deletion uses consistent confirmation or a multi-item undo model.

- [ ] **Step 1: Write failing accessibility contract tests**

Add pure contract tests for the new AutogramKit helpers:

```swift
func testConfidenceLabelRequiresNumericValue() {
    XCTAssertEqual(UXLabels.confidenceLabel(for: 0.62), "Istota 62 %")
}

func testPendingEvidenceLabelIncludesDeadlineState() {
    XCTAssertTrue(UXLabels.evidenceStatusLabel(for: .queuedForSubmission).contains("čaká"))
}
```

For view-only labels, use pure helper methods rather than snapshot tests. The tests must fail before helpers exist.

- [ ] **Step 2: Run the accessibility contract tests and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter AccessibilityContractTests
```

Expected: the new helper assertions fail because the current components expose only visual color or tooltip state.

- [ ] **Step 3: Replace gesture-only rows with focusable selection controls**

Wrap queue and identity rows in `Button` with `.buttonStyle(.plain)` and attach:

```swift
.accessibilityLabel("Certifikát \(identity.label)")
.accessibilityValue(isSelected ? "Vybraný" : "Nevybraný")
.accessibilityAddTraits(isSelected ? .isSelected : [])
```

Give queue rows equivalent selected/status values. Keep context menus for secondary actions.

- [ ] **Step 4: Make ElementRow legally editable**

Replace the one-line description `Text` with a `TextField` or multiline editor bound through `onDescriptionChange`. Add an explicit visible confidence label and provenance label such as `AI detekcia` or `Pridané ručne`. Give duplicate/delete/page/type controls explicit labels. Keep color as a secondary cue, never the only cue.

- [ ] **Step 5: Add non-gesture placement controls**

Add an inspector section for the selected element with numeric normalized X, Y, width, and height fields plus Move and Resize stepper controls. Add keyboard shortcuts for arrows and Shift plus arrows when the canvas is focused. Keep mouse drag and corner resize as accelerators, not the only interaction path. Announce selected element changes with accessibility values.

- [ ] **Step 6: Preserve evidence table scanning**

Change the evidence detail presentation so `Table(selection:)` does not directly drive the sheet. Add a toolbar/detail action and open the sheet on double-click or Return. Add `ContentUnavailableView` for an empty register and a distinct no-results state for active filters. Make overdue status textual, including `Blíži sa lehota` and `Po lehote`, alongside the color/icon signal.

- [ ] **Step 7: Normalize destructive actions and error recovery**

Add confirmation dialogs for queue, TSA, profile, and artwork deletion, or implement a multi-item undo stack. Keep the existing evidence-record confirmation as the reference pattern. Replace `try?` on user-visible save/export/copy operations with an error state adjacent to the action and a retry path. Keep the form content intact after errors.

- [ ] **Step 8: Remove fixed-size traps and hidden-label dependence**

Replace fixed `frame(width:)` values on analysis, attestation, signing, authorization, and evidence detail with flexible minimum/ideal/max columns. Preserve a usable compact layout with `ViewThatFits` or a collapsible inspector. Add explicit `.accessibilityLabel` to every icon-only button and every Picker whose visible label is hidden.

- [ ] **Step 9: Add runtime verification checklist**

Build the app and manually verify on macOS 27:

1. Full Keyboard Access reaches queue, certificate, evidence, and element controls.
2. VoiceOver announces selection, confidence, errors, and pending CEZZK state.
3. Reduce Transparency preserves contrast.
4. Reduce Motion does not animate critical state changes aggressively.
5. Increase Contrast preserves all selected and error states.
6. Window resizing from the default down to the minimum does not hide primary actions.

- [ ] **Step 10: Run focused tests and final package build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter AccessibilityContractTests
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test --filter SecurityElementsDetectorTests
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh
```

Expected: focused tests pass and the packaged macOS 27 app is created.

---

## Verification Matrix

| Requirement | Verification |
|---|---|
| macOS 27 only | Package contract test and generated `Info.plist` inspection |
| Truthful legal preflight | Validator, pure preflight, and authorization-state tests, including server-time call ordering |
| Automatic evidence number | Preflight/state test plus visible AttestationForm retry/error path |
| CEZZK queued state | Status outcome test and DoneView manual smoke path |
| Keyboard and VoiceOver | Full Keyboard Access and VoiceOver manual pass on macOS 27 |
| Flexible layout | Window resize pass at minimum, default, and large sizes |
| Rotation safety | Existing `SecurityElementsDetectorTests` rotated-page regression |
