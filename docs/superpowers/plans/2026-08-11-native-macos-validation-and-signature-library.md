# Autogram macOS Validation and Graphic Signature Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically complete DSS validation after signing, keep visible signatures inactive until deliberately chosen, and provide a minimal reusable artwork library.

**Architecture:** Reuse the existing `WorkspaceModel` validation generation guard and managed `SignatureAssetStore`. Post-signing inspection starts complete validation for the output descriptor. Artwork persists independently from per-document activation, and the inspector lists managed assets without reconstructing existing PDF appearances.

**Tech Stack:** Swift 6, SwiftUI, AppKit, PDFKit, Swift Testing, existing Java DSS signing engine

## Global Constraints

- Apple silicon only, ARM64 end to end.
- Keep Java DSS and Autogram as the signing and validation engine.
- Opening a document never activates a graphic signature automatically.
- Existing PDF appearance graphics remain immutable document content.
- Importing artwork stores a managed copy without retaining the external absolute path.
- Do not add profile presets, saved per-document placements, or a broad test matrix.
- Preserve unrelated uncommitted visible-signature work and stage only task-owned hunks.
- Never use em dash characters.

---

### Task 1: Complete Validation for Signed Outputs

**Files:**
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Test: `native-macos/AutogramTests/SigningCoordinatorTests.swift`

**Interfaces:**
- Consumes: `applyPostSigningInspectionResults(_:for:)`, `startCompleteValidation(for:requestGeneration:)`, and descriptor generation checks.
- Produces: automatic complete DSS validation for every successful output descriptor.

- [ ] **Step 1: Write the failing post-signing validation test**

Extend `completedSignedOutputBecomesActiveAndIsReinspected()` with a real fake-engine validation result and assertions that distinguish fast inspection from complete validation:

```swift
#expect(engine.validateCallCount == 1)
#expect(workspace.signatureValidationProgress == .complete)
#expect(workspace.items[0].inspection.signatures.map(\.validationState) == [.valid])
```

The fake must return an indeterminate signature from `inspect(files:)` and the same signature as valid from `validate(files:)`. The production mutation caught is omitting complete validation after post-signing inspection.

- [ ] **Step 2: Run the native test target and verify RED**

Run:

```bash
env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project native-macos/Autogram.xcodeproj \
  -scheme Autogram -destination 'platform=macOS' \
  -only-testing:AutogramTests test
```

Expected: the new assertions fail because post-signing processing calls `inspect(files:)` but never `validate(files:)`.

- [ ] **Step 3: Start complete validation after applying output inspection**

At the end of a successful `applyPostSigningInspectionResults(_:for:)`, start validation against exactly the output descriptors and current generation:

```swift
startCompleteValidation(
    for: descriptors,
    requestGeneration: inspectionRequestGeneration
)
```

Do not call `refreshInspections()`, because the output has already completed fast inspection. Retain the existing stale descriptor and generation guards.

- [ ] **Step 4: Verify GREEN**

Run the same `AutogramTests` target. Expected: all tests pass and the new test proves one complete validation request for the signed output.

- [ ] **Step 5: Commit the validation lifecycle**

```bash
git add native-macos/Autogram/Features/Workspace/WorkspaceModel.swift \
  native-macos/AutogramTests/SigningCoordinatorTests.swift
git commit -m "fix(macos): validate completed signatures"
```

---

### Task 2: Make Visible Signature Activation Explicit

**Files:**
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Modify: `native-macos/Autogram/Features/Signing/VisibleAppearanceInspector.swift`
- Test: `native-macos/AutogramTests/WorkspaceInspectionTests.swift`

**Interfaces:**
- Consumes: `VisibleSignaturePreferences`, `visibleSignatureEnabled`, `importVisibleSignatureArtwork(from:pdfPageIndex:)`, and `updateSignedOutput(for:to:)`.
- Produces: inactive startup, deliberate activation, and post-signing overlay reset.

- [ ] **Step 1: Write failing activation lifecycle tests**

Add two focused tests:

