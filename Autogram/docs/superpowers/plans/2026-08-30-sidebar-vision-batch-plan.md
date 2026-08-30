# Sidebar, Vision, and Batch Signing Implementation Plan

> **For agentic workers:** Use task-by-task implementation with a review checkpoint after each task. Steps use checkbox syntax for tracking. Do not run formatters, linters, or project-wide tests inside individual tasks. Run focused checks during tasks and the complete suite only in the final verification task.

**Goal:** Refine Autogram's native macOS sidebar and Vision settings, replace the signing format menu, and add a reviewed and observable multi-file signing workflow.

**Architecture:** Keep the existing `AutogramAppModel`, `SettingsView`, `SigningSessionStore`, and provider boundaries. Add a small persistent recent-document store using security-scoped bookmarks, add provider applicability metadata around the existing Vision pipeline, and add batch orchestration in `SigningSessionStore` while preserving serial single-request provider calls. Keep single-file signing behavior unchanged.

**Tech Stack:** Swift 6, SwiftUI, Observation, PDFKit, Foundation security-scoped bookmarks, existing AutogramKit signing and Vision APIs, XCTest.

## Global Constraints

- Target macOS 27.0 and build with `/Applications/Xcode-26.5.app/Contents/Developer`.
- Keep zero Swift package dependencies.
- Use native SwiftUI controls and existing `glassCard` design helpers.
- Keep legal signing primitives and EZZK protocol unchanged.
- Keep English comments and identifiers; use Slovak end-user strings.
- Never store document contents or extracted legal data in recent history.
- Never overwrite an existing signed output without explicit user action.
- Do not silently fall back from a selected LLM provider to built-in-only results.
- Do not reuse manual pixel coordinates for visual signatures across batch documents.
- Do not commit or push unless explicitly requested.

---

## File map

- Modify `Sources/AutogramApp/AutogramApp.swift`: construct and inject the recent-document store into the app model and signing store.
- Modify `Sources/AutogramKit/Support/AppSettings.swift`: add the persisted recent-history preference with Codable backward compatibility.
- Create `Sources/AutogramApp/RecentDocumentStore.swift`: own bounded security-scoped bookmark history, resolution, and removal.
- Modify `Sources/AutogramApp/SigningSessionStore.swift`: record opened URLs, expose batch state, preflight, progress, failure decisions, cancellation, retry, and collision-safe output destinations.
- Modify `Sources/AutogramApp/Views/RootView.swift`: remove the full Settings row, add bottom gear access, make queue rows selection-neutral, and render recent documents.
- Modify `Sources/AutogramApp/Views/SettingsView.swift`: add the recent-history preference and provider-aware Vision prompt presets and guidance.
- Modify `Sources/AutogramKit/VisionAI/LLMVisionProviders.swift`: replace the default prompt with the approved strict prompt while preserving the JSON suffix contract.
- Modify `Sources/AutogramApp/Views/SigningFlowViews.swift`: use segmented PAdES and ASiC-E/XAdES labels and add batch review, progress, and final summary surfaces.
- Modify `Sources/AutogramApp/ServicesProvider.swift` only if the Finder route needs an explicit multi-file review entry point; keep one-file behavior unchanged.
- Add `Tests/AutogramAppTests/RecentDocumentStoreTests.swift`.
- Add `Tests/AutogramAppTests/SigningBatchTests.swift`.
- Extend `Tests/AutogramKitTests/LLMVisionParserTests.swift` for the updated prompt contract.
- Extend or add focused UI-state contract tests where existing app-test patterns permit it.

---

### Task 1: Add recent-document persistence

**Files:**
- Modify: `Sources/AutogramKit/Support/AppSettings.swift:45-118, 120-179`
- Create: `Sources/AutogramApp/RecentDocumentStore.swift`
- Test: `Tests/AutogramAppTests/RecentDocumentStoreTests.swift`

**Interfaces:**
- `AppSettings.retainRecentDocuments: Bool`, default `false`, Codable with missing-key fallback to `false`.
- `RecentDocumentStore.RecentDocument: Identifiable, Codable, Hashable, Sendable` with `id: UUID`, `bookmarkData: Data`, `displayName: String`, and `lastOpenedAt: Date`.
- `@MainActor @Observable final class RecentDocumentStore`:
  - `init(settingsStore: AppSettingsStore, defaults: UserDefaults = .standard)`
  - `var entries: [RecentDocument]`
  - `var isEnabled: Bool` backed by `settingsStore.settings.retainRecentDocuments`
  - `func record(url: URL)`
  - `func resolve(_ entry: RecentDocument) -> URL?`
  - `func remove(id: UUID)`
  - `func clear()`

**Steps:**

