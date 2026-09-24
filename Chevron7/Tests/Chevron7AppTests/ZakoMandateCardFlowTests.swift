// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
import Chevron7Kit
@testable import Chevron7App

/// ZaKo only with a mandate certificate: the card comes before a real evidence number
/// and before the authorization, and its PIN is asked for once per app run.
@MainActor
final class ZakoMandateCardFlowTests: XCTestCase {
    private static let mandateLabel = "Marián Čuprík OPRÁVNENIE 1042"

    private func makeStore(provider: CardFlowProvider,
                           card: MandateCertificate.CardState) -> ZakoSessionStore {
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in ScriptedTransport([]) },
                                               productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.useRealSigningProvider(provider)
        let store = ZakoSessionStore(settingsStore: settingsStore)
        store.readMandateCardState = { card }
        return store
    }

    func testNoCardAsksForTheCardBeforeANumber() async {
        let store = makeStore(provider: CardFlowProvider(cardInserted: false), card: .noCard)

        await store.requestEvidenceNumber()

        XCTAssertEqual(store.cardPrompt, .insertCard)
        XCTAssertEqual(store.pendingCardAction, .evidenceNumber)
        XCTAssertFalse(store.fetchingEvidenceNumber)
    }

    func testCardWithoutMandateGetsNoNumber() async {
        let store = makeStore(provider: CardFlowProvider(), card: .noMandate(labels: ["Marián Čuprík"]))

        await store.requestEvidenceNumber()

        XCTAssertNil(store.cardPrompt)
        XCTAssertEqual(store.evidenceNumberError, ZakoSessionStore.noMandateMessage)
        XCTAssertNil(store.attestation.evidenceNumber)
    }

    /// The MQC seen without a PIN is enough for the number; the PIN waits for the signature.
    func testMandateSeenWithoutPINLetsTheNumberThrough() async {
        let provider = CardFlowProvider()
        let store = makeStore(provider: provider, card: .mandate(label: Self.mandateLabel))

        await store.requestEvidenceNumber()

        XCTAssertNil(store.cardPrompt)
        XCTAssertNil(store.pendingCardAction)
        XCTAssertEqual(provider.resolvedPINs, [])
        XCTAssertNotEqual(store.evidenceNumberError, ZakoSessionStore.noMandateMessage)
        XCTAssertNotEqual(store.evidenceNumberError, ZakoSessionStore.insertMandateCardMessage)
    }

    func testFetchingDirectlyWithoutTheCardIsRefused() async {
        let store = makeStore(provider: CardFlowProvider(cardInserted: false), card: .noCard)

        await store.fetchEvidenceNumber()

        XCTAssertEqual(store.evidenceNumberError, ZakoSessionStore.insertMandateCardMessage)
    }

    func testAuthorizationAsksForThePINAndSelectsTheMandateCertificate() async {
        let provider = CardFlowProvider()
        let store = makeStore(provider: provider, card: .mandate(label: Self.mandateLabel))

        await store.beginAuthorization()
        XCTAssertEqual(store.cardPrompt, .enterPIN)

        await store.submitCardPIN("1234")

        XCTAssertEqual(provider.resolvedPINs, ["1234"])
        XCTAssertNil(store.cardPrompt)
        XCTAssertEqual(store.selectedIdentityID, CardFlowProvider.mandate.id)
        XCTAssertEqual(store.signingPIN, "1234")
    }

    /// A refused PIN is asked for again and never retried on its own.
    func testWrongPINIsForgottenAndAskedAgain() async {
        let provider = CardFlowProvider()
        let store = makeStore(provider: provider, card: .mandate(label: Self.mandateLabel))
        await store.beginAuthorization()

        await store.submitCardPIN("0000")

        XCTAssertEqual(store.cardPrompt, .enterPIN)
        XCTAssertEqual(store.signingPIN, "")
        XCTAssertEqual(provider.resolvedPINs, ["0000"])
    }

    func testResolvedCardWithoutMandateIsRefusedAtAuthorization() async {
        let provider = CardFlowProvider(resolved: [CardFlowProvider.plain])
        let store = makeStore(provider: provider, card: .noCard)
        await store.beginAuthorization()

        await store.submitCardPIN("1234")

        XCTAssertNil(store.cardPrompt)
        XCTAssertEqual(store.lastError, ZakoSessionStore.noMandateMessage)
    }

    /// Straight to `authorizeAndSign` with a qualified certificate that is not an MQC.
    func testAuthorizeAndSignRefusesANonMandateCertificate() async {
        let store = makeStore(provider: CardFlowProvider(), card: .noCard)
        store.identities = [CardFlowProvider.plain]
        store.selectedIdentityID = CardFlowProvider.plain.id

        await store.authorizeAndSign()

        XCTAssertEqual(store.lastError, ZakoSessionStore.noMandateMessage)
        XCTAssertFalse(store.requiresMandateOverride, "a real card gets no override")
    }

    func testPINOutlivesANewDocumentButNotTheCard() {
        let store = makeStore(provider: CardFlowProvider(), card: .noCard)
        store.signingPIN = "1234"

        store.resetSession(keepingProfile: true)
        XCTAssertEqual(store.signingPIN, "1234")

        store.applyReaderIdentities([])
        XCTAssertEqual(store.signingPIN, "")
    }
}

/// A card reader as the engine reports it: a card before the PIN, its certificates after.
private final class CardFlowProvider: QualifiedSigningProviding, @unchecked Sendable {
    static let synthetic = SigningIdentityInfo(id: "engine:ica", label: "Karta pripojená: I.CA",
                                               issuerSummary: "Zadajte PIN", isQualified: true,
                                               requiresPIN: true)
    static let mandate = SigningIdentityInfo(id: "engine-cert:1", label: "Marián Čuprík OPRÁVNENIE 1042",
                                             issuerSummary: "I.CA EU Qualified CA-SK", isMandateCertificate: true,
                                             isQualified: true, requiresPIN: true)
    static let plain = SigningIdentityInfo(id: "engine-cert:2", label: "Marián Čuprík",
                                           issuerSummary: "I.CA EU Qualified CA-SK", isQualified: true,
                                           requiresPIN: true)

    private let lock = NSLock()
    private let cardInserted: Bool
    private let resolved: [SigningIdentityInfo]
    private var unlocked = false
    private var pins: [String] = []

    init(cardInserted: Bool = true, resolved: [SigningIdentityInfo] = [mandate, plain]) {
        self.cardInserted = cardInserted
        self.resolved = resolved
    }

    var resolvedPINs: [String] { lock.withLock { pins } }

    func availableIdentities() async -> [SigningIdentityInfo] {
        guard cardInserted else { return [] }
        return lock.withLock { unlocked } ? resolved : [Self.synthetic]
    }

    func resolveIdentities(pin: String) async -> [SigningIdentityInfo]? {
        lock.withLock { pins.append(pin) }
        guard pin == "1234" else { return nil }
        lock.withLock { unlocked = true }
        return resolved
    }

    func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        throw SigningError.signingFailed("not used")
    }
}
