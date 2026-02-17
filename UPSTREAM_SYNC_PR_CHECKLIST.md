# Upstream Sync PR Summary (codex/upstream-sync-v2.5.0)

## Scope

This PR continues upstream sync while preserving local macOS UI/UX redesign and release flow.

## Upstream commits integrated (this wave)

- `32720efb` `but allow when xdc xmlns present` (security/workflow hardening path preserved)
- `0b598ec2` `#541 [documentation] troubles during installing`
- `8bd5d7fe` `Add ErrorResponseBuilder singleton` (resolved to local architecture)

## Local compatibility commits (this wave)

- `08d199fa` Align transformation tests with XML Datacontainer constraints
- `23a43e5d` Restore `AutogramServer` constructor compatibility for GUI bootstrap

## Key outcomes

- Server-side error mapping now uses centralized `ErrorResponseBuilder`.
- Existing GUI bootstrap remains compatible (no break in server startup).
- Upstream install troubleshooting docs merged into local README variants.
- XML Datacontainer test expectations aligned with stricter signing parameter rules.

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
