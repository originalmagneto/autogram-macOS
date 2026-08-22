import Foundation
import PDFKit
import CoreGraphics

public enum PDFAConversionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case vectorPreserving = "Vektorová zachovávajúca"
    case rasterGuaranteed = "Rasterizovaná garancia"

    public var id: String { rawValue }
}

public enum PDFAError: LocalizedError, Equatable, Sendable {
    case emptyDocument
    case missingSRGBProfile(path: String)
    case rootNotFound
    case catalogNotFound(Int)
    case serializationFailed

    public var errorDescription: String? {
        switch self {
        case .emptyDocument: return "Dokument je prázdny."
        case .missingSRGBProfile(let path): return "Chýba sRGB ICC profil: \(path)"
        case .rootNotFound: return "PDF nemá čitateľný koreňový katalóg."
        case .catalogNotFound(let num): return "Katalógová objekt #\(num) sa nepodarilo načítať."
        case .serializationFailed: return "Serializácia PDF zlyhala."
        }
    }
}

public struct PDFAConverter: Sendable {
    public var producer: String

    public init(producer: String = "Autogram ZaKo 1.0") {
        self.producer = producer
    }

    public static let sRGBProfileSystemPath = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"

    public func convert(document: PDFDocument,
                        mode: PDFAConversionMode = .vectorPreserving,
                        title: String = "") throws -> Data {
        guard document.pageCount > 0 else { throw PDFAError.emptyDocument }

        var baseData: Data
        switch mode {
        case .vectorPreserving:
            guard let data = document.dataRepresentation() else { throw PDFAError.serializationFailed }
            baseData = data
        case .rasterGuaranteed:
            baseData = try Self.rasterize(document: document)
        }

        baseData = Self.forceVersionHeader(baseData)
        return try injectPDFACompliance(into: baseData, title: title)
    }

    static func forceVersionHeader(_ data: Data) -> Data {
        var out = data
        let headerPrefix = Data("%PDF-1.".utf8)
        if out.count > 8 && out.prefix(headerPrefix.count) == headerPrefix {
            out.replaceSubrange(7..<8, with: Data("7".utf8))
        }
        return out
    }

    static func rasterize(document: PDFDocument, dpi: CGFloat = 300) throws -> Data {
        let scale = dpi / 72.0
        var pageDatas: [Data] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let image = Self.renderPageImage(page: page, scale: scale) else { continue }
            let width = ceil(CGFloat(image.width) / scale)
            let height = ceil(CGFloat(image.height) / scale)
            var box = CGRect(x: 0, y: 0, width: width, height: height)

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

        return Self.mergePageDatas(pageDatas)
    }

    static func mergePageDatas(_ datas: [Data]) -> Data {
        guard !datas.isEmpty else { return Data() }
        let output = PDFDocument()
        var insertionIndex = 0
        for data in datas {
            guard let document = PDFDocument(data: data) else { continue }
            for pageIndex in 0..<document.pageCount {
                if let page = document.page(at: pageIndex) {
                    output.insert(page, at: insertionIndex)
                    insertionIndex += 1
                }
            }
        }
        return output.dataRepresentation() ?? Data()
    }

    static func renderPageImage(page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let width = max(Int(bounds.width * scale), 8)
        let height = max(Int(bounds.height * scale), 8)

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        if let ref = page.pageRef {
            ctx.drawPDFPage(ref)
        }
        return ctx.makeImage()
    }

    func injectPDFACompliance(into base: Data, title: String) throws -> Data {
        let iccPath = Self.sRGBProfileSystemPath
        guard let icc = FileManager.default.contents(atPath: iccPath), !icc.isEmpty else {
            throw PDFAError.missingSRGBProfile(path: iccPath)
        }

        guard let root = PDFObjectScanner.rootObjectNumber(in: base) else {
            throw PDFAError.rootNotFound
        }
        guard let catalogDict = PDFObjectScanner.catalogDictionary(number: root.objectNumber, in: base) else {
            throw PDFAError.catalogNotFound(root.objectNumber)
        }

        let maxNumber = max(PDFObjectScanner.maxObjectNumber(in: base), root.objectNumber)
        let metaNumber = maxNumber + 1
        let iccNumber = maxNumber + 2
        let oiNumber = maxNumber + 3
        let newCatalogNumber = maxNumber + 4

        let xmp = Self.buildXMPPacket(title: title, producer: producer)
        let xmpBytes = Data(xmp.utf8)

        var metaObj = Data("\(metaNumber) 0 obj\n<< /Type /Metadata /Subtype /XML /Length \(xmpBytes.count) >>\nstream\n".utf8)
        metaObj.append(xmpBytes)
        metaObj.append(Data("\nendstream\nendobj\n".utf8))

        var iccObj = Data("\(iccNumber) 0 obj\n<< /N 3 /Length \(icc.count) >>\nstream\n".utf8)
        iccObj.append(icc)
        iccObj.append(Data("\nendstream\nendobj\n".utf8))

        let oiBody = "<< /Type /OutputIntent /S /GTS_PDFA1 /OutputConditionIdentifier (sRGB IEC61966-2.1)" +
            " /Info (sRGB IEC61966-2.1) /RegistryName (http://www.color.org)" +
            " /DestOutputProfile \(iccNumber) 0 R >>"
        let oiObj = Data("\n\(oiNumber) 0 obj\n\(oiBody)\nendobj\n".utf8)

        var augmented = catalogDict
        if !augmented.contains("/OutputIntents") {
            augmented = PDFObjectScanner.augmentDictionary(
                augmented,
                appending: " /Metadata \(metaNumber) 0 R /OutputIntents [\(oiNumber) 0 R]")
        }
        let catalogObj = Data("\n\(newCatalogNumber) 0 obj\n\(augmented)\nendobj\n".utf8)

        var out = base
        var offsets: [(number: Int, offset: Int)] = []

        func trackAndAppend(_ chunk: Data, number: Int) {
            offsets.append((number, out.count))
            out.append(chunk)
        }

        trackAndAppend(metaObj, number: metaNumber)
        trackAndAppend(iccObj, number: iccNumber)
        trackAndAppend(oiObj, number: oiNumber)
        trackAndAppend(catalogObj, number: newCatalogNumber)

        let xrefOffset = out.count
        let firstNew = metaNumber
        let count = newCatalogNumber - firstNew + 1
        let byNumber = Dictionary(uniqueKeysWithValues: offsets.map { ($0.number, $0.offset) })

        var xref = Data("xref\n\(firstNew) \(count)\n".utf8)
        for n in firstNew...newCatalogNumber {
            let off = byNumber[n] ?? 0
            xref.append(Data(String(format: "%010d %05d n \n", off, 0).utf8))
        }
        let trailer = """
        trailer
        << /Size \(newCatalogNumber + 1) /Root \(newCatalogNumber) 0 R /Prev \(root.xrefOffset) >>
        startxref
        \(xrefOffset)
        %%EOF

        """
        xref.append(Data(trailer.utf8))
        out.append(xref)

        return out
    }

