# Native macOS ASiC Preview and Complete Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an embedded ASiC PDF inside Autogram macOS and replace provisional signature integrity with an explained complete DSS validation result.

**Architecture:** Protocol v1 remains the fast inspection path. Protocol v2 gains `PREVIEW` for DSS-owned ASiC extraction and `VALIDATE` for trusted-list validation. The Swift workspace keeps provisional and complete validation states separate, displays extracted PDFs through the existing PDFKit view, and never modifies the ASiC source.

**Tech Stack:** Java 25, European Commission DSS 6.4, Gson JSON Lines machine protocol, Swift 6, SwiftUI, PDFKit, XCTest and Swift Testing.

## Global Constraints

- The source ASiC container is never modified by preview or validation.
- Java Autogram and DSS remain responsible for ASiC parsing and signature validation.
- SwiftUI and PDFKit remain presentation-only for these operations.
- Validation uses EU trusted lists, certificate paths, OCSP, CRL, and DSS timestamp qualification.
- The fast inspection result must not be presented as confirmed validity.
- No document is sent to an external validation service.
- Errors expose safe reasons without stack traces, secrets, or personal absolute paths.
- Existing tests are extended where possible. No duplicate test matrix or unrelated refactor is admitted.
- Documentation, code comments, and commit messages must not contain em dash characters.

---

## File Map

- `src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java`: extract an inspected ASiC document and map complete DSS reasons.
- `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2ProtocolCodec.java`: add protocol v2 `PREVIEW` operation.
- `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliApp.java`: dispatch preview and complete validation requests.
- `src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java`: prove DSS extraction identity and validation reason mapping.
- `src/test/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliAppTest.java`: prove the two new protocol operations and terminal events.
- `native-macos/Autogram/Core/Models/InspectionModels.swift`: represent embedded documents and validation reasons.
- `native-macos/Autogram/Core/SigningEngine.swift`: expose preview and complete validation capabilities with safe defaults for existing fakes.
- `native-macos/Autogram/Infrastructure/CLI/MachineProtocolV2Models.swift`: encode `PREVIEW` and `VALIDATE` requests and decode preview data.
- `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`: call the long-lived v2 session for preview and validation.
- `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`: supervise preview selection, temporary files, validation replacement, retry, and cleanup.
- `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`: render the clickable ASiC list, internal PDF preview, and Back control.
- `native-macos/Autogram/Features/Signing/SigningInspector.swift`: show validation progress, result, reason, and retry action.
- `native-macos/AutogramTests/WorkspaceInspectionTests.swift`: prove workspace state transitions for preview and complete validation.

### Task 1: DSS-Owned Embedded PDF Extraction

**Files:**
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2ProtocolCodec.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliApp.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliAppTest.java`

**Interfaces:**
- Consumes: ASiC source path and an embedded document name previously returned by inspection.
- Produces: `MachineInspectionService.EmbeddedDocument(String name, String mediaType, byte[] content)` and protocol event `preview.completed` with `name`, `mediaType`, and `contentBase64`.

- [ ] **Step 1: Add the smallest failing extraction test**

Extend the existing ASiC fixture test to call:

```java
var service = new MachineInspectionService();
var embedded = service.extractEmbeddedDocument(sample, "sample.pdf");

assertEquals("sample.pdf", embedded.name());
assertEquals("application/pdf", embedded.mediaType());
assertArrayEquals(expectedPdf, embedded.content());
assertThrows(MachineProtocolException.class,
        () -> service.extractEmbeddedDocument(sample, "missing.pdf"));
```

- [ ] **Step 2: Run the focused Java test and confirm the missing API failure**

Run:

```bash
./mvnw -Psystem-jdk -Dtest=MachineInspectionServiceTest test
```

Expected: compilation fails because `extractEmbeddedDocument` and `EmbeddedDocument` do not exist.

- [ ] **Step 3: Add extraction through the existing DSS container extractors**

Implement the public boundary in `MachineInspectionService`:

```java
public EmbeddedDocument extractEmbeddedDocument(Path path, String expectedName) {
    DSSDocument source = new FileDocument(path.toFile());
    var validator = documentValidator(source);
    if (!isAsic(validator)) {
        throw new MachineProtocolException("PREVIEW_UNSUPPORTED");
    }
    return extractedDocuments(source, validator).stream()
            .filter(document -> expectedName.equals(document.getName()))
            .findFirst()
            .map(document -> new EmbeddedDocument(
                    document.getName(),
                    document.getMimeType() == null ? "application/octet-stream" : document.getMimeType().getMimeTypeString(),
                    readBytes(document)))
            .orElseThrow(() -> new MachineProtocolException("PREVIEW_DOCUMENT_NOT_FOUND"));
}

