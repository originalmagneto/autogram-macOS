# AGENTS.md - Autogram macOS UI

## Project Overview
Autogram is a 100% native macOS SwiftUI application for Qualified Electronic Signatures (KEP / eIDAS) and Guaranteed Conversion of legal documents (Zarucena konverzia according to Slovak Law No. 305/2013 Z. z. and Decree No. 70/2021 Z. z.).

## Architecture & Tech Stack
- Swift 6.0+ / Xcode 27.0 toolchain (`/Applications/Xcode-beta.app`)
- Native macOS SwiftUI (`NavigationSplitView`, `.regularMaterial`, `.ultraThinMaterial`, Liquid Glass design)
- Core Data / SQLite for Evidence and Conversion registers (CEZZK integration)
- PKCS#11 bridge for Slovak eID cards, SAK advocate cards, and Disig smartcards
- Signing with mobile (`Signing/AVM/`): `AVMClient` talks to the Autogram v mobile relay (`https://autogram.slovensko.digital/api/v1`, 32-byte key in `X-Encryption-Key`, `POST /documents`, QR link `/qr-code?guid&key`, polling `GET /documents/{guid}` with `If-Modified-Since`); `AVMSigningSession` drives upload, polling, timeout and cancel; `MobileSigningCoordinator` and `MobileSigningSheet` present the QR code; `SigningSessionStore.sign(viaMobile:)` and `ZakoSessionStore.authorizeAndSign(viaMobile:)` swap only the final signing step; ZaKo refuses a non-mandate signature (`AVMResultMapper.isMandate`). The AVM app only opens links for the public host, so `AppSettings.avmBaseURL` is test-only. Design and plan: `docs/superpowers/specs/2026-09-11-avm-mobile-signing-design.md`
- Browser signing (`WebBridge/`, `Sources/AutogramWebExtensionHandler/`, `WebExtension/`): a Safari web extension talks to the app by native messaging only, with no HTTP port. launchd owns the Mach service name, so a small on-demand agent (`autogram-webbridge-agent`, registered by `scripts/install-webbridge-agent.sh`) acts as a rendezvous: the app registers an anonymous `NSXPCListener` endpoint with it and the sandboxed extension asks for that endpoint, then talks to the app directly. `scripts/safari-spike.sh` verifies everything that does not need Safari; enabling an unsigned extension stays manual. Machine protocol sign requests carry optional eForm and XDC attributes so `XDCBuilder` and the UPVS, ORSR and FS resolvers in the bundled engine are reachable from Swift. Design and plan: `docs/superpowers/specs/2026-09-11-safari-extension-design.md`
- PDFKit, CoreGraphics, Apple Vision and FoundationModels for document analysis and security element detection
  - `LayeredDetectionProvider` (VisionAI/): one render plus fast and accurate OCR per page (`AccurateTextExclusions`); candidates from `BuiltInVisionProvider` (frozen, fed the shared exclusions), `DetectContoursRequest`, objectness saliency; merged by `CandidateMerger`, pruned by `CandidateQualityFilter` (text coverage, ruled boxes, ink inside OCR); classified by `TwoStageClassifier` (`FeaturePrintClassifier` kNN over `ExampleBank`, then on-device `FoundationModelClassifier` with a fresh session per crop, no heuristic hint, decisive negatives, 12 crops per page); `DetectionRunStats` carries model calls, unsure calls, filtered candidates and model seconds
  - `RealScanSmokeTests` runs the whole pipeline on a local scan named by `AUTOGRAM_DIAG_PDF` (skips without it); time it in release with `caffeinate -dimsu swift test -c release -Xswiftc -enable-testing`
  - `ExampleBank` at `~/Library/Application Support/Autogram/VisionBank` records confirm/reject decisions; `CreateMLExporter` writes Create ML object-detector datasets; `vision-eval` target scores precision/recall
  - `SegmentationSnapper` wraps `GenerateIterativeSegmentationRequest` for click-to-snap boxes in `AnalysisCanvasView`
  - Local LLM vision providers: oMLX (Apple Silicon MLX, `localhost:8000/v1`) and Ollama (`localhost:11434`), plus OpenAI-compatible cloud APIs with keys in Keychain
  - AI provider selection in Settings uses provider rows (`SettingsView.aiProviderRow`); config panel renders under the chosen mode; `LearningDatasetCard` holds the learning toggles and dataset export. Settings live in a regular `Window` scene (`SettingsWindow.id`, opened by `OpenSettingsButton`) because the `Settings` scene cannot be resized
  - `AnalysisCanvasView` review step: canvas holds only the document; the inspector has three cards (`pageReviewCard`, `findingsCard`, `addElementCard`); `ElementRow` is one line until selected; `markPageReviewedAndAdvance` and `confirmAllPendingElements(onPage:)` drive multi-page review; the detection provider menu sits in the `StickyActionBar`

