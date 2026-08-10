# Native macOS Visible PAdES Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a visible `Graphic signature` workflow that imports PNG or PDF artwork, previews a detailed certificate card directly on a PDF page, supports drag, resize, and free rotation, and binds the final appearance to a qualified PAdES Baseline T signature through DSS.

**Architecture:** SwiftUI, AppKit, and PDFKit own asset import, card rendering, placement editing, and presentation state. Machine protocol v2 carries one rendered transparent PNG and one page rectangle per PDF through a reusable JSONL helper session, while protocol v1 remains unchanged. Java snapshots the image, configures DSS visible-signature parameters, and publishes only after trusted validation proves PAdES Baseline T and a qualified timestamp.

**Tech Stack:** macOS 27, Swift 6, SwiftUI, AppKit, PDFKit, Java 25 ARM64, Autogram, European Commission DSS 6.4, JUnit 5, XCTest

## Global Constraints

- Minimum system is macOS 27.
- Architecture is ARM64 only.
- Java Autogram and DSS remain the sole signing and validation engine.
- Visible appearances apply only to PDF signed as PAdES Baseline T.
- Protocol v1 behavior and schema remain unchanged.
- Every published signed output has a qualified timestamp proven through DSS trusted validation.
- The complete card is pre-rendered for arbitrary rotation; DSS receives rotation `NONE`.
- Originals are never overwritten.
- The original artwork path, PIN, and TSA secret are never persisted.
- Keep `AGENTS.md` and `CLAUDE.md` identical.
- Never use an em dash in source, tests, documentation, or commit messages.
- Apply the MSW deletion rule to every claim and add only proof required by this contract.

---

### Task 1: Visual Signature Asset Library and Card Renderer

**Files:**
- Create: `native-macos/Autogram/Core/Models/VisibleSignatureModels.swift`
- Create: `native-macos/Autogram/Infrastructure/SignatureAssets/SignatureAssetStore.swift`
- Create: `native-macos/Autogram/Infrastructure/SignatureAssets/VisibleSignatureRenderer.swift`
- Create: `native-macos/AutogramTests/VisibleSignatureAssetTests.swift`

**Interfaces:**
- Consumes: a PNG or selected PDF page and an application support root.
- Produces: `SignatureAsset`, `VisibleSignaturePlacement`, `VisibleSignatureCardContent`, and a temporary transparent rendered PNG.

- [ ] **Step 1: Write the failing boundary tests**

```swift
@Test func importedArtworkUsesManagedStorageAndPreservesAlpha() throws {
    let asset = try store.importPNG(fixturePNG)
    #expect(asset.fileURL.deletingLastPathComponent() == store.assetsDirectory)
    #expect(asset.fileURL != fixturePNG)
    #expect(try pngHasAlpha(asset.fileURL))
}

@Test func rotatedCardHasTransparentCorners() throws {
    let output = try renderer.render(
        asset: asset,
        content: .init(
            signerName: "Test Signer",
            certificateQualification: "Qualified certificate",
            profile: "PAdES Baseline T",
            timestampStatus: "Qualified timestamp required"
        ),
        signingTime: instant,
        rotationDegrees: 27
    )
    #expect(try cornerPixelsAreTransparent(output))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project native-macos/Autogram.xcodeproj -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:AutogramTests/VisibleSignatureAssetTests
```

Expected: compilation fails because the types are missing.

- [ ] **Step 3: Implement models and managed import**

```swift
struct SignatureAsset: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable { case png, pdf }
    let id: UUID
    let kind: Kind
    let fileURL: URL
}

struct VisibleSignaturePlacement: Sendable, Equatable {
    var pageIndex: Int
    var pageRect: CGRect
    var rotationDegrees: Double
}
```

Copy PNG bytes into `Application Support/Autogram macOS/Visual Signatures/<UUID>.png` without flattening alpha. PDF import presents page selection, renders that page into a transparent bitmap, crops transparent outer pixels, and stores the managed PNG. Persist only asset ID and managed name. Reject unreadable or empty artwork. Do not invent a file-size limit.

- [ ] **Step 4: Implement the detailed card renderer**

The transparent card visibly contains:

```text
Digitally signed by
<artwork>
<signer name>
<authoritative qualification or Certificate qualification unavailable>
PAdES Baseline T
Qualified timestamp required
<shared signing time>
```

Render and rotate the complete card, expand its axis-aligned canvas, and write it to an app cache URL. Do not use `verified`.

- [ ] **Step 5: Run the test and commit**

Run the command from Step 2. Expected: PASS.

