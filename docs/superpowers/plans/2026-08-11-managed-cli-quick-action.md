# Managed CLI Quick Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Autogram macOS install, report, update, reinstall, and remove the direct Finder CLI signing action without development paths.

**Architecture:** Bundle a self-contained versioned workflow containing the current signing scripts. `QuickActionInstaller` compares its bundled marker with the installed marker, performs atomic replacement, and maintains only an already installed managed action at launch. Settings presents prerequisite and lifecycle state from this installer and the existing signing environment diagnostics.

**Tech Stack:** Swift 6, SwiftUI, AppKit Services registration, Automator workflow bundles, Bash, Xcode resources.

## Global Constraints

- Apple silicon and ARM64 only.
- I.CA requires SecureStore 8.3.1 or newer.
- The Quick Action must not contain a personal absolute path.
- The PIN must travel only through standard input and process memory.
- Removing the action must prevent automatic reinstallation.
- Existing Java DSS and Autogram remain the signing authority.
- Do not use em dashes.

---

### Task 1: Bundle the direct signing workflow

**Files:**
- Create: `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Info.plist`
- Create: `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow`
- Create: `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/autogram-quick-action.sh`
- Create: `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/autogram-cli-sign.sh`
- Create: `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/managed-version`
- Modify: `native-macos/Autogram.xcodeproj/project.pbxproj`
- Modify: `scripts/native-macos/verify-native-release.sh`
- Test: `scripts/macos-automation/test_autogram-cli-sign.sh`

**Interfaces:**
- Consumes: current scripts under `scripts/macos-automation` and `AutogramCLI-arm64` in the installed application.
- Produces: bundled resource named `Sign PDFs Autogram.workflow` with marker value `1`.

- [ ] **Step 1: Add a failing bundle verification**

Extend release verification to require the direct workflow, valid property lists, executable scripts, marker `1`, and no `/Users/`, Intel, or Rosetta text.

```bash
managed_workflow="${app_bundle}/Contents/Resources/Sign PDFs Autogram.workflow/Contents"
[[ "$(cat "${managed_workflow}/Resources/managed-version")" == "1" ]] || fail "Managed workflow version is invalid"
bash -n "${managed_workflow}/Resources/autogram-quick-action.sh"
bash -n "${managed_workflow}/Resources/autogram-cli-sign.sh"
```

- [ ] **Step 2: Run the focused verification and observe the missing workflow failure**

Run the resource validation against a native build or inspect the build resource phase. Expected: failure because `Sign PDFs Autogram.workflow` is absent.

- [ ] **Step 3: Create the self-contained workflow**

Use an Automator Run Shell Script action that resolves the managed workflow from the current user's Services directory and executes:

```bash
workflow_resources="$HOME/Library/Services/Sign PDFs Autogram.workflow/Contents/Resources"
exec "${workflow_resources}/autogram-quick-action.sh" "$@"
```

Copy the current safe launcher scripts into workflow Resources and add the workflow to the app resource phase.

- [ ] **Step 4: Run shell syntax, plist, and existing machine request checks**

Run:

```bash
bash -n native-macos/FinderQuickAction/Sign\ PDFs\ Autogram.workflow/Contents/Resources/*.sh
plutil -lint native-macos/FinderQuickAction/Sign\ PDFs\ Autogram.workflow/Contents/Info.plist
plutil -lint native-macos/FinderQuickAction/Sign\ PDFs\ Autogram.workflow/Contents/document.wflow
bash scripts/macos-automation/test_autogram-cli-sign.sh
```

Expected: all pass.

### Task 2: Add versioned installation and maintenance

**Files:**
- Modify: `native-macos/Autogram/Features/Settings/QuickActionInstaller.swift`
- Modify: `native-macos/Autogram/App/AutogramApp.swift`
- Create: `native-macos/AutogramTests/QuickActionInstallerTests.swift`

**Interfaces:**
- Consumes: bundled `Sign PDFs Autogram.workflow` and marker `managed-version`.
- Produces: `QuickActionInstaller.Status` cases `.notInstalled`, `.updateRequired`, and `.current`; methods `install()`, `remove()`, and `maintainIfInstalled()`.

- [ ] **Step 1: Write focused installer tests**

Use temporary bundle and Services directories to prove absent, install, stale update, current reinstall, remove, and no reinstall after removal.

```swift
let installer = QuickActionInstaller(
    fileManager: .default,
    servicesURL: services,
    bundledWorkflowURL: bundled
)
#expect(installer.status == .notInstalled)
try installer.install()
#expect(installer.status == .current)
```

- [ ] **Step 2: Run only `QuickActionInstallerTests` and observe failures**

Run:

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS' -only-testing:AutogramTests/QuickActionInstallerTests test
```

Expected: compile or assertion failure because version-aware interfaces do not exist.

- [ ] **Step 3: Implement atomic install and comparison**

Add injected bundle URL support for tests, compare trimmed marker contents, copy to a temporary sibling, then replace the installed workflow. `maintainIfInstalled()` returns without work when no workflow exists.

```swift
func maintainIfInstalled() throws {
    guard status != .notInstalled else { return }
    guard status == .updateRequired else { return }
    try install()
}
```

- [ ] **Step 4: Call maintenance once after application launch**

Create one installer in `AutogramApp.init()`, call `try? maintainIfInstalled()`, and never install an absent action.

- [ ] **Step 5: Run the focused installer tests**

Expected: all `QuickActionInstallerTests` pass.

### Task 3: Update Settings and public documentation

**Files:**
- Modify: `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`
- Modify: `README.md`
- Modify: `README-SK.md`
- Modify: `docs/native-macos-installation.md`

**Interfaces:**
- Consumes: version-aware installer status and existing workspace middleware diagnostics.
- Produces: direct signing action controls and matching installation documentation.

- [ ] **Step 1: Replace the Finder section copy and controls**

Show direct signing behavior, helper state, I.CA 8.3.1 requirement, eID middleware state, current version state, and contextual Install, Update, Reinstall, and Remove controls.

- [ ] **Step 2: Update English and Slovak documentation**

Document that the action directly signs one or more PDFs, prompts for card, certificate, and PIN, requires compatible middleware, is maintained after app updates, and can be removed from Settings.

- [ ] **Step 3: Run focused verification**

Run `git diff --check`, search changed public files for personal paths and em dashes, run the installer test, shell syntax checks, plist checks, and the existing CLI machine request test.

- [ ] **Step 4: Commit and push**

Create focused conventional commits for implementation and documentation, then push `codex/feature-cli-synced` to origin.
