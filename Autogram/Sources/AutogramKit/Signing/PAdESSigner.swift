import Foundation
import Security
import CryptoKit

public enum PAdESError: LocalizedError, Sendable {
    case rootNotFound
    case contentsTooLarge(required: Int)
    case signingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .rootNotFound: return "PDF nemá čitateľný katalóg pre vloženie podpisu."
        case .contentsTooLarge(let required):
            return "CMS podpis (\(required) B) sa nezmestil do rezervovaného miesta."
        case .signingFailed(let detail): return "PAdES podpisovanie zlyhalo: \(detail)"
        }
    }
}

public struct PAdESSigner: Sendable {
    public init() {}

        static let contentsHexCapacity = 32768

    public func sign(pdf: Data,
                     certificateDER: Data,
                     signer: RawSigner,
                     reason: String = "Autorizácia dokumentu — Autogram",
                     includeTimestamp: Bool,
                     tsaURL: URL?,
                     stamp: VisualStampSpec? = nil) async throws -> Data {
        var base = pdf
        if base.last != UInt8(ascii: "\n") { base.append(Data("\n".utf8)) }

        guard let root = PDFObjectScanner.rootObjectNumber(in: base),
              let catalogDict = PDFObjectScanner.catalogDictionary(number: root.objectNumber, in: base) else {
            throw PAdESError.rootNotFound
        }

        let maxNumber = max(PDFObjectScanner.maxObjectNumber(in: base), root.objectNumber)
        let widgetNumber = maxNumber + 1
        let acroFormNumber = maxNumber + 2
        let catalogNumber = maxNumber + 3
        let sigNumber = maxNumber + 4
        let smaskNumber = maxNumber + 5
        let imageNumber = maxNumber + 6
        let appearanceNumber = maxNumber + 7

        let zeroContents = String(repeating: "0", count: Self.contentsHexCapacity)
        let byteRangeTemplate = "/ByteRange [0000000000 0000000000 0000000000 0000000000]"
        let mDateFormatter = DateFormatter()
        mDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        mDateFormatter.timeZone = TimeZone(identifier: "GMT")
        mDateFormatter.dateFormat = "yyyyMMddHHmmss"
        let mDateString = "D:\(mDateFormatter.string(from: Date()))+00'00'"
        let escapedReason = reason
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "á", with: "a")
            .replacingOccurrences(of: "č", with: "c")
            .replacingOccurrences(of: "í", with: "i")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")

        var sigDict = "<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /ETSI.CAdES.detached "
        sigDict += byteRangeTemplate + " "
        sigDict += "/Contents <\(zeroContents)> "
        sigDict += "/Reason (\(escapedReason)) /M (\(mDateString)) >>"

        let augmentedCatalog = PDFObjectScanner.augmentDictionary(
            catalogDict, appending: "/AcroForm \(acroFormNumber) 0 R")

        var objects: [(number: Int, body: Data)] = []
        func objectBody(_ number: Int, _ dict: String) -> Data {
            Data("\(number) 0 obj\n\(dict)\nendobj\n".utf8)
        }

        let pageNumber = stamp.flatMap { Self.pageObjectNumber(for: $0.pageIndex, catalog: catalogDict, in: base) }
            ?? PDFObjectScanner.firstPageObjectNumber(catalog: catalogDict, in: base)
        let mediaBox = pageNumber.flatMap { PDFObjectScanner.catalogDictionary(number: $0, in: base) }
            .flatMap(Self.mediaBox(of:)) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        let stampRect: CGRect
        if let stamp {
            let r = stamp.normalizedRect
            stampRect = CGRect(x: mediaBox.minX + r.x * mediaBox.width,
                               y: mediaBox.minY + (1 - r.y - r.height) * mediaBox.height,
                               width: max(r.width * mediaBox.width, 90),
                               height: max(r.height * mediaBox.height, 30))
        } else {
            stampRect = CGRect(x: 36, y: 36, width: 180, height: 48)
        }

