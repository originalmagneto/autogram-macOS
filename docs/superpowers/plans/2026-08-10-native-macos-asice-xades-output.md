# Native macOS ASiC-E XAdES Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user choose automatic, PAdES, or ASiC-E with XAdES signing and produce a validated `.asice` output for a PDF when XAdES is selected.

**Architecture:** Keep SwiftUI responsible for the selected output intent and output filename. Pass the chosen Baseline T level through the existing machine request. Java Autogram and DSS choose PAdES or ASiC-E with XAdES, preserve the format of an existing ASiC container, require a qualified timestamp, and validate the produced signature before publication.

**Tech Stack:** Swift 6, SwiftUI, Java 25, Autogram, European Commission DSS 6.4, JSON Lines machine protocol v1, Swift Testing, JUnit 5.

## Global Constraints

- Minimum system: macOS 27.
- Architecture: ARM64 only.
- Java Autogram and DSS remain the only signing and validation engine.
- PAdES and ASiC outputs use Baseline T with a qualified timestamp.
- Existing ASiC containers keep their container type and signature family.
- Original files are never overwritten.
- PINs and TSA credentials remain standard-input-only secrets.
- Keep `AGENTS.md` and `CLAUDE.md` unchanged and identical.
- Do not add unrelated refactoring or duplicate tests.

---

### Task 1: Enable XAdES Baseline T at the machine boundary

**Files:**
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineDriverService.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineRequestValidator.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineSigningService.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineDriverServiceTest.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineRequestValidatorTest.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineSigningServiceTest.java`

**Interfaces:**
- Consumes: `SignRequest.signatureLevel()` with `PAdES_BASELINE_T` or `XAdES_BASELINE_T`.
- Produces: machine capabilities containing both levels and a DSS signing job that creates ASiC-E with XAdES for a standalone PDF when XAdES is requested.

- [ ] **Step 1: Add the failing machine behavior proofs**

Update the capabilities expectation to the literal ordered list:

```java
assertEquals(List.of("PAdES_BASELINE_T", "XAdES_BASELINE_T"),
        strings(payload.getAsJsonArray("signatureLevels")));
```

Add one validator assertion that `XAdES_BASELINE_T` is accepted with the existing required timestamp request. Add one signing parameter test that sets `MachineSettings` to `SignatureLevel.XAdES_BASELINE_T`, creates a job from `sample.pdf`, and asserts:

```java
assertEquals(SignatureLevel.XAdES_BASELINE_T, job.getParameters().getLevel());
assertEquals(SignatureForm.XAdES, job.getParameters().getSignatureType());
assertEquals(ASiCContainerType.ASiC_E, job.getParameters().getContainer());
```

The production mutation caught by these proofs is a helper that advertises, rejects, or routes only PAdES.

- [ ] **Step 2: Run the focused tests and verify the expected failures**

Run:

```bash
JAVA_HOME=$(/usr/libexec/java_home -v 25) ./mvnw -q \
  -Dtest=MachineDriverServiceTest,MachineRequestValidatorTest,MachineSigningServiceTest test
```

Expected: the new capability and validator assertions fail because only PAdES is accepted, and the PDF job remains PAdES.

- [ ] **Step 3: Add the minimal machine implementation**

Add `XAdES_BASELINE_T` to capabilities and allow exactly the two required levels in `validateSign`. In `DefaultSessionFactory.apply`, set the validated request level on `MachineSettings` before opening the signing session:

```java
settings.setSignatureLevel(SignatureLevel.valueOf(request.signatureLevel()));
```

In `DefaultSigningSession.signingParameters`, retain the existing ASiC preservation branches first. For a non-ASiC document, route `XAdES_BASELINE_T` to:

```java
return SigningParameters.buildForASiCWithXAdES(document, false, false,
        settings.getTspSource(), true);
```

Keep the existing PAdES branch as the only other accepted path.

- [ ] **Step 4: Run the focused machine tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit the machine boundary**

```bash
git add src/main/java/digital/slovensko/autogram/ui/machine/MachineDriverService.java \
  src/main/java/digital/slovensko/autogram/ui/machine/MachineRequestValidator.java \
  src/main/java/digital/slovensko/autogram/ui/machine/MachineSigningService.java \
  src/test/java/digital/slovensko/autogram/ui/machine/MachineDriverServiceTest.java \
  src/test/java/digital/slovensko/autogram/ui/machine/MachineRequestValidatorTest.java \
  src/test/java/digital/slovensko/autogram/ui/machine/MachineSigningServiceTest.java
git commit -m "feat(machine): add asice xades output"
```

### Task 2: Carry output intent through Swift and reserve `.asice`

**Files:**
- Modify: `native-macos/Autogram/Core/Models/SigningModels.swift`
- Modify: `native-macos/Autogram/Infrastructure/FileSystem/OutputService.swift`
- Modify: `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`
- Modify: `native-macos/Autogram/Infrastructure/Fakes/FakeSigningEngine.swift`
- Test: `native-macos/AutogramTests/OutputServiceTests.swift`
- Test: `native-macos/AutogramIntegrationTests/AutogramCLIEngineTests.swift`
- Update request initializers in existing tests that construct `SigningRequest`.

**Interfaces:**
- Produces: `SigningOutputFormat` with `.automatic`, `.pades`, and `.asiceXAdES`.
- Produces: `SigningRequest.outputFormat: SigningOutputFormat`.
- Consumes: output intent in `AutogramCLIEngine.sign(request:)`.

- [ ] **Step 1: Add the failing Swift boundary proof**

Add an `OutputService` proof that requesting extension `asice` for `case.pdf` reserves `case_signed.asice`. Add an integration proof that a `SigningRequest` with `.asiceXAdES` sends the literal level `XAdES_BASELINE_T`, targets an `.asice` path, finalizes an `.asice` file, and emits its `.asice` URL.

The production mutation caught by these proofs is ignoring the selected output format or retaining the source `.pdf` extension.

- [ ] **Step 2: Run the focused Swift tests and verify the expected failures**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project native-macos/Autogram.xcodeproj \
  -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' \
  test \
  -only-testing:AutogramTests/asicOutputIntentChangesTheReservedExtension \
  -only-testing:AutogramIntegrationTests/signingAsXAdESRequestsAndFinalizesASiCE
```