```bash
git add native-macos/Autogram/Core/Models/VisibleSignatureModels.swift \
  native-macos/Autogram/Infrastructure/SignatureAssets \
  native-macos/AutogramTests/VisibleSignatureAssetTests.swift
git commit -m "feat(macos): add visible signature assets"
```

### Task 2: Direct PDF Page Placement Editor

**Files:**
- Create: `native-macos/Autogram/Infrastructure/PDF/PDFCoordinateConverter.swift`
- Create: `native-macos/Autogram/Infrastructure/PDF/PDFPlacementOverlayView.swift`
- Modify: `native-macos/Autogram/Infrastructure/PDF/PDFPreviewView.swift`
- Modify: `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`
- Create: `native-macos/AutogramTests/VisibleSignatureGeometryTests.swift`

**Interfaces:**
- Consumes: a placement binding and card preview from Task 1.
- Produces: page, crop-box-local PDF rectangle, free rotation, and a DSS top-left rectangle.

- [ ] **Step 1: Write the failing converter test**

Use one table-driven test for PDF page rotations 0, 90, 180, and 270. Include this unrotated assertion:

```swift
let placement = VisibleSignaturePlacement(
    pageIndex: 1,
    pageRect: CGRect(x: 72, y: 144, width: 216, height: 108),
    rotationDegrees: 31
)
let field = converter.dssField(placement, cropBox: CGRect(x: 0, y: 0, width: 612, height: 792), pageRotation: 0)
#expect(field.page == 2)
#expect(field.originX == 72)
#expect(field.originY == 540)
```

- [ ] **Step 2: Run the test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project native-macos/Autogram.xcodeproj -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:AutogramTests/VisibleSignatureGeometryTests
```

Expected: compilation fails because the converter is missing.

- [ ] **Step 3: Implement the single coordinate converter**

For an unrotated crop box:

```swift
let dssY = cropBox.height - placement.pageRect.minY - placement.pageRect.height
return DSSVisibleField(
    page: placement.pageIndex + 1,
    originX: placement.pageRect.minX,
    originY: dssY,
    width: placement.pageRect.width,
    height: placement.pageRect.height
)
```

The same converter handles crop-box offsets and page rotations. No other file duplicates coordinate formulas.

- [ ] **Step 4: Add the direct AppKit overlay**

Host the overlay inside `PDFView.documentView`. It supports drag, four-corner resize, aspect preservation unless Option is held, edge and center snapping, arbitrary rotation handle, page reassignment, and accessible handle labels. Refresh after scale, page, document, and placement changes. Never add or save a PDF annotation.

- [ ] **Step 5: Run the test and commit**

Run the command from Step 2. Expected: PASS.

```bash
git add native-macos/Autogram/Infrastructure/PDF \
  native-macos/Autogram/Features/Workspace/PDFDetailView.swift \
  native-macos/AutogramTests/VisibleSignatureGeometryTests.swift
git commit -m "feat(macos): place visible signatures on pdf"
```

### Task 3: Protocol v2 Reusable Session

**Files:**
- Create: `protocol/v2/schema/request.schema.json`
- Create: `protocol/v2/schema/event.schema.json`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliApp.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2ProtocolCodec.java`
- Create: `src/test/java/digital/slovensko/autogram/ui/machine/v2/MachineV2CliAppTest.java`
- Create: `native-macos/Autogram/Infrastructure/CLI/MachineProtocolV2Models.swift`
- Create: `native-macos/Autogram/Infrastructure/CLI/MachineSessionProcess.swift`
- Modify: `src/main/java/digital/slovensko/autogram/core/AppStarter.java`
- Modify: `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`

**Interfaces:**
- Consumes: JSONL v2 requests.
- Produces: correlated events with exactly one terminal event per request and a helper process reused until EOF or unexpected exit.

- [ ] **Step 1: Write the failing session tests**

One Java test sends `CAPABILITIES` and `INSPECT` through one input stream and proves both request IDs complete exactly once. One Swift integration test proves two requests reuse one process and that a simulated unexpected exit fails the active request but allows the next call to start a new process.

- [ ] **Step 2: Run and verify RED**

```bash
JAVA_HOME="$PWD/target/jdkCache/LIBERICA_jdk25.0.4+9_macos_aarch64-full" \
  ./mvnw -q -Psystem-jdk -Dtest=MachineV2CliAppTest test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project native-macos/Autogram.xcodeproj -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:AutogramIntegrationTests/MachineSessionProcessTests
```

Expected: compilation fails because v2 is missing.

- [ ] **Step 3: Implement strict JSONL v2**

Support `CAPABILITIES`, `INSPECT`, `CERTIFICATES`, `SIGN`, `TIMESTAMP`, and `VALIDATE`. Keep token operations serialized. Every accepted request has one terminal event. Continue reading until EOF. `AppStarter` routes protocol 2 to v2 and leaves v1 unchanged.