- [ ] Write failing tests for a disabled store, enabling persistence, bounded eight-item ordering, duplicate refresh, bookmark resolution, missing bookmark removal, and clear.
- [ ] Run only `swift test --filter RecentDocumentStoreTests` and confirm the new behavior is not implemented.
- [ ] Add `retainRecentDocuments` to `AppSettings`, `CodingKeys`, initializer, decoder fallback, and encoder.
- [ ] Implement `RecentDocumentStore` with a dedicated UserDefaults key `sk.autogram.recentDocuments.v1`; encode only the bounded entry array.
- [ ] In `record(url:)`, create a security-scoped bookmark, remove an existing matching entry, insert the new entry at index zero, and truncate to eight entries. If disabled or bookmark creation fails, leave the store unchanged.
- [ ] In `resolve(_:)`, resolve the bookmark with `.withSecurityScope`, start access, and return the URL. Remove stale or invalid entries only through an explicit caller action or a dedicated cleanup method, not while iterating a SwiftUI view.
- [ ] Re-run `swift test --filter RecentDocumentStoreTests` and confirm all cases pass.

---

### Task 2: Wire recent history and fix sidebar focus/settings placement

**Files:**
- Modify: `Sources/AutogramApp/AutogramApp.swift:6-20`
- Modify: `Sources/AutogramApp/SigningSessionStore.swift:47-123`
- Modify: `Sources/AutogramApp/Views/RootView.swift:22-179, 232-256`
- Test: `Tests/AutogramAppTests/RecentDocumentStoreTests.swift` for integration-facing calls where possible.

**Interfaces:**
- `AutogramAppModel.recentDocumentStore: RecentDocumentStore`.
- `SigningSessionStore.init(signingProvider:settingsStore:recentDocumentStore:)`.
- Existing `SigningSessionStore.addDocuments(at:selectLast:)` records each accepted URL through the injected store.

**Steps:**

- [ ] Add `recentDocumentStore` to `AutogramAppModel`, construct it after `AppSettingsStore`, and pass it to `SigningSessionStore`.
- [ ] Update all `SigningSessionStore` construction sites to pass the store.
- [ ] In `addDocuments(at:selectLast:)`, record only newly accepted documents after URL deduplication.
- [ ] Remove the `Section("Predvoľby")` SettingsLink row from the main List.
- [ ] Add an icon-only `SettingsLink` with `gearshape` to `sidebarBottomBar`, with an accessibility label `Nastavenia` and help text. Preserve the Settings scene and `Command-,` menu item.
- [ ] Make queue rows selection-neutral: retain the explicit queue action and `selectedQueueID`, add the available focus suppression modifier, and replace the accent `listRowBackground` with a subtle neutral selected background that cannot render the stale blue focus artifact.
- [ ] Keep keyboard activation and accessibility traits for queue rows.
- [ ] Add a `Nedávne dokumenty` section between the office navigation and the current queue when `retainRecentDocuments` is enabled and entries exist. Resolve availability for display, show file name and unavailable state, and route an available row to `selection = .signing` plus `signingStore.loadDocument(at:)`.
- [ ] Add context actions to remove a recent entry and clear all recent entries. Do not duplicate a recent row in the queue section.
- [ ] Update `removeQueueItem` and flow reset handling so a removed or reset item cannot leave a stale selected queue highlight.
- [ ] Run focused app tests and manually inspect RootView compilation before moving on.

---

### Task 3: Add provider-aware AI Vision guidance and presets

**Files:**
- Modify: `Sources/AutogramApp/Views/SettingsView.swift:92-285`
- Modify: `Sources/AutogramKit/Support/AppSettings.swift` only if a provider applicability helper is placed in the domain model.
- Modify: `Sources/AutogramKit/VisionAI/LLMVisionProviders.swift` default prompt definition.
- Modify: `Sources/AutogramApp/ZakoSessionStore.swift:145-174, 210-230` for explicit readiness/error state.
- Extend: `Tests/AutogramKitTests/LLMVisionParserTests.swift`.

**Interfaces:**
- Add a private SettingsView enum `AIPromptPreset` with the five approved cases and a `promptText` property.
- Add an explicit store-facing readiness result or warning property for selected LLM configuration. It must distinguish built-in-only modes from an unavailable selected LLM provider.
- Preserve `LLMVisionParser.effectivePrompt(_:)` and the existing JSON parser contract.

**Steps:**

