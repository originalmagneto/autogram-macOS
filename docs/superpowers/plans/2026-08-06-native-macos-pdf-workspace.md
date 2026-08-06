# Native macOS PDF Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Apple silicon SwiftUI application that previews, inspects, and batch-signs PDF files through Autogram machine protocol version 1.

**Architecture:** A SwiftUI application owns presentation state while actor-isolated services own process, file, and signing work. PDFKit renders documents, `SigningEngine` hides the Java helper, and `FakeSigningEngine` drives deterministic tests and previews.

**Tech Stack:** macOS 27, Xcode 27, Swift 6.4, SwiftUI, AppKit, PDFKit, Observation, Swift Testing, XCTest

## Global Constraints

- Deployment target is macOS 27.0.
- Supported architecture is ARM64 only.
- The app supervises one native ARM64 Autogram 2.7.5 or newer helper.
- No Intel helper, Rosetta fallback, or translated process is allowed.
- I.CA requires SecureStore 8.3.1 or newer.
- Every selected PKCS#11 library must contain an arm64 slice before helper launch.
- Swift 6 strict concurrency is enabled.
- The application signs PDF only.
- `PAdES_BASELINE_T` and a qualified timestamp are mandatory and not user-disableable.
- JavaFX and Terminal never appear in the workflow.
- The PIN is never persisted, logged, passed as an argument, or placed in the environment.
- Original PDFs are never overwritten.
- All models crossing actor boundaries conform to `Sendable`.
- Views contain no process, token, network, or direct file-writing logic.
- Use system controls and system Liquid Glass behavior before custom effects.
- Comments and documentation use English and contain no em dash characters.

---

## Prerequisite Gate

Full Xcode 27 must be installed and selected. Command Line Tools alone are insufficient.

```bash
xcodebuild -version
xcrun swift --version
```

Expected: Xcode 27.x, Swift 6.4 or newer, target support for `arm64-apple-macosx27.0`.

## Locked File Map

- `native-macos/Autogram.xcodeproj/project.pbxproj`: app and test targets with file-system synchronized groups.
- `native-macos/Autogram/App/AutogramApp.swift`: app entry and scenes.
- `native-macos/Autogram/App/AppCommands.swift`: native commands and shortcuts.
- `native-macos/Autogram/Core/Models/*.swift`: immutable domain values.
- `native-macos/Autogram/Core/SigningEngine.swift`: async engine protocol.
- `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`: `@MainActor @Observable` presentation model.
- `native-macos/Autogram/Features/Workspace/SigningCoordinator.swift`: actor state machine.
- `native-macos/Autogram/Features/Workspace/WorkspaceView.swift`: root layout.
- `native-macos/Autogram/Features/Workspace/PDFListView.swift`: batch sidebar.
- `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`: selected PDF content.
- `native-macos/Autogram/Features/Signing/SigningInspector.swift`: signing metadata and action.
- `native-macos/Autogram/Features/Signing/PINSheet.swift`: ephemeral secure input.
- `native-macos/Autogram/Features/Certificates/CertificatePicker.swift`: certificate selection.
- `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`: native Settings scene.
- `native-macos/Autogram/Infrastructure/CLI/*.swift`: protocol codec, process runner, and real engine.
- `native-macos/Autogram/Infrastructure/Drivers/DriverResolver.swift`: helper and PKCS#11 architecture selection.
- `native-macos/Autogram/Infrastructure/PDF/PDFPreviewView.swift`: `PDFView` bridge.
- `native-macos/Autogram/Infrastructure/FileSystem/OutputService.swift`: output allocation and validation.
- `native-macos/Autogram/Infrastructure/Fakes/FakeSigningEngine.swift`: deterministic test engine.
- `native-macos/AutogramTests/*Tests.swift`: unit tests.
- `native-macos/AutogramIntegrationTests/*Tests.swift`: fake-process integration tests.
- `native-macos/AutogramUITests/*Tests.swift`: user-flow tests.

### Core Interfaces

