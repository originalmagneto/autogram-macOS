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

    func testUnimplementedOutputProfilesAreRejected() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let proposedProfile = ConversionOutputProfile.proposedPDFA1a

        XCTAssertThrowsError(try PDFAConverter().convert(
            document: document,
            profile: proposedProfile)) { error in
            XCTAssertEqual(error as? PDFAError,
                           .unsupportedOutputProfile(proposedProfile.id))
        }
        let validation = PDFAValidator().validate(Data(), profile: proposedProfile)
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains { $0.contains("nie je implementovaný") })
    }

    func testConversionOutputNamingUsesOriginalDocumentAndSiblingDirectory() throws {
        XCTAssertEqual(
            ConversionOutputNaming.pdfFileName(
                originalDocumentName: "Brezinová_diplom.pdf",
                requestedDocumentName: "Diplom PDF"),
            "Brezinová_diplom-Diplom PDF.pdf")
        XCTAssertEqual(
            ConversionOutputNaming.xdcfFileName(
                originalDocumentName: "Brezinová_diplom.pdf",
                pdfFileName: "Brezinová_diplom-Diplom PDF.pdf",
                evidenceNumber: "1563-260828-1"),
            "Brezinová_diplom-Diplom PDF-1563-260828-1.xml.xdcf")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zako-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("origin.pdf")
        try Data("pdf".utf8).write(to: source)
        XCTAssertEqual(ConversionOutputNaming.outputDirectory(sourceURL: source, fallback: URL(fileURLWithPath: "/tmp")), directory)
    }

    func testEngineNormalizationIsAvailableWhenBundledEngineIsInstalled() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let sourceData = try XCTUnwrap(source.dataRepresentation())
        guard JavaEngineLocator().locate() != nil else {
            throw XCTSkip("Bundled Java engine nie je nainštalovaný.")
        }

        let normalized = try XCTUnwrap(PDFAConverter.normalizeWithEngine(sourceData, title: "Test"))
        XCTAssertTrue(normalized.starts(with: Data("%PDF-".utf8)))
        XCTAssertTrue(String(decoding: normalized, as: UTF8.self).contains("pdfaid:part=\"2\""))
        XCTAssertEqual(PDFAValidator().validate(normalized).isValid, true,
                       "Java/PDFBox normalizovaný výstup musí prejsť lokálnou validáciou")
    }

    func testNormalizeForDeliveryRepairsAttachedPDF() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let converted = try PDFAConverter().convert(document: source)
        let attached = try EmbeddedFileService().embed(
            .init(fileName: "osvedcovacia-dolozka.xml", mimeType: "application/xml", data: Data("<x/>".utf8)),
            into: converted)
        let delivered = try PDFAConverter().normalizeForDelivery(attached, title: "Test")

        XCTAssertEqual(PDFAValidator().validate(delivered).isValid, true)
        let attachedText = String(decoding: attached, as: UTF8.self)
        XCTAssertTrue(attachedText.contains("/Subtype /application#2Fxml"))
        XCTAssertTrue(attachedText.contains("/Desc (application/xml)"))
        XCTAssertEqual(PDFDocument(data: delivered)?.pageCount, source.pageCount)
    }

    func testAttachedPDFKeepsValidPDFStructure() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let converted = try PDFAConverter().convert(document: source)
        let attached = try EmbeddedFileService().embed(
            .init(fileName: "osvedcovacia-dolozka.xml", mimeType: "application/xml", data: Data("<x/>".utf8)),
            into: converted)
        let delivered = try PDFAConverter().normalizeForDelivery(attached, title: "Test")
        XCTAssertEqual(PDFDocument(data: delivered)?.pageCount, source.pageCount)
        XCTAssertTrue(String(decoding: delivered, as: UTF8.self).contains("pdfaid:part=\"2\""))
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

    func testRasterModeKeepsUprightOrientation() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let rasterized = try PDFAConverter().convert(document: source, mode: .rasterGuaranteed)
        let output = try XCTUnwrap(PDFDocument(data: rasterized))
        let page = try XCTUnwrap(output.page(at: 0))
        let image = try XCTUnwrap(renderToImage(page: page))
        let width = image.width, height = image.height
        var topDark = 0, bottomDark = 0
        for x in stride(from: 0, to: width, by: 4) {
            for y in stride(from: 0, to: height, by: 4) {
                if y < height * 4 / 10, Self.isDark(image, x: x, y: y) { topDark += 1 }
                if y > height * 6 / 10, Self.isDark(image, x: x, y: y) { bottomDark += 1 }
            }
        }
        XCTAssertGreaterThan(topDark, bottomDark,
                             "Rasterizovaná strana je prevrátená — text musí ostať hore (top=\(topDark), bottom=\(bottomDark)).")
    }
    func testRasterModeHandlesRotatedPageWithoutCropping() throws {
        let source = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        try XCTUnwrap(source.page(at: 0)).rotation = 270
        let sourceBounds = try XCTUnwrap(source.page(at: 0)).bounds(for: .mediaBox)
        let output = try XCTUnwrap(PDFDocument(data: PDFAConverter().convert(
            document: source,
            mode: .rasterGuaranteed)))
        let outputPage = try XCTUnwrap(output.page(at: 0))
        let outputBounds = outputPage.bounds(for: .mediaBox)
        XCTAssertEqual(round(outputBounds.width), round(sourceBounds.height))
        XCTAssertEqual(round(outputBounds.height), round(sourceBounds.width))
        let image = try XCTUnwrap(renderToImage(page: outputPage))
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
        XCTAssertGreaterThan(Self.darkPixels(in: image, x: 0, y: 0, width: image.width / 2, height: image.height / 2), 10)
    }


    private func renderToImage(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 1.5
        guard bounds.width > 1, bounds.height > 1,
              let ctx = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: Int(bounds.width * scale) * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        if let ref = page.pageRef {
            ctx.drawPDFPage(ref)
        }
        return ctx.makeImage()
    }
    private static func darkPixels(in image: CGImage, x: Int, y: Int, width: Int, height: Int) -> Int {
        var count = 0
        for row in stride(from: y, to: min(y + height, image.height), by: 4) {
            for column in stride(from: x, to: min(x + width, image.width), by: 4) {
                if isDark(image, x: column, y: row) { count += 1 }
            }
        }
        return count
    }

    private static func isDark(_ image: CGImage, x: Int, y: Int) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        let offset = y * image.bytesPerRow + x * 4
        guard offset + 3 < CFDataGetLength(data) else { return false }
        return (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) < 300
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
        XCTAssertTrue(text.contains("/AFRelationship /Data"))
        XCTAssertTrue(text.contains("/AF ["))
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
