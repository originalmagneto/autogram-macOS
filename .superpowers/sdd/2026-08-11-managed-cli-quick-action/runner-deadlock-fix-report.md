# Runner Deadlock Fix Report

## Scope

- The Quick Action runner now drains helper standard output and standard error concurrently.
- It line-buffers machine output, detects `session.completed` and `session.failed` as soon as each complete event arrives, and terminates the helper after the first terminal event.
- The runner preserves collected output. A completed session exits successfully, while a failed session exits nonzero.
- PIN handling remains standard-input-only. The request construction and helper arguments are unchanged.

## Regression proof

1. The focused runner test was extended before the implementation. With the original runner it failed with `Quick Action runner did not return after terminal helper event.` because the helper filled standard error before writing its terminal event and then stayed alive.
2. `scripts/macos-automation/test_autogram-cli-sign.sh` passes after the implementation. It verifies that a 1 MiB helper standard error stream is retained, a completed terminal event returns successfully while the helper is still paused, and a failed terminal event returns nonzero.
3. Shell syntax checks passed for the focused test, native build script, and Quick Action launcher.
4. Both Quick Action property lists passed `plutil -lint`.
5. The ARM64 runner was compiled with the existing packaging invocation and replaced in the existing native bundle. `file` confirms the bundled runner is an ARM64 Mach-O executable.
6. `git diff --check` passed. The changed source and test have no personal absolute paths or secret-like values.

## Packaging note

The full `scripts/native-macos/build-native-app.sh` packager could not run because the available Java runtime is version 24 and the script requires JDK 25. It stopped before changing package resources. The focused runner build used the same ARM64 Swift compilation step and updated only `AutogramQuickActionRunner-arm64` in the existing bundle.

## Remaining risk

- The full JDK 25 native app build, DMG packaging, and release verification remain to be rerun in an environment with the required JDK.
- No real PKCS11 token or middleware session was used. The regression coverage uses an ARM64 machine-protocol helper fixture.

## Bounded terminal-event shutdown follow-up

- After a terminal JSON Lines event, the runner calls the local Process.terminate() operation first. That operation sends SIGTERM to the direct helper child.
- The 100 ms grace is a single local signal-delivery observation period. It is derived from SIGTERM defaulting to immediate process termination and exists only to let that local termination operation complete before escalation. It is not a signing, request, token, or network timeout.
- If the direct child has not exited after that grace, the runner sends SIGKILL. The Process.terminationHandler then closes the runner's read ends. This releases the drain group even if descendants inherited and retain the pipe write ends, so the runner does not wait indefinitely after a terminal event.
- The focused regression first failed against the previous runner with Quick Action runner did not return after terminal helper event. It now uses a helper that emits session.completed, ignores SIGTERM, and remains paused. The runner returns successfully and the recorded helper PID is no longer alive. The fixture now writes a real newline after its numeric PID, and a separate paused helper proves stop_helper can terminate the leftover through that PID file.
- Validation run: bash scripts/macos-automation/test_autogram-cli-sign.sh, bash -n scripts/macos-automation/test_autogram-cli-sign.sh, and git diff --check.
