import CryptoKit
import XCTest
@testable import AutogramKit

final class P2EConformanceTests: XCTestCase {
    func testReferenceProfileMatchesObservedP2EArtifact() {
        let profile = P2EConformanceProfile.referenceV1_2

        XCTAssertEqual(
            profile.clauseNamespace,
            "http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument/1.2")
        XCTAssertEqual(
            profile.clauseIdentifier,
            "http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument/1.2")
        XCTAssertEqual(profile.clauseRoot, "ConversionCertificateOfPaperToElectronicDocument")
        XCTAssertEqual(profile.clauseVersion, "1.2")
        XCTAssertEqual(profile.pdfa2Code, "PDFA2")
        XCTAssertEqual(profile.pdfa2Name, "PDF/A-2")
        XCTAssertEqual(profile.sha256Code, "SHA-256")
        XCTAssertEqual(profile.evidenceURIBase, "https://data.gov.sk/id/egov/conversion-record/")
    }
    func testTargetProfileMatchesOfficialCatalogue() {
        let profile = P2EConformanceProfile.targetV1_3

        XCTAssertEqual(
            profile.clauseNamespace,
            "http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3")
        XCTAssertEqual(
            profile.clauseIdentifier,
            "http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3")
        XCTAssertEqual(profile.clauseVersion, "1.3")
        XCTAssertEqual(profile.recordVersion, "1.0")
        XCTAssertTrue(
            P2EConformanceProfile.officialClauseV1_3MetadataURL.absoluteString.contains("vl=3"))
        XCTAssertTrue(
            P2EConformanceProfile.officialClauseV1_3ArchiveURL.absoluteString.contains("vl=3"))
    }

    func testTargetProfileValidatesClauseShape() throws {
        let profile = P2EConformanceProfile.targetV1_3
        let pdf = Data("target-pdf".utf8)
        let evidenceURI = "https://data.gov.sk/id/egov/conversion-record/1563-260830-1"
        let xml = xdcf(
            identifier: profile.clauseIdentifier,
            version: profile.clauseVersion,
            payload: clausePayload(
                namespace: profile.clauseNamespace,
                documentName: "target.pdf",
                fingerprint: P2EConformanceProfile.sha256Base64(pdf),
                evidenceURI: evidenceURI,
                conversionTime: "2026-08-30T01:00:00+02:00"))
        let asic = try signedArtifact(
            dataEntries: [
                ("target.xdcf", Data(xml.utf8)),
                ("target.pdf", pdf)
            ])

        let result = P2EConformanceValidator().validate(clauseASiC: asic)

        XCTAssertTrue(result.isValid, result.issues.joined(separator: "\n"))
        XCTAssertEqual(result.clause?.documentEntryName, "target.pdf")
    }


