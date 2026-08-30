# EZZK OAuth2 and REST UI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the legacy EZZK username/password path with native OAuth2 session handling, a typed REST client, and a fail-closed EZZK Settings UI while preserving demo mode and local evidence records.

**Architecture:** Keep EZZK protocol capabilities in AutogramKit. Add fixed sandbox and production environment identities, a dedicated Keychain token store, a serialized `EZZKClient` actor, and an app-layer `EZZKSessionController` that owns `ASWebAuthenticationSession`. The native callback remains disabled until the EZZK operator confirms a registered redirect URI or custom scheme. Consequential API calls are typed and user initiated, but cannot mark local records submitted without a confirmed receipt.

**Tech Stack:** Swift 6, macOS 27, SwiftUI, AuthenticationServices, Security Keychain, Foundation URLSession, CryptoKit, XCTest, existing AutogramKit EZZK capability protocols.

## Global Constraints

- Sandbox URL is `https://ezzk-test.iomo.sk` and production URL is `https://ezzk.iomo.sk`.
- API base path is `/api/zzkservice/v1`.
- Keycloak issuer is `https://ezzk.iomo.sk/sso/auth/realms/ezzk` and client ID is `login-app`.
- The observed web redirect `https://ezzk.iomo.sk/portal` MUST NOT be used as a guessed native callback.
- No native login is enabled until a native redirect URI or custom callback scheme is operator-confirmed.
- Access tokens, refresh tokens, authorization codes, passwords, and request bodies containing secrets MUST NOT enter logs, UserDefaults, AppSettings, evidence records, or exports.
- Sandbox and production endpoint identities MUST be fixed typed configurations. No arbitrary URL override is allowed in Settings.
- Demo mode may use `MockEZZKService`; the mock MUST NOT satisfy sandbox or production capability checks.
- A `401` may trigger one refresh and one retry only. There MUST be no infinite refresh loop.
- Read-only network failures MAY use bounded retries. Submit MUST NOT retry automatically after transport uncertainty.
- Missing, malformed, or unknown responses MUST fail closed and MUST NOT produce a submitted local status.
- User-visible errors and controls are Slovak. Code identifiers, comments, and internal documentation are English.
- No em dash characters in source, UI copy, or documentation.
- Every production-code change requires a focused behavioral test before implementation.
- This plan does not claim CEZZK production readiness. External EZZK operator confirmation and sandbox evidence remain release gates.

---

## File map

### AutogramKit domain and transport

- Create `Autogram/Sources/AutogramKit/EZZK/EZZKEnvironment.swift`: fixed environment identities and authority metadata.
- Create `Autogram/Sources/AutogramKit/EZZK/EZZKOAuthModels.swift`: OAuth configuration, token set, session errors, and authorization callback models.
- Create `Autogram/Sources/AutogramKit/EZZK/EZZKTokenStore.swift`: Keychain-backed token storage with injected clock and dedicated service namespace.
- Create `Autogram/Sources/AutogramKit/EZZK/EZZKHTTPClient.swift`: URLSession transport and serialized OAuth-aware REST client.
- Create `Autogram/Sources/AutogramKit/EZZK/EZZKAPIModels.swift`: typed `/ec`, history, record, file payload, and submission receipt models.
- Modify `Autogram/Sources/AutogramKit/EZZK/EZZKService.swift`: remove legacy password service from the OAuth path while preserving the mock and existing capability protocols.

### App-layer authentication and state

- Create `Autogram/Sources/AutogramApp/EZZK/EZZKAuthenticationSession.swift`: `ASWebAuthenticationSession` and PKCE callback broker.
- Create `Autogram/Sources/AutogramApp/EZZK/EZZKSessionController.swift`: `@MainActor` UI state and explicit EZZK actions.
- Modify `Autogram/Sources/AutogramApp/AppSettingsStore.swift`: own the session controller and rebuild services only at safe session boundaries.
- Modify `Autogram/Sources/AutogramApp/AutogramApp.swift`: inject the session controller into the app environment and lifecycle.
- Modify `Autogram/Sources/AutogramApp/Views/SettingsView.swift`: replace password login controls with environment and session controls.

### Tests and records

- Create `Autogram/Tests/AutogramKitTests/EZZKEnvironmentTests.swift`.
- Create `Autogram/Tests/AutogramKitTests/EZZKTokenStoreTests.swift`.
- Create `Autogram/Tests/AutogramKitTests/EZZKHTTPClientTests.swift`.
- Create `Autogram/Tests/AutogramKitTests/EZZKAPIModelsTests.swift`.
- Create `Autogram/docs/superpowers/reviews/2026-08-29-ezzk-oauth-rest-ui-review.md` only if implementation review requires a durable finding record.
- Modify `Autogram/docs/P2E-EZZK-FINDINGS.md` with implementation status, exact blockers, and verification results.