Capabilities contain:

```json
{
  "visibleAppearance": {
    "renderedPng": true,
    "importedAssetTypes": ["image/png", "application/pdf"],
    "arbitraryRotation": "RASTERIZED_IN_SWIFT",
    "fieldCoordinateSystem": "DSS_TOP_LEFT_PDF_POINTS"
  }
}
```

- [ ] **Step 4: Implement the Swift session owner**

Correlate events by request ID, serialize token operations, discard secrets on every terminal path, and restart only after unexpected exit. Retain the current one-shot runner for v1 automation.

- [ ] **Step 5: Run tests and commit**

Run Step 2. Expected: PASS.

```bash
git add protocol/v2 src/main/java/digital/slovensko/autogram/ui/machine/v2 \
  src/main/java/digital/slovensko/autogram/core/AppStarter.java \
  src/test/java/digital/slovensko/autogram/ui/machine/v2 \
  native-macos/Autogram/Infrastructure/CLI
git commit -m "feat(machine): add protocol v2 session"
```

### Task 4: DSS Appearance Binding and Trusted Publication Gate

**Files:**
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/v2/VisibleSignatureAppearance.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/v2/MachineV2RequestValidator.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineSigningService.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineTrustService.java`
- Modify: `src/main/java/digital/slovensko/autogram/core/SigningParameters.java`
- Modify: `src/main/java/digital/slovensko/autogram/core/SigningJob.java`
- Modify: `src/main/java/digital/slovensko/autogram/core/SignatureValidator.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineSigningServiceTest.java`
- Modify: `native-macos/Autogram/Core/Models/SigningModels.swift`
- Test: `native-macos/AutogramIntegrationTests/AutogramCLIEngineTests.swift`

**Interfaces:**
- Consumes: v2 per-file `visibleAppearance` and the trusted-list verifier.
- Produces: either a published, qualified PAdES Baseline T PDF or no output.

- [ ] **Step 1: Write the failing DSS and publication test**

The fixture requests page 2, X 72, Y 540, width 216, and height 108. Prove `PAdESSignatureParameters.getImageParameters()` contains the snapshotted PNG and rectangle. In the same service test, a trusted report with unavailable timestamp qualification must produce `TIMESTAMP_QUALIFICATION_FAILED` and no target; a qualified report publishes the target.

- [ ] **Step 2: Run and verify RED**

```bash
JAVA_HOME="$PWD/target/jdkCache/LIBERICA_jdk25.0.4+9_macos_aarch64-full" \
  ./mvnw -q -Psystem-jdk -Dtest=MachineSigningServiceTest test
```

Expected: FAIL because appearance and authoritative qualification are absent.

- [ ] **Step 3: Validate and snapshot the request**

```java
record VisibleSignatureAppearance(
        String renderedPngPath, int page, float originX, float originY,
        float width, float height, Instant signingTime) {
}
```

Allow it only for PDF plus `PAdES_BASELINE_T`. Require an absolute normalized regular PNG path without symlinks, a positive page, finite geometry, positive dimensions, and ISO-8601 signing time. Open without following links and retain an in-memory byte snapshot before certificate or token work. Do not invent a size cap.

- [ ] **Step 4: Bind the image before data-to-sign**

```java
var field = new SignatureFieldParameters();
field.setPage(appearance.page());
field.setOriginX(appearance.originX());
field.setOriginY(appearance.originY());
field.setWidth(appearance.width());
field.setHeight(appearance.height());
field.setRotation(VisualSignatureRotation.NONE);

var image = new SignatureImageParameters();
image.setImage(new InMemoryDocument(snapshotBytes, "visible-signature.png", MimeTypeEnum.PNG));
image.setFieldParameters(field);
image.setImageScaling(ImageScaling.STRETCH);
parameters.setImageParameters(image);
parameters.bLevel().setSigningDate(Date.from(appearance.signingTime()));
```

Set these parameters before `PAdESService.getDataToSign`.

- [ ] **Step 5: Require trusted qualification before publication**

Publish only when DSS proves the new signature is PAdES Baseline T, cryptographically intact, has a cryptographically intact timestamp qualified at production time, and preserves all previous signatures. If trusted validation is unavailable, discard the reserved output and appearance without describing it as qualified.

- [ ] **Step 6: Emit the typed Swift payload and clean temporary images**

`SigningFile` receives optional `VisibleSignatureRequest`. Use one captured instant for the card and Java signing date. Delete rendered images after success, failure, or cancellation.

- [ ] **Step 7: Run tests and commit**

Run Step 2 plus `AutogramCLIEngineTests`. Expected: PASS.

```bash
git add src/main/java/digital/slovensko/autogram/ui/machine/v2 \
  src/main/java/digital/slovensko/autogram/ui/machine \
  src/main/java/digital/slovensko/autogram/core \
  src/test/java/digital/slovensko/autogram/ui/machine/MachineSigningServiceTest.java \
  native-macos/Autogram/Core/Models/SigningModels.swift \
  native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift \
  native-macos/AutogramIntegrationTests/AutogramCLIEngineTests.swift
