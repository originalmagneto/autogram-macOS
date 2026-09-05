# AGENTS.md - Autogram macOS UI

## Project Overview
Autogram is a 100% native macOS SwiftUI application for Qualified Electronic Signatures (KEP / eIDAS) and Guaranteed Conversion of legal documents (Zarucena konverzia according to Slovak Law No. 305/2013 Z. z. and Decree No. 70/2021 Z. z.).

## Architecture & Tech Stack
- Swift 6.0+ / Xcode 27.0 toolchain (`/Applications/Xcode-beta.app`)
- Native macOS SwiftUI (`NavigationSplitView`, `.regularMaterial`, `.ultraThinMaterial`, Liquid Glass design)
- Core Data / SQLite for Evidence and Conversion registers (CEZZK integration)
- PKCS#11 bridge for Slovak eID cards, SAK advocate cards, and Disig smartcards
- PDFKit, CoreGraphics, Apple Vision and FoundationModels for document analysis and security element detection
  - `LayeredDetectionProvider` (VisionAI/): candidates from `BuiltInVisionProvider` (frozen), `DetectContoursRequest`, objectness saliency; merged by `CandidateMerger`; classified by `TwoStageClassifier` (`FeaturePrintClassifier` kNN over `ExampleBank`, then on-device `FoundationModelClassifier`)
  - `ExampleBank` at `~/Library/Application Support/Autogram/VisionBank` records confirm/reject decisions; `CreateMLExporter` writes Create ML object-detector datasets; `vision-eval` target scores precision/recall
  - `SegmentationSnapper` wraps `GenerateIterativeSegmentationRequest` for click-to-snap boxes in `AnalysisCanvasView`
  - Local LLM vision providers: oMLX (Apple Silicon MLX, `localhost:8000/v1`) and Ollama (`localhost:11434`), plus OpenAI-compatible cloud APIs with keys in Keychain
  - AI provider selection in Settings uses provider cards (`SettingsView.aiProviderRow`); config panel renders under the chosen mode; `LearningDatasetCard` holds the learning toggles and dataset export

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
- **Finder Quick Action (`Assets/Autogram Finder Quick Action.workflow`, `build_app.sh`)**: Automator workflow restricted to Finder via `NSRequiredContext`; runs `autogram-quick-action.sh` and the bundled legacy CLI helper in the background, with `AutogramCLI-arm64`, `AutogramQuickActionRunner-arm64`, JAR dependencies, and Java runtime bundled in the app. The flow shows driver, certificate, and PIN/BOK dialogs without opening the main app and accepts PDF files only.

## Build & Test Instructions
- Run build script: `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" ./build_app.sh`
- Run test suite: `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" swift test`
- Run detection eval harness: `swift run vision-eval <dataset>` (dataset export kept outside the repo)
- Binary output: `.build/arm64-apple-macosx/debug/Autogram.app`

## Code Conventions
- Strict typing and modular design
- English for code comments, identifiers, and documentation
- Slovak for end-user legal and interface strings
- Follow Apple Human Interface Guidelines for macOS (Sequoia / Tahoe / Liquid Glass style)
- Hard Rule: Never use em dashes in any document or written text! Use hyphens (-), colons (:), or parentheses instead.
- Hard Rule: Keep AGENTS.md and CLAUDE.md in project root in complete sync.
