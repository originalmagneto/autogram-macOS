# EZZK part B3: production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow evidence number allocation and record submission on production EZZK, first only on the owner's Mac through a hidden switch, and for everyone after the owner's first live conversion is processed.

**Architecture:** One value type, `EZZKProductionPolicy` (Chevron7Kit), decides whether consequential EZZK calls (allocation, consumption, submission) may run on production. The SOAP client and adapter read it instead of their hard refusals; the app's account controller creates it from a `defaults` key and hands it to every client, the status checker, the Register and Done presentations and Settings. Tasks 1 to 6 merge with production still refused for everyone; Task 7 flips one constant after the owner's live check.

**Tech Stack:** Swift 6, SwiftUI (macOS 27), XCTest, Ditec WCF SOAP (EZZK).

**Spec:** `Chevron7/docs/superpowers/specs/2026-09-23-ezzk-part-b-design.md` (sections "Delivery in three parts", "Rollout", "Revision 5: B2 amendments"; rev 5 wins).

## Global Constraints

- Every `feat`/`fix`/`perf` push to `main` publishes a release: after Tasks 1 to 6 production allocation and submission stay refused for everyone except a Mac with the owner switch set.
- Owner switch: `defaults write app.slovensko.chevron7 EZZKProductionOwnerSwitch -bool YES` (no UI); `defaults delete app.slovensko.chevron7 EZZKProductionOwnerSwitch` turns it off. Read when a client is created, so a change needs an app relaunch.
- `EZZKProductionPolicy` defaults to refused wherever it is a parameter, so no test and no forgotten call site can reach production.
- The legacy OAuth client (`EZZKSessionController`, `EZZKClient`) stays untouched.
- "Vyžiadať čísla" in Settings stays test only: a production number that no record uses lapses at midnight and breaks the 24-hour reporting duty.
- `ezzk-probe` keeps refusing `numbers`, `consume` and `receive` on production (ruling: production submission goes only through the app, where the register records it); `lookup` and `record` stay read-only as today.
- Tests never touch the real `~/Library/Application Support/Chevron7`, `~/Library/Caches/Chevron7` or the Keychain (`makeSettingsStore()`, `MemoryCredentialStore`, scripted transports).
- Build and test from `Chevron7/`: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- English code comments, Slovak UI strings, no em dash (U+2014) anywhere, `CLAUDE.md` and `AGENTS.md` at the repo root byte-identical.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push, never `git stash`.

## Review Focus

1. The owner switch is removed after production rows exist: the checker must neither send nor look them up, and the Register must say why (test in Task 2).
2. Production mode with the Demo signing provider (no bundled engine or no card identity): nothing may be allocated or sent, because a production number without a record lapses at midnight (test in Task 3).
3. A production row whose lookup returns 106 must settle instead of being looked up every hour forever (test in Task 4).
4. Deleting a Register row while ZaKo still signs its record must not bring the row back (test in Task 5).
5. A policy constructed anywhere without the key (tests, probe, previews) must refuse production (test in Task 1).

---

### Task 1: `EZZKProductionPolicy` in the SOAP client and adapter

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/EZZK/EZZKProductionPolicy.swift`
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPClient.swift` (init ~41, `perform` ~152-159)
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPServiceAdapter.swift` (~26, ~44)
- Test: `Chevron7/Tests/Chevron7KitTests/EZZKProductionPolicyTests.swift` (new)

**Interfaces:**
- Produces: `public struct EZZKProductionPolicy: Sendable, Equatable` with `allowsConsequentialCalls: Bool`, `static let refused`, `static let allowed`, `static let enabledForEveryone: Bool` (false), `static let ownerSwitchKey = "EZZKProductionOwnerSwitch"`, `static func current(defaults: UserDefaults) -> EZZKProductionPolicy`, `func refusal(environment: EZZKEnvironment, submitting: Bool) -> EZZKError?`. `EZZKSOAPClient.init(..., productionPolicy: EZZKProductionPolicy = .refused)` and `public nonisolated let productionPolicy`.

- [ ] **Step 1: Write the failing tests**

```swift
// Chevron7/Tests/Chevron7KitTests/EZZKProductionPolicyTests.swift
import XCTest
@testable import Chevron7Kit

