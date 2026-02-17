# Upstream Sync PR Summary (codex/upstream-sync-v2.5.0)

## Scope

This PR continues upstream sync while preserving local macOS UI/UX redesign and release flow.

## Upstream commits integrated (this wave)

- `32720efb` `but allow when xdc xmlns present` (security/workflow hardening path preserved)
- `0b598ec2` `#541 [documentation] troubles during installing`
- `8bd5d7fe` `Add ErrorResponseBuilder singleton` (resolved to local architecture)
- `d73b1454` `update tests` (partial, safe subset only)
- `77b6f36a` `#541 add i18n keys for token drivers` (safe subset with local compatibility fix)
- `374765cc` `#541 add EN l10n`
- `958055b6` `allo baseline b and t values in signature level api wo format` (resolved with local underscore-safe level mapping)
- `3134552c` `fix add underscore`
- `20baf1ee` `rm unwanted file`
- `15b9f208` `add a comment explaining that we ignore transformation for non-XDC documents`
- `0b5172fd` `fix asset loading in tests`
- `d1d05e11` `remove eform attributes from signing parameters unless signing eform`
- `0591b523` `#541 add i18n keys for settings reset dialog - localize in english` (merged with local compact dialog layout)
- `492c7077` `do not allow xslt without xdc`

## Local compatibility commits (this wave)

- `08d199fa` Align transformation tests with XML Datacontainer constraints
- `23a43e5d` Restore `AutogramServer` constructor compatibility for GUI bootstrap
- `cd4611cd` Keep `DriverDetectorSettings` decoupled from missing language mixin
- `bd405615` Align `SignRequestBodyTest` expectations with local validation behavior
- `a3f40405` Add i18n/base-controller compatibility bridge for future `#541` upstream sync

## Key outcomes

- Server-side error mapping now uses centralized `ErrorResponseBuilder`.
- Existing GUI bootstrap remains compatible (no break in server startup).
- Upstream install troubleshooting docs merged into local README variants.
- XML Datacontainer test expectations aligned with stricter signing parameter rules.
- Added upstream-compatible `BaseController`/`HasI18n` scaffolding without changing current macOS UI/UX behavior.
- API now supports baseline `B/T` level resolution path while preserving correct underscore mapping (`PAdES_BASELINE_*`, etc.).
- `SigningParameters` branch for non-XDC remains strict (rejects transformation without XDC) while staying aligned with upstream eForm-attribute cleanup intent.
- Test assets/resource loading changes from upstream are retained where non-breaking, with local stronger tests preserved.
- Settings reset dialog now uses i18n keys while preserving the local macOS compact visual layout.
- Transformation/signing tests were aligned to the stricter XSLT-without-XDC rejection path.

## Explicitly skipped in this wave

- `ddeb9e96` (`update test`) - conflicted with stronger local smoke coverage setup.
- `2259286f` (`add brackets`) - conflicted with stricter local `SigningParameters` logic.
- `004b668f` (`bump debian builder to stable 13`) - would overwrite customized packaging workflow in this fork.

## Validation runbook (executed)

```bash
./mvnw -Psystem-jdk -DskipTests compile
./mvnw -Psystem-jdk -Dtest=SignRequestBodyTest,SignHttpSmokeTest,SigningParametersTests,TransformationTests test
```

Status: passed.

## Reviewer checklist

- [ ] App launches from local build and opens main UI.
- [ ] Signing flow still works for PDF and XML/XDC cases.
- [ ] Server endpoints return localized errors via `ErrorResponseBuilder`.
- [ ] Existing macOS UI/UX changes are unchanged (dialogs, settings layout, dark-mode readability).
- [ ] Release workflow in `.github/workflows/package.yaml` still produces expected macOS assets.

## Merge notes

- Keep merge target as `main` in this fork.
- Prefer squash or small-batch merge strategy to keep upstream-sync history readable.
