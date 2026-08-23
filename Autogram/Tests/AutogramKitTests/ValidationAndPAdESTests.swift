import XCTest
import PDFKit
import Security
import CryptoKit
@testable import AutogramKit

final class ValidationAndPAdESTests: XCTestCase {
    private func sampleAttestation() -> (AttestationData, [SecurityElement]) {
        let profile = AdvocateProfile(fullName: "JUDr. Ján Advokát",
                                      position: "advokát",
                                      registrationNumber: "1234",
                                      ico: "35764102",
                                      officeName: "Advokátska kancelária Test")
        let attestation = AttestationData(
            originalDocumentOrder: 1,
            originalDocumentName: "Zmluva o dielo",
            numberOfSheets: 3,
            sheetCountingMethod: .duplexEstimate,
            nonEmptyPageCount: 5,
            paperSizeBreakdown: [.init(sizeClass: .a4Portrait, sheets: 3)],
            newDocumentName: "Zmluva o dielo.pdf",
            newDocumentFormatLabel: "PDF/A-2",
            conversionExecutionDateTime: Date(timeIntervalSince1970: 1_700_000_000),
            evidenceNumber: "1563-231114-42",
            performingPerson: profile,
            usedDeviceDescription: "Skenovanie / import do aplikácie Autogram")
        let elements = [
            SecurityElement(kind: .officialStamp, pageIndex: 0,
                            boundingBox: NormalizedRect(x: 0.75, y: 0.1, width: 0.15, height: 0.15),
                            confidence: 1)
        ]
        return (attestation, elements)
    }