final class EZZKProductionPolicyTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "EZZKProductionPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testWithoutTheOwnerSwitchProductionIsRefused() {
        let policy = EZZKProductionPolicy.current(defaults: defaults())
        XCTAssertFalse(EZZKProductionPolicy.enabledForEveryone)
        XCTAssertEqual(policy, .refused)
        XCTAssertEqual(policy.refusal(environment: .production, submitting: false), .productionAllocationDisabled)
        XCTAssertEqual(policy.refusal(environment: .production, submitting: true), .submissionUnavailable)
        XCTAssertNil(policy.refusal(environment: .sandbox, submitting: true))
    }

    func testTheOwnerSwitchAllowsProduction() {
        let store = defaults()
        store.set(true, forKey: EZZKProductionPolicy.ownerSwitchKey)
        let policy = EZZKProductionPolicy.current(defaults: store)
        XCTAssertEqual(policy, .allowed)
        XCTAssertNil(policy.refusal(environment: .production, submitting: true))
    }

    func testClientDefaultsToRefusedAndSendsNothingOnProduction() async throws {
        let transport = ScriptedTransport([])
        let client = EZZKSOAPClient(environment: .production, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "a", password: "b") })
        XCTAssertEqual(client.productionPolicy, .refused)
        do {
            _ = try await client.evidenceNumbers(for: EZZKPerson(corporateBodyFullName: "Advokát", ico: "12345678"))
            XCTFail("production allocation must be refused")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .productionAllocationDisabled)
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testAllowedClientReachesProductionForAllocation() async throws {
        let transport = ScriptedTransport([Fixtures.loginSucceeded, Fixtures.numbersReply])
        let client = EZZKSOAPClient(environment: .production, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "a", password: "b") },
                                    productionPolicy: .allowed)
        let numbers = try await client.evidenceNumbers(for: EZZKPerson(corporateBodyFullName: "Advokát", ico: "12345678"))
        XCTAssertEqual(numbers, ["260917-A"])
        XCTAssertEqual(transport.requestCount, 2)
    }
}
```

Use the Kit test doubles that already exist for the SOAP client (look in `Chevron7/Tests/Chevron7KitTests/` for the scripted transport and the login/number reply fixtures used by `EZZKSOAPClientTests`; reuse their names instead of `ScriptedTransport`/`Fixtures` if they differ, and keep `EZZKError` `Equatable` comparisons as those tests do). If the production transport pins or rejects in tests, construct the client exactly as the existing sandbox tests do, with `environment: .production`.

- [ ] **Step 2: Run them to see them fail**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter EZZKProductionPolicyTests`
Expected: FAIL to compile (`EZZKProductionPolicy` not defined).

- [ ] **Step 3: Implement the policy**

```swift
// Chevron7/Sources/Chevron7Kit/EZZK/EZZKProductionPolicy.swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Whether consequential EZZK calls (allocating or consuming an evidence number, sending a
/// record) may run on production. Read-only calls (login, server time, lookup) never need it.
/// Refused unless production is enabled for everyone or the owner switch is set on this Mac:
/// `defaults write app.slovensko.chevron7 EZZKProductionOwnerSwitch -bool YES`. The switch only
/// unlocks calls with the EZZK account the person already signed in with, so it grants nobody
/// access they do not have.
public struct EZZKProductionPolicy: Sendable, Equatable {
    /// Flipped to true by the release that enables production for everyone, after the owner's
    /// first live production conversion was processed (spec "Rollout", step 3).
    public static let enabledForEveryone = false
    public static let ownerSwitchKey = "EZZKProductionOwnerSwitch"

    public let allowsConsequentialCalls: Bool

    public init(allowsConsequentialCalls: Bool) {
        self.allowsConsequentialCalls = allowsConsequentialCalls
    }

    public static let refused = EZZKProductionPolicy(allowsConsequentialCalls: false)
    public static let allowed = EZZKProductionPolicy(allowsConsequentialCalls: true)

    public static func current(defaults: UserDefaults) -> EZZKProductionPolicy {
        EZZKProductionPolicy(allowsConsequentialCalls: enabledForEveryone || defaults.bool(forKey: ownerSwitchKey))
    }

    /// The error a consequential call gets, or nil when it may run.
    public func refusal(environment: EZZKEnvironment, submitting: Bool) -> EZZKError? {
        guard environment == .production, !allowsConsequentialCalls else { return nil }
        return submitting ? .submissionUnavailable : .productionAllocationDisabled
    }
}
```

- [ ] **Step 4: Read it in the client and the adapter**

