import XCTest
@testable import AutogramKit

final class AVMResultMapperTests: XCTestCase {
    private let personal = [AVMSigner(signedBy: "Ján Novák", issuedBy: "SVK eID ACA2")]
    private let mandate = [AVMSigner(signedBy: "JUDr. Ján Novák, mandát: advokát", issuedBy: "CA Disig QCA3")]

    func testPAdESResultKeepsSignedPDFAndNoContainer() throws {
        let document = AVMSignedDocument(filename: "a.pdf", mimeType: "application/pdf",
                                         content: Data("SIGNED".utf8).base64EncodedString(), signers: personal)
        let result = try AVMResultMapper.conversionResult(from: document, outputFormat: .embeddedPAdES,
                                                          uploadedPDF: Data("ORIG".utf8))
        XCTAssertEqual(result.pdfData, Data("SIGNED".utf8))
        XCTAssertNil(result.asicData)
        XCTAssertEqual(result.signatureLabel, "Ján Novák")
        XCTAssertTrue(result.isLegallyBinding)
        XCTAssertNil(result.timestampGenTime)
    }

    func testASiCResultKeepsUploadedPDFAndContainer() throws {
        let document = AVMSignedDocument(filename: "a.asice", mimeType: "application/vnd.etsi.asic-e+zip",
                                         content: Data("ZIP".utf8).base64EncodedString(), signers: personal)
        let result = try AVMResultMapper.conversionResult(from: document, outputFormat: .attachedASIC,
                                                          uploadedPDF: Data("ORIG".utf8))
        XCTAssertEqual(result.pdfData, Data("ORIG".utf8))
        XCTAssertEqual(result.asicData, Data("ZIP".utf8))
    }

    func testInvalidBase64Throws() {
        let document = AVMSignedDocument(filename: nil, mimeType: nil, content: "***", signers: nil)
        XCTAssertThrowsError(try AVMResultMapper.conversionResult(from: document, outputFormat: .embeddedPAdES, uploadedPDF: Data()))
    }

    func testMandateDetectionUsesSignerStrings() {
        XCTAssertFalse(AVMResultMapper.isMandate(signers: personal))
        XCTAssertTrue(AVMResultMapper.isMandate(signers: mandate))
        XCTAssertFalse(AVMResultMapper.isMandate(signers: []))
    }

    func testLabelJoinsMultipleSigners() {
        let label = AVMResultMapper.signatureLabel(signers: personal + mandate)
        XCTAssertEqual(label, "Ján Novák, JUDr. Ján Novák, mandát: advokát")
        XCTAssertEqual(AVMResultMapper.signatureLabel(signers: []), "Podpis z Autogram v mobile")
    }
}