```swift
protocol SigningEngine: Sendable {
    func capabilities() async throws -> EngineCapabilities
    func drivers() async throws -> [SigningDriver]
    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate]
    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection]
    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error>
    func cancel() async
}

struct SigningRequest: Sendable {
    let sessionID: UUID
    let driverID: String
    let certificateSerial: String
    let pin: Secret
    let files: [SigningFile]
}

enum SessionState: Sendable, Equatable {
    case idle
    case inspectingFiles
    case resolvingDriver
    case loadingCertificates
    case selectingCertificate
    case awaitingPIN
    case signing(progress: BatchProgress)
    case completed(BatchSummary)
    case partiallyCompleted(BatchSummary)
    case failed(SigningFailure)
    case cancelled
}
```

### Task 1: Scaffold the Xcode 27 Application

**Files:**
- Create: `native-macos/Autogram.xcodeproj/project.pbxproj`
- Create: `native-macos/Autogram/App/AutogramApp.swift`
- Create: `native-macos/Autogram/App/AppCommands.swift`
- Create: `native-macos/Autogram/Features/Workspace/WorkspaceView.swift`
- Create: `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/Contents.json`
- Create: `native-macos/AutogramTests/AppLaunchTests.swift`

**Interfaces:**
- Produces: app target `Autogram`, unit target `AutogramTests`, integration target `AutogramIntegrationTests`, and UI target `AutogramUITests`.

- [ ] **Step 1: Create a failing project-level test**

```swift
import Testing
@testable import Autogram

@Test func applicationIdentityIsStable() {
    #expect(AppIdentity.bundleIdentifier == "digital.slovensko.autogram.native")
    #expect(AppIdentity.minimumSystemVersion == "27.0")
}
```

- [ ] **Step 2: Create the project with exact build settings**

Set `MACOSX_DEPLOYMENT_TARGET = 27.0`, `ARCHS = arm64`, `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `ENABLE_HARDENED_RUNTIME = YES`, `GENERATE_INFOPLIST_FILE = YES`, and `PRODUCT_BUNDLE_IDENTIFIER = digital.slovensko.autogram.native`.

Use file-system synchronized groups for `Autogram`, `AutogramTests`, `AutogramIntegrationTests`, and `AutogramUITests` so later source files do not require repeated project-file edits.

- [ ] **Step 3: Add the minimal app and identity**

```swift
enum AppIdentity {
    static let bundleIdentifier = "digital.slovensko.autogram.native"
    static let minimumSystemVersion = "27.0"
}

@main
struct AutogramApp: App {
    var body: some Scene {
        WindowGroup { WorkspaceView() }
        Settings { AutogramSettingsView() }
    }
}
```

The initial `WorkspaceView` uses a real `ContentUnavailableView` with a disabled Select PDF action until file intake is implemented. The initial Settings view is a native `Form` containing the app version and protocol version. Tasks 6 and 7 expand these files without replacing the application shell.

- [ ] **Step 4: Build and test**

Run:

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' build
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test
```

Expected: build succeeds and `applicationIdentityIsStable` passes.

- [ ] **Step 5: Commit**

Commit: `feat(mac): scaffold native Autogram app`

### Task 2: Implement Domain Models and Workspace State

**Files:**
- Create: `native-macos/Autogram/Core/Models/PDFItem.swift`
- Create: `native-macos/Autogram/Core/Models/SigningModels.swift`
- Create: `native-macos/Autogram/Core/Models/InspectionModels.swift`
- Create: `native-macos/Autogram/Core/Models/EngineModels.swift`
- Create: `native-macos/Autogram/Core/SigningEngine.swift`
- Create: `native-macos/Autogram/Features/Workspace/WorkspaceModel.swift`
- Create: `native-macos/Autogram/Features/Workspace/SigningCoordinator.swift`
- Create: `native-macos/Autogram/Infrastructure/Fakes/FakeSigningEngine.swift`
- Test: `native-macos/AutogramTests/SigningCoordinatorTests.swift`

