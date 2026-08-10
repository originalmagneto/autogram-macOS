# Native macOS ASiC Inspection Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make supported ASiC containers return their contents and existing signatures through machine protocol v1, and make the native sidebar show inspection state truthfully.

**Architecture:** The Java inspection service gives every DSS document validator a local `CommonCertificateVerifier` before signatures are materialized. The Swift workspace derives sidebar status from inspection results and presents an explicit ASiC failure state without changing the signing protocol or adding trusted-list work to fast inspection.

**Tech Stack:** Java 25, European Commission DSS 6.4, Gson, JUnit 5, macOS 27, Swift 6, SwiftUI, Swift Testing

## Global Constraints

- Apply the MSW necessity test to every change and proof.
- Deployment target remains macOS 27.0.
- Supported architecture remains ARM64 only.
- Java Autogram and DSS remain the inspection and signing authority.
- Fast inspection does not initialize trusted lists or claim qualified validity.
- Existing PDF inspection behavior must remain unchanged.
- Original files are never modified.
- Machine output never exposes personal absolute paths or internal stack traces.
- Do not add protocol v2, signing-format selection, or unrelated refactoring in this plan.
- Comments, documentation, commit messages, and UI text contain no em dash characters.
- `AGENTS.md` and `CLAUDE.md` remain identical.

---

## Locked File Map

- `src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java`: constructs DSS validators and maps structural inspection results.
- `src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java`: proves local PDF and ASiC inspection behavior.
- `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`: applies inspection results to file state.
- `native-macos/Autogram/Features/Workspace/PDFListView.swift`: maps file state to sidebar labels and colors.
- `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`: displays completed, pending, or failed ASiC inspection.
- `native-macos/AutogramTests/WorkspaceInspectionTests.swift`: proves successful and failed inspections produce truthful workspace state.

### Task 1: Initialize DSS ASiC Analysis Correctly

**Files:**
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java`

**Interfaces:**
- Consumes: `DSSUtils.createDocumentValidator(DSSDocument)` and the existing `inspect(Path) -> JsonObject` contract.
- Produces: the unchanged inspection JSON payload with non-empty `documents` and `signatures` arrays for the existing `general_agenda.asice` fixture.

- [ ] **Step 1: Add the failing ASiC regression proof**

Add this test beside `returnsLocalCryptographicMetadataForSampleSignedPdf`:

```java
@Test
void returnsDocumentsAndSignaturesForAsicWithoutTrustedLists() {
    var sample = Path.of(MachineInspectionServiceTest.class
            .getResource("/digital/slovensko/autogram/general_agenda.asice").getFile());

    var payload = new MachineInspectionService().inspect(sample);

    assertFalse(payload.getAsJsonArray("documents").isEmpty());
    assertFalse(payload.getAsJsonArray("signatures").isEmpty());
}
```

- [ ] **Step 2: Run only the Java inspection proof and confirm the reproduced failure**

Run:

```bash
JAVA_HOME="$(pwd)/target/jdkCache/LIBERICA_jdk25.0.4+9_macos_aarch64-full" \
./mvnw -q -Psystem-jdk \
  -Dtest=MachineInspectionServiceTest#returnsDocumentsAndSignaturesForAsicWithoutTrustedLists \
  test
