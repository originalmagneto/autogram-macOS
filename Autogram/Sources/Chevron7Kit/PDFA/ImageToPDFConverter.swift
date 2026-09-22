import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageToPDFConverter {
    public static let supportedTypes: [UTType] = [.jpeg, .png, .tiff, .heic]

    public static func isSupportedImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let utType = CGImageSourceGetType(source) as String? else { return false }
        return supportedTypes.contains { $0.identifier == utType }
    }

    public static func pdf(fromImageData data: Data, dpi: CGFloat = 200) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let pageCount = CGImageSourceGetCount(source)
        guard pageCount > 0 else { return nil }

        let scale = dpi / 72.0
        var pageDatas: [Data] = []

        for index in 0..<pageCount {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let widthPt = ceil(CGFloat(image.width) / max(scale, 0.01))
            let heightPt = ceil(CGFloat(image.height) / max(scale, 0.01))
            var box = CGRect(x: 0, y: 0, width: widthPt, height: heightPt)

            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { continue }
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(box)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: box)
            ctx.endPDFPage()
            ctx.closePDF()
            pageDatas.append(pdfData as Data)
        }

        return PDFAConverter.mergePageDatas(pageDatas)
    }
}