**Interfaces:**
- Produces: the exact `SigningEngine`, `SigningRequest`, and `SessionState` interfaces declared above.

- [ ] **Step 1: Write failing state-transition tests**

```swift
@Test @MainActor func invalidSignBeforeInspectionIsRejected() async {
    let engine = FakeSigningEngine()
    let coordinator = SigningCoordinator(engine: engine)
    await #expect(throws: SigningFailure.invalidTransition) {
        try await coordinator.beginSigning(request: SigningRequest.fixture(ids: ["a"]))
    }
}

@Test @MainActor func oneFileFailureProducesPartialCompletion() async throws {
    let engine = FakeSigningEngine(script: [.completed("a"), .failed("b")])
    let coordinator = SigningCoordinator(engine: engine)
    try await coordinator.inspect(PDFItemDescriptor.fixtures(ids: ["a", "b"]))
    try await coordinator.beginSigning(request: SigningRequest.fixture(ids: ["a", "b"]))
    guard case .partiallyCompleted(let summary) = await coordinator.state else {
        Issue.record("Expected partial completion")
        return
    }
    #expect(summary.succeeded == 1)
    #expect(summary.failed == 1)
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test -only-testing:AutogramTests/SigningCoordinatorTests`

- [ ] **Step 3: Implement immutable sendable models**

Use UUID identity for workspace items and protocol file IDs. Store URLs in domain models but expose redacted display names to diagnostics. Keep `Secret` non-Codable and give it a single `consumeBytes()` operation.

- [ ] **Step 4: Implement the actor state machine**

Every public operation checks the current state. Signing consumes the PIN exactly once, processes stream events, updates per-file states on `MainActor`, and sets completed, partially completed, failed, or cancelled.

- [ ] **Step 5: Run tests and commit**

Expected: all state tests pass under Thread Sanitizer in a second local run.

Commit: `feat(mac): add signing workspace state`

### Task 3: Decode Machine Protocol Version 1

**Files:**
- Create: `native-macos/Autogram/Infrastructure/CLI/MachineProtocolModels.swift`
- Create: `native-macos/Autogram/Infrastructure/CLI/MachineProtocolDecoder.swift`
- Create: `native-macos/Autogram/Infrastructure/CLI/JSONLineBuffer.swift`
- Test: `native-macos/AutogramTests/MachineProtocolDecoderTests.swift`
- Read: `protocol/v1/fixtures/*.json*`

**Interfaces:**
- Consumes: protocol fixtures and names from the Java plan.
- Produces: `MachineRequestEncoder.encode(_:) -> Data` and `JSONLineBuffer.append(_:) throws -> [MachineEvent]`.

- [ ] **Step 1: Write failing fragmented-input tests**

```swift
@Test func decodesEventsAcrossArbitraryChunks() throws {
    var buffer = JSONLineBuffer(maxLineBytes: 1_048_576)
    #expect(try buffer.append(Data("{\"protocolVersion\":1,".utf8)).isEmpty)
    let events = try buffer.append(Data("\"type\":\"session.started\",\"sessionId\":\"s\",\"emittedAt\":\"2026-08-06T00:00:00Z\",\"fileId\":null,\"payload\":{}}\n".utf8))
    #expect(events.map(\.type) == [.sessionStarted])
}

@Test func rejectsOversizedLine() {
    var buffer = JSONLineBuffer(maxLineBytes: 8)
    #expect(throws: ProtocolFailure.lineTooLarge) { try buffer.append(Data(repeating: 65, count: 9)) }
}
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement strict Codable models**

Map unknown protocol versions, event types, session IDs, file IDs, and malformed payloads to typed `ProtocolFailure` values. Never fall back to parsing human output.

- [ ] **Step 4: Run Java fixture compatibility and Swift tests**

Run both `MachineProtocolCodecTest` and `MachineProtocolDecoderTests`. Expected: the same fixtures pass in both languages.

- [ ] **Step 5: Commit**

Commit: `feat(mac): decode Autogram machine protocol`

### Task 4: Supervise the Java Helper Process

**Files:**
- Create: `native-macos/Autogram/Infrastructure/CLI/CLIProcessRunner.swift`
- Create: `native-macos/Autogram/Infrastructure/CLI/ProcessConfiguration.swift`
- Create: `native-macos/AutogramIntegrationTests/Fixtures/FakeMachineHelper.swift`
- Test: `native-macos/AutogramIntegrationTests/CLIProcessRunnerTests.swift`

**Interfaces:**
- Consumes: Task 3 encoder and decoder.
- Produces: `CLIProcessRunner.run(request:configuration:) -> AsyncThrowingStream<MachineEvent, Error>` and `cancel() async`.

- [ ] **Step 1: Write failing process tests**

Test event streaming, stderr redaction, timeout, cancellation, non-zero exit, and a helper that writes one event in multiple byte chunks.

```swift
@Test func pinIsWrittenOnlyToStandardInput() async throws {
    let recorder = RecordingProcessLauncher()
    let runner = CLIProcessRunner(launcher: recorder)
    _ = try await runner.collect(request: fixtureRequest(pin: "4321"))
    #expect(!recorder.arguments.joined().contains("4321"))
    #expect(!recorder.environment.description.contains("4321"))
    #expect(recorder.standardInput.contains(Data("4321".utf8)))
}
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement actor-isolated process lifecycle**