- [ ] Extend parser tests to require the approved default prompt instructions: physical visibility, no text inference, tight boxes, every occurrence, omit when uncertain, and JSON-only output.
- [ ] Run `swift test --filter LLMVisionParserTests` and confirm the new prompt assertions fail before the prompt change.
- [ ] Replace only the maintained default prompt text in `LLMVisionProviders.swift`; preserve schema suffix generation and alias parsing.
- [ ] Add the five preset definitions in SettingsView. Selecting a preset writes its full prompt into the existing `aiPrompt` override; editing the editor selects `Vlastný prompt` without changing the storage schema.
- [ ] Add applicability copy directly below the provider list: the built-in detector always runs; the prompt applies only to oMLX, Ollama, and Custom API.
- [ ] Disable the prompt editor and preset controls for `builtInOnDevice` and `disabled`, while keeping reset/default guidance visible.
- [ ] Add readiness rows for oMLX URL/model, Ollama URL/model, and Custom API Keychain key. Surface missing or unavailable LLM configuration explicitly during analysis instead of silently treating it as success.
- [ ] Preserve built-in findings when LLM augmentation fails, but expose the provider failure in the analysis status and UI.
- [ ] Add tests for mode applicability metadata and default prompt restoration if the helper is public or internal-testable.
- [ ] Re-run `swift test --filter LLMVisionParserTests` and focused AI tests.

---

### Task 4: Replace output format menu with a segmented control

**Files:**
- Modify: `Sources/AutogramApp/Views/SigningFlowViews.swift:481-527`
- Test: `Tests/AutogramAppTests/SigningBatchTests.swift` or an existing signing contract test for enum-to-request mapping.

**Interfaces:**
- Keep `SigningOutputFormat` and `SigningRequest` unchanged.
- Add a local presentation label mapping:
  - `.embeddedPAdES -> "PAdES"`
  - `.attachedASIC -> "ASiC-E / XAdES"`

**Steps:**

- [ ] Add a focused test proving each presentation choice maps to the same existing `SigningOutputFormat` value.
- [ ] Replace the menu Picker with `Picker(selection: $store.outputFormat) { ... }.pickerStyle(.segmented)` using the concise labels.
- [ ] Add a dynamic caption explaining embedded PAdES versus ASiC-E/XAdES without changing signing behavior.
- [ ] Keep timestamp, TSA, PDF/A, and visual-signature controls unchanged.
- [ ] Run the focused signing contract test and compile the affected app target.

---

### Task 5: Introduce batch state and preflight orchestration

**Files:**
- Modify: `Sources/AutogramApp/SigningSessionStore.swift:8-51, 108-174, 245-427, 452-465`
- Create or modify: `Sources/AutogramApp/BatchSigningModels.swift` only if the state types cannot remain focused in SigningSessionStore.
- Test: `Tests/AutogramAppTests/SigningBatchTests.swift`

**Interfaces:**
- `SigningSessionStore.BatchPhase`: `.idle`, `.preflighting`, `.ready`, `.signing`, `.completed`, `.cancelled`.
- `SigningSessionStore.BatchFailureDecision`: `.continueBatch`, `.stopBatch`.
- `SigningSessionStore.BatchItemState`: `.pending`, `.signing`, `.signed`, `.failed`, `.skipped`, `.cancelled`.
- `SigningSessionStore.BatchItem`: `id: UUID`, `displayName: String`, `url: URL`, `state`, `errorMessage`, `outputURL`.
- `SigningSessionStore.batchPhase`, `batchItems`, `batchCompletedCount`, `batchFailedCount`, `batchCurrentIndex`, `batchErrorDecisionRequest`.
- `func prepareBatch(ids: [UUID]) async`.
- `func startBatch() async`.
- `func decideBatchFailure(_ decision: BatchFailureDecision)`.
- `func cancelBatch()`.
- `func retryFailedBatchItems() async`.

**Steps:**

- [ ] Write failing tests for URL deduplication, empty and invalid inputs, preflight blocking on unreadable PDFs, identity/PIN prerequisites, per-file state updates, successful serial processing, failure decision continuation, stop decision, cancellation preservation, and retrying failed items only.
- [ ] Run only `swift test --filter SigningBatchTests` and confirm the new batch contract is not implemented.
- [ ] Add batch state types with no second signing provider abstraction. Each `BatchItem` references the existing queue item ID and source URL.
- [ ] Implement `prepareBatch(ids:)` to snapshot ready and failed queue items, set `.preflighting`, validate every source URL and PDF, validate identity/PIN requirements, validate visual placement policy, and set `.ready` or attach blocking errors without signing.
- [ ] Add a batch settings snapshot containing output format, timestamp/TSA, PDF/A, selected identity, and visual-signature mode so the review and execution cannot drift if the user changes controls mid-batch.
- [ ] Implement `startBatch()` as a serial loop over the prepared snapshot. Reuse the existing `sign()` operation only through an internal per-item signing method that accepts the snapshot and item ID, rather than mutating the selected document UI as the only source of truth.
- [ ] Resolve certificate and validate PIN once before the first item when the provider requires it. Do not persist the PIN in recent history or batch logs.
- [ ] After each item, update queue status and batch item state. On failure, set `batchErrorDecisionRequest` and suspend until `decideBatchFailure` resumes the loop.
- [ ] Implement `cancelBatch()` to stop future work, preserve completed outputs, mark remaining items cancelled, invalidate pending asynchronous work, and set `.cancelled`.
- [ ] Implement retry for failed items only, after a new preflight and explicit confirmation.
- [ ] Preserve `signAllUnsigned()` for the single-file-compatible queue action only until the new reviewed batch entry point is wired; then route multi-file actions through `prepareBatch(ids:)`.
- [ ] Run `swift test --filter SigningBatchTests` and fix only failures related to this contract.