    func testPDFAValidatorAcceptsConvertedOutput() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let converted = try PDFAConverter().convert(document: document, mode: .vectorPreserving)
        let result = PDFAValidator().validate(converted)
        XCTAssertTrue(result.isValid, "Problémy: \(result.issues)")
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testPDFAValidatorRejectsPlainPDF() throws {
        let plain = TestPDFBuilder.typicalContractPDF()
        let result = PDFAValidator().validate(plain)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.contains("pdfaid:part") })
        XCTAssertTrue(result.issues.contains { $0.contains("OutputIntent") })
    }

    func testAttestationXMLValidatorPassesValidClause() {
        let (attestation, elements) = sampleAttestation()
        let fingerprint = String(repeating: "ab", count: 32)
        let xml = AttestationClauseGenerator().generateXML(
            input: .init(attestation: attestation,
                         securityElements: elements,
                         newDocumentFingerprintSHA256Hex: fingerprint))
        let issues = AttestationXMLValidator().validate(
            xml, context: .init(fingerprintSHA256Hex: fingerprint, securityElementCount: elements.count))
        XCTAssertEqual(issues, [], "Neočakávané problémy: \(issues)")
    }

    func testAttestationXMLValidatorCatchesCorruption() {
        let (attestation, elements) = sampleAttestation()
        let fingerprint = String(repeating: "ab", count: 32)
        var xml = AttestationClauseGenerator().generateXML(
            input: .init(attestation: attestation,
                         securityElements: elements,
                         newDocumentFingerprintSHA256Hex: fingerprint))

        let wrongFingerprint = AttestationXMLValidator().validate(
            xml, context: .init(fingerprintSHA256Hex: String(repeating: "cd", count: 32),
                                securityElementCount: elements.count))
        XCTAssertTrue(wrongFingerprint.contains { $0.contains("ElectronicFingerprintValue") },
                      "\(wrongFingerprint)")

        var strippedEvidence = xml.replacingOccurrences(
            of: "<ConversionRecordEvidenceNumber>https://data.gov.sk/id/egov/conversion-record/1563-231114-42</ConversionRecordEvidenceNumber>",
            with: "<ConversionRecordEvidenceNumber>2026/1</ConversionRecordEvidenceNumber>")
        let evidenceIssues = AttestationXMLValidator().validate(
            strippedEvidence,
            context: .init(fingerprintSHA256Hex: fingerprint, securityElementCount: elements.count))
        XCTAssertTrue(evidenceIssues.contains { $0.contains("ConversionRecordEvidenceNumber") })

        if let range = xml.range(of: "<UsedDevice>Skenovanie / import do aplikácie Autogram</UsedDevice>") {
            xml.replaceSubrange(range, with: "<UsedDevice></UsedDevice>")
        }
        let deviceIssues = AttestationXMLValidator().validate(
            xml, context: .init(fingerprintSHA256Hex: fingerprint, securityElementCount: elements.count))
        XCTAssertTrue(deviceIssues.contains { $0.contains("UsedDevice") })
        _ = strippedEvidence
        strippedEvidence = ""
    }

    func testASiCEVerifierValidatesDigests() throws {
        let packager = ASiCEPackager()
        let pdfData = TestPDFBuilder.typicalContractPDF()
        let dolozkaData = Data("<ConversionRecord/>".utf8)

        func signatureXML(entries: [(name: String, data: Data)]) -> String {
            var references = ""
            for entry in entries where !entry.name.hasPrefix("META-INF/") && entry.name != "mimetype" {
                let digest = Data(SHA256.hash(data: entry.data)).base64EncodedString()
                references += """
                  <ds:Reference URI="#{U}">
                    <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
                    <ds:DigestValue>\(digest)</ds:DigestValue>
                  </ds:Reference>
                """
                references = references.replacingOccurrences(of: "#{U}",
                                                             with: entry.name.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-")))!)
            }
            return """
            <?xml version="1.0" encoding="UTF-8" standalone="no"?>
            <asic:XAdESSignatures xmlns:asic="http://uri.etsi.org/02918/v1.2.1#">
              <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#" Id="id-test">
                <ds:SignedInfo>
                \(references)
                  <ds:Reference Type="http://uri.etsi.org/01903#SignedProperties" URI="#xades-id-test">
                    <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
                    <ds:DigestValue>Zm9v</ds:DigestValue>
                  </ds:Reference>
                </ds:SignedInfo>
                <ds:SignatureValue>dmFsdWU=</ds:SignatureValue>
              </ds:Signature>
            </asic:XAdESSignatures>
            """
        }

        var files = packager.zakoContainer(pdfData: pdfData,
                                           pdfFileName: "dokument.pdf",
                                           dolozkaXML: dolozkaData,
                                           dolozkaFileName: "1563-231114-1.xml.xdcf")
        let payload = files.filter { $0.path != "mimetype" && !$0.path.hasPrefix("META-INF/") }
            .map { (name: $0.path, data: $0.data) }
        files.append(.init(path: "META-INF/signatures001.xml",
                           data: Data(signatureXML(entries: payload).utf8)))

        let asic = try packager.package(files: files)
        let verification = ASiCEContainerVerifier().verify(asic)
        XCTAssertTrue(verification.isValid, "Problémy: \(verification.issues)")
        XCTAssertEqual(Set(verification.verifiedObjectURIs),
                       Set(["dokument.pdf", "1563-231114-1.xml.xdcf"]))
        XCTAssertFalse(verification.containsDemoSignature)

        var corruptedDolozka = dolozkaData
        corruptedDolozka[corruptedDolozka.startIndex] ^= 0xFF
        var tamperedFiles = packager.zakoContainer(pdfData: pdfData,
                                                   pdfFileName: "dokument.pdf",
                                                   dolozkaXML: corruptedDolozka,
                                                   dolozkaFileName: "1563-231114-1.xml.xdcf")
        tamperedFiles.append(.init(path: "META-INF/signatures001.xml",
                                   data: Data(signatureXML(entries: payload).utf8)))
        let tamperedAsic = try packager.package(files: tamperedFiles)
        let tamperedVerification = ASiCEContainerVerifier().verify(tamperedAsic)
        XCTAssertFalse(tamperedVerification.isValid)
        XCTAssertTrue(tamperedVerification.issues.contains { $0.contains("nezodpovedá") },
                      "\(tamperedVerification.issues)")
        XCTAssertEqual(tamperedVerification.verifiedObjectURIs, ["dokument.pdf"])
    }

    func testDemoContainerIsVerifiableWithoutSignatures() throws {
        let provider = DemoSigningProvider()
        _ = provider
        let packager = ASiCEPackager()
        let files = packager.zakoContainer(pdfData: TestPDFBuilder.typicalContractPDF(),
                                           pdfFileName: "d.pdf",
                                           dolozkaXML: Data("<x/>".utf8),
                                           dolozkaFileName: "e.xml.xdcf")
        let demoFiles = files + [.init(path: "META-INF/demo-signature.json", data: Data("{}".utf8))]
        let asic = try packager.package(files: demoFiles)
        let verification = ASiCEContainerVerifier().verify(asic)
        XCTAssertTrue(verification.isValid, "\(verification.issues)")
        XCTAssertTrue(verification.containsDemoSignature)
    }

    func testPAdESSigningProducesVerifiableIncrementalUpdate() async throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              error == nil else {
            throw XCTSkip("Nemožno vygenerovať testovací kľúč: \(error?.takeRetainedValue().localizedDescription ?? "?")")
        }

        let commonName = DER.tlv(0x0C, Data("Autogram Test".utf8))
        let name = DER.sequence([
            DER.tlv(0x31, DER.sequence([DER.oid("2.5.4.3"), commonName]))
        ])
        func utcTime(_ value: String) -> Data {
            DER.tlv(0x17, Data((value + "Z").utf8))
        }
        let tbsCertificate = DER.sequence([
            DER.tlv(0xA0, DER.integer(2)),
            DER.integerFromRaw([0x2A]),
            DER.sequence([DER.oid("1.2.840.113549.1.1.11")]),
            name,
            DER.sequence([utcTime("260101000000"), utcTime("270101000000")]),
            name,
            DER.sequence([
                DER.sequence([DER.oid("1.2.840.113549.1.1.1")]),
                DER.tlv(0x03, Data([0x00, 0x01, 0x02, 0x03, 0x04]))
            ])
        ])
        let fakeCertificate = DER.sequence([
            tbsCertificate,
            DER.sequence([DER.oid("1.2.840.113549.1.1.11")]),
            DER.tlv(0x03, Data([0x00] + Array(repeating: UInt8(0xAB), count: 16)))
        ])
        let source = TestPDFBuilder.typicalContractPDF()
        let pageCount = PDFDocument(data: source)?.pageCount ?? -1

        let signer = PAdESSigner()
        let signed = try await signer.sign(pdf: source,
                                           certificateDER: fakeCertificate,
                                           privateKey: privateKey,
                                           includeTimestamp: false,
                                           tsaURL: nil)

        let reopened = try XCTUnwrap(PDFDocument(data: signed))
        XCTAssertEqual(reopened.pageCount, pageCount, "PAdES nesmie meniť počet strán.")

        let text = String(decoding: signed, as: UTF8.self)
        let regex = try NSRegularExpression(pattern: #"/ByteRange \[(\d+) (\d+) (\d+) (\d+)\]"#)
        let range = NSRange(text.startIndex..., in: text)
        let match = try XCTUnwrap(regex.firstMatch(in: text, range: range))
        func group(_ i: Int) -> Int {
            Int(text[Range(match.range(at: i), in: text)!])!
        }
        let (o1, l1, o2, l2) = (group(1), group(2), group(3), group(4))
        XCTAssertEqual(o1, 0)
        XCTAssertEqual(o2 + l2, signed.count, "ByteRange pokrýva celý súbor až po EOF.")
        XCTAssertEqual(o2, l1 + PAdESSigner.contentsHexCapacity + 1,
                       "Medzera musí presne zodpovedať hex obsahu /Contents <…>.")

        let covered = signed.subdata(in: 0..<l1) + signed.subdata(in: o2..<(o2 + l2))
        let recomputedDigest = Data(SHA256.hash(data: covered))

        let hexStart = try XCTUnwrap(PAdESSigner.indexOf(signed, ascii: "/Contents <"))
            + "/Contents <".utf8.count
        XCTAssertEqual(o2 - l1 - 1, PAdESSigner.contentsHexCapacity)
        let cmsHex = String(decoding: signed.subdata(in: hexStart..<(o2 - 1)), as: UTF8.self)
        XCTAssertTrue(cmsHex.allSatisfy(\.isHexDigit))
        let cms = Data(hexEncoded: String(cmsHex.prefix(4096 * 2))) ?? Data()
        XCTAssertFalse(cms.isEmpty)
        let extracted = Self.messageDigest(fromCMS: cms)
        XCTAssertEqual(extracted, recomputedDigest,
                       "messageDigest v CMS sa musí zhodovať s SHA-256 nad ByteRange rozsahmi.")
    }

    static func messageDigest(fromCMS cms: Data) -> Data? {
        let bytes = [UInt8](cms)
        guard let root = DERNode.firstTLV(bytes: bytes, at: 0),
              let explicitContent = DERNode.children(bytes: bytes, in: root.contentRange).dropFirst().first,
              let signedData = DERNode.children(bytes: bytes, in: explicitContent.contentRange).first else { return nil }
        for node in DERNode.children(bytes: bytes, in: signedData.contentRange) where node.tag == 0x30 && node.offset > signedData.offset + 20 {
            let children = DERNode.children(bytes: bytes, in: node.contentRange)
            if let signedAttrs = children.first(where: { $0.tag == 0xA0 }) {
                for attributeRaw in DERNode.children(bytes: bytes, in: signedAttrs.contentRange) {
                    let parts = DERNode.children(bytes: bytes, in: attributeRaw.contentRange)
                    guard parts.count >= 2, parts[0].tag == 0x06,
                          parts[0].oidString(bytes: bytes) == "1.2.840.113549.1.9.4",
                          let setNode = parts.dropFirst().first,
                          let octet = DERNode.children(bytes: bytes, in: setNode.contentRange).first else { continue }
                    return Data(bytes[octet.contentRange])
                }
            }
        }
        return nil
    }
}

