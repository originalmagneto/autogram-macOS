# Security elements implementation plan

**Goal:** Implement the security-element catalogue, original-document observations, explicit empty review and reliable training export approved in the conversation on 2026-09-15.

**Architecture:** Keep persisted legacy kind identifiers. Add descriptive kinds and a visual-kind mapping; human certification never becomes an image label. Distinguish scan regions from physical-original observations. Keep the existing form pack unverified until whole-form conformance is established.

**Constraints:** Swift 6 / macOS 27; Slovak UI, English code and documentation; no em dashes; preserve unrelated workspace edits; sync root AGENTS.md and CLAUDE.md. No claim of trained-model accuracy without real held-out scans.

## Tasks

- [x] Verify official security-element XML fields and retain artifact provenance.
- [x] Add catalogue and backward-compatible observation data; test decoding and semantic export.
- [x] Add manual-original UI and explicit no-elements confirmation; test review invalidation and gates.
- [x] Extend visual classifier/parser labels for cord, tape and seal; preserve human assessment boundary.
- [x] Record complete page annotations separately from crop learning, exclude physical-only observations, and export only reviewed pages with document-level dataset splits.
- [x] Run focused tests, whole suite and app build; review diff; integrate only this task's changes into the shared workspace.

## Validation

Use failing regression tests for false stamp specificity, physical-only learning, absent-versus-unreviewed state, incomplete dataset pages and legacy decode. Run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test` from Autogram. Verify UI compilation and manually inspect the changed review flow if a runnable local app is available.

## Implementation status

- Implemented the 16-kind catalogue, physical-original observations, explicit no-elements review, extended visual proposals and complete-page training export.
- Corrected record 1.0 security details using official artifacts retained with provenance. The full form pack remains unverified.
- Review fixes cover neutral stamp descriptions, required human detail preservation, reversible nonempty-page overrides and exclusion of both pages referenced by physical observations. Independent follow-up review found no remaining actionable issue in these fixes.
- Integrated with the existing UI redesign (c00e9d35), preserving its source and documentation changes. Root AGENTS.md and CLAUDE.md remain synchronized; README and training documentation describe the resulting behavior.

## Verification and remaining limits

- Shared-workspace suite: 405 tests executed, 400 passed, 5 skipped, 0 failures. Skipped tests require a live signing engine or a real scan fixture.
- Native app bundle build and code-signature verification succeeded with the existing signing engine.
- GUI smoke check reached the running app; further interaction stopped on concurrent user activity. The changed ZaKo screen has not been visually verified.
- Training export does not train a model. Accuracy of the new classes remains to be measured on real held-out scans.
