# EZZK OAuth2 and REST UI Integration Design

Date: 2026-08-29
Status: approved design, implementation pending
Scope: native macOS authentication, typed EZZK REST transport, and EZZK Settings UI

## Problem

Autogram currently stores an EZZK username and password, then uses an unverified legacy HTTP service contract. Reverse engineering of the authenticated EZZK portal established a different contract:

- API base: `https://ezzk.iomo.sk/api/zzkservice/v1`
- OAuth2 Bearer authentication through Keycloak
- Read-only evidence and history endpoints
- Consequential evidence-number generation and conversion submission endpoints
- `.asice` files sent as Base64 values inside a `files` JSON array

The native app must use the observed authentication model without storing browser session data or inventing a redirect registration. It must expose authenticated EZZK state in Settings while keeping submission fail-closed.

## Goals

- Add explicit sandbox and production EZZK environments with fixed endpoint identities.
- Authenticate through `ASWebAuthenticationSession` and OAuth2 authorization-code flow.
- Store access and refresh tokens only in Keychain.
- Provide a serialized typed REST client with one refresh and one retry after `401`.
- Expose read-only EZZK operations and explicit consequential actions in the UI.
- Preserve local evidence records and audit data across logout.
- Prevent sandbox code from calling production and prevent unauthenticated POST operations.
- Keep unknown response shapes and unconfirmed native redirect configuration fail-closed.
- Retain the existing mock service for demo mode without allowing it to masquerade as sandbox or production.

## Non-goals

- No automatic generation of evidence numbers.
- No automatic conversion submission.
- No production enablement before the authority register contains the required EZZK production contract.
- No Safari cookie extraction, WKWebView login, copied browser session, or embedded credentials.
- No claim that a structurally valid local artifact is accepted by CEZZK.
- No replacement of the official P2E v1.3 form renderer in this workstream.
- No guessed native redirect URI. The known web redirect is recorded, but it is not treated as a valid native callback.

## Existing integration points

- `AppSettingsStore` currently rebuilds `MockEZZKService` or `HTTPSEZZKService` from username/password fields.
- `SettingsView.ezzkTab` currently edits IČO, username, password, notification email, and eDesk address.
- `ZakoSessionStore` consumes `EZZKServicing` for server time, evidence numbers, and submit.
- `EvidenceDashboardView` resubmits queued records through `EZZKServicing`.
- `EZZKService.swift` already defines `EZZKServerClock`, `EZZKEvidenceNumberProvider`, and `EZZKSubmissionTransport`.
- `KeychainStore` exists, but OAuth tokens require a dedicated namespace and Codable token record rather than the legacy password account.

The migration must keep demo behavior source-compatible while removing the legacy password flow from any sandbox or production path.

## Architecture

### Fixed environment identity

```swift
public enum EZZKEnvironment: String, Codable, CaseIterable, Sendable {
    case sandbox
    case production

    public var portalBaseURL: URL { get }
    public var apiBaseURL: URL { get }
    public var authorityID: String { get }
}
```

The sandbox base is `https://ezzk-test.iomo.sk`. The production base is `https://ezzk.iomo.sk`. The API path is fixed to `/api/zzkservice/v1`. Callers cannot construct an arbitrary endpoint by passing a URL string from Settings.

Production remains disabled until the authority register confirms its endpoint, registration prerequisites, authentication contract, submission contract, and release approval. The implementation may model production, but Settings must not allow a production session before those gates pass.

### OAuth configuration

```swift
public struct EZZKOAuthConfiguration: Sendable, Equatable {
    public let issuerURL: URL
    public let clientID: String
    public let redirectURI: URL
    public let callbackScheme: String
    public let scopes: [String]
}
```

The observed Keycloak issuer and client ID are:

- Issuer: `https://ezzk.iomo.sk/sso/auth/realms/ezzk`
- Client ID: `login-app`
- Observed web redirect: `https://ezzk.iomo.sk/portal`

