# Finder Quick Action and Unsigned Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an active Finder PDF Quick Action with visible Settings feedback, then publish an installable unsigned preview DMG with release notes.

**Architecture:** Keep the Automator workflow as the Finder integration and make the native installer responsible for atomic copying, Services refresh, and post-install verification. Keep preview packaging unsigned and use GitHub Actions plus a version tag to publish the DMG and checksum.

**Tech Stack:** SwiftUI, Foundation, AppKit Services, Automator workflow plist, Bash, GitHub Actions, GitHub Releases.

## Global Constraints

- Do not alter or delete the legacy user-created Quick Action.
- Do not claim Developer ID signing or notarization.
- Do not add secrets or personal paths.
- Keep `AGENTS.md` and `CLAUDE.md` identical.
- Do not use em dashes.

---

### Task 1: Verified Finder Quick Action installation

**Files:**
- Modify: `native-macos/Autogram/Features/Settings/QuickActionInstaller.swift`
- Modify: `native-macos/AutogramTests/QuickActionInstallerTests.swift`
- Modify: `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow`
- Modify: `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/managed-version`

**Interfaces:**
- Produces: an async-safe installation result that confirms installed Finder and PDF metadata.

- [ ] Add focused tests for installed metadata validation and invalid workflow rejection.
- [ ] Run only `QuickActionInstallerTests` and confirm the new tests fail.
- [ ] Add post-install metadata validation and Services refresh through a small injectable registrar boundary.
- [ ] Run only `QuickActionInstallerTests` and confirm they pass.
- [ ] Verify the installed workflow through `pbs -dump` on the local Mac.

### Task 2: Settings progress and result feedback

**Files:**
- Modify: `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`

**Interfaces:**
- Consumes: the verified installer from Task 1.
- Produces: installing, ready, and error UI states plus reveal behavior.

- [ ] Add `isQuickActionOperationRunning` and success-message state.
- [ ] Move install, reinstall, and remove work off the main actor while preserving UI state updates.
- [ ] Disable controls and show an indeterminate progress indicator during work.
- [ ] Show `Finder Quick Action ready` after verified installation.
- [ ] Add `Reveal Installed Quick Action` using `NSWorkspace`.
- [ ] Build the native app and run the focused installer tests.

### Task 3: Unsigned preview release pipeline

**Files:**
- Modify: `.github/workflows/native-macos-preview.yml`
- Modify: `.github/workflows/native-macos-release.yml`
- Modify: `scripts/native-macos/build-native-app.sh`
- Modify: `scripts/native-macos/verify-native-release.sh`
- Modify: `README.md`

**Interfaces:**
- Produces: an unsigned DMG, SHA-256 checksum, and GitHub Release for a `native-v*` tag.

- [ ] Replace CI-only `rg` checks with tools guaranteed on the runner or install no extra dependency.
- [ ] Add a tag-triggered unsigned release path that reuses the verified preview build.
- [ ] Generate release notes and prepend the unsigned Gatekeeper warning.
- [ ] Use stable artifact names containing `Autogram-macOS` and the tag version.
- [ ] Document unsigned installation and verification in README.
- [ ] Validate workflow YAML, shell syntax, release paths, and absence of secrets or personal paths.

### Task 4: Publish and verify

**Files:**
- No source files beyond Tasks 1 to 3.

**Interfaces:**
- Consumes: the verified Quick Action implementation and release workflow.
- Produces: pushed `main`, a version tag, and a GitHub Release URL.

- [ ] Install the rebuilt app and managed workflow locally.
- [ ] Confirm macOS Services lists the action for `com.adobe.pdf`.
- [ ] Commit and push the focused changes to `main`.
- [ ] Create and push `native-v0.1.0-preview.1`.
- [ ] Monitor the GitHub Actions run to completion.
- [ ] Verify the GitHub Release contains the DMG, checksum, generated changelog, and unsigned warning.

