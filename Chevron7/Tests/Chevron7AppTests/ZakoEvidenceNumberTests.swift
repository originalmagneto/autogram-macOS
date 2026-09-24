// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
import Chevron7Kit
@testable import Chevron7App

@MainActor
final class ZakoEvidenceNumberTests: XCTestCase {
    /// These tests are about the number pool and EZZK, so the reader holds a card with an MQC
    /// (ZaKo allocates a real number only for one).
    private func makeStoreWithMandateCard(_ settingsStore: AppSettingsStore) -> ZakoSessionStore {
        let store = ZakoSessionStore(settingsStore: settingsStore)
        store.readMandateCardState = { .mandate(label: "JUDr. Test Testovací OPRÁVNENIE 1") }
        return store
    }

    func testFetchedNumberRecordsItsAllocationTime() async {
        let settingsStore = makeSettingsStore()
        // Never reach EZZK from a unit test, whatever the developer selected in the app.
        settingsStore.ezzkAccountController.setMode(.demo)
        let store = makeStoreWithMandateCard(settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertNotNil(store.attestation.evidenceNumber)
        XCTAssertNotNil(store.attestation.evidenceNumberAllocatedAt)
        XCTAssertEqual(store.attestation.evidenceNumberMode, .demo)
    }

    /// A demo number must never reach a clause signed for EZZK. `authorizeAndSign` refuses it
    /// before any EZZK call; with no document loaded nothing past that check could run anyway.
    func testNumberFetchedInDemoIsRefusedAfterSwitchingToTest() async {
        // In-memory credentials and a transport with no replies: no Keychain, no network.
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .demo, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport }, productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        let store = makeStoreWithMandateCard(settingsStore)
        await store.fetchEvidenceNumber()
        XCTAssertNotNil(store.attestation.evidenceNumber)
        XCTAssertEqual(store.attestation.evidenceNumberMode, .demo)
        XCTAssertNil(store.evidenceNumberModeError)

        controller.setMode(.test)

        let refusal = EZZKError.evidenceNumberFromOtherMode.errorDescription
        XCTAssertNotNil(refusal)
        XCTAssertEqual(store.evidenceNumberModeError, refusal)
        await store.authorizeAndSign()
        XCTAssertEqual(store.evidenceNumberError, refusal)
        XCTAssertNil(store.result)
        XCTAssertNotEqual(store.step, .done)
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testIdentityWarningIsSilentInDemoMode() {
        let settingsStore = makeSettingsStore()
        let original = settingsStore.settings
        defer { settingsStore.settings = original }
        settingsStore.ezzkAccountController.setMode(.demo)
        settingsStore.settings.ezzkPersonName = "Advokát Test"
        settingsStore.settings.ezzkICO = "22222222"
        let store = makeStoreWithMandateCard(settingsStore)
        store.attestation.performingPerson = AdvocateProfile(fullName: "Iná osoba", ico: "11111111")

        XCTAssertNil(store.ezzkIdentityWarning)
    }

    func testIdentityWarningIsShownOutsideDemoModeOnMismatch() {
        let settingsStore = makeSettingsStore()
        let original = settingsStore.settings
        defer { settingsStore.settings = original }
        settingsStore.ezzkAccountController.setMode(.test)
        settingsStore.settings.ezzkPersonName = "Advokát Test"
        settingsStore.settings.ezzkICO = "22222222"
        let store = makeStoreWithMandateCard(settingsStore)
        store.attestation.performingPerson = AdvocateProfile(fullName: "Iná osoba", ico: "11111111")

        XCTAssertNotNil(store.ezzkIdentityWarning)
    }

    /// The pool exists so a second document never has to ask EZZK again for a number this
    /// app already holds unused from earlier today. `transport` carries only one login and
    /// one allocation reply: a second network request would find no reply and fail the test.
    func testReusesTodaysUnusedNumberBeforeAllocating() async throws {
        let credentialStore = MemoryCredentialStore()
        try credentialStore.save(EZZKSOAPCredentials(login: "ucet", password: "heslo"), environment: .sandbox)
        let transport = ScriptedTransport([loginSucceeded, numbersReply, serverTimeReply])
        let controller = EZZKAccountController(mode: .test, credentialStore: credentialStore,
                                               transportFactory: { _ in transport }, productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.settings.ezzkPersonName = "Advokátska kancelária Test"
        settingsStore.settings.ezzkICO = "12345678"
        let firstDocument = makeStoreWithMandateCard(settingsStore)

        await firstDocument.fetchEvidenceNumber()

        XCTAssertEqual(firstDocument.attestation.evidenceNumber, "260917-A")
        XCTAssertNotNil(firstDocument.attestation.evidenceNumberAllocatedAt)
        XCTAssertEqual(transport.requestCount, 3)

        // A second document, in the same session: it must reuse the pooled number instead
        // of allocating a new one.
        let secondDocument = makeStoreWithMandateCard(settingsStore)
        await secondDocument.fetchEvidenceNumber()

        XCTAssertEqual(secondDocument.attestation.evidenceNumber, "260917-A")
        XCTAssertEqual(secondDocument.attestation.evidenceNumberAllocatedAt,
                       firstDocument.attestation.evidenceNumberAllocatedAt)
        XCTAssertEqual(secondDocument.attestation.evidenceNumberMode, .test)
        XCTAssertNil(secondDocument.evidenceNumberError)
        XCTAssertEqual(transport.requestCount, 3,
                       "the second fetch must reuse the pooled number without another request")
    }

    /// The Demo simulator counts from 1 again after every launch; a number the register
    /// already holds must not be handed to a second document.
    func testDemoSkipsNumbersTheRegisterAlreadyHolds() async {
        let settingsStore = makeSettingsStore()
        settingsStore.ezzkAccountController.setMode(.demo)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd"
        let day = formatter.string(from: Date())
        for suffix in [1, 2] {
            settingsStore.evidenceStore.upsert(EvidenceRecord(
                status: .acceptedForProcessing, direction: .paperToElectronic,
                originalName: "Zmluva \(suffix)", newDocumentName: "Zmluva \(suffix).pdf",
                evidenceNumber: "1563-\(day)-\(suffix)", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                conversionTime: Date(), performingPersonName: "JUDr. Test Testovací",
                securityElementCount: 0, totalPages: 1, totalSheets: 1, ezzkMode: .demo,
                evidenceNumberAllocatedAt: Date()))
        }
        let store = makeStoreWithMandateCard(settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertEqual(store.attestation.evidenceNumber, "1563-\(day)-3")
    }

    /// A number requested from Settings is held by EZZK until a record uses it, so ZaKo
    /// must take it from the pool instead of asking again (which EZZK refuses with 113).
    func testNumberRequestedInSettingsIsUsedByTheNextConversion() async throws {
        let credentialStore = MemoryCredentialStore()
        try credentialStore.save(EZZKSOAPCredentials(login: "ucet", password: "heslo"), environment: .sandbox)
        let transport = ScriptedTransport([loginSucceeded, numbersReply, serverTimeReply])
        let controller = EZZKAccountController(mode: .test, credentialStore: credentialStore,
                                               transportFactory: { _ in transport }, productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.settings.ezzkPersonName = "Advokátska kancelária Test"
        settingsStore.settings.ezzkICO = "12345678"

        let requested = try await settingsStore.requestTestNumbersIntoPool()
        let store = makeStoreWithMandateCard(settingsStore)
        await store.fetchEvidenceNumber()

        XCTAssertEqual(requested, ["260917-A"])
        XCTAssertEqual(store.attestation.evidenceNumber, "260917-A")
        XCTAssertEqual(store.attestation.evidenceNumberMode, .test)
        XCTAssertEqual(transport.requestCount, 3, "ZaKo must not ask EZZK for another number")
    }

    /// A number whose register row the advocate deleted is never offered again: the next
    /// document asks EZZK for a new one.
    func testDeletedRowsNumberIsNotReused() async throws {
        let credentialStore = MemoryCredentialStore()
        try credentialStore.save(EZZKSOAPCredentials(login: "ucet", password: "heslo"), environment: .sandbox)
        let secondNumber = numbersReply.replacingOccurrences(of: "260917-A", with: "260917-B")
        let transport = ScriptedTransport([loginSucceeded, numbersReply, serverTimeReply, secondNumber, serverTimeReply])
        let controller = EZZKAccountController(mode: .test, credentialStore: credentialStore,
                                               transportFactory: { _ in transport }, productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.settings.ezzkPersonName = "Advokátska kancelária Test"
        settingsStore.settings.ezzkICO = "12345678"
        let firstDocument = makeStoreWithMandateCard(settingsStore)
        await firstDocument.fetchEvidenceNumber()
        XCTAssertEqual(firstDocument.attestation.evidenceNumber, "260917-A")
        let row = EvidenceRecord(status: .recordUnsigned, direction: .paperToElectronic,
                                 originalName: "Zmluva", newDocumentName: "Zmluva.pdf",
                                 evidenceNumber: "260917-A", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                 conversionTime: Date(), performingPersonName: "JUDr. Test Testovací",
                                 securityElementCount: 0, totalPages: 1, totalSheets: 1, ezzkMode: .test,
                                 evidenceNumberAllocatedAt: firstDocument.attestation.evidenceNumberAllocatedAt)
        settingsStore.evidenceStore.upsert(row)

        settingsStore.statusChecker.delete(id: row.id)
        let secondDocument = makeStoreWithMandateCard(settingsStore)
        await secondDocument.fetchEvidenceNumber()

        XCTAssertEqual(secondDocument.attestation.evidenceNumber, "260917-B")
        XCTAssertEqual(transport.requestCount, 5)
    }

    func testCode113ShowsTheLimitMessage() async throws {
        let credentialStore = MemoryCredentialStore()
        try credentialStore.save(EZZKSOAPCredentials(login: "ucet", password: "heslo"), environment: .sandbox)
        let transport = ScriptedTransport([loginSucceeded, numberLimitReply])
        let controller = EZZKAccountController(mode: .test, credentialStore: credentialStore,
                                               transportFactory: { _ in transport }, productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.settings.ezzkPersonName = "Advokátska kancelária Test"
        settingsStore.settings.ezzkICO = "12345678"
        let store = makeStoreWithMandateCard(settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertEqual(store.evidenceNumberError, EZZKError.numberLimitMessage)
        XCTAssertNil(store.attestation.evidenceNumber)
        XCTAssertFalse(store.evidenceNumberRequested)
    }

    /// Carried from the Task 6 review: the register is the legal record of every number
    /// already in use, so a fetch must refuse (and never touch the pool) while this build
    /// could not read it, rather than risk handing out a duplicate.
    func testFetchRefusesWhenTheRegisterCannotBeRead() async throws {
        let settingsStore = try makeSettingsStoreWithUnreadableRegister()
        XCTAssertNotNil(settingsStore.evidenceStore.loadError)
        let store = makeStoreWithMandateCard(settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertEqual(store.evidenceNumberError, settingsStore.evidenceStore.loadError)
        XCTAssertNil(store.attestation.evidenceNumber)
        XCTAssertFalse(store.evidenceNumberRequested)
    }

    /// Review focus 2: outside Demo, the Demo signing provider must not cost a real number.
    func testDemoSignatureOutsideDemoAllocatesNothing() async throws {
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport }, productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.useRealSigningProvider(DemoSigningProvider())
        let store = makeStoreWithMandateCard(settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertNil(store.attestation.evidenceNumber)
        XCTAssertEqual(store.evidenceNumberError, EZZKError.demoSignatureOutsideDemo.errorDescription)
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testDemoSignatureOutsideDemoIsNotAuthorized() async throws {
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport }, productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.useRealSigningProvider(DemoSigningProvider())
        let store = makeStoreWithMandateCard(settingsStore)
        store.attestation.evidenceNumber = "260924-X"
        store.attestation.evidenceNumberMode = .test
        store.attestation.evidenceNumberAllocatedAt = Date()

        await store.authorizeAndSign()

        XCTAssertNil(store.result)
        XCTAssertEqual(store.lastError, EZZKError.demoSignatureOutsideDemo.errorDescription)
        XCTAssertEqual(transport.requestCount, 0)
    }

    private let loginSucceeded = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><OutputMessageOf_LogInOutput xmlns="http://ditec/2017/06/iam/core"><Content xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ErrorCode i:nil="true"/><Account><Id>1</Id><Name>ucet-test</Name></Account><TokenDescriptor>token-1</TokenDescriptor></Content></OutputMessageOf_LogInOutput></s:Body></s:Envelope>"#

    private let numbersReply = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><GetConversionRecordEvidenceNumberResponse xmlns="http://www.ditec.sk/IEZZKService"><GetConversionRecordEvidenceNumberResult><Container xmlns="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"><Result><Code>0</Code><Description>OK</Description><Object><Data><ConversionRecordEvidenceNumberList><ConversionRecordEvidenceNumber>260917-A</ConversionRecordEvidenceNumber></ConversionRecordEvidenceNumberList></Data></Object></Result></Container></GetConversionRecordEvidenceNumberResult></GetConversionRecordEvidenceNumberResponse></s:Body></s:Envelope>"#

    private let numberLimitReply = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><GetConversionRecordEvidenceNumberResponse xmlns="http://www.ditec.sk/IEZZKService"><GetConversionRecordEvidenceNumberResult><Container xmlns="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"><Result><Code>113</Code><Description>Prekročený limit nespotrebovaných evidenčných čísel</Description></Result></Container></GetConversionRecordEvidenceNumberResult></GetConversionRecordEvidenceNumberResponse></s:Body></s:Envelope>"#

    /// `EZZKSOAPClient.serverTime()` reads the transport's "Date" header, not this body:
    /// any well-formed, non-fault envelope satisfies it.
    private let serverTimeReply = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body/></s:Envelope>"#
}