In `EZZKSOAPClient`, add `public nonisolated let productionPolicy: EZZKProductionPolicy`, an init parameter `productionPolicy: EZZKProductionPolicy = .refused` (last parameter, after `now:`), and replace the hard refusal in `perform`:

```swift
        // Consequential calls on production run only when the production policy allows them:
        // otherwise no login and no network use, whatever the transport would reply.
        if request.isConsequential,
           let refusal = productionPolicy.refusal(environment: environment,
                                                  submitting: request.operation == EZZKSOAPRequest.receiveOperation) {
            throw refusal
        }
```

In `EZZKSOAPServiceAdapter.requestEvidenceNumbers` and `submit`, replace `guard client.environment != .production else { throw ... }` with:

```swift
        if let refusal = client.productionPolicy.refusal(environment: client.environment, submitting: false) { throw refusal }
```

(and `submitting: true` in `submit`). Update the adapter's comment above `requestEvidenceNumbers`: production numbers are allocated only when the production policy allows sending, because an unused production number lapses at midnight.

- [ ] **Step 5: Run the Kit tests**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "EZZKProductionPolicyTests|EZZKSOAPClientTests|EZZKSOAPServiceAdapter"`
Expected: PASS (existing production-refusal tests keep passing because the default is `.refused`).

- [ ] **Step 6: Commit**

```bash
git add Chevron7/Sources/Chevron7Kit/EZZK/EZZKProductionPolicy.swift Chevron7/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPClient.swift Chevron7/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPServiceAdapter.swift Chevron7/Tests/Chevron7KitTests/EZZKProductionPolicyTests.swift
git commit -m "feat(ezzk): one production policy decides allocation and submission on production"
```

---

### Task 2: The app reads the policy everywhere

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/EZZK/EZZKAccountController.swift` (init, clients at ~93 and ~152, `requestTestNumbers` ~137)
- Modify: `Chevron7/Sources/Chevron7App/AppSettingsStore.swift` (~29, status checker)
- Modify: `Chevron7/Sources/Chevron7App/EZZK/EZZKStatusChecker.swift` (~99, ~115-126, ~210, ~290, ~350)
- Modify: `Chevron7/Sources/Chevron7App/EZZK/EZZKRecordPresentation.swift` (`ZakoDonePresentation.init` ~133 and ~184; `actions(for:currentMode:)` ~324 and ~342)
- Modify: `Chevron7/Sources/Chevron7App/Views/AuthorizeDoneViews.swift` (~473), `Chevron7/Sources/Chevron7App/Views/EvidenceDashboardView.swift` (callers of `actions`), `Chevron7/Sources/Chevron7App/Views/SettingsView.swift` (~685 `ezzkModeExplanation`, ~921 numbers card, `ezzkSubmissionStatus`)
- Test: `Chevron7/Tests/Chevron7AppTests/EZZKProductionPolicyAppTests.swift` (new)

**Interfaces:**
- Consumes: `EZZKProductionPolicy` (Task 1), `EZZKSOAPClient.init(..., productionPolicy:)`.
- Produces: `EZZKAccountController.productionPolicy: EZZKProductionPolicy` (init parameter `productionPolicy: EZZKProductionPolicy = .current(defaults: .standard)`); `EZZKStatusChecker` reads `controller.productionPolicy.allowsConsequentialCalls` for `sendsInProduction`; `EZZKRecordPresentation.actions(for:currentMode:productionAllowed: Bool = false)`; `ZakoDonePresentation.init(..., productionAllowed: Bool = false)`.

- [ ] **Step 1: Write the failing tests**