        var appearanceRefs = ""
        var extraObjects: [(number: Int, body: Data)] = []
        if let png = stamp?.imagePNG,
           let raster = Self.decodeRGBA(png) {
            let (rgb, alpha) = Self.splitAlpha(raster)
            let rgbZ = Self.zlibCompress(rgb)
            let alphaZ = Self.zlibCompress(alpha)
            let imageDict =
                "<< /Type /XObject /Subtype /Image /Width \(raster.width) /Height \(raster.height) " +
                "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /SMask \(smaskNumber) 0 R " +
                "/Length \(rgbZ.count) >>\nstream\n"
            var imageBody = Data("\(imageNumber) 0 obj\n".utf8)
            imageBody.append(Data(imageDict.utf8))
            imageBody.append(rgbZ)
            imageBody.append(Data("\nendstream\nendobj\n".utf8))
            let smaskDict =
                "<< /Type /XObject /Subtype /Image /Width \(raster.width) /Height \(raster.height) " +
                "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length \(alphaZ.count) >>\nstream\n"
            var smaskBody = Data("\(smaskNumber) 0 obj\n".utf8)
            smaskBody.append(Data(smaskDict.utf8))
            smaskBody.append(alphaZ)
            smaskBody.append(Data("\nendstream\nendobj\n".utf8))
            extraObjects.append((smaskNumber, smaskBody))
            extraObjects.append((imageNumber, imageBody))
            appearanceRefs = "/XObject << /Im0 \(imageNumber) 0 R >>"
        }

        let w = Self.pdfNumber(stampRect.width)
        let h = Self.pdfNumber(stampRect.height)
        let name = Self.asciiFold(stamp?.fullName ?? "Elektronicky podpisane")
        let stampDate = stamp.map { stamp in
            let f = DateFormatter()
            f.dateFormat = "d. M. yyyy HH:mm"
            f.locale = Locale(identifier: "sk_SK")
            return f.string(from: stamp.timestamp)
        } ?? ""
        let esc = name.replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let certificateText = stamp?.certificateName.map { Self.asciiFold($0) } ?? ""
        let qtsText = stamp?.timestampAuthorityName.map { Self.asciiFold($0) } ?? ""
        let escapedCertificate = certificateText
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let escapedQTS = qtsText
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let appearanceStream: String
        if stamp?.imagePNG != nil {
            let imageW = Self.pdfNumber(stampRect.height * 0.9)
            let textX = Self.pdfNumber(stampRect.height * 0.9 + 6)
            let textW = Self.pdfNumber(stampRect.width - stampRect.height * 0.9 - 10)
            appearanceStream =
                "q 0.96 0.97 0.985 rg 0 0 \(w) \(h) re f Q\n" +
                "q 0.15 0.28 0.48 RG 1.1 w 0.55 0.55 \(Self.pdfNumber(stampRect.width - 1.1)) \(Self.pdfNumber(stampRect.height - 1.1)) re S Q\n" +
                "q 0.96 0.97 0.985 rg \(textX) 1.5 \(textW) \(Self.pdfNumber(stampRect.height - 3)) re f Q\n" +
                "q \(imageW) 0 0 \(h) 0 0 cm /Im0 Do Q\n" +
                "q 0.15 0.28 0.48 RG 0.8 w \(textX) 1.5 \(textW) \(Self.pdfNumber(stampRect.height - 3)) re S Q\n" +
                "BT /Helv 6.5 Tf 0.35 0.45 0.6 rg \(Self.pdfNumber(stampRect.height * 0.9 + 8)) \(Self.pdfNumber(stampRect.height - 11)) Td (Elektronicky podpisane) Tj ET\n" +
                "BT /Helv 8.5 Tf 0.1 0.1 0.12 rg \(Self.pdfNumber(stampRect.height * 0.9 + 8)) \(Self.pdfNumber(stampRect.height - 23)) Td (\(esc)) Tj ET\n" +
                (certificateText.isEmpty ? "" :
                    "BT /Helv 5.5 Tf 0.35 0.4 0.45 rg \(Self.pdfNumber(stampRect.height * 0.9 + 8)) \(Self.pdfNumber(stampRect.height - 34)) Td (Certifikat: \(escapedCertificate)) Tj ET\n") +
                (qtsText.isEmpty ? "" :
                    "BT /Helv 5.5 Tf 0.35 0.4 0.45 rg \(Self.pdfNumber(stampRect.height * 0.9 + 8)) 5 Td (QTS: \(escapedQTS)) Tj ET\n")
        } else {
            appearanceStream =
                "q 0.96 0.97 0.985 rg 0 0 \(w) \(h) re f Q\n" +
                "q 0.15 0.28 0.48 RG 1.1 w 0.55 0.55 \(Self.pdfNumber(stampRect.width - 1.1)) \(Self.pdfNumber(stampRect.height - 1.1)) re S Q\n" +
                "BT /Helv 6.5 Tf 0.35 0.45 0.6 rg 7 \(Self.pdfNumber(stampRect.height - 11)) Td (Elektronicky podpisane · KEP) Tj ET\n" +
                "BT /Helv 9 Tf 0.1 0.1 0.12 rg 7 \(Self.pdfNumber(stampRect.height - 24)) Td (\(esc)) Tj ET\n" +
                (stampDate.isEmpty ? "" :
                    "BT /Helv 7.5 Tf 0.35 0.4 0.45 rg 7 6 Td (\(stampDate)) Tj ET\n")
        }
        let appearanceData = Data(appearanceStream.utf8)
        let appearanceObject =
            "<< /Type /XObject /Subtype /Form /BBox [0 0 \(w) \(h)] " +
            "/Resources << /Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> \(appearanceRefs) >> " +
            "/Length \(appearanceData.count) >>\nstream\n"
        var appearanceBody = Data("\(appearanceNumber) 0 obj\n".utf8)
        appearanceBody.append(Data(appearanceObject.utf8))
        appearanceBody.append(appearanceData)
        appearanceBody.append(Data("\nendstream\nendobj\n".utf8))

