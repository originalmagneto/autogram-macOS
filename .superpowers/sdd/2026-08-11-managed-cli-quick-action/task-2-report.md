# Task 2 Report: Versioned Finder Quick Action Maintenance

## Contract

Install and maintain the bundled `Sign PDFs Autogram.workflow` using its trimmed `Contents/Resources/managed-version` marker. An absent action must remain absent at launch. Existing managed actions must be classified as current or requiring an update, and replacement must be staged in a sibling temporary directory before the installed workflow is replaced.

## Changes

- Added injected bundled-workflow URLs for filesystem-backed installer tests.
- Added version-aware status comparison and the public `current` and `updateRequired` status values while retaining the existing status-case compatibility required by the untouched Settings view.
- Installed workflows now copy to a temporary sibling before either a move for initial installation or a replacement for an existing action.
- Added `maintainIfInstalled()` to update only existing stale actions.
- Called maintenance once during `AutogramApp` initialization.
- Added one focused Swift Testing suite covering absence, installation, stale maintenance, current replacement, removal, and no reinstallation after removal.

## Verification

Initial focused test run failed at compilation because the injected `bundledWorkflowURL` initializer parameter did not yet exist.

Final focused run:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS' -only-testing:AutogramTests/QuickActionInstallerTests test
```

Result: `TEST SUCCEEDED`, 6 tests in `QuickActionInstallerTests` passed.

## Self-Review

- `git diff --check` passed.
- Scoped source search found no personal absolute paths, credentials, or secrets in the changed Swift files.
- No files outside the assigned Swift files and this required report were changed.

## Remaining Risk

The legacy status case names remain as compatibility aliases for the existing Settings view. A later UI task can rename those case references without changing the installer behavior.

## Review Fix Round 1

### Reviewer findings resolved

- Replaced the compatibility aliases with real `Status` enum cases: `notInstalled`, `updateRequired`, and `current`.
- Changed `isInstalled` to report filesystem presence, so a stale installed workflow remains installed while its status is `updateRequired`.
- Reject empty and whitespace-only trimmed version markers from both bundled and installed workflows, classifying either condition as `updateRequired`.
- Added focused coverage proving `maintainIfInstalled()` leaves a current workflow untouched.
- Updated only the Settings status references required to compile after removing the obsolete alias cases. No Task 3 UI behavior was added.

### Verification

Red run before the production fix: 8 focused tests ran, with the expected failures for whitespace-only version markers and stale `isInstalled` classification.

Final focused run:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS' -only-testing:AutogramTests/QuickActionInstallerTests test
```

Result: `TEST SUCCEEDED`, 9 tests in `QuickActionInstallerTests` passed.

### Remaining risk

The focused test target passes. The Xcode beta run emits pre-existing project warnings about traditional headermaps and unavailable App Intents metadata registration; neither warning is caused by this change.