```swift
@Test @MainActor func savedArtworkDoesNotActivateGraphicSignatureInNewWorkspace() throws {
    // Persist an asset with the legacy enabled value true.
    // Create a new workspace using the same defaults and managed store.
    #expect(workspace.visibleSignatureAsset != nil)
    #expect(workspace.visibleSignatureEnabled == false)
}

@Test @MainActor func completedOutputDisablesPendingGraphicSignatureOverlay() throws {
    workspace.configureVisibleAppearance(asset: asset, enabled: true, placement: placement)
    workspace.updateSignedOutput(for: "document", to: output)
    #expect(workspace.visibleSignatureEnabled == false)
    #expect(PDFDetailView(item: workspace.items[0], workspace: workspace).cardPreview == nil)
}
```

The first catches restoration of the old enabled flag. The second catches retention of a new editable overlay over an appearance already embedded in the output.

- [ ] **Step 2: Run the native target and verify RED**

Run the `AutogramTests` command from Task 1. Expected: both new assertions fail against current restoration and output replacement behavior.

- [ ] **Step 3: Separate persistence from activation**

Change restoration so artwork and optional placement may load, but activation does not:

```swift
visibleSignatureAsset = preferences.assetID.map { id in
    SignatureAsset(id: id, kind: .png, managedFilename: "\(id.uuidString).png")
}
visibleSignatureEnabled = false
visibleSignaturePlacement = preferences.defaultPlacement?.placement
```

Persist `enabled: false` for backward-compatible decoding, or remove the field only if decoding old preferences remains explicitly supported. Do not create a migration subsystem.

- [ ] **Step 4: Activate only through deliberate artwork choice**

After a successful import or stored-asset selection, set:

```swift
visibleSignatureAsset = asset
visibleSignatureEnabled = true
```

The toggle may disable an active composition. Enabling without artwork must remain unavailable in the UI, so the user activates by choosing artwork rather than an empty switch.

- [ ] **Step 5: Disable composition when a signed output becomes active**

In `updateSignedOutput(for:to:)`, before replacing the descriptor:

```swift
visibleSignatureEnabled = false
visibleSignatureCardContent = nil
visibleSignatureCardPreview = nil
persistVisibleSignaturePreferences()
```

Keep the managed asset available for later reuse. Do not modify or remove graphics already embedded in the PDF.

- [ ] **Step 6: Verify GREEN and commit**

Run the `AutogramTests` target. Then selectively stage only Task 2 hunks:

```bash
git add -p native-macos/Autogram/Features/Workspace/WorkspaceModel.swift \
  native-macos/Autogram/Features/Signing/VisibleAppearanceInspector.swift \
  native-macos/AutogramTests/WorkspaceInspectionTests.swift
git commit -m "fix(macos): require explicit graphic signature"
```

---

### Task 3: Managed Artwork Library

**Files:**
- Modify: `native-macos/Autogram/Infrastructure/SignatureAssets/SignatureAssetStore.swift`
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Modify: `native-macos/Autogram/Features/Signing/VisibleAppearanceInspector.swift`
- Test: `native-macos/AutogramTests/VisibleSignatureAssetTests.swift`

**Interfaces:**
- Produces: `SignatureAssetStore.listAssets() throws -> [SignatureAsset]`.
- Produces: `SignatureAssetStore.delete(_ asset: SignatureAsset) throws`.
- Produces: `WorkspaceModel.visibleSignatureAssets: [SignatureAsset]`.
- Produces: `WorkspaceModel.selectVisibleSignatureArtwork(_ asset: SignatureAsset)`.
- Produces: `WorkspaceModel.deleteVisibleSignatureArtwork(_ asset: SignatureAsset) throws`.

- [ ] **Step 1: Write the failing asset-store lifecycle test**

Add one test that imports two fixtures and proves observable storage behavior:

```swift
let first = try store.importPNG(firstURL)
let second = try store.importPDF(pdfURL, pageIndex: 0)

#expect(Set(try store.listAssets().map(\.id)) == Set([first.id, second.id]))
try store.delete(first)
#expect(try store.listAssets().map(\.id) == [second.id])
#expect(!FileManager.default.fileExists(atPath: store.fileURL(for: first).path))
```

The production mutations caught are failing to enumerate managed files and deleting the wrong asset.

