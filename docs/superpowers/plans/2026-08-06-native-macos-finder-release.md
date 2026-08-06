# Native macOS Finder and Release Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the native Autogram application as a Finder-integrated, Developer ID signed, notarized, privacy-checked macOS 27 preview release.

**Architecture:** Native open-document events accept PDFs from Finder and an installable Automator Quick Action that contains AppleScript but no shell signing logic. Release scripts assemble one ARM64 Java helper, apply least-privilege entitlements, sign nested code from the inside out, notarize the DMG, and verify a clean ARM64-only artifact.

**Tech Stack:** macOS 27, Xcode 27, SwiftUI, AppKit open-document events, Automator workflow plist, AppleScript, codesign, notarytool, hdiutil, GitHub Actions

## Global Constraints

- Distribution is outside the Mac App Store.
- The application is Developer ID signed, Hardened Runtime enabled, notarized, and stapled.
- App Sandbox is disabled for the first release.
- Only Java helper executables that load external PKCS#11 libraries receive the library-validation exception.
- The Swift application does not receive the library-validation exception.
- The Finder Quick Action contains no personal path and performs no signing itself.
- The Finder Quick Action accepts one or more PDF files and does not open Terminal.
- Release artifacts contain no secrets, private documents, logs, or personal absolute paths.
- Preview releases target macOS 27 beta; stable release waits for final macOS 27 and Xcode 27.
- The release contains one native ARM64 Autogram 2.7.5 or newer helper.
- Intel helpers, translated processes, and x86_64-only compatibility artifacts are forbidden.
- I.CA support requires SecureStore 8.3.1 or newer and an arm64 PKCS#11 slice.
- Comments and documentation use English and contain no em dash characters.

---

## Locked File Map

- `native-macos/Autogram/App/OpenEventHandler.swift`: receives application open URLs.
- `native-macos/Autogram/App/AutogramApp.swift`: binds open events to the workspace.
- `native-macos/Autogram/Resources/Autogram.entitlements`: least-privilege main app entitlements.
- `native-macos/Helpers/JavaHelper.entitlements`: helper-only library validation exception.
- `native-macos/FinderQuickAction/Sign PDFs with Autogram.workflow/Contents/Info.plist`: workflow metadata.
- `native-macos/FinderQuickAction/Sign PDFs with Autogram.workflow/Contents/document.wflow`: Finder Quick Action definition.
- `native-macos/Autogram/Features/Settings/QuickActionInstaller.swift`: explicit install and remove actions.
- `scripts/native-macos/build-native-app.sh`: deterministic build and helper assembly.
- `scripts/native-macos/sign-native-app.sh`: nested signing and verification.
- `scripts/native-macos/package-native-dmg.sh`: DMG construction.
- `scripts/native-macos/notarize-native-dmg.sh`: notary submission and stapling.
- `scripts/native-macos/verify-native-release.sh`: artifact, privacy, and architecture audit.
- `.github/workflows/native-macos-preview.yml`: unsigned test build on GitHub-hosted macOS 26 with Xcode 27 preview.
- `.github/workflows/native-macos-release.yml`: signed release workflow with protected environment secrets.
- `docs/native-macos-installation.md`: installation and requirements.
- `docs/native-macos-release-checklist.md`: hardware and release gate.

### Task 1: Accept Finder and Open With URLs

**Files:**
- Create: `native-macos/Autogram/App/OpenEventHandler.swift`
- Modify: `native-macos/Autogram/App/AutogramApp.swift`
- Modify: `native-macos/Autogram/Core/Models/PDFItem.swift`
- Test: `native-macos/AutogramTests/OpenEventHandlerTests.swift`
- Test: `native-macos/AutogramUITests/OpenWithFlowTests.swift`

**Interfaces:**
- Consumes: `WorkspaceModel.addFiles(_ urls: [URL])` from the workspace plan.
- Produces: `OpenEventHandler.handle(_ urls: [URL]) async`.

- [ ] **Step 1: Write failing URL intake tests**