        let pageRect = "[\(Int(stampRect.minX)) \(Int(stampRect.minY)) \(Int(stampRect.maxX)) \(Int(stampRect.maxY))]"
        var widgetDict = "<< /Type /Annot /Subtype /Widget /FT /Sig /Rect \(pageRect) /F 4 /V \(sigNumber) 0 R"
        if let pageNumber {
            widgetDict += " /P \(pageNumber) 0 R"
        }
        widgetDict += " /T (Signature1) /AP << /N \(appearanceNumber) 0 R >> >>"
        objects.append((widgetNumber, objectBody(widgetNumber, widgetDict)))
        objects.append((acroFormNumber, objectBody(acroFormNumber,
            "<< /Fields [\(widgetNumber) 0 R] /SigFlags 3 >>")))
        objects.append((catalogNumber, objectBody(catalogNumber, augmentedCatalog)))
        objects.append((sigNumber, objectBody(sigNumber, sigDict)))
        objects.append((appearanceNumber, appearanceBody))
        objects.append(contentsOf: extraObjects)

        var updatedPage: (number: Int, body: Data)?
        if let pageNumber,
           let pageDict = PDFObjectScanner.catalogDictionary(number: pageNumber, in: base) {
            let newPage = PDFObjectScanner.pageWithAnnotation(pageDict: pageDict, widgetNumber: widgetNumber)
            updatedPage = (pageNumber, objectBody(pageNumber, newPage))
        }

        var out = base
        var offsets: [Int: Int] = [:]
        if let updatedPage {
            offsets[updatedPage.number] = out.count
            out.append(updatedPage.body)
        }
        for (number, body) in objects {
            offsets[number] = out.count
            out.append(body)
        }

