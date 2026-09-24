// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import Foundation
import PDFKit
import XCTest
@testable import Chevron7App

/// ZaKo after the client container: the conversion record 1.0 is built before anything is
/// signed, signed with the same card into its own container, stored in the register and
/// sent to EZZK through the submission coordinator.
@MainActor
final class ZakoRecordRouteTests: XCTestCase {
    private var source: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Chevron7App/ZakoSessionStore.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testAuthorizationSignsAndSendsTheRecordThroughTheCoordinator() throws {
        let text = try source
        XCTAssertTrue(text.contains("ZakoRecordDeliveryBuilder()"))
        XCTAssertTrue(text.contains("signsAsRecordContainer: true"))
        XCTAssertTrue(text.contains("timestampServers: "))
        XCTAssertTrue(text.contains("statusChecker.submit(id:"),
                      "the record is sent through the app's status checker, which applies the coordinator")
        XCTAssertTrue(text.contains(".recordUnsigned"))
        XCTAssertFalse(text.contains("clauseGenerator.generateXML"),
                       "the register keeps the record 1.0 XML, not the legacy generator's output")
    }

    /// Demo end to end: Demo signing provider, Demo EZZK (`MockEZZKService`), nothing leaves
    /// the machine. The row ends accepted, with the record container stored in the register.
    func testDemoConversionSignsTheRecordAndEndsAcceptedForProcessing() async throws {
        try requireXMLLint()
        let settingsStore = makeSettingsStore()
        settingsStore.useRealSigningProvider(DemoSigningProvider())
        let store = try makeReadyStore(settingsStore: settingsStore)
        store.setMandateOverride(true)
        await store.fetchEvidenceNumber()
        let number = try XCTUnwrap(store.attestation.evidenceNumber)
        let demoService = try XCTUnwrap(settingsStore.ezzkService as? MockEZZKService)

        await store.authorizeAndSign()

        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.step, .done)
        XCTAssertEqual(store.submissionStatus, .acceptedForProcessing)
        let row = try XCTUnwrap(settingsStore.evidenceStore.record(id: store.currentRecordID))
        XCTAssertEqual(row.status, .acceptedForProcessing)
        XCTAssertEqual(row.ezzkMode, .demo)
        XCTAssertEqual(row.evidenceNumber, number)
        XCTAssertNotNil(row.evidenceNumberAllocatedAt)
        XCTAssertNotNil(row.submittedAt)
        XCTAssertNotNil(row.submissionMessageID)
        XCTAssertTrue(row.attestationXML.contains(
            "https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0"),
            "the register keeps the record 1.0 XML")
        let stored = try XCTUnwrap(settingsStore.evidenceStore.recordContainerData(for: row))
        XCTAssertTrue(ASiCEContainerVerifier().verify(stored).isValid)