public record EmbeddedDocument(String name, String mediaType, byte[] content) {
}
```

Use one private `extractedDocuments` method for both `asicDocuments` and extraction. Read bytes from the returned `DSSDocument` stream and close it in the same method.

- [ ] **Step 4: Add and prove protocol v2 `PREVIEW`**

Add `PREVIEW` to both Java and Swift operation enums and add `preview.completed` to the Swift event enum. In `MachineV2CliApp`, require exactly `source` and `document`, call `extractEmbeddedDocument`, and emit:

```json
{
  "type": "preview.completed",
  "payload": {
    "name": "sample.pdf",
    "mediaType": "application/pdf",
    "contentBase64": "JVBERi0..."
  }
}
```

Add one v2 CLI test that asserts `request.started`, `preview.completed`, and `request.completed`, plus rejection of an unknown embedded name without leaking the source path.

Run:

```bash
./mvnw -Psystem-jdk -Dtest=MachineInspectionServiceTest,MachineV2CliAppTest test
```

Expected: PASS.

- [ ] **Step 5: Commit the extraction boundary**

```bash
git add src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2ProtocolCodec.java src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliApp.java src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java src/test/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliAppTest.java
git commit -m "feat(machine): preview ASiC documents"
```

### Task 2: Complete DSS Validation With an Explained Result

**Files:**
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliApp.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliAppTest.java`

**Interfaces:**
- Consumes: protocol v2 `VALIDATE` payload containing the standard `files` array.
- Produces: `validation.completed` per file with the same signature structure as inspection plus `subIndication` and `validationReason` on each signature.

- [ ] **Step 1: Add one failing report-mapping test**

Extend the existing injected `SimpleReport` test so one signature returns `INDETERMINATE`, its DSS sub-indication, and an AdES validation error. Assert:

```java
assertEquals("INDETERMINATE", signature.get("indication").getAsString());
assertEquals(expectedSubIndication, signature.get("subIndication").getAsString());
assertEquals(expectedSafeReason, signature.get("validationReason").getAsString());
```

Use `SimpleReport.getAdESValidationErrors(signatureId)` as the existing Autogram GUI already does. Select the first nonblank localized value and omit the field when DSS supplies none.

- [ ] **Step 2: Run the focused test and confirm the absent fields**

Run:

```bash
./mvnw -Psystem-jdk -Dtest=MachineInspectionServiceTest test
```

Expected: FAIL because the mapped signature lacks the new fields.

- [ ] **Step 3: Map complete DSS indication details**

In `mapSignature`, add:

```java
addEnum(signature, "subIndication", report.getSubIndication(signatureId));
addString(signature, "validationReason", firstValidationReason(report, signatureId));
```

Keep structural inspection provisional. Do not add these fields to the structural hard-coded `INDETERMINATE` result.

- [ ] **Step 4: Implement protocol v2 `VALIDATE` using shared trust state**

Construct one `MachineTrustService` and one `MachineInspectionService.forTrustedValidation()` for the long-lived v2 app session. On the first `VALIDATE` request, initialize `SignatureValidator`; subsequent requests reuse its trusted-list cache. For each file, emit `validation.completed` or `file.failed`, then one terminal request event.

The handler shape is:

```java
private static void validate(
        MachineV2Request request,
        EventWriter writer,
        MachineInspectionService trustedInspection,
        MachineTrustService trustService) {
    trustService.initialize();
    for (var file : requiredFiles(request.payload())) {
        writer.write("validation.completed", request.requestId(), file.id(),
                trustedInspection.inspect(Path.of(file.source())));
    }
    writer.completed(request.requestId(), new JsonObject());
}
```