Use `Foundation.Process`, separate pipes, termination handlers bridged to continuations, and a bounded cancellation sequence: terminate, wait two seconds, then interrupt. Cap stdout line size and stderr capture size.

Invoke the helper with exactly `--cli --machine-readable --protocol-version 1 --operation <operation>`. Normalize the operation name to the Java enum value and require the JSON envelope operation to match.

- [ ] **Step 4: Clear request data after write**

Encode directly before writing, close standard input, clear the model PIN, and retain only redacted request metadata.

- [ ] **Step 5: Run tests and commit**

Commit: `feat(mac): supervise Autogram CLI helper`

### Task 5: Resolve Driver Architecture and Safe Outputs

**Files:**
- Create: `native-macos/Autogram/Infrastructure/Drivers/DriverResolver.swift`
- Create: `native-macos/Autogram/Infrastructure/Drivers/MachOInspector.swift`
- Create: `native-macos/Autogram/Infrastructure/Drivers/MiddlewareRequirementValidator.swift`
- Create: `native-macos/Autogram/Infrastructure/FileSystem/OutputService.swift`
- Create: `native-macos/Autogram/Infrastructure/FileSystem/PDFArtifactValidator.swift`
- Create: `native-macos/Autogram/Infrastructure/FileSystem/CloudFileMaterializer.swift`
- Test: `native-macos/AutogramTests/DriverResolverTests.swift`
- Test: `native-macos/AutogramTests/OutputServiceTests.swift`
- Test: `native-macos/AutogramTests/CloudFileMaterializerTests.swift`

**Interfaces:**
- Produces: `ResolvedDriver(helperURL: URL, driverURL: URL, architecture: HelperArchitecture, middlewareVersion: String?)` and `OutputReservation(temporaryURL: URL, finalURL: URL)`.

- [ ] **Step 1: Write failing resolver and collision tests**