```swift
// Chevron7/Tests/Chevron7AppTests/EZZKProductionPolicyAppTests.swift
import XCTest
import Chevron7Kit
@testable import Chevron7App

@MainActor
final class EZZKProductionPolicyAppTests: XCTestCase {
    private func productionRow(status: EvidenceRecord.Status) -> EvidenceRecord {
        var row = EvidenceRecord(status: status, direction: .paperToElectronic,
                                 originalName: "Zmluva", newDocumentName: "Zmluva.pdf",
                                 evidenceNumber: "260924-P1", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                 conversionTime: Date(), performingPersonName: "JUDr. Test Testovací",
                                 securityElementCount: 0, totalPages: 1, totalSheets: 1, ezzkMode: .production,
                                 evidenceNumberAllocatedAt: Date())
        row.recordContainerPath = "records/x.asice"
        return row
    }

    func testRegisterOffersProductionActionsOnlyWhenAllowed() {
        let queued = productionRow(status: .queuedForSubmission)
        let refused = EZZKRecordPresentation.actions(for: queued, currentMode: .production)
        XCTAssertFalse(refused.canSend)
        XCTAssertEqual(refused.note, EZZKError.submissionUnavailable.errorDescription)
        let allowed = EZZKRecordPresentation.actions(for: queued, currentMode: .production, productionAllowed: true)
        XCTAssertTrue(allowed.canSend)

        let accepted = productionRow(status: .acceptedForProcessing)
        XCTAssertTrue(EZZKRecordPresentation.actions(for: accepted, currentMode: .production, productionAllowed: true).canVerify)
    }

    func testControllerHandsItsPolicyToTheChecker() {
        let controller = EZZKAccountController(mode: .production, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in ScriptedTransport([]) },
                                               productionPolicy: .allowed)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        XCTAssertEqual(settingsStore.ezzkAccountController.productionPolicy, .allowed)
        XCTAssertNil(settingsStore.statusChecker.refusalReason(forMode: .production))
    }

    /// Review focus 1: a production row created under the owner switch is left alone once the
    /// switch is gone, and the Register says why.
    func testWithoutTheSwitchProductionRowsAreLeftAlone() {
        let controller = EZZKAccountController(mode: .production, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in ScriptedTransport([]) })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        XCTAssertEqual(settingsStore.ezzkAccountController.productionPolicy, .refused)
        XCTAssertEqual(settingsStore.statusChecker.refusalReason(forMode: .production), EZZKStatusChecker.productionRefusal)
    }
}
```

`refusalReason(forMode:)` is the small internal accessor this task adds to `EZZKStatusChecker` around its existing `if mode == .production, !sendsInProduction { return Self.productionRefusal }` (~350), so the refusal is testable without a network pass. `makeSettingsStore(ezzkAccountController:)` and `MemoryCredentialStore`, `ScriptedTransport` exist in `Chevron7/Tests/Chevron7TestSupport` / App tests; match their real names.

- [ ] **Step 2: Run them to see them fail**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter EZZKProductionPolicyAppTests`
Expected: FAIL to compile (`productionPolicy`, `productionAllowed`, `refusalReason` missing).

- [ ] **Step 3: Implement**

1. `EZZKAccountController`: add `let productionPolicy: EZZKProductionPolicy` and the init parameter `productionPolicy: EZZKProductionPolicy = .current(defaults: .standard)` (last parameter). Pass `productionPolicy: productionPolicy` to both `EZZKSOAPClient(...)` constructions. `requestTestNumbers` stays test only (Global Constraints); change nothing in its guard.
2. `EZZKStatusChecker`: in the convenience `init(evidenceStore:numberPool:controller:)` pass `sendsInProduction: controller.productionPolicy.allowsConsequentialCalls`; add
   ```swift
   /// The reason the checker leaves rows of this mode alone, or nil when it may act on them.
   func refusalReason(forMode mode: AppSettings.EZZKMode) -> String? {
       mode == .production && !sendsInProduction ? Self.productionRefusal : nil
   }
   ```
   and use it at the existing check (~350).
3. `EZZKRecordPresentation.actions`: add `productionAllowed: Bool = false`; the production branch becomes `if mode == .production, !productionAllowed { return Actions(canSend: false, canVerify: false, note: EZZKError.submissionUnavailable.errorDescription) }`. `ZakoDonePresentation.init`: add `productionAllowed: Bool = false`; `if mode == .production` becomes `if mode == .production, !productionAllowed`, and `isVerifiable(status), mode != .production` becomes `isVerifiable(status), mode != .production || productionAllowed`. Update the doc comments ("never in Production yet" becomes "in Production only when the production policy allows it").
4. Views: every caller of `actions(for:currentMode:)` and `ZakoDonePresentation(...)` passes `productionAllowed: settingsStore.ezzkAccountController.productionPolicy.allowsConsequentialCalls` (ZaKo: `store.settingsStore...` or the store's existing path to the settings store).
5. `SettingsView`:
   - `ezzkModeExplanation(.production)`: allowed: "Ostré EZZK: čísla aj záznamy majú právne účinky. Každá konverzia sa zapíše do centrálnej evidencie."; refused: keep "Ostré EZZK. Zatiaľ iba overenie prihlásenia, čas servera a vyhľadanie záznamu."
   - numbers card in production (~921): label "V produkcii sa evidenčné číslo získava iba v zaručenej konverzii." with the lock icon, whatever the policy.
   - `ezzkSubmissionStatus(.production)`: allowed: ("Zapnuté automaticky", "checkmark.circle", "Po autorizácii sa záznam o konverzii podpíše rovnakým PIN a hneď odošle do ostrého EZZK. Čakajúce odoslania a stav spracovania aplikácia overuje každých päť minút; výsledok je v Registri konverzií."); refused: keep today's text.

- [ ] **Step 4: Run the App tests**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "EZZKProductionPolicyAppTests|EZZKRecordPresentationTests|EZZKStatusChecker|EvidenceSubmissionFlowTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Chevron7/Sources/Chevron7App Chevron7/Tests/Chevron7AppTests/EZZKProductionPolicyAppTests.swift
git commit -m "feat(ezzk): the app follows the production policy in ZaKo, Register, checker and Settings"
```

