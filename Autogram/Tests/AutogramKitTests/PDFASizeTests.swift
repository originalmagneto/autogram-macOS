import XCTest
import PDFKit
@testable import AutogramKit

final class PDFASizeTests: XCTestCase {
    func testRasterPDFIsJPEGCompressed() throws {
        let pdf = TestPDFBuilder.typicalContractPDF()
        let doc = try XCTUnwrap(PDFDocument(data: pdf))
        let raster = try PDFAConverter().convert(document: doc, mode: .rasterGuaranteed, title: "t")
        // 3 strany A4 raster musia zostať v stovkách KB, nie desiatkach MB
        XCTAssertLessThan(raster.count, 3_000_000, "Raster PDF/A je príliš veľký: \(raster.count) B")
        let check = PDFAValidator().validate(raster)
        XCTAssertTrue(check.isValid, "Raster výstup nie je PDF/A: \(check.issues)")
        XCTAssertEqual(String(decoding: pdf.prefix(8), as: UTF8.self).hasPrefix("%PDF-"), true)
    }
}