        // The client gets one file: the ASiC-E holding the PDF/A and the clause, signed
        // together. The signed record stays in the register, where it can be saved from.
        let outputs = try FileManager.default.contentsOfDirectory(atPath: try XCTUnwrap(store.outputDirectory).path)
        XCTAssertEqual(outputs.count, 1, "outputs: \(outputs)")
        let delivered = try XCTUnwrap(outputs.first)
        XCTAssertTrue(delivered.hasSuffix(".asice"), "outputs: \(outputs)")
        XCTAssertFalse(delivered.hasSuffix(".record.asice"), "outputs: \(outputs)")
        XCTAssertEqual(row.deliveredFileName, delivered)
        XCTAssertNotNil(row.pdfFileName)
        XCTAssertEqual(demoService.submittedRecords.count, 1)
        XCTAssertEqual(demoService.submittedRecords.first?.signedRecordContainer, stored)
    }

    /// The phone route (Demo only) signs the PDF/A alone and the relay wraps it into its own
    /// ASiC-E without the clause, so the loose PDF/A and clause XDCF are still written next
    /// to that container, and the Done screen exports the PDF/A.
    func testPhoneRouteStillWritesThePDFAndTheClauseNextToItsContainer() async throws {
        try requireXMLLint()
        let settingsStore = makeSettingsStore()
        settingsStore.ezzkAccountController.setMode(.demo)
        settingsStore.settings.mobileSigningEnabled = true
        let container = try await DemoSigningProvider().sign(SigningRequest(pdfData: Data("PDF".utf8),
                                                                           identityID: "demo",
                                                                           includeTimestamp: false))
        let signed = try XCTUnwrap(container.asicData)
        let document = #"{"filename":"a.asice","mimeType":"application/vnd.etsi.asic-e+zip","content":""#
            + signed.base64EncodedString()
            + #"","signers":[{"signedBy":"JUDr. Test Testovací, mandát: advokát","issuedBy":"CA Disig QCA3"}]}"#
        let transport = RelayTransport(replies: [
            (["Last-Modified": "Thu, 24 Sep 2026 10:00:01 GMT"], #"{"guid":"g1"}"#),
            ([:], document)
        ])
        let mobile = MobileSigningCoordinator(clientFactory: {
            AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        }, pollInterval: .milliseconds(5))
        let store = try makeReadyStore(settingsStore: settingsStore, mobileSigning: mobile)
        await store.fetchEvidenceNumber()

        await store.authorizeAndSign(viaMobile: true)

        XCTAssertEqual(store.step, .done, store.lastError ?? "")
        let outputs = try FileManager.default.contentsOfDirectory(atPath: try XCTUnwrap(store.outputDirectory).path)
        XCTAssertTrue(outputs.contains { $0.hasSuffix(".pdf") }, "outputs: \(outputs)")
        XCTAssertTrue(outputs.contains { $0.hasSuffix(".xml.xdcf") }, "outputs: \(outputs)")
        XCTAssertTrue(outputs.contains { $0.hasSuffix(".asice") }, "outputs: \(outputs)")
        XCTAssertFalse(outputs.contains { $0.hasSuffix(".record.asice") }, "outputs: \(outputs)")
        let row = try XCTUnwrap(settingsStore.evidenceStore.record(id: store.currentRecordID))
        XCTAssertEqual(row.deliveredFileName, row.pdfFileName)
        XCTAssertTrue(outputs.contains(try XCTUnwrap(row.deliveredFileName)), "outputs: \(outputs)")
    }

    /// The advocate's details used in a signed clause become the active profile, so the next
    /// conversion starts with them instead of asking for name, SAK number and IČO again.
    func testSignedConversionSavesThePersonAsTheActiveProfile() async throws {
        try requireXMLLint()
        let settingsStore = makeSettingsStore()
        settingsStore.useRealSigningProvider(DemoSigningProvider())
        let store = try makeReadyStore(settingsStore: settingsStore)
        settingsStore.settings.profiles = []
        settingsStore.settings.activeProfileID = nil
        store.setMandateOverride(true)
        await store.fetchEvidenceNumber()

        await store.authorizeAndSign()

        XCTAssertEqual(store.step, .done)
        let next = ZakoSessionStore(settingsStore: settingsStore)
        XCTAssertEqual(next.activeProfile().fullName, "JUDr. Test Testovací")
        XCTAssertEqual(next.activeProfile().registrationNumber, "4321")
        XCTAssertEqual(next.activeProfile().ico, "35764102")
    }

    /// Outside Demo both signatures get only the qualified built-in authorities, whatever the
    /// (hidden) QTS toggle says. A failed record signature keeps the client outputs, saves the
    /// row as unsigned and sends nothing.
    func testOutsideDemoRecordFailureKeepsClientOutputsAndSendsNothing() async throws {
        try requireXMLLint()
        let transport = ScriptedTransport([Self.optionsReply])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        let provider = RecordRefusingProvider()
        settingsStore.useRealSigningProvider(provider)
        let store = try makeReadyStore(settingsStore: settingsStore)
        XCTAssertFalse(store.includeQualifiedTimestamp, "the hidden switch is off, yet both signatures are stamped")
        XCTAssertFalse(store.showsQualifiedTimestampToggle)
        store.attestation.evidenceNumber = "1563-260924-7"
        store.attestation.evidenceNumberAllocatedAt = Date()
        store.attestation.evidenceNumberMode = .test

        await store.authorizeAndSign()

        let requests = provider.requests
        guard requests.count == 2 else {
            return XCTFail("expected the client container and the record to be signed, got \(requests.count) requests")
        }
        let qualified = TimestampAuthority.qualifiedURLs.map(\.absoluteString)
        XCTAssertFalse(qualified.isEmpty)
        for request in requests {
            XCTAssertTrue(request.includeTimestamp)
            XCTAssertEqual(request.timestampServers, qualified)
        }
        XCTAssertFalse(requests[0].signsAsRecordContainer)
        XCTAssertTrue(requests[1].signsAsRecordContainer)
        XCTAssertEqual(requests[1].filename, "1563-260924-7.record.xml.xdcf")

        XCTAssertEqual(store.step, .done)
        XCTAssertEqual(store.submissionStatus, .recordUnsigned)
        XCTAssertEqual(store.lastError, ZakoSessionStore.recordUnsignedMessage(RecordRefusingProvider.failure))
        let row = try XCTUnwrap(settingsStore.evidenceStore.record(id: store.currentRecordID))
        XCTAssertEqual(row.status, .recordUnsigned)
        XCTAssertEqual(row.ezzkMode, .test)
        XCTAssertNil(row.recordContainerPath)
        XCTAssertEqual(row.ezzkResultDescription, RecordRefusingProvider.failure.localizedDescription)
        let outputs = try FileManager.default.contentsOfDirectory(atPath: try XCTUnwrap(store.outputDirectory).path)
        XCTAssertEqual(outputs.count, 1, "only the client ASiC-E is delivered: \(outputs)")
        XCTAssertTrue(outputs.first?.hasSuffix(".asice") == true, "outputs: \(outputs)")
        XCTAssertFalse(outputs.contains { $0.hasSuffix(".pdf") }, "outputs: \(outputs)")
        XCTAssertFalse(outputs.contains { $0.hasSuffix(".xml.xdcf") }, "outputs: \(outputs)")
        XCTAssertFalse(outputs.contains { $0.hasSuffix(".record.asice") }, "outputs: \(outputs)")
        XCTAssertEqual(row.deliveredFileName, outputs.first)
        XCTAssertEqual(transport.operations, ["GetOptions"], "nothing but the server time reaches EZZK")
    }

    /// From the moment the client container is verified it carries the number, so the pool
    /// never offers it again, even when the record signature then fails.
    func testVerifiedClientContainerSpendsTheNumberEvenWhenTheRecordFails() async throws {
        try requireXMLLint()
        let transport = ScriptedTransport([Self.optionsReply])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        settingsStore.useRealSigningProvider(RecordRefusingProvider())
        let store = try makeReadyStore(settingsStore: settingsStore)
        let allocatedAt = Date()
        settingsStore.evidenceNumberPool.add(.init(number: "1563-260924-7", mode: .test, allocatedAt: allocatedAt))
        store.attestation.evidenceNumber = "1563-260924-7"
        store.attestation.evidenceNumberAllocatedAt = allocatedAt
        store.attestation.evidenceNumberMode = .test

        await store.authorizeAndSign()

        XCTAssertEqual(store.submissionStatus, .recordUnsigned)
        XCTAssertNil(settingsStore.evidenceNumberPool.reusable(mode: .test, at: allocatedAt, excluding: []),
                     "the client documents carry the number, so it is never offered again")
    }

    /// The row is in the register before the record is signed, so a crash or force-quit
    /// during the second signature leaves a visible row. The status checker leaves it alone
    /// meanwhile, and the final state updates that same row.
    func testRowIsRegisteredAndHeldWhileTheRecordIsSigned() async throws {
        try requireXMLLint()
        let transport = ScriptedTransport([Self.optionsReply])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        let provider = RecordRefusingProvider()
        settingsStore.useRealSigningProvider(provider)
        let store = try makeReadyStore(settingsStore: settingsStore)
        store.attestation.evidenceNumber = "1563-260924-7"
        store.attestation.evidenceNumberAllocatedAt = Date()
        store.attestation.evidenceNumberMode = .test
        let rowID = store.currentRecordID
        var seen: (row: EvidenceRecord?, busy: Bool, afterCheck: EvidenceRecord?) = (nil, false, nil)
        provider.onRecordSigning = {
            let row = settingsStore.evidenceStore.record(id: rowID)
            let busy = settingsStore.statusChecker.isBusy(rowID)
            await settingsStore.statusChecker.runOnce()
            seen = (row, busy, settingsStore.evidenceStore.record(id: rowID))
        }

        await store.authorizeAndSign()

        let during = try XCTUnwrap(seen.row, "the row must exist before the record is signed")
        XCTAssertEqual(during.status, .signed)
        XCTAssertNil(during.recordContainerPath)
        XCTAssertEqual(during.evidenceNumber, "1563-260924-7")
        XCTAssertTrue(seen.busy, "the status checker must not act on the row while ZaKo signs its record")
        XCTAssertEqual(seen.afterCheck?.status, .signed)
        XCTAssertEqual(seen.afterCheck?.updatedAt, during.updatedAt)
        XCTAssertFalse(settingsStore.statusChecker.isBusy(rowID))
        XCTAssertEqual(settingsStore.evidenceStore.records.count, 1, "the final state updates the same row")
        XCTAssertEqual(settingsStore.evidenceStore.record(id: rowID)?.status, .recordUnsigned)
    }

    /// A register this build cannot read is the legal record of numbers already used, so
    /// nothing is signed or sent while it is unreadable.
    func testUnreadableRegisterRefusesToSign() async throws {
        let settingsStore = try makeSettingsStoreWithUnreadableRegister()
        let provider = RecordRefusingProvider()
        settingsStore.useRealSigningProvider(provider)
        let loadError = try XCTUnwrap(settingsStore.evidenceStore.loadError)
        let store = try makeReadyStore(settingsStore: settingsStore)
        store.attestation.evidenceNumber = "1563-260924-8"
        store.attestation.evidenceNumberAllocatedAt = Date()
        store.attestation.evidenceNumberMode = .demo
        let demoService = try XCTUnwrap(settingsStore.ezzkService as? MockEZZKService)

        await store.authorizeAndSign()

        XCTAssertEqual(store.lastError, loadError)
        XCTAssertNil(store.result)
        XCTAssertNotEqual(store.step, .done)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertTrue(demoService.submittedRecords.isEmpty)
    }

    // MARK: - Fixtures

    private static let optionsReply = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing">"#
        + #"<s:Header><a:Action s:mustUnderstand="1">http://www.ditec.sk/IEZZKService/IEZZKService/GetOptionsResponse</a:Action></s:Header><s:Body><GetOptionsResponse xmlns="http://www.ditec.sk/IEZZKService"/></s:Body></s:Envelope>"#

    private func requireXMLLint() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation of the clause and the record.")
        }
    }

    /// A two-page document with every page reviewed, no security elements confirmed on
    /// purpose, a complete advocate profile and a mandate identity selected.
    private func makeReadyStore(settingsStore: AppSettingsStore,
                                mobileSigning: MobileSigningCoordinator? = nil) throws -> ZakoSessionStore {
        let original = settingsStore.settings
        addTeardownBlock { await MainActor.run { settingsStore.settings = original } }
        settingsStore.settings.learnFromReviews = false
        let a4 = CGSize(width: 595, height: 842)
        let data = TestPDFBuilderApp.build(pages: [
            (a4, { ctx, size in TestPDFBuilderApp.text("Zmluva o dielo", at: CGPoint(x: 60, y: size.height - 90), size: 16)(ctx, size) }),
            (a4, { ctx, size in TestPDFBuilderApp.text("Podpisy zmluvných strán", at: CGPoint(x: 60, y: size.height - 90), size: 16)(ctx, size) })
        ])
        let bank = ExampleBank(directory: makeTemporaryDirectory("record-route-bank"))
        let store = ZakoSessionStore(settingsStore: settingsStore, exampleBank: bank, mobileSigning: mobileSigning)
        store.document = try XCTUnwrap(PDFDocument(data: data))
        store.documentData = data
        store.analysis = PDFAnalysisEngine().analyze(document: try XCTUnwrap(store.document))
        store.inputSignatureInspection = .completed(signatures: [])
        store.markPageReviewed(0)
        store.markPageReviewed(1)
        store.confirmNoSecurityElements()

        store.attestation.originalDocumentName = "Zmluva o dielo"
        store.attestation.originalDocumentTypeLabel = "Zmluva"
        store.attestation.originConfirmed = true
        store.attestation.numberOfSheets = 1
        store.attestation.nonEmptyPageCount = store.analysis.nonEmptyPages
        store.attestation.paperSizeBreakdown = [.init(sizeClass: .a4Portrait, sheets: 1)]
        store.attestation.newDocumentName = "Zmluva o dielo.pdf"
        store.attestation.newDocumentFormatLabel = "PDF/A-2"
        store.attestation.performingPerson = AdvocateProfile(fullName: "JUDr. Test Testovací",
                                                             position: "advokát",
                                                             registrationNumber: "4321",
                                                             ico: "35764102")
        store.attestation.usedDeviceDescription = "Skenovanie / import do aplikácie Chevron7"

        store.identities = [SigningIdentityInfo(id: "demo", label: "Test mandátny certifikát",
                                                issuerSummary: "Test CA", isMandateCertificate: true,
                                                isQualified: true)]
        store.selectedIdentityID = "demo"
        // The Demo signing provider would ask a real TSA over the network for a timestamp.
        store.includeQualifiedTimestamp = false
        store.step = .authorize
        return store
    }
}

