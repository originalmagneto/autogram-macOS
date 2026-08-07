# Task 2B core report

## Status

Complete.

## Commit

`761c4e7b feat(native): add certificate discovery core`

## Files

- `native-macos/Autogram/Core/Models/EngineModels.swift`
- `native-macos/Autogram/Core/Models/CertificateDiscovery.swift`
- `native-macos/Autogram/Core/SigningEngine.swift`
- `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`
- `native-macos/Autogram/Infrastructure/Fakes/FakeSigningEngine.swift`
- `native-macos/AutogramIntegrationTests/AutogramCLIEngineTests.swift`
- `native-macos/AutogramTests/CertificateDefaultSelectionTests.swift`

## Tests

Executed with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`:

```sh
xcodebuild test -project Autogram.xcodeproj -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AutogramTests \
  -only-testing:AutogramIntegrationTests
```

Passed: 20 native unit tests and 11 native integration tests, including:

- `certificateDefaultSelectionUsesTheRequiredOrderAndStoresOnlyPublicMetadata()`
- `certificateDiscoveryMapsTheMachinePayload()`

## Self-review

- Java payload mapping requires token key, provider name, serial, friendly certificate metadata, validity dates, certificate key, and holder key.
- The selector checks exact certificate key, then one valid holder-key renewal when the exact certificate is absent or expired, then one eligible certificate, otherwise picker.
- Stored defaults contain opaque keys and friendly public metadata only. Serial, PIN, raw subject, driver ID, and private material are not stored.
- The existing array-returning engine call remains as a compatibility adapter. Task 2C can consume `certificateDiscovery` without changing Task 1 UI behavior.
- `git diff --check` passed before the implementation commit.

## Concerns

- Xcode file-qualified Swift Testing filters selected zero cases, so validation used the two relevant test targets. The two required new tests executed and passed within those target runs.
- Task 2C remains responsible for wiring the discovery contract, selector, and store into `WorkspaceModel`, picker, and Settings UI.