    static func buildXMPPacket(title: String, producer: String) -> String {
        let iso = ISO8601DateFormatter().string(from: Date())
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:pdf="http://ns.adobe.com/pdf/1.3/"
            xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"
            pdfaid:part="2"
            pdfaid:conformance="B">
           <dc:title><rdf:Alt><rdf:li xml:lang="x-default">\(xmlEscape(title))</rdf:li></rdf:Alt></dc:title>
           <pdf:Producer>\(xmlEscape(producer))</pdf:Producer>
           <xmp:CreateDate>\(iso)</xmp:CreateDate>
           <xmp:ModifyDate>\(iso)</xmp:ModifyDate>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public enum PDFObjectScanner {
    public struct RootRef: Equatable, Sendable {
        public var objectNumber: Int
        public var xrefOffset: Int
    }

    public static func rootObjectNumber(in data: Data) -> RootRef? {
        let tailText = String(decoding: data.suffix(min(data.count, 4096)), as: UTF8.self)
        guard let xrefRange = tailText.range(of: "startxref") else { return nil }
        let afterStart = tailText[xrefRange.upperBound...]
        let tokens = afterStart.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" })
        guard let rawOffset = tokens.first,
              let xrefOffset = Int(rawOffset.trimmingCharacters(in: CharacterSet.whitespaces)),
              xrefOffset >= 0, xrefOffset < data.count else { return nil }

        let regionEnd = min(xrefOffset + 4096, data.count)
        let region = String(decoding: data.subdata(in: xrefOffset..<regionEnd), as: UTF8.self)

        guard let rootRange = region.range(of: "/Root") else { return nil }
        let rest = region[rootRange.upperBound...]
        let nums = rest.split { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == ">" }
        guard nums.count >= 2, let num = Int(nums[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        return RootRef(objectNumber: num, xrefOffset: xrefOffset)
    }

    public static func catalogDictionary(number: Int, in data: Data) -> String? {
        let pattern = Data("\(number) 0 obj".utf8)
        guard let found = data.range(of: pattern, options: .backwards) else { return nil }

        let headEnd = min(found.lowerBound + 128, data.count)
        let head = String(decoding: data.subdata(in: found.lowerBound..<headEnd), as: UTF8.self)
        guard let openRange = head.range(of: "<<") else { return nil }
        let dictStartDataOffset = found.lowerBound + head.distance(from: head.startIndex, to: openRange.lowerBound)

        var depth = 0
        var i = dictStartDataOffset
        var inString = false
        var escape = false

        while i < data.count {
            let b = data[data.startIndex + i]

            if inString {
                if escape { escape = false }
                else if b == 0x5C { escape = true }
                else if b == 0x29 { inString = false }
                i += 1
                continue
            }
            if b == 0x28 { inString = true; i += 1; continue }
            if b == 0x3C && i + 1 < data.count && data[data.startIndex + i + 1] == 0x3C {
                depth += 1; i += 2; continue
            }
            if b == 0x3E && i + 1 < data.count && data[data.startIndex + i + 1] == 0x3E {
                depth -= 1
                if depth == 0 {
                    let slice = data.subdata(in: dictStartDataOffset..<i + 2)
                    return String(decoding: slice, as: UTF8.self)
                }
                i += 2; continue
            }
            i += 1
        }
        return nil
    }

    public static func augmentDictionary(_ dict: String, appending suffix: String) -> String {
        guard let range = dict.range(of: ">>", options: .backwards) else { return dict }
        return dict[dict.startIndex..<range.lowerBound] + suffix + " " + dict[range.lowerBound...]
    }

    public static func maxObjectNumber(in data: Data) -> Int {
        let text = String(decoding: data, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\s+0\\s+obj") else { return 1 }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var maxNum = 0
        for m in matches {
            let group = nsText.substring(with: m.range(at: 1))
            if let n = Int(group), n > maxNum { maxNum = n }
        }
        return max(maxNum, 1)
    }
}
