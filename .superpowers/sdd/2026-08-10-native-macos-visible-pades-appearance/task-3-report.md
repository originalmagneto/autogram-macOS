# Task 3 report

## RED evidence

- `JAVA_HOME="$PWD/target/jdkCache/LIBERICA_jdk25.0.4+9_macos_aarch64-full" ./mvnw -q -Psystem-jdk -Dtest=MachineV2CliAppTest test` failed because `MachineV2CliApp` did not exist.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test -only-testing:AutogramIntegrationTests/MachineSessionProcessTests` failed because `MachineSessionProcess` and `MachineSessionProcessFailure` did not exist.

## GREEN evidence

- The Java focused test passes. It sends `CAPABILITIES` and `INSPECT` on one JSONL input stream and proves one terminal event for each request ID.
- The Swift focused test passes. It proves two requests reuse one helper process, an unexpected exit fails the active request, and the following request launches a new helper process.
- `git diff --check` passes.

## Self-review

- Protocol v1 routing remains unchanged unless `--protocol-version 2` is selected.
- Protocol v2 accepts JSONL until EOF, validates strict envelopes, uses request IDs for event correlation, and emits one `request.completed` or `request.failed` terminal event for every decoded request.
- The v2 schema includes `CAPABILITIES`, `INSPECT`, `CERTIFICATES`, `SIGN`, `TIMESTAMP`, and `VALIDATE`. The session establishes terminal handling for all six; Task 4 owns the signing and validation service binding.
- Swift keeps the v1 one-shot runner. Its v2 session owner serializes token operations, clears request secrets on every return path, and only launches a new process after the current process exits unexpectedly.
