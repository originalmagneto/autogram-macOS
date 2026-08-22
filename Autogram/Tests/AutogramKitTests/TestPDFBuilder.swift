import Foundation
import CoreGraphics
import PDFKit
@testable import AutogramKit

enum TestPDFBuilder {
    static func build(pages: [(size: CGSize, draw: (CGContext, CGSize) -> Void)]) -> Data {
        var pageDatas: [Data] = []

        for page in pages {
            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
                fatalError("consumer")
            }
            var mediaBox = CGRect(origin: .zero, size: page.size)
            guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                fatalError("context")
            }
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(mediaBox)
            page.draw(ctx, page.size)
            ctx.endPDFPage()
            ctx.closePDF()
            pageDatas.append(pdfData as Data)
        }

        return PDFAConverter.mergePageDatas(pageDatas)
    }

    static func text(_ text: String, at point: CGPoint, size: CGFloat = 14,
                     color: CGColor = CGColor(gray: 0.1, alpha: 1)) -> (CGContext, CGSize) -> Void {
        { context, _ in
            context.saveGState()
            context.setFillColor(color)
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .black]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = point
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    static func filledCircle(center: CGPoint, radius: CGFloat,
                             color: CGColor) -> (CGContext, CGSize) -> Void {
        { context, _ in
            context.saveGState()
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
            context.restoreGState()
        }
    }

    static func ring(center: CGPoint, radius: CGFloat, lineWidth: CGFloat,
                     color: CGColor) -> (CGContext, CGSize) -> Void {
        { context, _ in
            context.saveGState()
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2))
            context.restoreGState()
        }
    }

    static func polyline(points: [CGPoint], lineWidth: CGFloat,
                         color: CGColor = CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)) -> (CGContext, CGSize) -> Void {
        { context, _ in
            guard points.count > 1 else { return }
            context.saveGState()
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: points[0])
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
            context.restoreGState()
        }
    }

    static func typicalContractPDF() -> Data {
        let a4 = CGSize(width: 595, height: 842)
        var signaturePoints: [CGPoint] = []
        for i in 0...24 {
            let x = CGFloat(70 + i * 9)
            let y = CGFloat(120 + (i % 2 == 0 ? 6 : -4))
            signaturePoints.append(CGPoint(x: x, y: y))
        }

        return build(pages: [
            (a4, { ctx, size in
                text("ZMLUVA O DIELO", at: CGPoint(x: 60, y: size.height - 90))(ctx, size)
                text("uzavretá medzi stranami podľa zákona č. 513/1991 Z. z.", at: CGPoint(x: 60, y: size.height - 120))(ctx, size)
                for i in 0..<18 {
                    text("Paragraf \(i + 1): Zmluvné strany sa dohodli na nasledovných podmienkach plnenia.",
                         at: CGPoint(x: 60, y: CGFloat(700 - i * 26)), size: 10)(ctx, size)
                }
                ring(center: CGPoint(x: size.width - 110, y: 150),
                     radius: 42, lineWidth: 4,
                     color: CGColor(red: 0.15, green: 0.25, blue: 0.85, alpha: 1))(ctx, size)
                polyline(points: signaturePoints, lineWidth: 3.5)(ctx, size)
            }),
            (a4, { _, _ in }),
            (CGSize(width: 1191, height: 842), { ctx, size in
                text("PRÍLOHA Č. 1", at: CGPoint(x: 80, y: size.height - 100))(ctx, size)
            })
        ])
    }

    static func singlePageWhitePDF() -> Data {
        build(pages: [(CGSize(width: 595, height: 842), { _, _ in })])
    }
}

import AppKit