```swift
@Test @MainActor func acceptsPdfAndIgnoresDuplicate() async throws {
    let workspace = WorkspaceModel.fixture()
    let handler = OpenEventHandler(workspace: workspace)
    await handler.handle([fixturePDF, fixturePDF])
    #expect(workspace.items.count == 1)
}

@Test @MainActor func rejectsNonPdfWithoutRejectingValidSibling() async throws {
    let workspace = WorkspaceModel.fixture()
    await OpenEventHandler(workspace: workspace).handle([fixturePDF, fixtureText])
    #expect(workspace.items.count == 1)
    #expect(workspace.intakeFailures.count == 1)
}
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement SwiftUI open handling**

Attach `.onOpenURL` for URL-based delivery and the macOS open-document bridge for file URLs. Canonicalize URLs, accept PDF UTType only, preserve valid siblings, and activate the existing workspace window.

- [ ] **Step 4: Add app document declarations**

Declare PDF as an imported document type with role Viewer. Do not register the application as a PDF editor or default owner.

- [ ] **Step 5: Run tests and commit**

Commit: `feat(mac): accept PDFs from Finder`

### Task 2: Ship an Installable Finder Quick Action

**Files:**
- Create: `native-macos/FinderQuickAction/Sign PDFs with Autogram.workflow/Contents/Info.plist`
- Create: `native-macos/FinderQuickAction/Sign PDFs with Autogram.workflow/Contents/document.wflow`
- Create: `native-macos/Autogram/Features/Settings/QuickActionInstaller.swift`
- Modify: `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`
- Test: `native-macos/AutogramTests/QuickActionInstallerTests.swift`
- Test: `scripts/tests/native-macos-quick-action-smoke.sh`

**Interfaces:**
- Consumes: Task 1 open-document handling.
- Produces: `QuickActionInstaller.status()`, `install()`, and `remove()`.

- [ ] **Step 1: Write failing installer tests**

```swift
@Test func installationCopiesOnlyTheKnownWorkflow() throws {
    let fileSystem = InMemoryFileSystem()
    let installer = QuickActionInstaller(fileSystem: fileSystem, servicesURL: servicesURL)
    try installer.install()
    #expect(fileSystem.exists(servicesURL.appending(path: "Sign PDFs with Autogram.workflow")))
    #expect(fileSystem.copiedItems.count == 1)
}
```

- [ ] **Step 2: Create the workflow with exact AppleScript behavior**

The Run AppleScript action uses:

```applescript
on run {input, parameters}
    tell application id "digital.slovensko.autogram.native"
        open input
        activate
    end tell
    return input
end run
```

Configure the workflow to receive PDF files in Finder. Do not add Run Shell Script, terminal commands, repository paths, or signing logic.

- [ ] **Step 3: Validate the workflow**

Run:

```bash
plutil -lint 'native-macos/FinderQuickAction/Sign PDFs with Autogram.workflow/Contents/Info.plist'
plutil -lint 'native-macos/FinderQuickAction/Sign PDFs with Autogram.workflow/Contents/document.wflow'
scripts/tests/native-macos-quick-action-smoke.sh
```

Expected: both plists are valid and the smoke test finds the bundle ID, PDF input type, and no shell action.

- [ ] **Step 4: Implement explicit install and remove buttons**

Copy only after the user presses Install in Settings. Create `~/Library/Services` if needed, replace only the exact Autogram workflow, refresh Services registration, and show installed status. Remove only the same bundle.

- [ ] **Step 5: Run tests and commit**

Commit: `feat(mac): add Finder PDF Quick Action`

### Task 3: Assemble Native and Java Runtime Components

**Files:**
- Create: `native-macos/Autogram/Resources/Autogram.entitlements`
- Create: `native-macos/Helpers/JavaHelper.entitlements`
- Create: `scripts/native-macos/build-native-app.sh`
- Test: `scripts/tests/native-macos-build-smoke.sh`

**Interfaces:**
- Consumes: native Xcode project and Java machine CLI.
- Produces: `build/native/Autogram.app` with the ARM64 Swift app and one ARM64 Java helper.

- [ ] **Step 1: Write a failing bundle-layout smoke test**

```bash
test -x build/native/Autogram.app/Contents/MacOS/Autogram
test -x build/native/Autogram.app/Contents/Helpers/AutogramCLI-arm64
test ! -e build/native/Autogram.app/Contents/Helpers/AutogramCLI-x86_64
test "$(plutil -extract LSMinimumSystemVersion raw build/native/Autogram.app/Contents/Info.plist)" = "27.0"
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Add least-privilege entitlements**