        let xrefOffset = out.count
        var xref = Data("xref\n".utf8)
        if let updatedPage {
            xref.append(Data("\(updatedPage.number) 1\n".utf8))
            xref.append(Data(String(format: "%010d %05d n \n", offsets[updatedPage.number] ?? 0, 0).utf8))
        }
        xref.append(Data("\(widgetNumber) \(objects.count)\n".utf8))
        for (number, _) in objects {
            xref.append(Data(String(format: "%010d %05d n \n", offsets[number] ?? 0, 0).utf8))
        }
        let trailer = """
        trailer
        << /Size \(max(sigNumber, appearanceNumber) + 1) /Root \(catalogNumber) 0 R /Prev \(root.xrefOffset) >>
        startxref
        \(xrefOffset)
        %%EOF

        """
        xref.append(Data(trailer.utf8))
        out.append(xref)

        let appendedFrom = base.count
        guard let contentsStart = Self.indexOf(out, ascii: "/Contents <", from: appendedFrom)
                .map({ $0 + "/Contents <".utf8.count }),
              let contentsEnd = Self.indexOf(out, ascii: ">", from: contentsStart),
              contentsEnd > contentsStart else {
            throw PAdESError.rootNotFound
        }

        guard let rangeSlotStart = Self.indexOf(out, ascii: "/ByteRange [", from: appendedFrom)
                .map({ $0 + "/ByteRange [".utf8.count }) else {
            throw PAdESError.rootNotFound
        }
        let totalLength = out.count
        let values = [0, contentsStart - 1, contentsEnd + 1, totalLength - (contentsEnd + 1)]
        var slot = rangeSlotStart
        for value in values {
            let text = String(format: "%010d", value)
            out.replaceSubrange(slot..<(slot + 10), with: Data(text.utf8))
            slot += 11
        }

        let covered = out.subdata(in: 0..<(contentsStart - 1)) +
            out.subdata(in: (contentsEnd + 1)..<out.count)
        let digest = Data(SHA256.hash(data: covered))