Expected: compile failure because the output format model and extension-aware reservation do not exist.

- [ ] **Step 3: Add the minimal Swift model and output routing**

Add:

```swift
enum SigningOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case pades
    case asiceXAdES

    var id: Self { self }
    var signatureLevel: String { self == .asiceXAdES ? "XAdES_BASELINE_T" : "PAdES_BASELINE_T" }
}
```

Add `outputFormat` to `SigningRequest`, defaulting to `.automatic` only where a compatibility default is necessary. Extend `OutputService.reserve` with an optional `outputExtension`; use it when deriving the non-overwriting destination. In `AutogramCLIEngine`, reserve `.asice` for `.asiceXAdES` PDF inputs, retain `.asice` for existing containers, and send `request.outputFormat.signatureLevel`.

If inspection already reserved a PDF output, replace that reservation before XAdES signing and remove only its temporary placeholder.

- [ ] **Step 4: Run the focused Swift tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit Swift output routing**

```bash
git add native-macos/Autogram/Core/Models/SigningModels.swift \
  native-macos/Autogram/Infrastructure/FileSystem/OutputService.swift \
  native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift \
  native-macos/Autogram/Infrastructure/Fakes/FakeSigningEngine.swift \
  native-macos/AutogramTests native-macos/AutogramIntegrationTests
git commit -m "feat(macos): route asice xades output"
```

### Task 3: Add the native format picker and install the app

**Files:**
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Modify: `native-macos/Autogram/Features/Signing/SigningInspector.swift`
- Modify: `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`
- Modify: `native-macos/Autogram/Resources/Localizable.xcstrings` only if Xcode does not extract the new labels automatically.

**Interfaces:**
- Consumes: `SigningOutputFormat` and `SigningRequest.outputFormat` from Task 2.
- Produces: one inspector picker whose selection is used by the next signing request.

- [ ] **Step 1: Bind the workspace selection into signing**

Add `selectedOutputFormat: SigningOutputFormat = .automatic` to `WorkspaceModel`. Pass it to `SigningRequest` in `sign(driverID:certificateSerial:pin:)`.

- [ ] **Step 2: Add the format picker**

Replace the static profile value in `SigningInspector` with a picker containing:

```swift
Picker("Format", selection: Binding(
    get: { workspace.selectedOutputFormat },
    set: { workspace.selectedOutputFormat = $0 }
)) {
    Text("Automatic").tag(SigningOutputFormat.automatic)
    Text("PDF with PAdES").tag(SigningOutputFormat.pades)
    Text("ASiC-E with XAdES").tag(SigningOutputFormat.asiceXAdES)
}
```

Keep `Qualified timestamp` visible and mandatory. For an existing ASiC selection, show secondary text explaining that its existing XAdES or CAdES family will be preserved.

- [ ] **Step 3: Run all existing Java and native non-UI tests**

Run:

```bash
JAVA_HOME=$(/usr/libexec/java_home -v 25) ./mvnw -q \
  -Dtest='digital.slovensko.autogram.ui.machine.*Test' test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project native-macos/Autogram.xcodeproj \
  -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' \
  test \
  -only-testing:AutogramTests \
  -only-testing:AutogramIntegrationTests
```

Expected: PASS.

- [ ] **Step 4: Build and install the ARM64 application**

Build the Java helper with Java 25, package the Release app using `scripts/native-macos/build-native-app.sh`, verify the helper and app are ARM64, verify the app signature, preserve the current `/Applications/Autogram macOS.app` as an explicit recoverable backup, and install the new app.

- [ ] **Step 5: Perform live acceptance**

Open one PDF, choose `ASiC-E with XAdES`, sign with the real I.CA card, and prove all of the following:

- the output ends in `.asice`;
- the original PDF remains unchanged;
- the output contains the original PDF;
- inspection displays one XAdES Baseline T signature;
- inspection displays a qualified timestamp;
- the produced container can be opened again and co-signed.

- [ ] **Step 6: Commit the native picker**

```bash
git add native-macos/Autogram/Features/Workspace/WorkspaceModel.swift \
  native-macos/Autogram/Features/Signing/SigningInspector.swift \
  native-macos/Autogram/Features/Settings/AutogramSettingsView.swift \
  native-macos/Autogram/Resources/Localizable.xcstrings
git commit -m "feat(macos): choose signing output format"
```

## Contract Proof

The implementation is complete when the focused Java proof confirms DSS selects XAdES Baseline T with ASiC-E, the Swift integration proof confirms the exact machine payload and `.asice` final output, all existing machine and native tests pass, and the live card acceptance confirms a qualified timestamped XAdES signature inside the generated ASiC-E container.