Authorization and token endpoints are obtained from the issuer's OpenID Connect discovery metadata or an operator-confirmed configuration. The client must validate that both endpoints use HTTPS and belong to the configured issuer. Until the native redirect registration is confirmed, the login action returns a blocking configuration error rather than using the web redirect as a guessed callback.

### Token storage

```swift
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

The Keychain implementation uses a dedicated service and environment-specific accounts. Token values never enter `UserDefaults`, `AppSettings`, `ConversionRecordEnvelope`, ordinary logs, or exported evidence. Keychain failures are surfaced as authentication failures. Logout deletes the access token, refresh token, and expiry record for the selected environment.

### HTTP transport and client

```swift
public protocol EZZKHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public actor EZZKClient: EZZKServerClock, EZZKEvidenceNumberProvider, EZZKSubmissionTransport {
    public init(environment: EZZKEnvironment,
                oauth: EZZKOAuthConfiguration,
                tokenStore: any EZZKTokenStoring,
                transport: any EZZKHTTPTransport)
}
```

The client owns request construction, Bearer headers, token refresh, status mapping, JSON decoding, server date extraction, retry rules, and response receipt handling. The UI and `ZakoSessionStore` do not manipulate `URLRequest` or tokens.

The existing capability protocols remain the application boundary. The new client conforms to them only when the required response and submission models are authoritative enough for the selected environment.

## Data flow

### Login

1. Settings asks `EZZKSessionController.login()`.
2. The controller verifies that native redirect configuration exists for the selected environment.
3. It generates a cryptographically random state and PKCE verifier.
4. It starts `ASWebAuthenticationSession` with the Keycloak authorization endpoint.
5. It validates the returned callback state and authorization code.
6. It exchanges the code at the Keycloak token endpoint.
7. It validates token type and expiry, then stores the token set in Keychain.
8. It calls authenticated `GET /ec` as a read-only connectivity check.
9. It publishes the authenticated state and available evidence-number count.

Cancellation, invalid state, callback mismatch, token exchange failure, and Keychain failure all leave the app signed out or failed. They never create a partially authenticated service.

### Token refresh

Before an authenticated request, the client loads the token set. If the access token is expired or inside a small expiry safety window, it attempts one refresh. If a request returns `401`, it invalidates the access token, attempts one refresh, and retries the original request exactly once. A second `401` transitions the session to `expired`.

Concurrent requests share the actor and must not start parallel refresh operations. A failed refresh must not fall back to the legacy password service or mock service.

### Read-only API operations

The first client increment supports these operations:

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/ec` | Available evidence numbers |
| `GET` | `/ec/consumed` | Consumed evidence numbers |
| `GET` | `/zzk/{evidenceNumber}` | Conversion record |
| `GET` | `/zzk/{evidenceNumber}/original` | Original artefact |
| `GET` | `/zzk?...` | History query |

`serverTime()` uses the HTTP `Date` header from an authenticated read-only response. Missing or invalid server time is an error. Local time is never used as a sandbox or production fallback.

### Consequential API operations

Evidence-number generation uses `POST /ec`. Conversion submission uses `POST /zzk`. Both are explicit client methods and require an authorization context supplied by the user-facing action.

The upload model is:

```swift
public struct EZZKFilePayload: Codable, Sendable, Equatable {
    public let fileName: String
    public let fileType: String
    public let value: String
}

public struct EZZKFilesRequest: Codable, Sendable, Equatable {
    public let files: [EZZKFilePayload]
}
```

The observed `.asice` MIME type is `application/vnd.etsi.asic-e+zip`. The client rejects non-ASiC-E input before encoding. The submission layer must receive the signed clause and record ASiC files from the validated conversion pipeline. It must not regenerate or mutate them.

Until the complete POST response and receipt schema is confirmed in the EZZK sandbox, an unknown response is an error and cannot produce a submitted state. No automatic submit retry is allowed.

## Session controller and UI