The main entitlement file contains no `com.apple.security.cs.disable-library-validation`. The Java helper entitlement file sets only `com.apple.security.cs.disable-library-validation` to true in addition to required Hardened Runtime defaults.

- [ ] **Step 4: Implement deterministic assembly**

The script runs `xcodebuild` for ARM64, packages the native ARM64 Autogram helper, copies only documented runtime files, removes debug logs and source metadata, and fails when any required executable lacks an arm64 slice or when an Intel helper artifact is present.

- [ ] **Step 5: Run smoke test and commit**

Commit: `build(mac): assemble native Autogram bundle`

### Task 4: Sign Nested Code and Package the DMG

**Files:**
- Create: `scripts/native-macos/sign-native-app.sh`
- Create: `scripts/native-macos/package-native-dmg.sh`
- Create: `scripts/tests/native-macos-signing-smoke.sh`

**Interfaces:**
- Consumes: unsigned app from Task 3 and `DEVELOPER_ID_APPLICATION` environment value.
- Produces: strictly signed app and `build/native/Autogram-native-preview.dmg`.

- [ ] **Step 1: Write the failing verification script**

The smoke test runs `codesign --verify --deep --strict --verbose=2`, verifies the main app lacks the library-validation exception, verifies Java helpers contain it, and checks every nested Mach-O has the expected Team ID.

- [ ] **Step 2: Implement inside-out signing**

Sign nested dylibs and binaries first, Java runtime containers next, helper bundles next, and the Swift app last. Use `--options runtime`, timestamping, explicit entitlements, and no `--deep` during signing.

- [ ] **Step 3: Package a deterministic DMG**

Create a staging directory containing `Autogram.app`, an Applications symlink, and the installation guide. Build with `hdiutil create`, set a stable volume name, and emit a SHA-256 checksum.

- [ ] **Step 4: Run verification and commit**

Commit: `build(mac): sign and package native Autogram`

### Task 5: Notarize and Verify the Release Artifact

**Files:**
- Create: `scripts/native-macos/notarize-native-dmg.sh`
- Create: `scripts/native-macos/verify-native-release.sh`
- Create: `docs/native-macos-release-checklist.md`

**Interfaces:**
- Consumes: signed DMG and notarytool Keychain profile name from `NOTARYTOOL_PROFILE`.
- Produces: stapled DMG and machine-readable verification summary.

- [ ] **Step 1: Implement notary submission without secret arguments**

```bash
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
```

- [ ] **Step 2: Add release privacy and architecture checks**

Mount the DMG read-only, enumerate files, reject logs, source maps, private keys, provisioning profiles, repository metadata, personal absolute paths, unexpected executables, and Intel helpers. Verify the ARM64 main app, the single ARM64 helper, protocol fixture version, and Quick Action plist validity.

- [ ] **Step 3: Add manual hardware checklist**

Cover eID with an ARM64-capable PKCS#11 library, I.CA SecureStore 8.3.1 or newer, rejection of an x86_64-only test dylib, rejection of I.CA 8.1.0 metadata, correct and incorrect PIN, card removal, one and many PDFs, existing signatures, unavailable TSA, local and cloud files, Finder Quick Action, and a fresh macOS 27 user account.

- [ ] **Step 4: Run on a signed candidate and commit**

Commit: `build(mac): notarize and audit release`

### Task 6: Add Preview and Release Workflows

**Files:**
- Create: `.github/workflows/native-macos-preview.yml`
- Create: `.github/workflows/native-macos-release.yml`
- Modify: `.github/CODEOWNERS`

**Interfaces:**
- Consumes: all build, test, signing, and verification scripts.
- Produces: unsigned PR artifact and protected signed release artifact.

- [ ] **Step 1: Add preview CI on available GitHub infrastructure**

