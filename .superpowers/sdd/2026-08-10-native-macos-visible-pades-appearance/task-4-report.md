# Task 4 report

## RED evidence

- `JAVA_HOME="$PWD/target/jdkCache/LIBERICA_jdk25.0.4+9_macos_aarch64-full" ./mvnw -q -Psystem-jdk -Dtest=MachineSigningServiceTest test` failed because `VisibleSignatureAppearance` did not exist.

## GREEN evidence

- The focused Java test passes. It proves that the DSS PAdES parameters receive a snapshotted PNG, page 2, rectangle 72/540/216/108, `NONE` rotation, `STRETCH` scaling, and the supplied signing instant. It also proves that trusted-list unavailability and unavailable timestamp qualification leave no target output, with `TRUSTED_LIST_UNAVAILABLE` and `TIMESTAMP_QUALIFICATION_FAILED` respectively.
- The focused Swift test passes. It compiles the typed `VisibleSignatureRequest` payload path and verifies protocol v2 fields plus deletion of the rendered PNG.
- `git diff --check` passes.

## Self-review

- Visible appearance is accepted only by v2 for a regular, normalized, non-symlink PNG path and a PDF source with `PAdES_BASELINE_T`.
- PNG bytes are copied to memory before session or token access. DSS receives only the snapshot and `VisualSignatureRotation.NONE`.
- Trusted-list initialization occurs before signing. Publication requires one new intact PAdES Baseline T signature, preservation of previous signature IDs, an intact timestamp, and authoritative qualified timestamp status.
- The Swift visible path uses one supplied signing instant for the v2 request and removes rendered PNG files on success, failure, or cancellation. The v1 one-shot path is unchanged for requests without visible appearance.
- The focused suites emit pre-existing toolchain warnings about deprecated APIs and headermaps. They contain no test failures.

## Fix round 1

- Production protocol v2 signing now constructs `MachineInspectionService` with trusted DSS reports, so authoritative timestamp qualification can pass the publication gate.
- Rendered PNG cleanup is registered at the start of the Swift signing task, before timestamp configuration and helper-gate waiting.
- Trusted-list initialization and qualified timestamp publication checks now apply only when a file carries a visible appearance. Protocol v1 signing retains its previous behavior.
- Visible publication independently requires a PDF output whose new signature format is exactly `PAdES_BASELINE_T`. Non-visible validation retains the existing Baseline T formats.
- `progress.md` restores Task 4 to pending and contains no placeholder commit.
- GREEN: focused `MachineSigningServiceTest` and `AutogramCLIEngineTests` passed. `git diff --check` passed.
