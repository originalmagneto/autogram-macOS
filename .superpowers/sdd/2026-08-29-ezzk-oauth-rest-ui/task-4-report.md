# Task 4 report: app-layer EZZK session wiring

## Files

- `Autogram/Sources/AutogramApp/EZZK/EZZKSessionController.swift`
  - Added the `@MainActor` observable session state machine with signed-out, authenticating, authenticated, expired, and failed states.
  - Added login, logout, refresh, connectivity testing, and explicit evidence-number request actions.
  - Native login remains blocked until the OAuth configuration has a confirmed native callback.
  - Keychain restoration performs a read-only `/ec` check before publishing authenticated state.
  - Access and refresh tokens stay in the injected token store and are never exposed through UI state.
  - Sandbox is the only selectable environment. Production remains closed behind a constant false authority gate.
  - The authenticated REST client is held privately behind a capability adapter. Legacy envelope submission remains fail-closed until the signed ASiC submission boundary is available.
  - Slovak, secret-free error messages are used for UI state.
- `Autogram/Sources/AutogramApp/AppSettingsStore.swift`
  - Owns one session controller and exposes its service capability.
  - Removed username/password service selection and service rebuilding from settings changes.
  - Kept the legacy password value and persistence method only for migration compatibility; it cannot authenticate EZZK.
  - Local evidence storage remains created once and is unaffected by logout.
- `Autogram/Sources/AutogramApp/AutogramApp.swift`
  - Keeps the controller in `AutogramAppModel` and injects the same instance into the main window and Settings scene environment.

No new app-target test target exists in this package, so controller state and local-store lifecycle cannot be exercised from the existing AutogramKit-only test target without changing package boundaries.

## Verification

- `DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --build-path /tmp/ezzk-task4-final-tests --filter EZZKHTTPClientTests`
  - PASS, 16 tests, 0 failures.
- `DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift build --product Autogram --build-path /tmp/ezzk-task4-guard-build`
  - PASS, Autogram product built successfully.

Only focused tests and app builds were run. Existing project warnings remain outside this task.

## Concerns

- Native EZZK login remains intentionally unavailable until the operator confirms and registers a native redirect URI or callback scheme for `login-app`.
- Production selection remains disabled until the authority register and release gate are populated.
- The existing Settings EZZK tab still presents legacy credential fields until the dedicated Settings UI task replaces them. Those values no longer select or authenticate an EZZK service.
- The authenticated adapter intentionally rejects legacy `ConversionRecordEnvelope` submission because the validated signed ASiC upload and authoritative receipt boundary are not yet wired.