/// Signs the client container with the Demo provider and refuses the record, recording
/// every request it receives.
private final class RecordRefusingProvider: QualifiedSigningProviding, @unchecked Sendable {
    static let failure = SigningError.signingFailed("Karta bola vybratá počas podpisu záznamu.")
    private let lock = NSLock()
    private var received: [SigningRequest] = []
    private let demo = DemoSigningProvider()
    /// Runs on the main actor when the record signature starts, before it fails.
    nonisolated(unsafe) var onRecordSigning: (@MainActor () async -> Void)?

    var requests: [SigningRequest] { lock.withLock { received } }

    func availableIdentities() async -> [SigningIdentityInfo] { [] }

    func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        lock.withLock { received.append(request) }
        if request.signsAsRecordContainer {
            if let onRecordSigning { await onRecordSigning() }
            throw Self.failure
        }
        // The Demo provider would ask a real TSA for a timestamp; the requests above carry
        // what the app asked for, which is what this test checks.
        var local = request
        local.includeTimestamp = false
        return try await demo.sign(local)
    }
}

/// The Autogram v mobile relay as the phone route sees it: the upload answer, then the
/// signed document on the first poll. Deletes and any further request get an empty reply.
private final class RelayTransport: AVMHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [([String: String], String)]

    init(replies: [([String: String], String)]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: ([String: String], String)? = lock.withLock {
            request.httpMethod == "DELETE" || replies.isEmpty ? nil : replies.removeFirst()
        }
        guard let (headers, body) = next else {
            let status = request.httpMethod == "DELETE" ? 200 : 304
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
    }
}