- [ ] **Step 2: Run the native target and verify RED**

Run the `AutogramTests` command from Task 1. Expected: compilation fails because `listAssets()` and `delete(_:)` do not exist.

- [ ] **Step 3: Implement deterministic managed enumeration and deletion**

List only regular `.png` files directly inside `assetsDirectory` whose stem decodes as a UUID. Return them sorted by managed filename for stable UI ordering:

```swift
func listAssets() throws -> [SignatureAsset] {
    guard fileManager.fileExists(atPath: assetsDirectory.path) else { return [] }
    return try fileManager.contentsOfDirectory(
        at: assetsDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    .compactMap { url in
        guard url.pathExtension.lowercased() == "png",
              let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
        return SignatureAsset(id: id, kind: .png, managedFilename: url.lastPathComponent)
    }
    .sorted { $0.managedFilename < $1.managedFilename }
}

func delete(_ asset: SignatureAsset) throws {
    try fileManager.removeItem(at: fileURL(for: asset))
}
```

Do not scan external folders or introduce a database or manifest.

- [ ] **Step 4: Add the workspace library boundary**

Load `visibleSignatureAssets` from managed storage during initialization and refresh it after import or deletion. Selecting an asset must set it active and initialize placement on the current PDF when needed. Deleting the active asset must clear selection, disable composition, and remove its overlay state.

- [ ] **Step 5: Replace the single artwork controls with a compact native library**

In `VisibleAppearanceInspector`, show stored assets in a compact horizontal `ScrollView` or `Picker` with image thumbnails. Each item calls:

```swift
workspace.selectVisibleSignatureArtwork(asset)
```

Keep one `Choose PNG or PDF` import button and one delete action for the selected asset. Do not add names, tags, profiles, placement presets, or automatic selection.

- [ ] **Step 6: Verify GREEN and commit**

Run the `AutogramTests` target and a Debug build:

```bash
env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project native-macos/Autogram.xcodeproj \
  -scheme Autogram -configuration Debug -destination 'platform=macOS' build
```

Selectively stage only Task 3 hunks:

```bash
git add native-macos/Autogram/Infrastructure/SignatureAssets/SignatureAssetStore.swift
git add -p native-macos/Autogram/Features/Workspace/WorkspaceModel.swift \
  native-macos/Autogram/Features/Signing/VisibleAppearanceInspector.swift \
  native-macos/AutogramTests/VisibleSignatureAssetTests.swift
git commit -m "feat(macos): add graphic signature library"
```

---

### Task 4: Integrated Proof and Installation

**Files:**
- Modify only if a proven integration failure leaves the contract unmet.

**Interfaces:**
- Consumes: Tasks 1 through 3.
- Produces: verified and installed `/Applications/Autogram macOS.app`.

- [ ] **Step 1: Run the smallest automated proof**

Run the complete native target once and the Debug build once. Do not add tests unless one of the six contract claims remains unproven.

- [ ] **Step 2: Build and sign the ARM64 application**

Use:

```bash
env AUTOGRAM_JAVA_HOME=/Users/Magneto/.sdkman/candidates/java/25.0.4.fx-librca \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  scripts/native-macos/build-native-app.sh
env DEVELOPER_ID_APPLICATION=- scripts/native-macos/sign-native-app.sh
```

- [ ] **Step 3: Replace only the native application**

Preserve the current `/Applications/Autogram macOS.app` as a recoverable temporary backup, then replace exactly that bundle. Do not touch any Java Autogram application.

- [ ] **Step 4: Verify the installed artifact**

Verify the installed code signature and confirm that the app executable, CLI helper, and bundled Java report ARM64.

- [ ] **Step 5: Live acceptance**

Open a signed PDF, add one new signature, and prove:

1. all signatures automatically leave the provisional state after DSS validation;
2. `Verify Again` appears only if validation is incomplete;
3. no editable graphic overlay appears until artwork is deliberately chosen;
4. selecting stored artwork enables one overlay;
5. after signing, the embedded appearance remains and no second editable overlay overlaps it.

If acceptance proves a defect, fix only that defect and rerun the proof it broke.