---

## Task 1: Add fixed environments and secure token primitives

**Files:**
- Create: `Autogram/Sources/AutogramKit/EZZK/EZZKEnvironment.swift`
- Create: `Autogram/Sources/AutogramKit/EZZK/EZZKOAuthModels.swift`
- Create: `Autogram/Sources/AutogramKit/EZZK/EZZKTokenStore.swift`
- Test: `Autogram/Tests/AutogramKitTests/EZZKEnvironmentTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/EZZKTokenStoreTests.swift`

**Interfaces:**

```swift
public enum EZZKEnvironment: String, Codable, CaseIterable, Sendable {
    case sandbox
    case production

    public var portalBaseURL: URL { get }
    public var apiBaseURL: URL { get }
    public var authorityID: String { get }
}

public struct EZZKOAuthConfiguration: Sendable, Equatable {
    public let issuerURL: URL
    public let clientID: String
    public let redirectURI: URL?
    public let callbackScheme: String?
    public let scopes: [String]
    public var isNativeCallbackConfigured: Bool { get }
}

public struct EZZKTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiration: Date
    public let tokenType: String
}

public protocol EZZKTokenStoring: Sendable {
    func load(environment: EZZKEnvironment) throws -> EZZKTokenSet?
    func save(_ tokenSet: EZZKTokenSet, environment: EZZKEnvironment) throws
    func delete(environment: EZZKEnvironment) throws
}
```

- [ ] **Step 1: Write environment tests first**

Assert exact sandbox and production portal URLs, API URLs, authority IDs, and that no environment exposes a user-settable URL. Assert the OAuth configuration is not native-ready when redirect URI or callback scheme is absent.

- [ ] **Step 2: Run the environment tests and verify failure**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKEnvironmentTests
```

Expected: compile failure because the new types do not exist.

- [ ] **Step 3: Implement fixed environment and OAuth models**

Use exact URLs from the findings register. Keep `redirectURI` and `callbackScheme` optional and default them to nil. Derive only the API path internally. Reject non-HTTPS issuer and endpoint URLs during initialization where the interface permits validation.

- [ ] **Step 4: Write token-store behavior tests first**

Use an isolated Keychain account namespace and test double for the Keychain adapter. Cover save/load, environment separation, delete, malformed stored data, and inaccessible storage. Tests MUST prove that sandbox and production token sets cannot overwrite each other.

- [ ] **Step 5: Implement dedicated Keychain token storage**

Use a service identifier distinct from `KeychainStore.service`. Store one Codable token record per environment. Map Keychain failures to a typed storage error. Do not use `UserDefaults` for token material.

- [ ] **Step 6: Run primitive tests and commit**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKEnvironmentTests
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKTokenStoreTests
```

Expected: all focused tests pass. Commit:

```bash
git add Autogram/Sources/AutogramKit/EZZK/EZZKEnvironment.swift Autogram/Sources/AutogramKit/EZZK/EZZKOAuthModels.swift Autogram/Sources/AutogramKit/EZZK/EZZKTokenStore.swift Autogram/Tests/AutogramKitTests/EZZKEnvironmentTests.swift Autogram/Tests/AutogramKitTests/EZZKTokenStoreTests.swift
git commit -m "feat: add EZZK environments and token storage"
```

---

## Task 2: Implement OAuth authorization-code and PKCE broker

**Files:**
- Create: `Autogram/Sources/AutogramApp/EZZK/EZZKAuthenticationSession.swift`
- Modify: `Autogram/Sources/AutogramKit/EZZK/EZZKOAuthModels.swift` only if the tested token exchange model needs a narrow addition.
- Test: `Autogram/Tests/AutogramKitTests/EZZKEnvironmentTests.swift` for pure PKCE and callback parsing.

**Interfaces:**

```swift
public struct EZZKPKCEChallenge: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let state: String
}

@MainActor
protocol EZZKAuthenticationSessionRunning: AnyObject {
    func authenticate(configuration: EZZKOAuthConfiguration) async throws -> EZZKTokenSet
}
```

- [ ] **Step 1: Write pure PKCE and callback tests first**