Use `runs-on: macos-26`, select the available Xcode 27 public preview with `maxim-lobanov/setup-xcode@v1` and `xcode-version: '27.0'`, install Liberica JDK 25, then run Java tests, Swift tests, unsigned assembly, shell syntax checks, plist validation, and privacy scans.

- [ ] **Step 2: Add protected release workflow**

Trigger only by manual dispatch or `native-v*` tag. Use the protected `packaging` environment. Import certificates into an ephemeral Keychain, use a preconfigured notarytool profile, sign, notarize, verify, upload the DMG and checksum, then delete the Keychain in an `always()` step.

- [ ] **Step 3: Pin third-party actions by commit SHA**

Resolve the reviewed release tags to immutable commits, then place those commits after `@` in both workflows:

```bash
gh api repos/actions/checkout/git/ref/tags/v4 --jq .object.sha
gh api repos/actions/setup-java/git/ref/tags/v4 --jq .object.sha
gh api repos/maxim-lobanov/setup-xcode/git/ref/tags/v1 --jq .object.sha
gh api repos/actions/upload-artifact/git/ref/tags/v4 --jq .object.sha
gh api repos/softprops/action-gh-release/git/ref/tags/v2 --jq .object.sha
```

Record the corresponding human-readable tag in a YAML comment. Do not use floating `main`, `master`, or unpinned major tags in the release workflow.

- [ ] **Step 4: Update code ownership and run workflow lint**

Add `native-macos/`, `scripts/native-macos/`, and both workflows to the release-team ownership boundary. Parse workflow YAML and run actionlint.

- [ ] **Step 5: Commit**

Commit: `ci(mac): build native preview and release`

### Task 7: Installation Documentation and Final Smoke Test

**Files:**
- Create: `docs/native-macos-installation.md`
- Modify: `README.md`
- Modify: `docs/macos-cli-automation.md`
- Test: `scripts/tests/native-macos-release-smoke.sh`

**Interfaces:**
- Consumes: verified DMG and Finder workflow.
- Produces: public installation and requirements documentation with no personal assumptions.

- [ ] **Step 1: Write the installation guide**

Document macOS 27+, Apple silicon, Autogram 2.7.5 or newer, supported card middleware, I.CA SecureStore 8.3.1 or newer, the startup arm64 driver check, network requirement for qualified timestamping, DMG installation, Quick Action installation from Settings, batch behavior, output naming, privacy model, and troubleshooting.

- [ ] **Step 2: Update the root README**

Clearly distinguish the cross-platform JavaFX app, the existing CLI automation, and the native macOS preview. State that the Quick Action belongs to Finder and accepts multiple PDFs.

- [ ] **Step 3: Run the final smoke sequence**

```bash
bash -n scripts/native-macos/*.sh scripts/tests/native-macos-*.sh
plutil -lint 'native-macos/FinderQuickAction/Sign PDFs with Autogram.workflow/Contents/'*.plist
scripts/tests/native-macos-release-smoke.sh build/native/Autogram-native-preview.dmg
git diff --check
rg -n $'\u2014|/Users/|BEGIN .*PRIVATE KEY|api[_-]?key|password\\s*=' native-macos scripts/native-macos docs README.md
```

Expected: all checks pass and the secret scan returns no findings.

- [ ] **Step 4: Commit**

Commit: `docs(mac): add native installation guide`

## Completion Gate

- Finder Quick Action installs only after explicit user action.
- Quick Action passes multiple PDFs through native open-document events.
- No Terminal or JavaFX UI appears.
- Main app and nested helpers pass strict signing validation.
- Only Java helpers carry the library-validation exception.
- The release contains no Intel helper or x86_64-only compatibility path.
- Startup diagnostics reject an incompatible PKCS#11 dylib with a clear middleware repair instruction.
- DMG is notarized, stapled, and accepted by Gatekeeper.
- Release artifact contains no private paths, secrets, logs, or client data.
- Preview CI uses the current Xcode 27 public preview on `macos-26`; a stable release waits for final Xcode 27.
- SOL performs final acceptance on the complete artifact.
- Luna performs read-only privacy, entitlements, workflow, and release-content audits.
