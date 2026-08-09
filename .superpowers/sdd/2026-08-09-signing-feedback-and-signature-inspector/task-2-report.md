# Task 2 Report: Continuous Workflow Activity

## Status

Implemented Task 2 on top of `80bc2fe60df1e345eb1beb68f034aa4b63fda3b3`.

## Changes

- Added the `SigningActivityPhase` model and observable workspace phase state.
- Set truthful phases at inspection, driver and certificate discovery, signing preparation, machine progress, completion, cancellation, and failure boundaries.
- Streamed signing events directly from `CLIProcessRunner` while retaining session identity checks, terminal failure validation, and output finalization.
- Ignored unknown `file.progress` phase values.
- Added machine protocol events for preparing, signing, validating, and saving at their corresponding signing boundaries.
- Added the headless Java property to the bundled CLI launcher.
- Added focused machine and native engine regression coverage for phase events, including an unknown phase.
- Included the pre-existing Task 2 plan and specification updates in this commit.

## Validation

- Xcode beta native build succeeded: `xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' build`.
- Rebuilt the ARM64 CLI launcher and inspected the supplied signed PDF. It emitted `inspection.completed` and `session.completed`, reported two signatures, and produced no Java crash report.
- `MachineSigningServiceTest` could not execute. The host has no full JDK 25 compiler. The bundled JDK 25 runtime lacks `javac`, and Maven's automatic JDK cache download ended with `Truncated TAR archive`.

## Review

The change does not add synthetic timing or percentages. The inspector uses indeterminate phase feedback and retains determinate batch progress only after completed or failed file counts exist. No UI diagnostic exposes filesystem paths or secrets.

## Remaining Risk

Run `./mvnw -q -Dtest=MachineSigningServiceTest test` again with a complete JDK 25 installation to execute the focused Java regression suite.

## Fix Round 1

### Changes

- Deferred output finalization and `SigningEvent.completed` emission until `session.completed` passes terminal validation.
- Added a native regression for `file.completed` followed by `session.failed`; it proves the stream exposes the terminal failure without a completed-file event.
- Changed the BellSoft JDK cache architecture from `amd64-full` to `aarch64-full`.
- Removed only the corrupt generated JDK cache before the authoritative ARM64 cache download.

### Validation

- Red proof: the focused native integration target ran 13 tests and failed exactly one regression before the fix. The failure showed the premature `.completed("agreement")` event.
- Green proof: the same Xcode beta integration target ran 13 tests with 0 failures after the fix.
- ARM64 proof: the downloaded BellSoft JDK 25 cache contains ARM64 `java` and `javac`; the Surefire report records Java 25.0.4, `os.arch=aarch64`, and 28 `MachineSigningServiceTest` tests with 0 failures, 0 errors, and 0 skipped.

The previous JDK validation risk is resolved.
