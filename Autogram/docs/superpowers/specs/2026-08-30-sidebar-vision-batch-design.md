# Autogram Sidebar, Vision, and Batch Signing Design

## Status

Approved by the user on 2026-08-30. Implementation follows in a separate plan.

## Scope

This change refines the native macOS UI without changing the legal signing primitives or EZZK protocol. It covers:

1. Sidebar focus and settings placement.
2. Optional recent-document history.
3. AI Vision provider and classification-prompt guidance.
4. PAdES and ASiC-E/XAdES output selection.
5. Reviewed multi-file signing from Autogram and Finder.

## Design decisions

### Sidebar

The primary sidebar remains a `List(selection:)` containing only the three top-level office sections. Signing queue rows remain actionable document rows but are not treated as competing `List` section selections. Queue rows use selection-neutral interaction and suppress the native focus artifact. The current document can retain a subtle neutral highlight, but must not retain a stale blue focus ring after navigation, Settings, or flow reset.

The Settings scene remains the canonical macOS Settings surface. The main sidebar no longer includes a full-width Settings row. A small gear button appears in the bottom sidebar area beside the card status and opens the existing `Settings` scene. The application menu item and `Command-,` remain available.

### Recent documents

A user-selectable setting controls whether recent document links are retained after relaunch. The default is off. When enabled, Autogram stores at most eight local security-scoped bookmarks plus display metadata. It never stores document contents or extracted legal data in the recent-history record.

Recent rows show the file name, status where known, and availability. Missing files are visibly unavailable and can be removed. Opening a recent item revalidates the bookmark, restores access, and routes to the existing signing intake or document flow. The current signing queue remains separate and is not duplicated as a second persistent queue.

### AI Vision

Apple Vision remains the always-on built-in detector. The configured classification prompt applies only to oMLX, Ollama, and Custom API LLM augmentation. It does not apply to Interný režim or Vypnuté. Vypnuté means no LLM augmentation, not no built-in detection.

The AI settings show provider applicability and readiness. The prompt editor is disabled for modes that do not consume it. A blank prompt means the maintained default prompt. The UI offers these prompt presets:

- Právne dokumenty
- Konzervatívna kontrola
- Podpisy a parafy
- Pečiatky a reliéfne prvky
- Vlastný prompt

Selecting or editing a preset updates the existing prompt override storage. The fixed JSON schema suffix and parser validation remain authoritative. The default prompt instructs the model to detect only physically visible elements, report every occurrence separately, use tight boxes, avoid text-based inference, exclude ordinary printed content, and return an empty array when uncertain.

Provider errors and missing API keys are surfaced explicitly. The implementation must not silently present a successful-looking built-in-only result when the selected LLM provider was unavailable.

Prompt changes cannot improve the on-device detector. Built-in accuracy remains a separate future tuning area covering render resolution, masks, OCR exclusions, connected-component thresholds, and geometry heuristics.

### Output format

The existing `SigningOutputFormat` remains the domain enum and request field. Its UI changes from a menu picker to a compact segmented control with concise labels:

- `PAdES`
- `ASiC-E / XAdES`

A dynamic caption explains that PAdES embeds the signature in the PDF, while ASiC-E/XAdES produces a signed container. Timestamp, PDF/A, and other settings retain their existing controls.

### Batch signing

Single-file signing keeps its current direct flow. A multi-file selection, including a Finder selection of more than one PDF, enters a batch review flow.

The batch flow is:

1. Collect and deduplicate input URLs.
2. Run preflight for readability, supported format, existing signatures or conflicts, output collisions, certificate availability, and compatible settings.
3. Show a review screen with files, settings, selected certificate, target outputs, and any blocking issue.
4. Require one explicit `Spustiť dávku` confirmation.
5. Resolve the certificate and request the PIN once for the batch session.
6. Sign files serially while updating per-file state and aggregate progress.
7. On a file error, ask whether to continue or stop. The user selected this interactive policy rather than an unconditional continue or stop policy.
8. Show a final summary with successful, failed, and skipped files, plus actions to reveal outputs, retry failures, or export a batch log.

The current first-error stop behavior is replaced only for the reviewed batch flow. A retry operates on failed files only. Output naming must use collision-safe sibling names and never overwrite an existing signed output without explicit user action.

Finder behavior is intentionally different for one versus many files. One selected PDF keeps the existing quick action. Multiple selected PDFs are enqueued into the reviewed batch flow and are never silently signed.

### Visual signatures in a batch

Manual pixel coordinates from one document must not be reused blindly for other documents. Batch visual signing is opt-in. The batch flow uses a relative placement preset, such as a normalized lower-right position, and preflights every page against the available bounds. A file that cannot accept the selected placement is blocked before signing. If no safe batch placement is selected, visual signing is disabled for the batch.

## Component boundaries

- `RootView` owns sidebar navigation, settings access, queue and recent row presentation.
- `AppSettingsStore` persists the recent-history preference and recent bookmark metadata.
- A focused recent-document helper owns bookmark resolution and bounded history updates.
- `SettingsView` owns provider applicability, prompt presets, and prompt guidance.
- `SigningFlowViews` owns the segmented output control and batch review/progress surfaces.
- `SigningSessionStore` owns batch state transitions, preflight results, per-file outcomes, and cancellation.
- Existing providers remain responsible for one cryptographic signing request unless a later engine-specific optimization is introduced behind a separate interface.
- Existing engine multi-file events may be consumed in a future optimization, but the first implementation preserves serial provider calls for predictable PKCS#11 state.

## Error handling

- Missing recent bookmark: show unavailable, allow removal.
- Duplicate input: show one entry and explain that duplicates were removed.
- Existing output path: allocate a collision-safe sibling name or require an explicit replacement choice.
- Missing certificate or PIN: block batch start and identify the missing prerequisite.
- Provider failure: mark only the affected file failed, then ask the selected continue or stop question.
- Cancellation: preserve completed outputs, mark remaining items cancelled, and show the final partial summary.
- LLM unavailable: show provider failure and retain the built-in findings with an explicit explanation.
- Invalid visual placement: block the affected file before signing rather than placing an unreviewed mark.

## Accessibility and macOS conventions

Controls use native `SettingsLink`, `NavigationSplitView`, `List`, `Picker`, `Button`, and `ProgressView` semantics. The Settings menu item and `Command-,` remain available. All new status rows expose a meaningful accessibility label and value. Focus styling is suppressed only for queue rows where it creates a stale artifact; keyboard navigation and activation remain available.

## Verification requirements

- Test queue selection and reset behavior without stale focus state.
- Test recent-history preference, bounded ordering, bookmark failure, and removal.
- Test prompt applicability for all five AI modes and default-prompt restoration.
- Test concise output-format mapping without changing request semantics.
- Test batch preflight, one-time PIN handoff, per-file outcomes, continue-or-stop decision, cancellation, retry failures, and collision-safe outputs.
- Build with the project Xcode toolchain.
- Smoke test the actual macOS sidebar, Settings, AI Vision, single-file signing, and multi-file review surfaces.
