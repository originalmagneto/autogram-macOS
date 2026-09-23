// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import CryptoKit
@testable import Chevron7Kit

final class ZakoClauseDeliveryBuilderTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    func testDeliveredContainerPassesTheConformanceValidator() throws {
        let pdf = Data("%PDF-1.7 synthetic delivered bytes".utf8)
        let attestation = ConversionFormModelTests.attestation()
        let delivery = try ZakoClauseDeliveryBuilder().build(
            finalPDF: pdf, attestation: attestation,
            securityElements: [ConversionFormModelTests.scanElement()],
            originalNonEmptyPageIndices: [0], usedDevice: "Chevron7 v0.5.0")

        XCTAssertEqual(delivery.model.fingerprintBase64, Data(SHA256.hash(data: pdf)).base64EncodedString())

        var entries = ASiCEPackager().zakoContainer(pdfData: pdf, pdfFileName: "dokument.pdf",
                                                     dolozkaXML: delivery.clauseXDCF,
                                                     dolozkaFileName: "1563-260824-1.xml.xdcf")
        entries.append(ASiCEPackager.Entry(path: "META-INF/signatures001.xml",
                                           data: Self.fakeSignature(for: [("dokument.pdf", pdf),
                                                                          ("1563-260824-1.xml.xdcf", delivery.clauseXDCF)])))
        let asic = try ASiCEPackager().package(files: entries)
        let result = P2EConformanceValidator().validate(
            clauseASiC: asic,
            context: .init(expectedPDFData: pdf, expectedEvidenceNumber: "1563-260824-1",
                           expectedConversionTime: attestation.conversionExecutionDateTime))
        XCTAssertTrue(result.isValid, result.issues.joined(separator: "\n"))
    }

    func testInvalidModelNeverReachesTheContainer() {
        var attestation = ConversionFormModelTests.attestation()
        attestation.originalDocumentName = ""
        XCTAssertThrowsError(try ZakoClauseDeliveryBuilder().build(
            finalPDF: Data("%PDF".utf8), attestation: attestation, securityElements: [],
            originalNonEmptyPageIndices: nil, usedDevice: "Chevron7"))
    }

    static func fakeSignature(for objects: [(String, Data)]) -> Data {
        let references = objects.map { name, data in
            "<ds:Reference URI=\"\(name)\"><ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"/><ds:DigestValue>\(Data(SHA256.hash(data: data)).base64EncodedString())</ds:DigestValue></ds:Reference>"
        }.joined()
        let xml = "<asic:XAdESSignatures xmlns:asic=\"http://uri.etsi.org/02918/v1.2.1#\" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\" xmlns:xades=\"http://uri.etsi.org/01903/v1.3.2#\"><ds:Signature Id=\"s\"><ds:SignedInfo>\(references)<ds:Reference Type=\"http://uri.etsi.org/01903#SignedProperties\" URI=\"#xades-s\"><ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"/><ds:DigestValue>AA==</ds:DigestValue></ds:Reference></ds:SignedInfo><ds:Object><xades:QualifyingProperties><xades:UnsignedProperties><xades:UnsignedSignatureProperties><xades:SignatureTimeStamp/></xades:UnsignedSignatureProperties></xades:UnsignedProperties></xades:QualifyingProperties></ds:Object></ds:Signature></asic:XAdESSignatures>"
        return Data(xml.utf8)
    }
}