git commit -m "feat(machine): bind visible pades appearance"
```

### Task 5: Graphic Signature Controls and Signing Flow

**Files:**
- Create: `native-macos/Autogram/Features/Signing/VisibleAppearanceInspector.swift`
- Modify: `native-macos/Autogram/Features/Signing/SigningInspector.swift`
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceView.swift`
- Modify: `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`
- Modify: `native-macos/AutogramTests/WorkspaceInspectionTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 4.
- Produces: visible `Graphic signature` controls and a complete request using the selected certificate.

- [ ] **Step 1: Write the failing workspace propagation test**

Enable a managed asset and placement, complete certificate selection, and prove the captured request contains one rendered PNG, the selected page, and the converted rectangle.

- [ ] **Step 2: Run and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project native-macos/Autogram.xcodeproj -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:AutogramTests/WorkspaceInspectionTests
```

Expected: compilation fails because workspace appearance state is absent.

- [ ] **Step 3: Add the visible controls**

For PDF with `Automatic` or `PDF with PAdES`, show `Graphic signature` with:

- `Show signature on document` toggle;
- artwork preview;
- `Choose PNG or PDF`;
- `Remove artwork`;
- page, X, Y, width, height, and rotation values;
- `Reset placement`;
- help text `Drag, resize, or rotate the card directly on the page.`

Hide it for ASiC and XAdES output.

- [ ] **Step 4: Build the final card after certificate selection**

Use the certificate display name and authoritative qualification from Java. If unavailable, render `Certificate qualification unavailable`. Use the same instant sent to Java. Stop before signing if artwork is missing or unreadable.

- [ ] **Step 5: Persist only safe preferences**

Remember the managed asset ID, enabled state, and default placement rule. Never persist the original path, rendered card, PIN, or TSA secret.

- [ ] **Step 6: Run native tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project native-macos/Autogram.xcodeproj -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:AutogramTests -only-testing:AutogramIntegrationTests
```

Expected: PASS.

```bash
git add native-macos/Autogram/Features native-macos/AutogramTests/WorkspaceInspectionTests.swift
git commit -m "feat(macos): configure visible pades signatures"
```

### Task 6: Package, Install, and Live Acceptance

**Files:**
- Modify only if evidence requires it: `scripts/native-macos/build-native-app.sh`
- Modify only if evidence requires it: `scripts/native-macos/sign-native-app.sh`

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: verified `/Applications/Autogram macOS.app` and live I.CA acceptance.

- [ ] **Step 1: Run contract tests and build**

Run the focused Java and complete native non-UI commands above. Build using the repository JDK 25 cache and Xcode beta.

- [ ] **Step 2: Sign without replacing bundled JDK signatures**

```bash
DEVELOPER_ID_APPLICATION=- scripts/native-macos/sign-native-app.sh
```

Expected: app-owned Mach-O files are signed, BellSoft runtime signatures are preserved, and the runtime retains `disable-library-validation`.

- [ ] **Step 3: Verify the helper before installation**

Run bundled Java `-version` and machine `CAPABILITIES`. Both must complete before replacing the installed app.

- [ ] **Step 4: Preserve and replace one app**

Quit `digital.slovensko.autogram.native`, move the current `/Applications/Autogram macOS.app` to an explicit `/tmp` backup, copy the verified build, and open it. Do not touch the original Java Autogram app.

- [ ] **Step 5: Perform live I.CA acceptance**

1. Choose `PDF with PAdES`.
2. Enable `Show signature on document`.
3. Import transparent PNG and then a selected PDF artwork page.
4. Drag, resize, and rotate to a non-quarter angle.
5. Sign using I.CA and PIN.
6. Reopen output and confirm the visible card placement.
7. Confirm PAdES Baseline T and qualified timestamp in inspection.
8. Confirm the original is unchanged and the output can be co-signed.

## Contract Proof

Complete means the installed app visibly exposes `Graphic signature`, PNG and PDF artwork import work, direct placement supports move, resize, and free rotation, protocol v2 carries the final card, DSS binds it to PAdES Baseline T, trusted validation proves the qualified timestamp before publication, and live I.CA acceptance passes.