        let cms = try await Self.buildCMS(digest: digest,
                                          certificateDER: certificateDER,
                                          signer: signer,
                                          includeTimestamp: includeTimestamp,
                                          tsaURL: tsaURL)
        let hex = cms.map { String(format: "%02X", $0) }.joined()
        guard hex.count <= Self.contentsHexCapacity else {
            throw PAdESError.contentsTooLarge(required: cms.count)
        }
        let paddedHex = hex + String(repeating: "0", count: Self.contentsHexCapacity - hex.count)
        out.replaceSubrange(contentsStart..<contentsEnd, with: Data(paddedHex.utf8))
        return out
    }

    static func buildCMS(digest: Data,
                         certificateDER: Data,
                         signer: RawSigner,
                         includeTimestamp: Bool,
                         tsaURL: URL?) async throws -> Data {
        let contentTypeAttr = DER.tlv(0x30, DER.oid("1.2.840.113549.1.9.3") +
            DER.tlv(0x31, DER.oid("1.2.840.113549.1.7.1")))
        let messageDigestAttr = DER.tlv(0x30, DER.oid("1.2.840.113549.1.9.4") +
            DER.tlv(0x31, DER.octetString(digest)))
        let signingTimeValue = Self.utcTime(Date())
        let signingTimeAttr = DER.tlv(0x30, DER.oid("1.2.840.113549.1.9.5") +
            DER.tlv(0x31, DER.tlv(0x17, Data(signingTimeValue.utf8))))
        let certDigest = Data(SHA256.hash(data: certificateDER))
        var certIDContent = DER.sequence([DER.oid("2.16.840.1.101.3.4.2.1"), DER.tlv(0x05, Data())]) +
            DER.octetString(certDigest)
        if let issuerSerial = X509Inspector.issuerAndSerial(certificateData: certificateDER) {
            let issuerGeneralName = DER.tlv(0xA4, issuerSerial.issuerDER)
            certIDContent += DER.sequence([issuerGeneralName,
                                           DER.integerFromRaw(issuerSerial.serialRaw)])
        }
        let certID = DER.tlv(0x30, certIDContent)
        let scvValue = DER.sequence([certID])
        let scvAttr = DER.tlv(0x30, DER.oid("1.2.840.113549.1.9.16.2.47") + DER.tlv(0x31, scvValue))

        let signedAttrsContent = contentTypeAttr + messageDigestAttr + signingTimeAttr + scvAttr
        let signedAttrs = DER.tlv(0xA0, signedAttrsContent)
        let signedAttrsForSigning = DER.tlv(0x31, signedAttrsContent)

        guard signer.isRSA else { throw XAdESError.unsupportedKeyType }
        let signature = try signer.sign(signedAttrsForSigning)

        var unsignedAttrs = Data()
        if includeTimestamp {
            guard let tsaURL, tsaURL.scheme != nil else { throw SigningError.timestampFailed }
            let reply = try await RFC3161TimestampClient().requestToken(for: signature, tsaURL: tsaURL)
            let tsrAttr = DER.tlv(0x30, DER.oid("1.2.840.113549.1.9.16.2.14") +
                DER.tlv(0x31, DER.octetString(reply.token)))
            unsignedAttrs = DER.tlv(0xA1, tsrAttr)
        }

        guard let issuerSerial = X509Inspector.issuerAndSerial(certificateData: certificateDER) else {
            throw PAdESError.signingFailed("Certifikát bez Issuer/Serial.")
        }
        let issuerAndSerial = DER.sequence([
            issuerSerial.issuerDER,
            DER.integerFromRaw(issuerSerial.serialRaw)
        ])
        let sha256Alg = DER.sequence([DER.oid("2.16.840.1.101.3.4.2.1"), DER.tlv(0x05, Data())])
        let rsaEncryption = DER.sequence([DER.oid("1.2.840.113549.1.1.1"), DER.tlv(0x05, Data())])

        var signerInfoContent = DER.integer(1) +
            issuerAndSerial +
            sha256Alg +
            signedAttrs +
            rsaEncryption +
            DER.octetString(signature)
        if !unsignedAttrs.isEmpty { signerInfoContent += unsignedAttrs }
        let signerInfo = DER.sequence([signerInfoContent])

        let signedData = DER.sequence([
            DER.integer(1),
            DER.tlv(0x31, sha256Alg),
            DER.sequence([DER.oid("1.2.840.113549.1.7.1")]),
            DER.tlv(0xA0, certificateDER),
            DER.tlv(0x31, signerInfo)
        ])
        return DER.sequence([DER.oid("1.2.840.113549.1.7.2"), DER.tlv(0xA0, signedData)])
    }

    static func pdfNumber(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    static func utcTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return formatter.string(from: date)
    }

    static func indexOf(_ data: Data, ascii pattern: String) -> Int? {
        indexOf(data, ascii: pattern, from: 0)
    }

    static func indexOf(_ data: Data, ascii pattern: String, from startOffset: Int) -> Int? {
        let needle = Array(pattern.utf8)
        let haystack = [UInt8](data)
        guard !needle.isEmpty, haystack.count >= needle.count, startOffset >= 0,
              startOffset <= haystack.count - needle.count else { return nil }
        var index = startOffset
        while index <= haystack.count - needle.count {
            if haystack[index] == needle[0],
               Array(haystack[index..<(index + needle.count)]) == needle {
                return index
            }
            index += 1
        }
        return nil
    }

    static func pageObjectNumber(for index: Int, catalog: String, in data: Data) -> Int? {
        guard let pagesNumber = PDFObjectScanner.integerReference(named: "Pages", in: catalog),
              let pagesDict = PDFObjectScanner.catalogDictionary(number: pagesNumber, in: data) else { return nil }
        return resolvePage(index: index, dict: pagesDict, number: pagesNumber, data: data)
    }

    private static func resolvePage(index: Int, dict: String, number: Int, data: Data) -> Int? {
        guard dict.contains("/Kids") else { return index == 0 ? number : nil }
        var offset = 0
        for kid in kidsNumbers(in: dict) {
            guard let kidDict = PDFObjectScanner.catalogDictionary(number: kid, in: data) else { continue }
            let count = kidDict.contains("/Kids")
                ? (PDFObjectScanner.integerReference(named: "Count", in: kidDict) ?? 1)
                : 1
            if index < offset + count {
                return resolvePage(index: index - offset, dict: kidDict, number: kid, data: data)
            }
            offset += count
        }
        return nil
    }

    static func kidsNumbers(in pagesDict: String) -> [Int] {
        guard let start = pagesDict.range(of: "/Kids")?.upperBound,
              let open = pagesDict.range(of: "[", range: start..<pagesDict.endIndex),
              let close = pagesDict.range(of: "]", range: open.upperBound..<pagesDict.endIndex) else { return [] }
        let body = String(pagesDict[open.upperBound..<close.lowerBound])
        let regex = try? NSRegularExpression(pattern: "(\\d+)\\s+0\\s+R")
        let ns = body as NSString
        return (regex?.matches(in: body, range: NSRange(location: 0, length: ns.length)) ?? [])
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
    }

    static func mediaBox(of pageDict: String) -> CGRect? {
        let pattern = "/MediaBox\\s*\\[\\s*(-?[\\d.]+)\\s+(-?[\\d.]+)\\s+(-?[\\d.]+)\\s+(-?[\\d.]+)\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: pageDict, range: NSRange(pageDict.startIndex..., in: pageDict)),
              let r0 = Range(match.range(at: 1), in: pageDict),
              let r1 = Range(match.range(at: 2), in: pageDict),
              let r2 = Range(match.range(at: 3), in: pageDict),
              let r3 = Range(match.range(at: 4), in: pageDict),
              let x = Double(pageDict[r0]), let y = Double(pageDict[r1]),
              let w = Double(pageDict[r2]), let h = Double(pageDict[r3]) else { return nil }
        return CGRect(x: x, y: y, width: w - x, height: h - y)
    }

    struct RasterImage {
        var width: Int
        var height: Int
        var rgba: Data
    }

    static func decodeRGBA(_ png: Data) -> RasterImage? {
        guard let image = NSImage(data: png) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let width = min(cg.width, 1600)
        let height = min(cg.height, 1600)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        return RasterImage(width: width, height: height,
                           rgba: Data(bytes: data.assumingMemoryBound(to: UInt8.self),
                                      count: width * height * 4))
    }

    static func splitAlpha(_ raster: RasterImage) -> (rgb: Data, alpha: Data) {
        var rgb = Data(capacity: raster.width * raster.height * 3)
        var alpha = Data(capacity: raster.width * raster.height)
        let bytes = [UInt8](raster.rgba)
        var i = 0
        while i + 3 < bytes.count {
            rgb.append(contentsOf: bytes[i..<(i + 3)])
            alpha.append(bytes[i + 3])
            i += 4
        }
        return (rgb, alpha)
    }

    static func zlibCompress(_ data: Data) -> Data {
        let capacity = data.count + 128
        var buffer = Data(count: capacity)
        let written = buffer.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return data }
        var out = Data([0x78, 0x9C])
        out.append(buffer.prefix(written))
        out.append(adler32(data))
        return out
    }

    static func adler32(_ data: Data) -> Data {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in [UInt8](data) {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        var value = (b << 16) | a
        var out = Data(capacity: 4)
        for _ in 0..<4 {
            out.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return out
    }

    static func asciiFold(_ text: String) -> String {
        let map: [Character: String] = [
            "á": "a", "ä": "a", "č": "c", "ď": "d", "é": "e", "ě": "e", "í": "i",
            "ľ": "l", "ĺ": "l", "ň": "n", "ó": "o", "ô": "o", "ř": "r", "š": "s",
            "ť": "t", "ú": "u", "ů": "u", "ý": "y", "ž": "z",
            "Á": "A", "Ä": "A", "Č": "C", "Ď": "D", "É": "E", "Ě": "E", "Í": "I",
            "Ľ": "L", "Ĺ": "L", "Ň": "N", "Ó": "O", "Ô": "O", "Ř": "R", "Š": "S",
            "Ť": "T", "Ú": "U", "Ů": "U", "Ý": "Y", "Ž": "Z",
            "·": "-", "—": "-", "–": "-"
        ]
        return String(text.map { map[$0] ?? String($0) }.joined())
    }
}

import AppKit
import Compression
import CoreGraphics