Test that the verifier and state are non-empty, repeated challenges differ, the S256 challenge is deterministic for a supplied verifier, callback query parsing requires `code` and matching `state`, and OAuth error callbacks map to cancellation or authentication failure without exposing the code.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKEnvironmentTests
```

Expected: failure for missing PKCE and callback helpers.

- [ ] **Step 3: Implement PKCE and strict callback parsing**

Use `CryptoKit` SHA-256 and Base64URL without padding. Compare state using constant-time-safe equality for equal-length strings. Reject missing, duplicated, or malformed callback fields. Do not log callback URLs or authorization codes.

- [ ] **Step 4: Implement `ASWebAuthenticationSession` broker**

Use `ASWebAuthenticationSession` from the app target. Require `configuration.isNativeCallbackConfigured` before creating the session. Use the configured callback scheme, not the observed web redirect. Present the session on the main actor and map user cancellation to a typed cancellation error. Leave the session signed out after all failures.

- [ ] **Step 5: Implement discovery and token exchange without guessed endpoints**

Load OpenID Connect discovery metadata from the configured issuer or use an operator-confirmed endpoint configuration. Validate HTTPS and issuer ownership before the token request. Send authorization-code plus PKCE verifier to the discovered token endpoint. Decode `access_token`, optional `refresh_token`, `expires_in`, and `token_type`; reject missing or malformed values.

- [ ] **Step 6: Run authentication tests and commit**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKEnvironmentTests
```

Expected: all pure authentication tests pass. The live browser flow remains disabled until native redirect configuration is supplied. Commit:

```bash
git add Autogram/Sources/AutogramApp/EZZK/EZZKAuthenticationSession.swift Autogram/Sources/AutogramKit/EZZK/EZZKOAuthModels.swift Autogram/Tests/AutogramKitTests/EZZKEnvironmentTests.swift
git commit -m "feat: add EZZK OAuth PKCE broker"
```

---

## Task 3: Implement typed EZZK REST client

**Files:**
- Create: `Autogram/Sources/AutogramKit/EZZK/EZZKAPIModels.swift`
- Create: `Autogram/Sources/AutogramKit/EZZK/EZZKHTTPClient.swift`
- Modify: `Autogram/Sources/AutogramKit/EZZK/EZZKService.swift`
- Test: `Autogram/Tests/AutogramKitTests/EZZKAPIModelsTests.swift`
- Test: `Autogram/Tests/AutogramKitTests/EZZKHTTPClientTests.swift`

**Interfaces:**

```swift
public struct EZZKAvailableEvidenceResponse: Codable, Sendable, Equatable {
    public let availableEvidenceNumbers: [String]
    public let description: String?
}

public struct EZZKFilePayload: Codable, Sendable, Equatable {
    public let fileName: String
    public let fileType: String
    public let value: String
}

public struct EZZKFilesRequest: Codable, Sendable, Equatable {
    public let files: [EZZKFilePayload]
}

public protocol EZZKHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public actor EZZKClient {
    public init(environment: EZZKEnvironment,
                oauth: EZZKOAuthConfiguration,
                tokenStore: any EZZKTokenStoring,
                transport: any EZZKHTTPTransport)

    public func availableEvidenceNumbers() async throws -> EZZKAvailableEvidenceResponse
    public func consumedEvidenceNumbers() async throws -> Data
    public func record(evidenceNumber: String) async throws -> Data
    public func original(evidenceNumber: String) async throws -> Data
    public func history(query: [URLQueryItem]) async throws -> Data
    public func requestEvidenceNumbers(count: Int) async throws -> [String]
    public func submit(files: EZZKFilesRequest) async throws -> EZZKSubmissionReceipt
}
```

- [ ] **Step 1: Write response and request model tests first**

Decode the observed empty `/ec` response exactly. Encode the `.asice` payload with `application/vnd.etsi.asic-e+zip`. Reject empty file lists, non-ASiC MIME types, and empty Base64 values. Keep record and original responses as `Data` until their authoritative schemas are known.

- [ ] **Step 2: Write HTTP behavior tests first**

Use an injected fake transport. Assert exact sandbox URL construction, Bearer header, JSON content type, `/ec` decoding, server `Date` extraction, one refresh plus one retry after `401`, no second retry, no token fallback, status mapping for `400`, `403`, `409`, `429`, and `5xx`, and no automatic submit retry. Assert an unknown submit response is not a receipt.