```swift
@Test func driverWithoutArm64SliceIsRejected() throws {
    let driver = DriverFixture(architectures: [.x86_64], middlewareVersion: "8.3.1")
    #expect(throws: DriverRequirementError.arm64Required) {
        try resolver.resolve(driver: driver)
    }
}

@Test func oldICASecureStoreIsRejected() throws {
    let driver = DriverFixture(architectures: [.arm64], middlewareVersion: "8.1.0")
    #expect(throws: DriverRequirementError.icaSecureStoreUpdateRequired(minimum: "8.3.1")) {
        try resolver.resolve(driver: driver)
    }
}

@Test func collisionUsesNextNumberWithoutOverwrite() throws {
    fileSystem.create("case_signed.pdf")
    let reservation = try output.reserve(for: URL(fileURLWithPath: "case.pdf"))
    #expect(reservation.finalURL.lastPathComponent == "case_signed (2).pdf")
}
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement ARM64 middleware validation and helper resolution**

Inspect the bundled Autogram helper and every selected PKCS#11 dylib with system `lipo -archs` through a small injectable process interface. Do not infer architecture from file names. Require an arm64 slice for both binaries. Require I.CA SecureStore 8.3.1 or newer for I.CA. Return a localized repair instruction when either requirement fails. Launch only the single ARM64 helper and provide no translated fallback.

- [ ] **Step 4: Implement exclusive output reservation**

Canonicalize URLs, reject symlink targets and source-target identity, create a temporary sibling with restrictive permissions, validate `%PDF-` and a trailing `%%EOF`, then atomically move only after the machine engine reports cryptographic success.

- [ ] **Step 5: Materialize cloud-backed input with file coordination**

Use `NSFileCoordinator` through an injectable adapter, wait for ubiquitous-item download completion with a bounded timeout, and return a per-file `cloudMaterializationFailed` error without rejecting local siblings.

- [ ] **Step 6: Run tests and commit**

Commit: `feat(mac): resolve drivers and reserve PDF outputs`

### Task 6: Expand the Fake Engine and Build the Workspace UI

**Files:**
- Modify: `native-macos/Autogram/Infrastructure/Fakes/FakeSigningEngine.swift`
- Modify: `native-macos/Autogram/Features/Workspace/WorkspaceView.swift`
- Create: `native-macos/Autogram/Features/Workspace/PDFListView.swift`
- Create: `native-macos/Autogram/Features/Workspace/PDFDetailView.swift`
- Create: `native-macos/Autogram/Features/Signing/SigningInspector.swift`
- Create: `native-macos/Autogram/Infrastructure/PDF/PDFPreviewView.swift`
- Test: `native-macos/AutogramUITests/WorkspaceFlowTests.swift`

**Interfaces:**
- Consumes: Task 2 state model.
- Produces: root `NavigationSplitView` with list, PDFKit detail, inspector, and toolbar.

- [ ] **Step 1: Write failing UI tests**

Launch with `AUTOGRAM_FAKE_ENGINE=partial-failure` and verify empty state, multi-file sidebar, Sign button, per-file progress, partial summary, and Reveal actions.

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement the native layout**

Use a three-part `NavigationSplitView`, an inspector modifier, a system toolbar with visibility priorities, `ContentUnavailableView` for the empty state, and native list reordering. Keep Sign pinned as the primary trailing action. Add `NSOpenPanel` file selection and SwiftUI PDF drop handling, preserving valid files when one dropped item is rejected.

- [ ] **Step 4: Bridge PDFKit**

Wrap `PDFView` in `NSViewRepresentable`, enable automatic scaling, keep PDF rendering separate from cryptographic inspection, and release documents when rows are removed.

- [ ] **Step 5: Run UI tests and commit**

Commit: `feat(mac): build native PDF workspace`

### Task 7: Implement Certificate, PIN, and Settings Flows

**Files:**
- Create: `native-macos/Autogram/Features/Certificates/CertificatePicker.swift`
- Create: `native-macos/Autogram/Features/Signing/PINSheet.swift`
- Modify: `native-macos/Autogram/Features/Settings/AutogramSettingsView.swift`
- Create: `native-macos/Autogram/Resources/Localizable.xcstrings`
- Create: `native-macos/Autogram/Core/Models/UserPreferences.swift`
- Test: `native-macos/AutogramTests/UserPreferencesTests.swift`
- Test: `native-macos/AutogramUITests/CredentialFlowTests.swift`

**Interfaces:**
- Produces: persisted driver ID, persisted public certificate serial, output policy, and non-persisted `Secret` PIN.

- [ ] **Step 1: Write failing persistence tests**

```swift
@Test func preferencesNeverEncodePin() throws {
    let data = try JSONEncoder().encode(UserPreferences.fixture)
    #expect(!String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("pin"))
}
```

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement native sheets and Settings scene**

Use `SecureField`, disable submission when empty, clear the binding on dismissal and task completion, and store only driver ID and certificate serial in `AppStorage`. Include output naming, destination behavior, and post-signing Finder behavior. Do not expose signature level or timestamp disabling controls. Resolve machine `messageKey` values through the string catalog and use the safe fallback only when a key is unavailable.

- [ ] **Step 4: Add diagnostics without personal data**

Show Autogram helper version, ARM64 validation status, middleware version, protocol version, and redacted status. Exclude full paths, signer names, certificate serials, and PIN state. For I.CA failures, state that SecureStore 8.3.1 or newer is required and link to the official download page.

- [ ] **Step 5: Run tests and commit**

Commit: `feat(mac): add secure signing configuration`

### Task 8: Connect the Real CLI Engine

**Files:**
- Create: `native-macos/Autogram/Infrastructure/CLI/AutogramCLIEngine.swift`
- Modify: `native-macos/Autogram/App/AutogramApp.swift`
- Modify: `native-macos/Autogram/Features/Workspace/SigningCoordinator.swift`
- Test: `native-macos/AutogramIntegrationTests/AutogramCLIEngineTests.swift`

**Interfaces:**
- Consumes: all protocol, process, driver, output, and state components.
- Produces: production `SigningEngine` dependency selected unless the explicit UI-test fake flag is present.

- [ ] **Step 1: Write failing engine integration tests**

Test capabilities, drivers, inspection, successful file event mapping, partial failure, unsupported protocol version, malformed helper output, and cancellation against the fake helper process.

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement request and event translation**

Generate one session UUID, one stable ID per PDF, explicit source-target pairs, `PAdES_BASELINE_T`, and `timestamp.required = true`. Reject any completion lacking Java QTSA validation and local PDF artifact validation.

- [ ] **Step 4: Wire dependency selection**

Production uses `AutogramCLIEngine`. UI tests use `FakeSigningEngine` only when a launch environment flag is present. Release builds ignore that flag unless compiled with the UI-testing configuration.

- [ ] **Step 5: Run integration and full Swift tests**

Run:

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test
```

