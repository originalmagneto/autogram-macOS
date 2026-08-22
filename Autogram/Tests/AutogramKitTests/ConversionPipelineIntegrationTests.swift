import XCTest
import PDFKit
@testable import AutogramKit

final class ConversionPipelineIntegrationTests: XCTestCase {
    @MainActor
    func testFullPaperToElectronicPipeline() async throws {
        let sourceData = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: sourceData))

        let engine = PDFAnalysisEngine()
        let analysis = engine.analyze(document: document)
        let provider = BuiltInVisionProvider()
        let elements = await provider.detect(in: document, pageAnalyses: analysis.pageAnalyses)

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
            newDocumentName: "Zmluva o dielo (PDF/A)",
            performingPerson: profile)
        attestation.evidenceNumber = "2026/000777"

        let converter = PDFAConverter()
        let pdfaData = try converter.convert(document: document,
                                             mode: .vectorPreserving,
                                             title: attestation.newDocumentName)

        let withClause = ZakoClauseTestBridge.appendClause(pdfaData: pdfaData,
                                                          attestation: attestation,
                                                          elements: elements)

        let fingerprint = AttestationClauseGenerator.sha256Hex(of: withClause)
        XCTAssertEqual(fingerprint.count, 64)

        let xml = AttestationClauseGenerator().generateXML(
            input: .init(attestation: attestation,
                         securityElements: elements,
                         newDocumentFingerprintSHA256Hex: fingerprint))
        XCTAssertTrue(xml.contains("2026/000777"))
        XCTAssertTrue(xml.contains(fingerprint))

        let finalPDF = try EmbeddedFileService().embed(
            .init(fileName: "osvedcovacia-dolozka.xml",
                  mimeType: "text+xml",
                  data: Data(xml.utf8)),
            into: withClause)

        let reopened = try XCTUnwrap(PDFDocument(data: finalPDF))
        XCTAssertEqual(reopened.pageCount, analysis.totalPages + 1,
                       "K dokumentu musela pribudnúť strana osvedčovacej doložky.")

        let signer = DemoSigningProvider()
        let identities = await signer.availableIdentities()
        let result = try await signer.sign(pdf: finalPDF,
                                           identityID: identities[0].id,
                                           includeTimestamp: true)
        XCTAssertNotNil(result.asicData)
        XCTAssertFalse(result.isLegallyBinding)

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

enum ZakoClauseTestBridge {
    static func appendClause(pdfaData: Data, attestation: AttestationData,
                             elements: [SecurityElement]) -> Data {
        let renderer = ClausePDFRenderer()
        guard let mainDoc = PDFDocument(data: pdfaData) else { return pdfaData }
        let clauseData = renderer.render(
            title: "OSVEDČOVACIA DOLOŽKA",
            subtitle: nil,
            sections: [
                .init(heading: "Pôvodný dokument", lines: [
                    ("Názov", attestation.originalDocumentName),
                    ("Počet listov", "\(attestation.numberOfSheets)")
                ]),
                .init(heading: "Bezpečnostné prvky", lines:
                        elements.map { ("\($0.kind.rawValue)", "strana \($0.pageIndex + 1)") })
            ])
        guard let clauseDoc = PDFDocument(data: clauseData) else { return pdfaData }
        for i in 0..<clauseDoc.pageCount {
            if let p = clauseDoc.page(at: i) {
                mainDoc.insert(p, at: mainDoc.pageCount)
            }
        }
        return mainDoc.dataRepresentation() ?? pdfaData
    }
}