---

### Task 6: Make batch outputs and visual placement safe

**Files:**
- Modify: `Sources/AutogramApp/SigningSessionStore.swift:366-395, 491-501`
- Modify: `Sources/AutogramKit/EngineBridge/FS/OutputService.swift:1-68` only if the existing collision-safe implementation is exposed for app use.
- Test: `Tests/AutogramAppTests/SigningBatchTests.swift`

**Interfaces:**
- Add a collision-safe output resolver returning a unique sibling URL using `_podpisane`, `_podpisane (2)`, and so on, or expose equivalent existing `OutputService` behavior through a public AutogramKit API.
- Add a normalized visual-placement validation function for every target PDF page.

**Steps:**

- [ ] Write tests proving an existing output is never replaced, the second output receives a deterministic suffix, and an invalid visual placement blocks only the affected batch item before signing.
- [ ] Run the focused output tests and confirm they fail against the current direct `.atomic` writes.
- [ ] Replace direct final-path selection in the batch path with collision-safe sibling resolution and a non-overwriting final write. Keep single-file naming behavior compatible unless the existing path already exists.
- [ ] For batch visual signing, require an explicit relative placement preset. Validate normalized coordinates against each target page's bounds and mark incompatible items blocked before signing.
- [ ] Never copy `visualPlacement` pixel coordinates from the first document into subsequent documents.
- [ ] Run focused output and visual-placement tests.

---

### Task 7: Build batch review, progress, and final summary UI

**Files:**
- Modify: `Sources/AutogramApp/Views/SigningFlowViews.swift:568-588` and the signing flow container around the existing prepare/intake views.
- Modify: `Sources/AutogramApp/Views/RootView.swift:96-108` for the queue batch action.
- Modify: `Sources/AutogramApp/ServicesProvider.swift` only if route metadata must distinguish one versus many URLs.

**Interfaces:**
- UI binds to `SigningSessionStore.batchPhase`, `batchItems`, `batchErrorDecisionRequest`, and batch commands from Task 5.
- Existing single-file `signButton` remains unchanged for one selected document.

**Steps:**

- [ ] Add a batch review view showing file name, input availability, preflight state, selected identity, output format, TSA, PDF/A, visual-signature policy, and blocking issues.
- [ ] Add `Spustiť dávku` only when the batch is `.ready` and no blocking item remains.
- [ ] Add aggregate progress with completed, failed, current file, and cancel action while `.signing`.
- [ ] Add a decision dialog when `batchErrorDecisionRequest` is set with `Pokračovať na ďalšie` and `Zastaviť dávku`.
- [ ] Add a final summary for `.completed` and `.cancelled` with successful, failed, skipped, and cancelled counts, plus reveal, retry, and export-log actions where the existing output APIs support them.
- [ ] Change RootView's `Podpísať všetky` action to prepare the batch and navigate to the review instead of signing immediately.
- [ ] Change Finder routing so one PDF retains its existing direct behavior and multiple PDFs enter the same reviewed batch flow.
- [ ] Ensure every new control has Slovak accessibility labels and meaningful values.
- [ ] Run a focused app-target compile and inspect the review/progress view in the running app.

---

### Task 8: Final verification and documentation alignment

**Files:**
- Modify: `README.md` current test-count and feature summary lines if counts or version changed.
- Modify: `docs/superpowers/specs/2026-08-30-sidebar-vision-batch-design.md` only if implementation decisions materially differ from the approved design.

**Steps:**

- [ ] Run focused tests for recent documents, Vision prompt parsing, signing format mapping, and batch behavior.
- [ ] Run `DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test` and require zero failures.
- [ ] Run `DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh`.
- [ ] Smoke test the installed macOS app: sidebar navigation after focus changes, gear Settings access, optional recent documents, AI provider applicability, prompt preset switching, segmented signing format, one-file signing, multi-file review, failure decision, cancellation, and final summary.
- [ ] Verify Finder one-file and multi-file paths separately without signing real documents unless explicitly authorized.
- [ ] Update README only with observed test totals and current behavior. Do not claim EZZK production interoperability until external callback registration is confirmed.