Expected: all unit, integration, and UI tests pass.

Commit: `feat(mac): connect native app to Autogram CLI`

### Task 9: Accessibility, Privacy, and Performance Gate

**Files:**
- Modify: native views from Tasks 6 and 7.
- Create: `native-macos/AutogramTests/PrivacyRegressionTests.swift`
- Create: `native-macos/AutogramUITests/AccessibilityFlowTests.swift`
- Create: `native-macos/README.md`

**Interfaces:**
- Consumes: completed native workspace.
- Produces: implementation-ready native app for Finder and release integration.

- [ ] **Step 1: Add failing accessibility and privacy tests**

Verify keyboard-only signing, VoiceOver identifiers, Reduce Motion behavior, dark mode, high contrast, and redaction of paths and certificate data.

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Add semantic labels and environment handling**

Every icon-only control receives a label and help text. Progress is announced without repeated noisy updates. Animations become minimal when Reduce Motion is enabled. Custom glass effects are removed when Reduce Transparency is enabled.

- [ ] **Step 4: Run static and full verification**

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' analyze
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' test
git diff --check
rg -n $'\u2014|/Users/|BEGIN .*PRIVATE KEY|api[_-]?key|password\\s*=' native-macos
```

Expected: analyzer succeeds, tests pass, diff is clean, and privacy scan has no matches.

- [ ] **Step 5: Commit**

Commit: `test(mac): verify native workspace quality`

## Completion Gate

- The native app builds only for Apple silicon and macOS 27.
- Unit, integration, and UI tests pass.
- PDFKit preview is independent of DSS signature inspection.
- Fake and real engines conform to the same protocol.
- Batch partial failures are visible and recoverable.
- PIN data is absent from arguments, environment, settings, and diagnostics.
- SOL reviews architecture and integration boundaries.
- Luna performs read-only UI, privacy, and test-result audits.
