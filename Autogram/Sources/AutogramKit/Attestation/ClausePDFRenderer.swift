import Foundation
import CoreGraphics
import CoreText
import AppKit

public struct ClausePDFRenderer: Sendable {
    public init() {}

    public struct Section: Sendable {
        public var heading: String?
        public var lines: [(label: String, value: String)]

        public init(heading: String? = nil, lines: [(String, String)]) {
            self.heading = heading
            self.lines = lines.map { (label: $0.0, value: $0.1) }
        }
    }

    public func render(title: String, subtitle: String?, sections: [Section]) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return Data() }
        var box = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            return Data()
        }

        let attributed = buildAttributedText(title: title, subtitle: subtitle, sections: sections)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let totalLength = CFAttributedStringGetLength(attributed)

        let inset: CGFloat = 64
        let textRect = CGRect(x: inset, y: inset,
                              width: pageRect.width - inset * 2,
                              height: pageRect.height - inset * 2)
        var rendered = 0

        context.beginPDFPage(nil)
        while rendered < totalLength {
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter,
                                                 CFRange(location: rendered, length: 0),
                                                 path, nil)
            context.saveGState()
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1.0, y: -1.0)
            CTFrameDraw(frame, context)
            context.restoreGState()

            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            rendered += visible.length
            if rendered < totalLength {
                context.endPDFPage()
                context.beginPDFPage(nil)
            }
        }
        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private func buildAttributedText(title: String, subtitle: String?,
                                     sections: [Section]) -> CFAttributedString {
        let result = NSMutableAttributedString()
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 17, nil)
        let headFont = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 12, nil)
        let labelFont = CTFontCreateWithName("HelveticaNeue" as CFString, 10.5, nil)
        let valueFont = CTFontCreateWithName("HelveticaNeue" as CFString, 10.5, nil)

        func append(_ text: String, font: CTFont, color: NSColor = .black, spacingAfter: CGFloat = 4) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = spacingAfter
            style.lineSpacing = 1.2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ]
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        append(title + "\n", font: titleFont, spacingAfter: 2)
        if let subtitle, !subtitle.isEmpty {
            append(subtitle + "\n", font: labelFont, color: .darkGray, spacingAfter: 12)
        } else {
            append("\n", font: labelFont, spacingAfter: 10)
        }

        for section in sections {
            if let heading = section.heading {
                append(heading + "\n", font: headFont, spacingAfter: 4)
            }
            for line in section.lines {
                append("\(line.label): ", font: labelFont, color: .darkGray)
                append(line.value + "\n", font: valueFont, spacingAfter: 2)
            }
            append("\n", font: labelFont, spacingAfter: 4)
        }

        return result
    }
}
