# Upstream Sync PR Summary (codex/upstream-sync-2026-08)

## Goal
Sync this fork with `upstream/main` through v2.7.5 while preserving local macOS UI/UX redesign, release workflow customizations, and the headless CLI signing Quick Action.

## Branch State
- Branch: `codex/upstream-sync-2026-08`
- Upstream head: `d8e63ac5` (`upstream/main`, v2.7.5)
- Fork main before sync: `416eac46`
- Upstream commits missing from the fork main before sync: `47`
- Fork-only commits retained: `247`
- Upstream merge commit included: `606130a1` (`chore: sync upstream main through v2.7.5`)
- Headless CLI feature commit on top: `93e734f0` (`feat: add headless macOS PDF signing automation`)

## What Was Integrated
- Upstream JDK 25 and dependency updates, including DSS 6.4 and PDFBox 3.0.8.
- Upstream qualified TSA default and trusted-list refresh behavior.
- Upstream XML security hardening and PKCS#11 invocation changes.
- Upstream macOS arm64 and Intel packaging workflow split.
- Upstream eForm resource loading, validation, and related regression tests.
- Headless CLI signing with certificate listing, certificate selection, PIN from stdin, PAdES baseline T, and Finder multi-file automation.

## Local Preservation Rules Applied During Merge
- Kept local macOS UI/UX behavior and layout decisions (dark mode polish, modal behavior, panel sizing, inline overlays).
- Kept local release/packaging intent for this fork.
- Added compatibility shims where upstream API signatures diverged from local architecture.

## Post-Merge Stabilization Commits
- The merge was stabilized with compatibility fixes for the macOS fork's JavaFX dependencies, i18n controller API, password focus flow, and XML security tests.

## Validation Executed
```bash
JAVA_HOME=<JDK-25-with-JavaFX> ./mvnw -Psystem-jdk test
JAVA_HOME=<JDK-25-with-JavaFX> ./mvnw -DskipTests package
```

Status: all 342 tests passed with JDK 25. Packaging requires JavaFX modules in the selected jlink runtime.

## Reviewer Checklist
- [x] Build and test suite pass locally with JDK 25 and JavaFX dependencies.
- [x] Headless CLI regression tests pass, including PAdES baseline T selection.
- [ ] Main signing workflows (PDF + XML/XDC) still work in GUI.
- [x] Local macOS UI/UX polish remains intact in the synchronized source tree.
- [ ] Release workflow produces expected macOS artifacts with a JavaFX-capable JDK 25.

## Merge Recommendation
- Open PR from `codex/upstream-sync-2026-08` to `main`.
- Merge as a normal merge commit (not squash) to retain explicit upstream-sync traceability.