---

### Task 3: Never allocate or send with the Demo signature outside Demo

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/ZakoSessionStore.swift` (`fetchEvidenceNumber` ~1041, `authorizeAndSign` start, `signingProviderIsDemo` ~1073)
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/EZZKService.swift` (new `EZZKError` case and message)
- Test: `Chevron7/Tests/Chevron7AppTests/ZakoEvidenceNumberTests.swift`

**Interfaces:**
- Produces: `EZZKError.demoSignatureOutsideDemo` with the message "Bez podpisového enginu alebo karty aplikácia podpisuje iba ukážkovo (Demo). Mimo režimu Demo preto nepridelí evidenčné číslo ani neodošle záznam. Vložte kartu SAK a skontrolujte inštaláciu Chevron7."

- [ ] **Step 1: Write the failing tests** (append to `ZakoEvidenceNumberTests`)

```swift
    /// Review focus 2: outside Demo, the Demo signing provider must not cost a real number.
    func testDemoSignatureOutsideDemoAllocatesNothing() async throws {
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.useRealSigningProvider(DemoSigningProvider())
        let store = ZakoSessionStore(settingsStore: settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertNil(store.attestation.evidenceNumber)
        XCTAssertEqual(store.evidenceNumberError, EZZKError.demoSignatureOutsideDemo.errorDescription)
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testDemoSignatureOutsideDemoIsNotAuthorized() async throws {
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.useRealSigningProvider(DemoSigningProvider())
        let store = ZakoSessionStore(settingsStore: settingsStore)
        store.attestation.evidenceNumber = "260924-X"
        store.attestation.evidenceNumberMode = .test
        store.attestation.evidenceNumberAllocatedAt = Date()

        await store.authorizeAndSign()

        XCTAssertNil(store.result)
        XCTAssertEqual(store.lastError, EZZKError.demoSignatureOutsideDemo.errorDescription)
        XCTAssertEqual(transport.requestCount, 0)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoEvidenceNumberTests`
Expected: FAIL (`demoSignatureOutsideDemo` missing).

- [ ] **Step 3: Implement**

