import XCTest
import PDFKit
import AppKit
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
    func testPDFARasterizationPreservesGraphicStampPixels() throws {
        func blankDocument() -> PDFDocument {
            let document = PDFDocument()
            let page = PDFPage()
            let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
            page.setBounds(bounds, for: .mediaBox)
            page.setBounds(bounds, for: .cropBox)
            document.insert(page, at: 0)
            return document
        }

        let plain = blankDocument()
        let stamped = blankDocument()
        let artwork = NSImage(size: NSSize(width: 80, height: 40))
        artwork.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(origin: .zero, size: artwork.size).fill()
        artwork.unlockFocus()
        let png = try XCTUnwrap(
            artwork.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
                .representation(using: .png, properties: [:]))
        let stamp = VisibleSignatureStamper.StampData(
            fullName: "Test signer",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            pageIndex: 0,
            normalizedRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.15),
            imagePNG: png)
        let stampedData = try XCTUnwrap(
            VisibleSignatureStamper().stamp(document: stamped, stamp: stamp, includeTimestamp: false))

        let plainRaster = try PDFAConverter.rasterize(document: plain)
        let stampedRaster = try PDFAConverter.rasterize(
            document: try XCTUnwrap(PDFDocument(data: stampedData)))
        let plainRasterDocument = try XCTUnwrap(PDFDocument(data: plainRaster))
        let stampedRasterDocument = try XCTUnwrap(PDFDocument(data: stampedRaster))
        let plainImage = try XCTUnwrap(
            PDFAConverter.renderPageImage(
                page: try XCTUnwrap(plainRasterDocument.page(at: 0)),
                scale: 1))
        let stampedImage = try XCTUnwrap(
            PDFAConverter.renderPageImage(
                page: try XCTUnwrap(stampedRasterDocument.page(at: 0)),
                scale: 1))
        XCTAssertNotEqual(
            plainImage.dataProvider?.data as Data?,
            stampedImage.dataProvider?.data as Data?,
            "PDF/A rasterizácia nesmie zahodiť grafickú pečiatku")
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
        let rawSigner = RawSigner.secKey(privateKey)
        let signed = try await signer.sign(pdf: source,
                                           certificateDER: fakeCertificate,
                                           signer: rawSigner,
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
        XCTAssertEqual(o2, l1 + PAdESSigner.contentsHexCapacity + 2,
                       "Medzera musí zodpovedať <hex> vrátane hranatých zátvoriek.")

        let covered = signed.subdata(in: 0..<l1) + signed.subdata(in: o2..<(o2 + l2))
        let recomputedDigest = Data(SHA256.hash(data: covered))

        let hexStart = try XCTUnwrap(PAdESSigner.indexOf(signed, ascii: "/Contents <"))
            + "/Contents <".utf8.count
        XCTAssertEqual(o2 - l1 - 2, PAdESSigner.contentsHexCapacity)
        let cmsHex = String(decoding: signed.subdata(in: hexStart..<(o2 - 1)), as: UTF8.self)
        XCTAssertTrue(cmsHex.allSatisfy(\.isHexDigit))
        let cms = Data(hexEncoded: String(cmsHex.prefix(4096 * 2))) ?? Data()
        XCTAssertFalse(cms.isEmpty)
        let extracted = Self.messageDigest(fromCMS: cms)
        XCTAssertEqual(extracted, recomputedDigest,
                       "messageDigest v CMS sa musí zhodovať s SHA-256 nad ByteRange rozsahmi.")
        XCTAssertTrue(text.contains("/Annots"), "Widget musí byť pripojený na stránku cez /Annots.")
        XCTAssertTrue(text.contains("/Subtype /Widget"), "PAdES musí obsahovať podpisový widget.")
        XCTAssertTrue(text.contains("/AP << /N"), "Widget musí mať vzhľad /AP, inak Preview podpis neukáže.")
        XCTAssertEqual(cms.first, 0x30)
        let cmsBytes = [UInt8](cms)
        // ContentInfo → [0] SignedData → last child before end must be SET OF SignerInfos (0x31)
        if let root = DERNode.firstTLV(bytes: cmsBytes, at: 0),
           let explicit = DERNode.children(bytes: cmsBytes, in: root.contentRange).dropFirst().first,
           let signedData = DERNode.children(bytes: cmsBytes, in: explicit.contentRange).first {
            let kids = DERNode.children(bytes: cmsBytes, in: signedData.contentRange)
            XCTAssertTrue(kids.contains(where: { $0.tag == 0x31 && $0.offset > signedData.offset + 20 }),
                          "signerInfos musí byť SET (0x31), nie SEQUENCE.")
        }

        let xrefStart = try XCTUnwrap(PAdESSigner.indexOf(signed, ascii: "xref\n", from: source.count))
        let xrefText = String(decoding: signed.subdata(in: xrefStart..<signed.count), as: UTF8.self)
        let offsetRegex = try NSRegularExpression(pattern: #"(?m)^(\d{10}) 00000 n $"#)
        let offsetMatches = offsetRegex.matches(in: xrefText, range: NSRange(xrefText.startIndex..., in: xrefText))
        XCTAssertFalse(offsetMatches.isEmpty)
        for match in offsetMatches {
            let offset = Int(xrefText[Range(match.range(at: 1), in: xrefText)!])!
            let header = String(decoding: signed.subdata(in: offset..<min(offset + 12, signed.count)), as: UTF8.self)
            XCTAssertTrue(header.contains("0 obj"), "xref offset \(offset) musí ukazovať na objekt, nie na nový riadok: \(header)")
        }

        let png = Self.makeTestPNG(width: 40, height: 20)
        let stamped = try await signer.sign(pdf: source,
                                            certificateDER: fakeCertificate,
                                            signer: rawSigner,
                                            includeTimestamp: false,
                                            tsaURL: nil,
                                            stamp: VisualStampSpec(fullName: "Marián Čuprík",
                                                                   timestamp: Date(),
                                                                   pageIndex: 0,
                                                                   normalizedRect: NormalizedRect(x: 0.6, y: 0.8, width: 0.3, height: 0.09),
                                                                   imagePNG: png))
        let stampedText = String(decoding: stamped, as: UTF8.self)
        XCTAssertTrue(stampedText.contains("/Subtype /Image"), "PNG musí byť vložené ako image XObject.")
        XCTAssertTrue(stampedText.contains("/SMask"), "PNG transparentnosť musí ísť cez /SMask.")
        XCTAssertTrue(stampedText.contains("/Im0 Do"), "Appearance musí kresliť vložený obraz.")

        let rendered = try XCTUnwrap(PDFDocument(data: stamped))
        XCTAssertEqual(rendered.pageCount, pageCount)
        let stampPage = try XCTUnwrap(rendered.page(at: 0))
        let norm = NormalizedRect(x: 0.6, y: 0.8, width: 0.3, height: 0.09)
        let widgetRect = CGRect(x: norm.x * 595,
                                y: (1 - norm.y - norm.height) * 842,
                                width: max(norm.width * 595, 90),
                                height: max(norm.height * 842, 30))
        let ink = Self.inkPixels(in: stampPage, pdfRect: widgetRect)
        XCTAssertGreaterThan(ink, 50, "Widget appearance sa musí vykresliť (ink=\(ink)) — BBox/obsah musia byť validné pre CoreGraphics.")
    }

    static func inkPixels(in page: PDFPage, pdfRect: CGRect) -> Int {
        let nsimg = page.thumbnail(of: CGSize(width: 595, height: 842), for: .mediaBox)
        var rect = CGRect(origin: .zero, size: nsimg.size)
        guard let cg = nsimg.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return 0 }
        let scale = CGFloat(cg.width) / 595.0
        let rep = NSBitmapImageRep(cgImage: cg)
        var ink = 0
        var py = Int(pdfRect.minY)
        while py < Int(pdfRect.maxY) {
            let row = Int(842.0 - Double(py) - 1.0)
            var x = Int(pdfRect.minX)
            while x < Int(pdfRect.maxX) {
                if let c = rep.colorAt(x: Int(Double(x) * scale), y: Int(Double(row) * scale)),
                   c.brightnessComponent < 0.92 {
                    ink += 1
                }
                x += 2
            }
            py += 1
        }
        return ink
    }

    static func makeTestPNG(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.7, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testRootScannerUsesAbsoluteStartxrefOnLargePDF() throws {
        let original = TestPDFBuilder.typicalContractPDF()
        guard let root = PDFObjectScanner.rootObjectNumber(in: original) else {
            return XCTFail("pôvodný PDF musí mať čitateľný katalóg")
        }
        var padded = Data(repeating: 0x20, count: 400_000)
        padded.append(original)
        let shifted = PDFObjectScanner.rootObjectNumber(in: padded)
        XCTAssertNil(shifted, "štartxref je absolútny — padding pred súborom ho zneplatní")

        var commentPadded = original
        if commentPadded.last != UInt8(ascii: "\n") { commentPadded.append(0x0A) }
        commentPadded.append(Data(repeating: 0x25, count: 300_000))
        commentPadded.append(Data("\nstartxref\n\(root.xrefOffset)\n%%EOF\n".utf8))
        let found = try XCTUnwrap(PDFObjectScanner.rootObjectNumber(in: commentPadded))
        XCTAssertEqual(found.objectNumber, root.objectNumber)
        XCTAssertEqual(found.xrefOffset, root.xrefOffset)
    }

    static func messageDigest(fromCMS cms: Data) -> Data? {
        let bytes = [UInt8](cms)
        guard let root = DERNode.firstTLV(bytes: bytes, at: 0),
              let explicitContent = DERNode.children(bytes: bytes, in: root.contentRange).dropFirst().first,
              let signedData = DERNode.children(bytes: bytes, in: explicitContent.contentRange).first else { return nil }
        var signerInfos = DERNode.children(bytes: bytes, in: signedData.contentRange)
            .filter { $0.tag == 0x30 && $0.offset > signedData.offset + 20 }
        for setNode in DERNode.children(bytes: bytes, in: signedData.contentRange) where setNode.tag == 0x31 && setNode.offset > signedData.offset + 20 {
            signerInfos.append(contentsOf: DERNode.children(bytes: bytes, in: setNode.contentRange).filter { $0.tag == 0x30 })
        }
        for node in signerInfos {
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

