import XCTest
import PDFKit
@testable import AutogramKit

final class PDFAConverterTests: XCTestCase {
    func testVectorPreservingConversionProducesPDFA2bMarkers() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let converter = PDFAConverter()
        let output = try converter.convert(document: source,
                                           mode: .vectorPreserving,
                                           title: "Zmluva o dielo")

        XCTAssertTrue(output.starts(with: Data("%PDF-1.7".utf8)),
                      "Hlavička nie je PDF 1.7")
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("pdfaid:part=\"2\""))
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("pdfaid:conformance=\"B\""))
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("/GTS_PDFA1"))

        let reopened = try XCTUnwrap(PDFDocument(data: output),
                                     "Výstup sa nedá otvoriť v PDFKit")
        XCTAssertEqual(reopened.pageCount, source.pageCount)
        XCTAssertTrue(reopened.page(at: 0)?.string?.contains("ZMLUVA") == true,
                      "Textová vrstva musí zostať zachovaná pri vektorovom režime")
    }

    func testRasterModeFlattensAndPreservesPageCount() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let converter = PDFAConverter()
        let output = try converter.convert(document: source,
                                           mode: .rasterGuaranteed,
                                           title: "Rastr")

        let reopened = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(reopened.pageCount, 3)
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("pdfaid"))
    }

    func testIncrementalUpdateKeepsOriginalObjectsReadable() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let converter = PDFAConverter()
        let output = try converter.convert(document: source)

        guard let root = PDFObjectScanner.rootObjectNumber(in: output) else {
            return XCTFail("Nový katalóg nebol nájdený cez startxref reťazec.")
        }
        XCTAssertGreaterThan(root.xrefOffset, 0)
    }

    func testEmbeddedFileIsInjectedAndDiscoverable() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let converter = PDFAConverter()
        let pdfa = try converter.convert(document: source, title: "t")

        let xmlPayload = "<ConversionRecord><Test>hodnota</Test></ConversionRecord>"
        let service = EmbeddedFileService()
        let withAttachment = try service.embed(
            .init(fileName: "osvedcovacia-dolozka.xml",
                  mimeType: "text+xml",
                  data: Data(xmlPayload.utf8)),
            into: pdfa)

        let text = String(decoding: withAttachment, as: UTF8.self)
        XCTAssertTrue(text.contains("/EmbeddedFiles"))
        XCTAssertTrue(text.contains("osvedcovacia-dolozka.xml"))
        XCTAssertTrue(text.contains(xmlPayload))

        let reopened = try XCTUnwrap(PDFDocument(data: withAttachment))
        XCTAssertEqual(reopened.pageCount, 3)
    }

    func testForceVersionHeader() {
        var data = Data("%PDF-1.4\n%âãÏÓ".utf8)
        data.append(Data(repeating: 0x41, count: 64))
        let forced = PDFAConverter.forceVersionHeader(data)
        XCTAssertTrue(forced.starts(with: Data("%PDF-1.7".utf8)))
    }
}