Add `case demoSignatureOutsideDemo` to `EZZKError` with the message above (and map it in `EZZKSubmissionCoordinator`'s exhaustive switches with the "nothing was sent" group). In `ZakoSessionStore.fetchEvidenceNumber`, right after the register load check:

```swift
        // Outside Demo a real number must be backed by a real signature: the Demo signing
        // provider (no bundled engine or no card identity) would leave it without a record.
        if mode != .demo, signingProviderIsDemo {
            evidenceNumberError = EZZKError.demoSignatureOutsideDemo.errorDescription
            lastError = evidenceNumberError
            recomputePreflight()
            return
        }
```

(compute `mode` before this check, moving the existing `let mode = settingsStore.ezzkAccountController.mode` up). At the start of `authorizeAndSign`, before any signing or EZZK work and after the existing evidence-number mode check, refuse the same way with `lastError`. Keep the phone route (`viaMobile`) rule as it is (Demo only).

- [ ] **Step 4: Run the tests**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "ZakoEvidenceNumberTests|ZakoRecordRouteTests"`
Expected: PASS. `ZakoRecordRouteTests` outside-Demo tests must use a non-Demo signing double; if one currently uses `DemoSigningProvider` outside Demo on purpose, switch it to the existing scripted signing double in that file and note it in the report.

- [ ] **Step 5: Commit**

```bash
git add Chevron7/Sources/Chevron7App/ZakoSessionStore.swift Chevron7/Sources/Chevron7Kit/EZZK Chevron7/Tests/Chevron7AppTests
git commit -m "fix(zako): never allocate or send with the Demo signature outside Demo"
```

---

### Task 4: A lookup result 106 settles

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/EZZKSubmissionCoordinator.swift` (protocol `EZZKRecordLookingUp`, `EZZKRecordLookupFunction`, lookup handling in `resolveUnknown` ~123 and `refreshStatus` ~161)
- Modify: `Chevron7/Sources/Chevron7App/EZZK/EZZKStatusChecker.swift` (~146-153), `Chevron7/Sources/Chevron7App/EZZK/EZZKAccountController.swift` (`lookUp(evidenceNumber:in:)` gains `executionTime: Date? = nil`)
- Test: `Chevron7/Tests/Chevron7KitTests/` coordinator tests (the file holding `testLookupResult106KeepsAnAcceptedRowAccepted`)

**Interfaces:**
- Produces: `EZZKRecordLookingUp.publicRecord(evidenceNumber: String, executionTime: Date?) async throws -> EZZKRecordLookup`; `EZZKRecordLookupFunction.init(_ lookup: @escaping @Sendable (String, Date?) async throws -> EZZKRecordLookup)`.

- [ ] **Step 1: Write the failing test** (next to `testLookupResult106KeepsAnAcceptedRowAccepted`)

```swift
    /// Review focus 3: 106 means several records share the number; EZZK tells them apart by
    /// the conversion time, so the coordinator asks once more with it and settles the row.
    func testLookupResult106AsksAgainWithTheConversionTime() async throws {
        let conversionTime = Date(timeIntervalSince1970: 1_790_000_000)
        let calls = LockedCalls()
        let lookup = EZZKRecordLookupFunction { number, executionTime in
            await calls.append(executionTime)
            if executionTime == nil { throw EZZKError.serviceRejected(code: 106, message: "viac záznamov") }
            return EZZKRecordLookup(isProcessed: true, info: nil)
        }
        var row = acceptedRow(number: "260924-P1")
        row.conversionTime = conversionTime
        let coordinator = makeCoordinator(lookup: lookup)

        let updated = try await coordinator.refreshStatus(row)

        XCTAssertEqual(updated.status, .processed)
        let recorded = await calls.values
        XCTAssertEqual(recorded, [nil, conversionTime])
    }
```

Reuse the file's existing helpers for an accepted row and a coordinator; `LockedCalls` is a small actor in the test file (`actor LockedCalls { var values: [Date?] = []; func append(_ v: Date?) { values.append(v) } }`). Match how the existing 106 test signals 106 (thrown `serviceRejected(code: 106, ...)` or a lookup result); do the same.

- [ ] **Step 2: Run it to see it fail**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testLookupResult106AsksAgainWithTheConversionTime`
Expected: FAIL to compile (closure takes one argument).

- [ ] **Step 3: Implement**

Change the protocol and wrapper to carry `executionTime: Date?`. In the coordinator's lookup step, when the result is 106 and the call was made without an execution time, repeat it once with `record.conversionTime` and use that result; if the repeat is 106 again, keep today's R17 handling (accepted, code and text kept). The app's checker closure passes the time through: `EZZKRecordLookupFunction { number, time in try await controller.lookUp(evidenceNumber: number, in: mode, executionTime: time) }`; `EZZKAccountController.lookUp(evidenceNumber:in:executionTime:)` calls `publicRecord(evidenceNumber:executionTime:)`. The Demo closure ignores the time. Update every other implementer of `EZZKRecordLookingUp` in tests.

- [ ] **Step 4: Run the tests**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "Coordinator|EvidenceSubmissionFlowTests|EZZKStatusChecker"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Chevron7/Sources Chevron7/Tests
git commit -m "fix(ezzk): a lookup that returns 106 asks again with the conversion time"
```

---

### Task 5: Register safety and wording

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/EZZK/EZZKStatusChecker.swift` (`delete(id:)` ~335)
- Modify: `Chevron7/Sources/Chevron7App/Views/EvidenceDashboardView.swift` (~179, ~528)
- Modify: `Chevron7/Sources/Chevron7App/EZZK/EZZKRecordPresentation.swift` (`resendConfirmation` ~356)
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/EZZKService.swift` (`outcomeUnknown` message ~111)
- Test: `Chevron7/Tests/Chevron7AppTests/EvidenceSubmissionFlowTests.swift` (or the file holding `testDeletingARowDropsItsNumberFromThePool`), `EZZKRecordPresentationTests.swift`

**Interfaces:**
- Produces: `EZZKStatusChecker.delete(id:) -> Bool` (`@discardableResult`, false when the row is busy); `static let busyDeleteMessage = "Riadok sa práve spracúva (podpis alebo odoslanie záznamu). Vymažte ho, keď sa spracovanie skončí."`

- [ ] **Step 1: Write the failing tests**

```swift
    /// Review focus 4: a row ZaKo still signs cannot be deleted, so the later write cannot
    /// bring it back.
    func testDeletingAHeldRowIsRefused() {
        let settingsStore = makeSettingsStore()
        let row = EvidenceRecord(status: .signed, direction: .paperToElectronic,
                                 originalName: "Zmluva", newDocumentName: "Zmluva.pdf",
                                 evidenceNumber: "260924-H", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                 conversionTime: Date(), performingPersonName: "JUDr. Test Testovací",
                                 securityElementCount: 0, totalPages: 1, totalSheets: 1, ezzkMode: .test,
                                 evidenceNumberAllocatedAt: Date())
        settingsStore.evidenceStore.upsert(row)
        XCTAssertTrue(settingsStore.statusChecker.hold(row.id))

        XCTAssertFalse(settingsStore.statusChecker.delete(id: row.id))
        XCTAssertNotNil(settingsStore.evidenceStore.record(id: row.id))

        settingsStore.statusChecker.release(row.id)
        XCTAssertTrue(settingsStore.statusChecker.delete(id: row.id))
        XCTAssertNil(settingsStore.evidenceStore.record(id: row.id))
    }
```

```swift
    func testResendConfirmationMentionsALateRecord() {
        var row = rejectedAtSubmissionRow() // the helper the existing resend tests use
        row.evidenceNumberAllocatedAt = Date(timeIntervalSinceNow: -3 * 24 * 3600)
        let text = EZZKRecordPresentation.resendConfirmation(for: row)
        XCTAssertTrue(text.contains(EZZKRecordPresentation.lateWarning), text)
    }

    func testOutcomeUnknownNamesAServerFaultToo() {
        let text = EZZKError.outcomeUnknown.errorDescription ?? ""
        XCTAssertTrue(text.contains("chyba servera"), text)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "testDeletingAHeldRowIsRefused|testResendConfirmationMentionsALateRecord|testOutcomeUnknownNamesAServerFaultToo"`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
    /// Deletes a register row ("Vymazať z evidencie") and drops its number from the pool,
    /// so a deleted row's number is never offered to a new conversion. A row ZaKo still
    /// signs or the checker still sends is refused: its later write would bring it back.
    @discardableResult
    func delete(id: UUID) -> Bool {
        guard !isBusy(id) else { return false }
        if let number = evidenceStore.record(id: id)?.evidenceNumber {
            numberPool.remove(number)
        }
        evidenceStore.delete(id: id)
        changeCount += 1
        return true
    }
```

In both `EvidenceDashboardView` call sites show `EZZKStatusChecker.busyDeleteMessage` in the existing error line when `delete` returns false, and disable the delete action while `statusChecker.isBusy(record.id)`. In `resendConfirmation`, when `record.evidenceNumberAllocatedAt` is set and `!EZZKEvidenceNumberPolicy.isUsable(allocatedAt:at: Date())`, append " " + `lateWarning` to the question. Change the `outcomeUnknown` message to: "EZZK neodpovedalo zrozumiteľne (prerušené spojenie alebo chyba servera) a nie je isté, či požiadavku spracovalo. Pred opakovaním overte stav v EZZK." and update any test that pins the old text.

- [ ] **Step 4: Run the full suite**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS (report the Kit and App counts).

- [ ] **Step 5: Commit**

```bash
git add Chevron7/Sources Chevron7/Tests
git commit -m "fix(register): refuse deleting a row in progress, warn about lateness on resend, name server faults"
```

---

### Task 6: Owner switch documentation and the live production recipe

**Files:**
- Modify: `Chevron7/docs/EZZK-INTEGRATION.md` (new section "Production and the owner switch")
- Modify: `Chevron7/docs/P2E-EZZK-FINDINGS.md` (new "Part B3" section with the live recipe, result "not yet run")
- Modify: `CLAUDE.md` and `AGENTS.md` (EZZK bullet: `EZZKProductionPolicy`, owner switch key, `enabledForEveryone`)

- [ ] **Step 1: Write the docs**

EZZK-INTEGRATION.md section content (English):
- `EZZKProductionPolicy` decides consequential calls on production; read at the SOAP client, adapter, status checker, Register and Done presentations and Settings; tests and the probe default to refused.
- Owner switch: `defaults write app.slovensko.chevron7 EZZKProductionOwnerSwitch -bool YES`, relaunch Chevron7; off: `defaults delete app.slovensko.chevron7 EZZKProductionOwnerSwitch`.
- "Vyžiadať čísla" stays test only; `ezzk-probe` never allocates, consumes or sends on production.

P2E-EZZK-FINDINGS.md "Part B3" live recipe:
1. The owner sets the switch, relaunches, selects Produkcia in Settings and checks "Prihlásenie uložené" for the production account.
2. One real conversion the owner needs anyway (production is a legal record: never a synthetic or test document), with the SAK card; "Získať číslo", authorize.
3. Expected: Done screen "EZZK prijalo záznam na spracovanie"; `swift run ezzk-probe lookup <number> --env production` reports the record, later "Záznam je spracovaný"; `swift run ezzk-probe record <number> --env production --name "<EZZK name>" --ico <IČO> --out /tmp/prod-record.asice` returns the record byte-identical to the Register copy (compare with "Uložiť záznam…").
4. Result: not yet run.

- [ ] **Step 2: Check and commit**

Run: `cmp CLAUDE.md AGENTS.md && grep -c $'\\u2014' CLAUDE.md Chevron7/docs/EZZK-INTEGRATION.md Chevron7/docs/P2E-EZZK-FINDINGS.md`
Expected: identical, every count 0.

```bash
git add CLAUDE.md AGENTS.md Chevron7/docs/EZZK-INTEGRATION.md Chevron7/docs/P2E-EZZK-FINDINGS.md
git commit -m "docs(ezzk): production policy, owner switch and the live production recipe"
```

After Task 6 the branch merges to `main` (a release with production still refused for everyone). The owner then sets the switch and performs the live production conversion. Task 7 starts only after the lookup reports "Záznam je spracovaný".

---

### Task 7: Enable production for everyone (after the owner's live check)

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/EZZKProductionPolicy.swift` (`enabledForEveryone = true`)
- Modify: `Chevron7/Tests/Chevron7KitTests/EZZKProductionPolicyTests.swift`
- Modify: `README.md`, `CLAUDE.md`, `AGENTS.md`, `Chevron7/docs/EZZK-INTEGRATION.md`, `Chevron7/docs/P2E-EZZK-FINDINGS.md` (live result)
- Create: `docs/releases/vX.Y.0.md` (Slovak, detailed; version from `Chevron7/scripts/next-version.sh` after `git fetch --tags`)

- [ ] **Step 1: Update the tests first**

In `EZZKProductionPolicyTests`, `testWithoutTheOwnerSwitchProductionIsRefused` becomes `testProductionIsEnabledForEveryone`: `XCTAssertTrue(EZZKProductionPolicy.enabledForEveryone)` and `current(defaults:)` without the key returns `.allowed`. Keep `.refused` as the explicit default of `EZZKSOAPClient.init` and presentation parameters (tests stay isolated); the app's controller now gets `.allowed` from `current(defaults:)`.

- [ ] **Step 2: Run it to see it fail, flip the constant, run the full suite**

Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS after `enabledForEveryone = true`.

- [ ] **Step 3: Docs and release notes**

README (Slovak): production is enabled (Settings EZZK section, "Čo funguje kde", Obmedzenia); CLAUDE.md = AGENTS.md; EZZK-INTEGRATION.md: switch now only matters for older builds; P2E: live production result with the evidence number and dates. Release notes in Slovak, detailed: what production means for the advocate (real numbers, legal record, 24-hour duty, what the app does automatically, how to check in the Register, what to do on "Odmietnutý v EZZK" or "Výsledok odoslania neznámy"), requirements (own production EZZK account, SAK card, bundled engine), and that Demo and Test stay available.

- [ ] **Step 4: Commit**

```bash
git add -A Chevron7/Sources Chevron7/Tests README.md CLAUDE.md AGENTS.md Chevron7/docs docs/releases
git commit -m "feat(ezzk): enable production evidence numbers and record submission for everyone"
```

The owner decides the merge; merging publishes the release.