    func testValidClauseAndRecordArtifactsPass() throws {
        let pdf = Data("reference-pdf".utf8)
        let conversionTime = Date(timeIntervalSince1970: 1_787_589_344)
        let evidenceURI = "https://data.gov.sk/id/egov/conversion-record/1563-260824-1"
        let fingerprint = P2EConformanceProfile.sha256Base64(pdf)
        let clauseXML = xdcf(
            identifier: P2EConformanceProfile.referenceV1_2.clauseIdentifier,
            version: "1.2",
            payload: clausePayload(
                namespace: P2EConformanceProfile.referenceV1_2.clauseNamespace,
                documentName: "reference.pdf",
                fingerprint: fingerprint,
                evidenceURI: evidenceURI,
                conversionTime: "2026-08-24T18:35:44+02:00"))
        let recordXML = xdcf(
            identifier: P2EConformanceProfile.referenceV1_2.recordIdentifier,
            version: "1.0",
            payload: recordPayload(
                namespace: P2EConformanceProfile.referenceV1_2.recordNamespace,
                fingerprint: fingerprint,
                evidenceURI: evidenceURI,
                conversionTime: "2026-08-24T18:35:44+02:00"))

        let clauseASiC = try signedArtifact(
            dataEntries: [
                ("reference.xdcf", Data(clauseXML.utf8)),
                ("reference.pdf", pdf)
            ])
        let recordASiC = try signedArtifact(
            dataEntries: [("record.xdcf", Data(recordXML.utf8))])
        let result = P2EConformanceValidator().validate(
            clauseASiC: clauseASiC,
            recordASiC: recordASiC,
            context: .init(
                expectedPDFData: pdf,
                expectedEvidenceNumber: "1563-260824-1",
                expectedConversionTime: conversionTime),
            profile: .referenceV1_2)

        XCTAssertTrue(result.isValid, result.issues.joined(separator: "\n"))
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.clause?.documentEntryName, "reference.pdf")
        XCTAssertEqual(result.clause?.fingerprintBase64, fingerprint)
        XCTAssertEqual(result.clause?.evidenceURI, evidenceURI)
        XCTAssertEqual(result.clause?.conversionTime?.timeIntervalSince1970 ?? 0,
                       conversionTime.timeIntervalSince1970,
                       accuracy: 1)
        XCTAssertTrue(result.clause?.hasTimestamp == true)
        XCTAssertTrue(result.record?.hasTimestamp == true)
    }

    func testRejectsWrongNamespaceAndFingerprint() throws {
        let pdf = Data("reference-pdf".utf8)
        let evidenceURI = "https://data.gov.sk/id/egov/conversion-record/1563-260824-1"
        let clauseXML = xdcf(
            identifier: P2EConformanceProfile.referenceV1_2.clauseIdentifier,
            version: "1.2",
            payload: clausePayload(
                namespace: "https://wrong.example/p2e",
                documentName: "reference.pdf",
                fingerprint: String(repeating: "A", count: 44),
                evidenceURI: evidenceURI,
                conversionTime: "2026-08-24T18:35:44+02:00"))
        let clauseASiC = try signedArtifact(
            dataEntries: [
                ("reference.xdcf", Data(clauseXML.utf8)),
                ("reference.pdf", pdf)
            ])

        let result = P2EConformanceValidator().validate(
            clauseASiC: clauseASiC,
            profile: .referenceV1_2)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains("P2E XML nemá očakávaný namespace doložky."))
        XCTAssertTrue(result.issues.contains("Fingerprint PDF v kontajneri nezodpovedá doložke."))
    }

    func testRejectsMissingTimestampAndDemoSignature() throws {
        let pdf = Data("reference-pdf".utf8)
        let clauseXML = xdcf(
            identifier: P2EConformanceProfile.referenceV1_2.clauseIdentifier,
            version: "1.2",
            payload: clausePayload(
                namespace: P2EConformanceProfile.referenceV1_2.clauseNamespace,
                documentName: "reference.pdf",
                fingerprint: P2EConformanceProfile.sha256Base64(pdf),
                evidenceURI: "https://data.gov.sk/id/egov/conversion-record/1563-260824-1",
                conversionTime: "2026-08-24T18:35:44+02:00"))
        let clauseASiC = try signedArtifact(
            dataEntries: [
                ("reference.xdcf", Data(clauseXML.utf8)),
                ("reference.pdf", pdf)
            ],
            includeTimestamp: false,
            includeDemoMarker: true)

        let result = P2EConformanceValidator().validate(
            clauseASiC: clauseASiC,
            profile: .referenceV1_2)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains("ASiC neobsahuje XAdES SignatureTimeStamp."))
        XCTAssertTrue(result.issues.contains("ASiC obsahuje demo podpisový marker."))
    }

    func testRejectsMissingXDCFAndPDFDataObjects() throws {
        let manifestOnly = try signedArtifact(dataEntries: [("other.bin", Data("x".utf8))])
        let missingPDF = try signedArtifact(
            dataEntries: [("clause.xdcf", Data("<invalid/>".utf8))])

        let noXDCF = P2EConformanceValidator().validate(clauseASiC: manifestOnly)
        let noPDF = P2EConformanceValidator().validate(clauseASiC: missingPDF)

        XCTAssertFalse(noXDCF.isValid)
        XCTAssertTrue(noXDCF.issues.contains("Chýba P2E XDCF doložky."))
        XCTAssertFalse(noPDF.isValid)
        XCTAssertTrue(noPDF.issues.contains("Chýba PDF objekt doložky."))
        XCTAssertTrue(noPDF.issues.contains("ASiC doložky obsahuje neplatný počet PDF objektov."))
    }

    private func xdcf(identifier: String, version: String, payload: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <XMLDataContainer xmlns="http://data.gov.sk/def/container/xmldatacontainer+xml/1.1">
          <XMLData ContentType="application/xml; charset=UTF-8" Identifier="\(identifier)" Version="\(version)">\(payload)</XMLData>
        </XMLDataContainer>
        """
    }

    private func clausePayload(namespace: String,
                               documentName: String,
                               fingerprint: String,
                               evidenceURI: String,
                               conversionTime: String) -> String {
        """
        <ConversionCertificateOfPaperToElectronicDocument xmlns="\(namespace)">
          <OriginalDocumentInfo>
            <OriginalDocumentName>Reference</OriginalDocumentName>
            <OriginalDocumentNumberOfSheets>1</OriginalDocumentNumberOfSheets>
            <OriginalDocumentNonEmptyPageCount>1</OriginalDocumentNonEmptyPageCount>
            <OriginalDocumentPaperSize><PaperSizeNumberOfSheets>1</PaperSizeNumberOfSheets></OriginalDocumentPaperSize>
            <DocumentSecurityElementsDetails><OriginalDocumentSecurityElementsPage>1</OriginalDocumentSecurityElementsPage></DocumentSecurityElementsDetails>
          </OriginalDocumentInfo>
          <NewDocumentInfo>
            <NewDocumentName>\(documentName)</NewDocumentName>
            <NewDocumentFormat><Codelist><CodelistCode>53</CodelistCode><CodelistItem><ItemCode>PDFA2</ItemCode><ItemName Language="sk">PDF/A-2</ItemName></CodelistItem></Codelist></NewDocumentFormat>
            <ElectronicFingerprintValue>\(fingerprint)</ElectronicFingerprintValue>
            <ElectronicFingerprintCalculationMethod><Codelist><CodelistCode>14</CodelistCode><CodelistItem><ItemCode>SHA-256</ItemCode><ItemName Language="sk">SHA-256</ItemName></CodelistItem></Codelist></ElectronicFingerprintCalculationMethod>
          </NewDocumentInfo>
          <ConversionRecordEvidenceNumber>\(evidenceURI)</ConversionRecordEvidenceNumber>
          <ConversionExecutionDateTime>\(conversionTime)</ConversionExecutionDateTime>
        </ConversionCertificateOfPaperToElectronicDocument>
        """
    }

    private func recordPayload(namespace: String,
                               fingerprint: String,
                               evidenceURI: String,
                               conversionTime: String) -> String {
        """
        <ConversionRecord xmlns="\(namespace)">
          <OriginalDocumentInfo><OriginalDocumentName>Reference</OriginalDocumentName></OriginalDocumentInfo>
          <NewDocumentInfo>
            <NewDocumentName>reference.pdf</NewDocumentName>
            <NewDocumentFormat><Codelist><CodelistCode>53</CodelistCode><CodelistItem><ItemCode>PDFA2</ItemCode><ItemName Language="sk">PDF/A-2</ItemName></CodelistItem></Codelist></NewDocumentFormat>
            <ElectronicFingerprintValue>\(fingerprint)</ElectronicFingerprintValue>
            <ElectronicFingerprintCalculationMethod><Codelist><CodelistCode>14</CodelistCode><CodelistItem><ItemCode>SHA-256</ItemCode><ItemName Language="sk">SHA-256</ItemName></CodelistItem></Codelist></ElectronicFingerprintCalculationMethod>
          </NewDocumentInfo>
          <ConversionRecordEvidenceNumber>\(evidenceURI)</ConversionRecordEvidenceNumber>
          <ConversionExecutionDateTime>\(conversionTime)</ConversionExecutionDateTime>
        </ConversionRecord>
        """
    }

    private func signedArtifact(
        dataEntries: [(String, Data)],
        includeTimestamp: Bool = true,
        includeDemoMarker: Bool = false) throws -> Data {
        var entries = [ASiCEPackager.Entry(
            path: "mimetype",
            data: Data(ASiCEPackager.asicMimeType.utf8),
            storeUncompressed: true)]
        entries += dataEntries.map { ASiCEPackager.Entry(path: $0.0, data: $0.1) }
        let manifest = ASiCEPackager.manifestXML(
            entries: dataEntries.map { (path: $0.0, mediaType: ASiCEPackager.mediaType(forPath: $0.0)) })
        entries.append(.init(path: "META-INF/manifest.xml", data: Data(manifest.utf8)))
        let references = dataEntries.map { name, data in
            "<ds:Reference URI=\"\(name)\"><ds:DigestValue>\(P2EConformanceProfile.sha256Base64(data))</ds:DigestValue></ds:Reference>"
        }.joined()
        let timestamp = includeTimestamp ? "<xades:SignatureTimeStamp/>" : ""
        let signature = """
        <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#" xmlns:xades="http://uri.etsi.org/01903/v1.3.2#">
          <ds:SignedInfo>\(references)<ds:Reference URI="#xades-properties"><ds:DigestValue>ignored</ds:DigestValue></ds:Reference></ds:SignedInfo>
          <xades:QualifyingProperties Id="xades-properties">\(timestamp)</xades:QualifyingProperties>
        </ds:Signature>
        """
        entries.append(.init(path: "META-INF/signatures001.xml", data: Data(signature.utf8)))
        if includeDemoMarker {
            entries.append(.init(path: "META-INF/demo-signature.json", data: Data("{}".utf8)))
        }
        return try ASiCEPackager().package(files: entries)
    }
}
