import XCTest
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import AutogramKit

final class ImageToPDFConverterTests: XCTestCase {
    private func makeJPEG(width: Int = 600, height: Int = 848,
                          color: CGColor = CGColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1)) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 4,
                                   width: width / 2, height: height / 2))
        let image = ctx.makeImage()!

        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testConvertsSingleJPEGToSinglePagePDF() throws {
        let jpeg = makeJPEG()
        XCTAssertTrue(ImageToPDFConverter.isSupportedImage(jpeg))

        let pdfData = try XCTUnwrap(ImageToPDFConverter.pdf(fromImageData: jpeg))
        XCTAssertTrue(pdfData.starts(with: Data("%PDF".utf8)))

        let document = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(document.pageCount, 1)

        let bounds = document.page(at: 0)!.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, ceil(600 * 72.0 / 200.0), accuracy: 2.0)
    }

    func testConvertsMultiPageTIFFIntoMultiPagePDF() throws {
        let images: [CGImage] = (0..<3).map { index in
            let ctx = CGContext(data: nil, width: 400, height: 560, bitsPerComponent: 8,
                                bytesPerRow: 400 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(index.isMultiple(of: 2) ? CGColor(red: 1, green: 0, blue: 0, alpha: 1)
                                                      : CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 100, y: 140, width: 200, height: 280))
            return ctx.makeImage()!
        }

        let tiffOut = NSMutableData()
        let dest = CGImageDestinationCreateWithData(tiffOut, UTType.tiff.identifier as CFString, 3, nil)!
        for image in images { CGImageDestinationAddImage(dest, image, nil) }
        CGImageDestinationFinalize(dest)

        let pdfData = try XCTUnwrap(ImageToPDFConverter.pdf(fromImageData: tiffOut as Data))
        let document = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(document.pageCount, 3, "Viacstránkový TIFF musí dať viacstránkové PDF")
    }

    func testRejectsNonImageData() throws {
        XCTAssertFalse(ImageToPDFConverter.isSupportedImage(Data("%PDF-1.7 fake".utf8)))
        XCTAssertNil(ImageToPDFConverter.pdf(fromImageData: Data("not an image".utf8)))
        XCTAssertNil(ImageToPDFConverter.pdf(fromImageData: Data()))
    }
}