```swift
public enum EZZKSessionState: Equatable, Sendable {
    case signedOut
    case authenticating
    case authenticated(environment: EZZKEnvironment, availableEvidenceNumbers: Int)
    case expired
    case failed(String)
}
```

`EZZKSessionController` is `@MainActor` and owns the UI-facing state. It provides:

- `login()`
- `logout()`
- `refresh()`
- `testConnection()`
- `requestEvidenceNumbers(count:)`
- `submit(...)`

Settings changes cannot replace an active client during a conversion. Environment selection and provider capability are locked while a conversion session is active.

The EZZK Settings tab will show:

- environment picker with Sandbox selected by default,
- current session state,
- `Prihlásiť cez EZZK`, `Obnoviť session`, and `Odhlásiť` actions,
- read-only portal and API endpoint identity,
- last connectivity check and available number count,
- explicit evidence-number request action with count confirmation,
- clear sandbox and production status labels.

The legacy IČO, username, and password fields are no longer used for OAuth authentication. Existing notification email and eDesk fields remain only if the confirmed EZZK submission contract requires them. They must not affect token acquisition.

When the native redirect is not registered, the login control is disabled and the UI explains that EZZK operator configuration is required. The UI must not suggest that Safari login automatically authenticates Autogram.

## Error and retry policy

- `400`, `422`: request validation failure, no retry.
- `401`: one token refresh and one original-request retry, then `expired`.
- `403`: authorization failure, no retry.
- `409`: permanent evidence-number or record collision, no retry.
- `408`, `429`, `5xx`, and timeout: retry only read-only operations with bounded exponential backoff.
- Submit never retries automatically after a transport uncertainty.
- Unknown status, malformed JSON, missing required response fields, and missing server `Date`: `invalidResponse` or a typed transport error.
- Missing redirect configuration: `authenticationUnavailable`.
- Keychain failure: `tokenStorageFailure`.
- No error path changes a local record to `submitted` without an authoritative successful receipt.

Errors exposed to users must be Slovak. Diagnostic details may be retained in memory for the current Settings screen but must not include tokens, authorization codes, passwords, or full request bodies.

## Tests and acceptance

Tests are written before production implementation for each component.

### Token and OAuth tests

- Keychain save, load, delete, environment separation, expiry, and storage failure.
- PKCE and state generation properties.
- Successful callback and token exchange.
- User cancellation, invalid state, wrong callback scheme, and token endpoint rejection.
- One refresh after an expired token.
- One refresh and one retry after `401`.
- No infinite refresh loop.
- No fallback to password, mock, local time, or production endpoint.

### REST client tests

- Exact sandbox and production URL construction.
- Bearer header and content type.
- `/ec` response decoding, including the observed empty response.
- Read-only server `Date` extraction.
- `.asice` payload encoding and rejection of other MIME types.
- Status mapping and bounded read-only retry.
- Unknown response and missing receipt remain failures.
- Production client is unavailable until its authority gate is satisfied.

### UI and integration tests

- Settings displays each session state.
- Login is blocked without native redirect configuration.
- Sandbox is the default environment.
- Logout removes tokens but preserves local evidence records.
- Explicit evidence-number request requires user action.
- Explicit submit requires validated signed artefacts and confirmation.
- Active conversion prevents environment and client replacement.
- Demo mode continues to use the mock service without being represented as sandbox or production.

### Acceptance boundary

This workstream is complete when native authentication, typed client behavior, UI session state, and all listed local tests pass. It is not production-ready until EZZK confirms native redirect registration, the sandbox POST response and receipt contract are captured, a sandbox account completes a real non-production smoke test, and the authority register is updated with those artifacts.

## Open external blockers

1. EZZK operator must confirm a native redirect URI or custom callback scheme for client `login-app`.
2. EZZK sandbox registration and test account must be provided.
3. Full `POST /ec` request and response contract must be confirmed in sandbox.
4. Full `POST /zzk` request, response receipt, error, retry, and idempotency contract must be confirmed in sandbox.
5. Production endpoint and release authorization must be recorded in the authority register before production selection is enabled.