```

Expected before the fix: FAIL with the DSS `NullPointerException` originating from `DefaultDocumentAnalyzer.setCertificateVerifier` while ASiC signatures are materialized.

- [ ] **Step 3: Attach the local verifier before any signature lookup**

Change `documentValidator` to configure the validator once at creation:

```java
private static SignedDocumentValidator documentValidator(DSSDocument document) {
    var validator = DSSUtils.createDocumentValidator(document);
    if (validator == null) {
        throw new IllegalArgumentException("Unsupported document");
    }
    validator.setCertificateVerifier(new CommonCertificateVerifier());
    return validator;
}
```

Do not initialize `MachineTrustService` and do not change the structural payload's `INDETERMINATE` indication.

- [ ] **Step 4: Run the focused Java inspection service tests**

Run:

```bash
JAVA_HOME="$(pwd)/target/jdkCache/LIBERICA_jdk25.0.4+9_macos_aarch64-full" \
./mvnw -q -Psystem-jdk -Dtest=MachineInspectionServiceTest test
```

Expected: PASS. The new ASiC proof and existing PDF structural proof both pass.

- [ ] **Step 5: Verify machine protocol output on the repository ASiC fixture**

Build the Java classes if the preceding test did not already compile them, then send one `INSPECT` request through the bundled helper. The response must contain `inspection.completed`, at least one document, at least one signature, and `session.completed`. It must not contain an absolute source path.

Use the exact v1 command shape:

```bash
jq -nc \
  --arg source "$(pwd)/src/test/resources/digital/slovensko/autogram/general_agenda.asice" \
  --arg target "/private/tmp/autogram-asic-plan-target.asice" \
  '{protocolVersion:1,requestId:"asic-proof",operation:"INSPECT",payload:{files:[{id:"file-1",source:$source,target:$target}]}}' \
| "build/native/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64" \
    --cli --machine-readable --protocol-version 1 --operation INSPECT
```

If the existing app bundle predates Task 1, rebuild it before this step with `scripts/native-macos/build-native-app.sh`.

- [ ] **Step 6: Commit the Java fix**

```bash
git add \
  src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java \
  src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java
git commit -m "fix(machine): inspect asic with local verifier"
```

### Task 2: Make Native Inspection Status Truthful

**Files:**
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Modify: `native-macos/Autogram/Features/Workspace/PDFListView.swift`
- Modify: `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`
- Test: `native-macos/AutogramTests/WorkspaceInspectionTests.swift`

**Interfaces:**
- Consumes: `PDFItemInspection.pending`, `.completed(InspectedPDF)`, and `.failed`.
- Produces: matching `PDFItemStatus.pending`, `.inspected`, and `.failed` values for inspection work.
- Produces: sidebar labels `Inspecting`, `Ready`, and `Inspection failed`.

- [ ] **Step 1: Extend the existing workspace inspection proof**

In `inspectionStoresSignedAndUnsignedResultsPerWorkspaceItem`, add only these assertions after the existing inspection assertions:

```swift
#expect(workspace.items[0].status == .inspected)
#expect(workspace.items[1].status == .inspected)
#expect(workspace.items[2].status == .failed)
```

- [ ] **Step 2: Run the Autogram unit-test target and confirm the new assertions fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project native-macos/Autogram.xcodeproj \
  -scheme Autogram \
  -destination 'platform=macOS' \
  test -only-testing:AutogramTests
```

Expected before the fix: `inspectionStoresSignedAndUnsignedResultsPerWorkspaceItem` fails because all three statuses remain `.pending`.

- [ ] **Step 3: Update status when inspection results are applied**

In `WorkspaceModel.applyInspectionResults`, replace the two result branches with status-aware values:

```swift
guard let result = results[item.descriptor.id], result.isSignable else {
    return item
        .updatingInspection(to: .failed)
        .updatingStatus(to: .failed)
}
return item
    .updatingInspection(to: .completed(result))
    .updatingStatus(to: .inspected)
```

In `updateInspection`, derive the transient status from the supplied inspection:

```swift
let status: PDFItemStatus = switch inspection {
case .pending: .pending
case .completed: .inspected
case .failed: .failed
}
items = items.map { item in
    inspectedIDs.contains(item.descriptor.id)
        ? item.updatingInspection(to: inspection).updatingStatus(to: status)
        : item
}
```

- [ ] **Step 4: Correct the sidebar labels**

In `PDFListView.workspaceLabel`, use:

```swift
switch self {
case .pending: "Inspecting"
case .inspected: "Ready"
case .signing: "Signing"
case .completed: "Signed"
case .failed: "Inspection failed"
}
```

Keep existing semantic colors, with `.failed` red and `.completed` green.