- [ ] **Step 3: Run focused tests and verify failure**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKHTTPClientTests
```

Expected: compile failure for missing client and models.

- [ ] **Step 4: Implement URL construction and authenticated request execution**

Construct all paths from `environment.apiBaseURL`. Add `Authorization: Bearer <token>` and `Accept: application/json`. Never include credentials in query parameters. Reject requests whose URL host differs from the selected environment.

- [ ] **Step 5: Implement refresh, retry, and server-time behavior**

Serialize all operations in the actor. Refresh only once for an expired token or a `401`. Use the HTTP `Date` response header for `serverTime()`. Missing or invalid date is a typed error. Apply bounded exponential backoff only to read-only requests.

- [ ] **Step 6: Implement typed consequential boundaries**

Validate `count > 0` for `POST /ec`. Validate all files before `POST /zzk`. Decode only a confirmed receipt shape. Until sandbox confirms the complete response schema, represent an unrecognized successful response as `invalidResponse` rather than success. Do not automatically conform this client to the legacy password service.

- [ ] **Step 7: Update service wiring boundary and run tests**

Keep `MockEZZKService` unchanged for demo behavior. Add a new OAuth-backed service adapter only for the typed client methods whose contracts are confirmed. Do not make the current `ZakoSessionStore` submit legacy `ConversionRecordEnvelope` data as if it were the final ASiC file payload.

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKAPIModelsTests
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKHTTPClientTests
```

Expected: all focused tests pass. Commit:

```bash
git add Autogram/Sources/AutogramKit/EZZK/EZZKAPIModels.swift Autogram/Sources/AutogramKit/EZZK/EZZKHTTPClient.swift Autogram/Sources/AutogramKit/EZZK/EZZKService.swift Autogram/Tests/AutogramKitTests/EZZKAPIModelsTests.swift Autogram/Tests/AutogramKitTests/EZZKHTTPClientTests.swift
git commit -m "feat: add typed EZZK REST client"
```

---

## Task 4: Add app-layer session controller and settings wiring

**Files:**
- Create: `Autogram/Sources/AutogramApp/EZZK/EZZKSessionController.swift`
- Modify: `Autogram/Sources/AutogramApp/AppSettingsStore.swift`
- Modify: `Autogram/Sources/AutogramApp/AutogramApp.swift`
- Test: `Autogram/Tests/AutogramKitTests/EZZKHTTPClientTests.swift` for service selection invariants where possible.

**Interfaces:**

```swift
@MainActor
final class EZZKSessionController {
    enum State: Equatable {
        case signedOut
        case authenticating
        case authenticated(environment: EZZKEnvironment, availableEvidenceNumbers: Int)
        case expired
        case failed(String)
    }

    private(set) var state: State
    var selectedEnvironment: EZZKEnvironment

    func login() async
    func logout()
    func refresh() async
    func testConnection() async
    func requestEvidenceNumbers(count: Int) async
}
```

- [ ] **Step 1: Write service selection tests first**

Prove that an empty OAuth configuration cannot create an authenticated sandbox or production service, demo mode still selects `MockEZZKService`, logout preserves `LocalEvidenceStore`, and production selection remains disabled until its authority gate is true.

- [ ] **Step 2: Implement session controller state machine**

Initialize from Keychain tokens but require a read-only connectivity check before publishing `authenticated`. Keep the client and authentication runner private. Map errors to Slovak UI messages without including secrets.

- [ ] **Step 3: Replace password-based rebuild for non-demo modes**

`AppSettingsStore` must stop using `EZZKCredentials` to select sandbox or production behavior. Existing legacy credential values may remain decodable for migration, but changing them must not authenticate the new client. Demo mode uses the mock. OAuth session state owns sandbox service availability.

- [ ] **Step 4: Inject controller into application lifecycle**

Create the controller once in `AutogramAppModel`, pass it to `SettingsView`, and ensure a settings change cannot replace the active client during a conversion session. Do not write token values into the observable settings model.