Guard repeated initialization with session-owned state rather than introducing another global singleton. A trust-loading failure must yield `TRUSTED_LIST_UNAVAILABLE`, not `Invalid`.

- [ ] **Step 5: Prove the v2 validation event contract**

Inject a trusted inspection service and trust initializer into `MachineV2CliAppTest`. Assert one initialization, one `validation.completed` event, and preservation of the DSS indication and reason.

Run:

```bash
./mvnw -Psystem-jdk -Dtest=MachineInspectionServiceTest,MachineV2CliAppTest test
```

Expected: PASS.

- [ ] **Step 6: Commit complete validation**

```bash
git add src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliApp.java src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java src/test/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliAppTest.java
git commit -m "feat(machine): validate signatures with DSS trust data"
```

### Task 3: Native Preview and Validation State

**Files:**
- Modify: `native-macos/Autogram/Core/Models/InspectionModels.swift`
- Modify: `native-macos/Autogram/Core/SigningEngine.swift`
- Modify: `native-macos/Autogram/Infrastructure/CLI/MachineProtocolV2Models.swift`
- Modify: `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Test: `native-macos/AutogramTests/WorkspaceInspectionTests.swift`

**Interfaces:**
- Consumes: `preview.completed` and `validation.completed` protocol v2 events.
- Produces: `EmbeddedDocumentPreview`, `SignatureValidationProgress`, `WorkspaceModel.previewEmbeddedDocument(named:)`, `closeEmbeddedPreview()`, and `verifySelectedDocumentAgain()`.

- [ ] **Step 1: Add one failing workspace state test**

Extend the local fake engine in `WorkspaceInspectionTests` with recorded preview and validation calls. Prove this sequence:

```swift
await workspace.previewEmbeddedDocument(named: "sample.pdf")
#expect(workspace.embeddedPreview?.displayName == "sample.pdf")
#expect(workspace.embeddedPreview?.url.pathExtension == "pdf")

workspace.closeEmbeddedPreview()
#expect(workspace.embeddedPreview == nil)

await workspace.verifySelectedDocumentAgain()
#expect(workspace.selectedItem?.inspection.signatures.first?.validationState == .valid)
```

- [ ] **Step 2: Run the focused Swift test and confirm missing state and methods**

Run:

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS' -only-testing:AutogramTests/WorkspaceInspectionTests test
```

Expected: compilation fails because preview and complete validation interfaces do not exist.

- [ ] **Step 3: Add minimal models and engine defaults**

Define:

```swift
struct EmbeddedDocumentPreview: Sendable, Equatable {
    let displayName: String
    let mediaType: String
    let url: URL
}

enum SignatureValidationProgress: Sendable, Equatable {
    case provisional
    case validating
    case complete
}
```

Add `subIndication: String?` and `validationReason: String?` to `ExistingPDFSignature`. Add these `SigningEngine` requirements with default implementations that throw an unavailable engine error so existing focused test fakes remain source compatible:

```swift
func previewEmbeddedDocument(sourceURL: URL, named: String) async throws -> EmbeddedDocumentPreview
func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection]
```

- [ ] **Step 4: Implement the v2 CLI calls**

Encode `PREVIEW` with `source` and `document`. Decode `contentBase64`, write it to an app-owned temporary directory using the returned display name, and return its URL. Add `validation.completed` to the Swift event enum. Encode `VALIDATE` with the same file objects used by inspection and decode `validation.completed` through the existing signature mapper, including `subIndication` and `validationReason`.

Both operations must call the existing long-lived `MachineSessionProcess` through `runV2`.

- [ ] **Step 5: Implement workspace lifecycle**

Store only one selected embedded preview. Remove its temporary directory when Back is selected, the source item is removed, another preview replaces it, or the workspace is released. Ignore stale responses using the existing inspection generation pattern.

After fast inspection completes, start complete validation without blocking the PDF or ASiC contents view. Replace only matching item inspection results. `verifySelectedDocumentAgain()` runs the same complete validation path for the selected item.

- [ ] **Step 6: Run the focused native test**