- [ ] **Step 5: Present an explicit failed ASiC detail state**

Replace the two-branch `ASiCContentsView` body with a complete switch:

```swift
GroupBox("ASiC-E Contents") {
    switch inspection {
    case .pending:
        ProgressView("Inspecting container")
    case .failed:
        ContentUnavailableView(
            "ASiC inspection failed",
            systemImage: "exclamationmark.triangle"
        )
    case .completed(let document):
        ForEach(document.documents, id: \.self) { name in
            Label(name, systemImage: "doc")
        }
    }
}
.padding()
```

Do not add another error property in this task. Protocol v2 will carry typed inspection failure reasons in its own plan.

- [ ] **Step 6: Run the native unit-test target**

Run the same `xcodebuild` command from Step 2.

Expected: PASS, including the three new status assertions.

- [ ] **Step 7: Build the release app**

Run:

```bash
AUTOGRAM_JAVA_HOME="$(pwd)/target/jdkCache/LIBERICA_jdk25.0.4+9_macos_aarch64-full" \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
scripts/native-macos/build-native-app.sh
```

Expected: `build/native/Autogram macOS.app` exists, and both the app executable and `Contents/Helpers/AutogramCLI-arm64` are ARM64 Mach-O files.

- [ ] **Step 8: Commit the native status fix**

```bash
git add \
  native-macos/Autogram/Features/Workspace/WorkspaceModel.swift \
  native-macos/Autogram/Features/Workspace/PDFListView.swift \
  native-macos/Autogram/Features/Workspace/PDFDetailView.swift \
  native-macos/AutogramTests/WorkspaceInspectionTests.swift
git commit -m "fix(macos): show truthful inspection status"
```

### Task 3: Install and Perform Live ASiC Acceptance

**Files:**
- No source changes unless live evidence proves this plan's contract remains unmet.

**Interfaces:**
- Consumes: the release app produced by Task 2.
- Produces: an installed `/Applications/Autogram macOS.app` that opens a real ASiC with contents and signatures visible and no inspection failure.

- [ ] **Step 1: Sign and verify the app bundle locally**

Run:

```bash
codesign --force --deep --sign - --timestamp=none \
  --entitlements native-macos/Autogram/Resources/Autogram.entitlements \
  "build/native/Autogram macOS.app"
codesign --verify --deep --strict --verbose=2 "build/native/Autogram macOS.app"
```

Expected: the bundle is valid on disk and satisfies its designated requirement.

- [ ] **Step 2: Replace only the native test application**

Quit the bundle identifier `digital.slovensko.autogram.native`, replace exactly `/Applications/Autogram macOS.app`, and leave all original Java Autogram applications untouched.

```bash
osascript -e 'tell application id "digital.slovensko.autogram.native" to quit'
rm -rf "/Applications/Autogram macOS.app"
ditto "build/native/Autogram macOS.app" "/Applications/Autogram macOS.app"
```

- [ ] **Step 3: Verify the installed artifact**

Run:

```bash
codesign --verify --deep --strict --verbose=2 "/Applications/Autogram macOS.app"
file "/Applications/Autogram macOS.app/Contents/MacOS/Autogram"
file "/Applications/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64"
```

Expected: code signature verification succeeds and both executables report ARM64 only.

- [ ] **Step 4: Open one real ASiC in the installed app**

Use a user-selected ASiC file or the previously reproduced local sample. Open it explicitly with the native app:

```bash
open -a "/Applications/Autogram macOS.app" "/absolute/path/to/selected.asice"
```

Expected in the UI:

- `Inspecting` appears only while work is active;
- the sidebar changes to `Ready` after successful inspection;
- the detail area lists embedded document names;
- the inspector lists existing signatures and timestamps;
- `Signature inspection failed` does not appear.

- [ ] **Step 5: Halt and report**

Report the contract outcome, the focused Java and Swift proof, the installed app identity, and the live ASiC result. Do not add follow-up fixes unless the live result reproducibly leaves an acceptance claim unmet.

