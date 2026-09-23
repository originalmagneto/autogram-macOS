// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import PDFKit
@testable import Chevron7Kit

final class ConversionPipelineIntegrationTests: XCTestCase {
    @MainActor
    func testFullPaperToElectronicPipeline() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation of the clause.")
        }
        let sourceData = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: sourceData))

        let engine = PDFAnalysisEngine()
        let doc = TestUncheckedSendable(document)
        let analysis = await Task.detached(priority: .userInitiated) { [doc] in
            engine.analyze(document: doc.value)
        }.value
        let provider = BuiltInVisionProvider()
        let elements = await provider.detect(in: doc.value, pageAnalyses: analysis.pageAnalyses)

        XCTAssertGreaterThanOrEqual(analysis.totalPages, 3)
        XCTAssertGreaterThanOrEqual(elements.count, 1)

        let profile = AdvocateProfile(fullName: "JUDr. Test Testovací",
                                      position: "advokát",
                                      registrationNumber: "4321",
                                      ico: "35764102")

        var attestation = AttestationData(
            originalDocumentName: "Zmluva o dielo",
            originalDocumentTypeLabel: "Zmluva",
            numberOfSheets: analysis.estimatedSheetsDuplex,
            sheetCountingMethod: .duplexEstimate,
            nonEmptyPageCount: analysis.nonEmptyPages,
            paperSizeBreakdown: [.init(sizeClass: .a4Portrait, sheets: analysis.estimatedSheetsDuplex)],
            newDocumentName: "Zmluva o dielo.pdf",
            newDocumentFormatLabel: "PDF/A-2",
            performingPerson: profile,
            usedDeviceDescription: "Skenovanie / import do aplikácie Chevron7")
        attestation.evidenceNumber = "1563-231114-777"

        let converter = PDFAConverter()
        let pdfaData = try converter.convert(document: document,
                                             mode: .vectorPreserving,
                                             title: attestation.newDocumentName)

        // The delivered PDF/A is final before the clause fingerprints it: nothing is embedded.
        let finalPDF = try converter.normalizeForDelivery(pdfaData, title: attestation.newDocumentName)
        let fingerprint = AttestationClauseGenerator.sha256Hex(of: finalPDF)
        XCTAssertEqual(fingerprint.count, 64)

        let clause = try ZakoClauseDeliveryBuilder().build(
            finalPDF: finalPDF,
            attestation: attestation,
            securityElements: elements,
            originalNonEmptyPageIndices: nil,
            usedDevice: attestation.usedDeviceDescription)
        XCTAssertEqual(clause.model.fingerprintBase64, AttestationClauseGenerator.fingerprintBase64(hex: fingerprint))
        XCTAssertTrue(String(decoding: clause.clauseXDCF, as: UTF8.self).contains("XMLDataContainer"))

        // Record XML for the register only.
        let xml = AttestationClauseGenerator().generateXML(
            input: .init(attestation: attestation,
                         securityElements: elements,
                         newDocumentFingerprintSHA256Hex: fingerprint))
        XCTAssertTrue(xml.contains("1563-231114-777"))

        let reopened = try XCTUnwrap(PDFDocument(data: finalPDF))
        XCTAssertEqual(reopened.pageCount, analysis.totalPages,
                       "Konvertovaný dokument nesmie mať pridanú tlačiteľnú stranu doložky.")

        let signer = DemoSigningProvider()
        let identities = await signer.availableIdentities()
        let packager = ASiCEPackager()
        let containerFiles = packager.zakoContainer(pdfData: finalPDF,
                                                    pdfFileName: "Zmluva o dielo.pdf",
                                                    dolozkaXML: clause.clauseXDCF,
                                                    dolozkaFileName: "1563-231114-777.xml.xdcf")
        let result = try await signer.sign(pdf: finalPDF,
                                           identityID: identities[0].id,
                                           includeTimestamp: false,
                                           extraFiles: containerFiles)
        let asic = try XCTUnwrap(result.asicData)
        XCTAssertFalse(result.isLegallyBinding)
        XCTAssertEqual(result.pdfData, finalPDF)
        XCTAssertEqual(containerFiles.first { $0.path == "1563-231114-777.xml.xdcf" }?.data, clause.clauseXDCF)

        let listing = String(decoding: asic, as: UTF8.self)
        XCTAssertTrue(listing.contains("1563-231114-777.xml.xdcf"))
        XCTAssertTrue(listing.contains("META-INF/manifest.xml"))
        XCTAssertTrue(listing.contains("META-INF/demo-signature.json"))

        let ezzk = MockEZZKService()
        _ = try await ezzk.requestEvidenceNumbers(count: 1)
        let envelope = ConversionRecordEnvelope(
            evidenceNumber: attestation.evidenceNumber!,
            direction: .paperToElectronic,
            originalName: attestation.originalDocumentName,
            newDocumentName: attestation.newDocumentName,
            attestationXML: xml,
            fingerprintSHA256Hex: fingerprint,
            conversionTime: Date())
        try await ezzk.submit(envelope)
        XCTAssertEqual(ezzk.submittedRecords.count, 1)
    }
}