Run:

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS' -only-testing:AutogramTests/WorkspaceInspectionTests test
```

Expected: PASS.

- [ ] **Step 7: Commit native state and protocol integration**

```bash
git add native-macos/Autogram/Core/Models/InspectionModels.swift native-macos/Autogram/Core/SigningEngine.swift native-macos/Autogram/Infrastructure/CLI/MachineProtocolV2Models.swift native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift native-macos/Autogram/Features/Workspace/WorkspaceModel.swift native-macos/AutogramTests/WorkspaceInspectionTests.swift
git commit -m "feat(macos): load ASiC previews and validation"
```

### Task 4: Native ASiC and Signature Inspector UI

**Files:**
- Modify: `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`
- Modify: `native-macos/Autogram/Features/Signing/SigningInspector.swift`
- Test: `native-macos/AutogramTests/WorkspaceInspectionTests.swift`

**Interfaces:**
- Consumes: workspace preview URL, validation progress, final state, and safe reason from Task 3.
- Produces: one-click embedded PDF preview, Back control, validation progress, final explained status, and Verify Again action.

- [ ] **Step 1: Render a one-click internal PDF preview**

Change `ASiCContentsView` to accept `workspace` and the selected item. Render PDF entries as borderless buttons:

```swift
Button {
    Task { await workspace.previewEmbeddedDocument(named: name) }
} label: {
    Label(name, systemImage: "doc.richtext")
}
.buttonStyle(.plain)
```

When `workspace.embeddedPreview` belongs to the selected ASiC, render the existing `PDFPreviewView` with no signature placement and add a toolbar-style `Back to ASiC Contents` button. Non-PDF entries remain labels.

- [ ] **Step 2: Render truthful validation progress and reasons**

While complete validation is running, show `Checking trust status` with an indeterminate `ProgressView`. Once complete, retain the existing green, red, and orange status colors and show `validationReason` beneath an indeterminate or invalid signature. Add `Verify Again` only for incomplete validation or a validation request failure.

- [ ] **Step 3: Run the focused state test and build the app**

Run:

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS' -only-testing:AutogramTests/WorkspaceInspectionTests test
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -configuration Debug -destination 'platform=macOS' build
```

Expected: focused tests pass and the app builds.

- [ ] **Step 4: Commit the UI**

```bash
git add native-macos/Autogram/Features/Workspace/PDFDetailView.swift native-macos/Autogram/Features/Signing/SigningInspector.swift native-macos/AutogramTests/WorkspaceInspectionTests.swift
git commit -m "feat(macos): show ASiC previews and trust status"
```

### Task 5: Integrated Proof and Installation

**Files:**
- Modify only if required by a proven integration failure: files already listed in Tasks 1 through 4.

**Interfaces:**
- Consumes: complete Java and native implementations.
- Produces: a locally installed `Autogram macOS.app` ready for the user's live ASiC check.

- [ ] **Step 1: Run the smallest integrated automated proof**

Run:

```bash
./mvnw -Psystem-jdk -Dtest=MachineInspectionServiceTest,MachineV2CliAppTest test
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS' -only-testing:AutogramTests/WorkspaceInspectionTests test
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -configuration Debug -destination 'platform=macOS' build
```

Expected: all commands pass. Do not add more tests unless one of the contract claims remains unproven.

- [ ] **Step 2: Install the verified build**

Use the project's existing native macOS packaging and installation procedure to replace `/Applications/Autogram macOS.app`. Verify the installed executable is ARM64 and its code signature is valid.

- [ ] **Step 3: Perform the live acceptance check**

Open the supplied ASiC in the installed app and prove:

1. One click on `IdSMPdf.pdf` opens it in the central PDF view.
2. Back returns to the ASiC contents list.
3. The signature card leaves the provisional state and shows valid, invalid, or incomplete with a reason.
4. Verify Again runs another complete validation without modifying the source ASiC.

- [ ] **Step 4: Commit only a necessary integration correction**

If Step 3 exposes a contract-breaking defect, fix only that defect, rerun the proof that failed, and commit the focused correction. If no defect exists, do not create an empty integration commit.
