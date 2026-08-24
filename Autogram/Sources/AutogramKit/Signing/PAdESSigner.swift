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

    static let contentsHexCapacity = 16384

    public func sign(pdf: Data,
                     certificateDER: Data,
                     signer: RawSigner,
                     reason: String = "Autorizácia dokumentu — Autogram",
                     includeTimestamp: Bool,
                     tsaURL: URL?) async throws -> Data {
        var base = pdf
        if base.last != UInt8(ascii: "\n") { base.append(Data("\n".utf8)) }

        guard let root = Self.locateRoot(in: base),
              let catalogDict = PDFObjectScanner.catalogDictionary(number: root.objectNumber, in: base) else {
            throw PAdESError.rootNotFound
        }

        let maxNumber = max(PDFObjectScanner.maxObjectNumber(in: base), root.objectNumber)
        let widgetNumber = maxNumber + 1
        let acroFormNumber = maxNumber + 2
        let catalogNumber = maxNumber + 3
        let sigNumber = maxNumber + 4

        let zeroContents = String(repeating: "0", count: Self.contentsHexCapacity)
        let byteRangeTemplate = "/ByteRange [0000000000 0000000000 0000000000 0000000000]"
        let mDateFormatter = DateFormatter()
        mDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        mDateFormatter.timeZone = TimeZone(identifier: "GMT")
        mDateFormatter.dateFormat = "yyyyMMddHHmmss"
        let mDateString = "D:\(mDateFormatter.string(from: Date()))+00'00'"
        let escapedReason = reason.replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")

        var sigDict = "<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached "
        sigDict += byteRangeTemplate + " "
        sigDict += "/Contents <\(zeroContents)> "
        sigDict += "/Reason (\(escapedReason)) /M (\(mDateString)) >>"

        let augmentedCatalog = PDFObjectScanner.augmentDictionary(
            catalogDict, appending: "/AcroForm \(acroFormNumber) 0 R")

        var objects: [(number: Int, body: Data)] = []
        func objectBody(_ number: Int, _ dict: String) -> Data {
            Data("\n\(number) 0 obj\n\(dict)\nendobj\n".utf8)
        }
        objects.append((widgetNumber, objectBody(widgetNumber,
            "<< /Type /Annot /Subtype /Widget /FT /Sig /Rect [0 0 120 48] /F 132 /V \(sigNumber) 0 R >>")))
        objects.append((acroFormNumber, objectBody(acroFormNumber,
            "<< /Fields [\(widgetNumber) 0 R] /SigFlags 3 >>")))
        objects.append((catalogNumber, objectBody(catalogNumber, augmentedCatalog)))
        objects.append((sigNumber, objectBody(sigNumber, sigDict)))

        var out = base
        var offsets: [Int: Int] = [:]
        for (number, body) in objects {
            offsets[number] = out.count
            out.append(body)
        }

        let xrefOffset = out.count
        var xref = Data("xref\n\(widgetNumber) \(objects.count)\n".utf8)
        for (number, _) in objects {
            xref.append(Data(String(format: "%010d %05d n \n", offsets[number] ?? 0, 0).utf8))
        }
        let trailer = """
        trailer
        << /Size \(sigNumber + 1) /Root \(catalogNumber) 0 R /Prev \(root.xrefOffset) >>
        startxref
        \(xrefOffset)
        %%EOF

        """
        xref.append(Data(trailer.utf8))
        out.append(xref)

        guard let contentsStart = Self.indexOf(out, ascii: "/Contents <").map({ $0 + "/Contents <".utf8.count }),
              let contentsEnd = Self.indexOf(out, ascii: ">", from: contentsStart),
              contentsEnd > contentsStart else {
            throw PAdESError.rootNotFound
        }

        guard let rangeSlotStart = Self.indexOf(out, ascii: "/ByteRange [").map({ $0 + "/ByteRange [".utf8.count }) else {
            throw PAdESError.rootNotFound
        }
        let totalLength = out.count
        let values = [0, contentsStart, contentsEnd + 1, totalLength - (contentsEnd + 1)]
        var slot = rangeSlotStart
        for value in values {
            let text = String(format: "%010d", value)
            out.replaceSubrange(slot..<(slot + 10), with: Data(text.utf8))
            slot += 11
        }

        let covered = out.subdata(in: 0..<contentsStart) +
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
        let scvValue = DER.sequence([DER.sequence([DER.octetString(certDigest)])])
        let scvAttr = DER.tlv(0x30, DER.oid("1.2.840.113549.1.9.16.2.47") + DER.tlv(0x31, scvValue))

        let signedAttrsContent = contentTypeAttr + messageDigestAttr + signingTimeAttr + scvAttr
        let signedAttrs = DER.tlv(0xA0, signedAttrsContent)

        guard signer.isRSA else { throw XAdESError.unsupportedKeyType }
        let signature = try signer.sign(signedAttrs)

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
        let sha256Alg = DER.sequence([DER.oid("2.16.840.1.101.3.4.2.1")])
        let rsaEncryption = DER.sequence([DER.oid("1.2.840.113549.1.1.1")])

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
            signerInfo
        ])
        return DER.sequence([DER.oid("1.2.840.113549.1.7.2"), DER.tlv(0xA0, signedData)])
    }

    static func utcTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return formatter.string(from: date)
    }

    static func locateRoot(in data: Data) -> PDFObjectScanner.RootRef? {
        let text = String(decoding: data.suffix(min(data.count, 262_144)), as: UTF8.self)
        let baseOffset = data.count - text.utf8.count
        guard let range = text.range(of: "startxref", options: .backwards) else { return nil }
        let tokens = text[range.upperBound...].split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" })
        guard let raw = tokens.first,
              let relativeOffset = Int(raw.trimmingCharacters(in: .whitespaces)),
              relativeOffset >= 0 else { return nil }
        let xrefOffset = max(baseOffset, 0) + relativeOffset
        guard xrefOffset < data.count else { return nil }
        let regionEnd = min(xrefOffset + 8192, data.count)
        let region = String(decoding: data.subdata(in: xrefOffset..<regionEnd), as: UTF8.self)
        guard let rootRange = region.range(of: "/Root") else { return nil }
        let rest = region[rootRange.upperBound...]
        let numbers = rest.split { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == ">" }
        guard numbers.count >= 2, let objectNumber = Int(numbers[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        return PDFObjectScanner.RootRef(objectNumber: objectNumber, xrefOffset: xrefOffset)
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
}