## Design System & UI/UX Structure
- **DesignSystem.swift**: Contains `.liquidGlass()` modifiers, `StickyActionBar` containers, `SmartcardHUDStatus` reader badges, `EIDASBadge` verification pills, and `FlowStepBar` subheader stepper navigation.
- **App Shell (RootView.swift)**: Minimalist sidebar with primary sections (Podpisovanie, Zarucena konverzia, Register konverzií), bottom card reader status indicator (`SmartcardHUDStatus`), and signing queue management.
- **Signing Suite (SigningFlowViews.swift)**:
  - `SigningIntakeView`: Clean dropzone with `DropzoneArtwork`, support chips, and `⌘O` shortcut.
  - `SigningPrepareView`: PDF preview and sticky action bar with `Podpisat KEP` (`⌘⏎`) and `VisibleAppearanceInspector`.
  - `SigningDoneView`: Result summary with `EIDASBadge` and Quick Look / Finder actions.
- **ZaKo Advocate Studio (ZakoFlowViews.swift, AnalysisCanvasView.swift, AttestationFormView.swift, AuthorizeDoneViews.swift)**:
  - `AnalysisCanvasView`: Floating segmented markup toolbar (Select, Stamp, Signature, Seal, Initial) and left page thumbnail strip.
  - `AttestationFormView`: Deduplicated advocate profile fields, live clause preview, and template menu.
  - `AuthorizeView`: Mandate certificate verification, PIN handling, and sticky authorization action bar.
  - `DoneView`: Direct access to converted PDF/A and clause files.
- **Evidence Dashboard (EvidenceDashboardView.swift)**: Search filter, segmented status picker, SQLite table with right-click context menu, and confirmation dialog for deletions.
- **Signing engine (`engine/`, `Autogram/scripts/build-engine.sh`)**: EUPL fork of slovensko-digital/autogram (DSS, PKCS#11, machine protocol v1/v2) plus the C launcher and Swift Quick Action runner; built into a jlink arm64 runtime and bundled by `build_app.sh`. Machine mode SIGKILLs itself after the terminal event, so exit 137 after `session.completed` is expected.
- **Finder Quick Action (`Assets/Autogram Finder Quick Action.workflow`, `build_app.sh`)**: Automator workflow restricted to Finder via `NSRequiredContext`; runs `autogram-quick-action.sh` and the bundled legacy CLI helper in the background, with `AutogramCLI-arm64`, `AutogramQuickActionRunner-arm64`, JAR dependencies, and Java runtime bundled in the app. The flow shows driver, certificate, and PIN/BOK dialogs without opening the main app and accepts PDF files only.

## Build & Test Instructions
- Build the signing engine first (once, or after changes in `engine/`): `scripts/build-engine.sh` (needs an arm64 JDK 25 with JavaFX jmods, Azul Zulu FX 25, under `~/Library/Java` or `AUTOGRAM_JAVA_HOME`; output `.build/engine/Contents`)
- Run build script: `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" ./build_app.sh [--release] [install]` (bundles `.build/engine/Contents` into `Contents/{Helpers,app,runtime}`; without it signing falls back to Keychain/DEMO and the Quick Action cannot sign)
- Run test suite: `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" swift test`
- Probe the AVM server end to end: `swift run avm-probe <file.pdf|file.asice> [--level PAdES_BASELINE_T] [--container ASiC-E] [--out <dir>] [--timeout <s>]` (prints the QR link, opens the QR PNG, waits for the phone, prints signers)
- Run detection eval harness: `swift run vision-eval <dataset> [--builtin-only] [--no-fm] [--bank <dir>] [--iou 0.4] [--json]` (dataset export kept outside the repo; `--bank <dir>` picks the example bank, default is a fresh empty temporary directory)
- Binary output: `$(swift build --show-bin-path)/Autogram.app` (Xcode 27: `.build/out/Products/Debug/Autogram.app`)

## Code Conventions
- Strict typing and modular design
- English for code comments, identifiers, and documentation
- Slovak for end-user legal and interface strings
- Follow Apple Human Interface Guidelines for macOS (Sequoia / Tahoe / Liquid Glass style)
- Hard Rule: Never use em dashes in any document or written text! Use hyphens (-), colons (:), or parentheses instead.
- Hard Rule: Keep AGENTS.md and CLAUDE.md in project root in complete sync.
