# Upstream Sync PR Summary (codex/upstream-sync-v2.5.0)

## Goal
Sync this fork with `upstream/main` while preserving local macOS UI/UX redesign and release workflow customizations.

## Branch State
- Branch: `codex/upstream-sync-v2.5.0`
- Upstream delta check: `git log --cherry-pick --right-only --no-merges HEAD...upstream/main | wc -l` = `0`
- Upstream merge commit included: `164cf9d2` (`merge upstream/main while preserving macOS UI branch customizations`)

## What Was Integrated
- Upstream security/workflow hardening around XSLT/XDC validation.
- Upstream i18n key wave (`#541`) with compatibility bridges for local GUI architecture.
- Upstream server error-response builder path and related DTO/error handling adjustments.
- Upstream CI/build updates, including Debian builder image move and workflow deltas.
- Upstream tests/assets updates where compatible with local branch behavior.

## Local Preservation Rules Applied During Merge
- Kept local macOS UI/UX behavior and layout decisions (dark mode polish, modal behavior, panel sizing, inline overlays).
- Kept local release/packaging intent for this fork.
- Added compatibility shims where upstream API signatures diverged from local architecture.

## Post-Merge Stabilization Commits
- `a0a921fe` resolve upstream i18n/api contract conflicts after sync wave
- `9175be93` stabilize `SignRequestBodyTest` expectations after upstream merge

## Validation Executed
```bash
./mvnw -Psystem-jdk -DskipTests compile
./mvnw -Psystem-jdk -Dtest=SigningJobTests,SigningParametersTests,TransformationTests,SignRequestBodyTest test
```

Status: passed.

## Reviewer Checklist
- [ ] Build compiles locally with `-Psystem-jdk`.
- [ ] Targeted regression suite passes (SigningJob/SigningParameters/Transformation/SignRequestBody).
- [ ] Main signing workflows (PDF + XML/XDC) still work in GUI.
- [ ] Local macOS UI/UX polish remains intact (settings layout, overlays, PIN focus flow, dark-mode readability).
- [ ] Release workflow still produces expected macOS artifacts for this fork.

## Merge Recommendation
- Open PR from `codex/upstream-sync-v2.5.0` to `main`.
- Merge as a normal merge commit (not squash) to retain explicit upstream-sync traceability.