- [ ] **Step 5: Run app build and focused tests**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test --filter EZZKHTTPClientTests
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh
```

Expected: focused tests pass and the app builds. Commit:

```bash
git add Autogram/Sources/AutogramApp/EZZK/EZZKSessionController.swift Autogram/Sources/AutogramApp/AppSettingsStore.swift Autogram/Sources/AutogramApp/AutogramApp.swift Autogram/Tests/AutogramKitTests/EZZKHTTPClientTests.swift
git commit -m "feat: wire EZZK OAuth session state"
```

---

## Task 5: Replace EZZK Settings UI with guarded controls

**Files:**
- Modify: `Autogram/Sources/AutogramApp/Views/SettingsView.swift`
- Modify: `Autogram/Sources/AutogramApp/AppSettingsStore.swift` only for presentation-facing state access.
- Test: `Autogram/Tests/AutogramKitTests/EZZKEnvironmentTests.swift` for fixed labels and environment gates where testable without UI.

- [ ] **Step 1: Add UI state requirements to tests**

Assert the default environment is sandbox, the production action is unavailable when the authority gate is false, and logout does not clear local evidence storage.

- [ ] **Step 2: Replace legacy password controls**

Show environment, fixed portal and API identity, current session state, last connectivity check, available number count, and the actions `Prihlásiť cez EZZK`, `Obnoviť session`, and `Odhlásiť`. Remove the implication that entering IČO, username, and password authenticates the OAuth client.

- [ ] **Step 3: Add explicit evidence-number request control**

The control must require a positive count, display a confirmation dialog, show the result, and never run on view appearance. Errors remain visible without changing local evidence status.

- [ ] **Step 4: Add explicit submit boundary**

Expose submit only when the conversion workflow supplies validated signed ASiC files and the selected environment has the required capability. If the current workflow does not provide those files, show a disabled state explaining the missing signed artefacts instead of sending `ConversionRecordEnvelope` metadata.

- [ ] **Step 5: Verify the actual Settings surface**

Launch the built app, open Settings > EZZK, and verify visually that sandbox is selected, production is disabled, login is blocked without native redirect configuration, and no password field is presented as an OAuth login. Record any UI issue before proceeding.

- [ ] **Step 6: Commit the guarded UI**

```bash
git add Autogram/Sources/AutogramApp/Views/SettingsView.swift Autogram/Sources/AutogramApp/AppSettingsStore.swift Autogram/Tests/AutogramKitTests/EZZKEnvironmentTests.swift
git commit -m "feat: add guarded EZZK settings controls"
```

---

## Task 6: Integrate records, update findings, and verify the branch

**Files:**
- Modify: `Autogram/docs/P2E-EZZK-FINDINGS.md`
- Modify: `Autogram/Sources/AutogramKit/EZZK/EZZKService.swift` only if a receipt or artifact boundary requires a narrow fix.
- Modify: focused tests only if a missing observable contract is discovered.

- [ ] **Step 1: Add receipt and uncertainty tests**

Prove that a confirmed receipt can advance a record, an unknown successful response cannot, a timeout during submit leaves the local record non-submitted, and logout preserves all evidence rows.

- [ ] **Step 2: Verify no legacy production path remains**

Search the EZZK wiring and Settings UI for password-based authentication, arbitrary endpoint input, mock fallback from OAuth failure, and local-clock fallback in sandbox or production. Remove only obsolete code made unreachable by this cutover.

- [ ] **Step 3: Update the findings register**

Record implemented components, exact test results, the native redirect blocker, sandbox account blocker, and the still-unconfirmed POST response and receipt schema. Do not state that EZZK production integration is complete.

- [ ] **Step 4: Run complete verification**

Run:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" swift test
DEVELOPER_DIR="/Applications/Xcode-26.5.app/Contents/Developer" ./build_app.sh
```

Expected: zero test failures and successful app build. Any existing unrelated warning must be recorded without suppressing it.

- [ ] **Step 5: Perform final review and commit**

Review the complete branch diff for secrets, endpoint confusion, unsafe retries, false submitted states, missing UI state, forbidden em dashes, and scope expansion. Commit:

```bash
git add Autogram/docs/P2E-EZZK-FINDINGS.md Autogram/Sources/AutogramKit/EZZK Autogram/Sources/AutogramApp/EZZK Autogram/Sources/AutogramApp/AppSettingsStore.swift Autogram/Sources/AutogramApp/AutogramApp.swift Autogram/Sources/AutogramApp/Views/SettingsView.swift Autogram/Tests/AutogramKitTests
git commit -m "feat: complete guarded EZZK OAuth integration"
```

## Release boundary

The implementation may be considered locally complete only when all tests and the app build pass and the Settings surface is verified. It remains externally blocked from production until:

1. EZZK confirms a native redirect URI or callback scheme for `login-app`.
2. A non-production EZZK sandbox account is available.
3. The complete `POST /ec` contract is captured from sandbox.
4. The complete `POST /zzk` request, receipt, error, retry, and idempotency contract is captured from sandbox.
5. Signed clause and record ASiC artefacts are supplied by the conversion pipeline.
6. The authority register records sandbox evidence and production release approval.

## Execution status

Completed on `main` after local fast-forward merge from `codex/ezzk-oauth-rest-ui`.

- Tasks 1 through 6 completed and reviewed.
- Final branch review completed with all Important findings fixed.
- Merged verification: 187 tests executed, 3 skipped, 0 failures.
- Merged build: `Autogram/.build/arm64-apple-macosx/debug/Autogram.app`.
- Production remains blocked by the external release boundary above.
