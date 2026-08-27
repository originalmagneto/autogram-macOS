import Foundation
import Compression
import CryptoKit

public struct ASiCEContainerVerifier: Sendable {
    public struct Verification: Sendable {
        public var isValid: Bool
        public var issues: [String]
        public var entryNames: [String]
        public var verifiedObjectURIs: [String]
        public var containsDemoSignature: Bool
    }

    public init() {}

    public static func readEntries(_ data: Data) -> [(name: String, data: Data)]? {
        let bytes = [UInt8](data)
        var result: [(String, Data)] = []
        var cursor = 0

        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) |
            (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
        }

        while cursor + 4 <= bytes.count {
            guard u32(cursor) == 0x04034B50 else { break }
            let method = u16(cursor + 8)
            let compressedSize = u32(cursor + 18)
            let uncompressedSize = u32(cursor + 22)
            let nameLength = u16(cursor + 26)
            let extraLength = u16(cursor + 28)
            let nameStart = cursor + 30
            guard nameStart + nameLength + extraLength + compressedSize <= bytes.count else { return nil }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let contentStart = nameStart + nameLength + extraLength
            if !name.hasSuffix("/") {
                let payload: Data
                switch method {
                case 0:
                    payload = Data(bytes[contentStart..<(contentStart + compressedSize)])
                case 8:
                    guard uncompressedSize > 0 else { return nil }
                    var dst = Data(count: uncompressedSize)
                    let written = dst.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
                        let srcSlice = bytes[contentStart..<(contentStart + compressedSize)]
                        return srcSlice.withContiguousStorageIfAvailable { srcPtr -> Int in
                            compression_decode_buffer(
                                dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                uncompressedSize,
                                srcPtr.baseAddress!,
                                compressedSize,
                                nil,
                                COMPRESSION_ZLIB)
                        } ?? 0
                    }
                    guard written == uncompressedSize else { return nil }
                    payload = dst
                default:
                    return nil
                }
                result.append((name, payload))
            }
            cursor = contentStart + compressedSize
        }
        return result.isEmpty ? nil : result
    }

    public func verify(_ asic: Data) -> Verification {
        var issues: [String] = []

        guard let entries = Self.readEntries(asic) else {
            return Verification(isValid: false,
                                issues: ["Kontajner nie je čitateľný ASiC-E ZIP."],
                                entryNames: [], verifiedObjectURIs: [], containsDemoSignature: false)
        }
        let names = entries.map(\.name)

        if let first = entries.first, first.name != "mimetype" {
            issues.append("Prvá položka kontajnera musí byť mimetype.")
        } else if entries.isEmpty {
            issues.append("Kontajner je prázdny.")
        }
        if let mimetype = entries.first(where: { $0.name == "mimetype" }),
           String(decoding: mimetype.data, as: UTF8.self) != ASiCEPackager.asicMimeType {
            issues.append("mimetype nemá hodnotu \(ASiCEPackager.asicMimeType).")
        }

        var manifestPaths: [String] = []
        if let manifestEntry = entries.first(where: { $0.name == "META-INF/manifest.xml" }) {
            let xml = String(decoding: manifestEntry.data, as: UTF8.self)
            manifestPaths = Self.extractAttributeValues(xml: xml,
                                                        element: "manifest:file-entry",
                                                        attribute: "full-path")
        } else {
            issues.append("Chýba META-INF/manifest.xml.")
        }

        if !manifestPaths.contains("/") {
            issues.append("Manifest neobsahuje koreňový záznam \"/\".")
        }

        let dataEntries = entries.filter { $0.name != "mimetype" && !$0.name.hasPrefix("META-INF/") }
        for entry in dataEntries where !manifestPaths.contains(entry.name) {
            issues.append("Dátový objekt \(entry.name) nie je uvedený v manifeste.")
        }
        for path in manifestPaths where path != "/" && !names.contains(path) {
            issues.append("Manifest odkazuje na neexistujúci súbor \(path).")
        }

        var verifiedURIs: [String] = []
        if let signatureEntry = entries.first(where: { $0.name == "META-INF/signatures001.xml" }) {
            let xml = String(decoding: signatureEntry.data, as: UTF8.self)
            let references = Self.parseReferences(xml: xml)
            if references.isEmpty {
                issues.append("signatures001.xml neobsahuje žiadne ds:Reference.")
            }
            for reference in references where !reference.uri.hasPrefix("#") {
                let decoded = reference.uri.removingPercentEncoding ?? reference.uri
                guard let target = entries.first(where: { $0.name == decoded }) else {
                    issues.append("Signatúra odkazuje na chýbajúci objekt \(decoded).")
                    continue
                }
                let digest = Data(SHA256.hash(data: target.data)).base64EncodedString()
                if digest == reference.digestBase64 {
                    verifiedURIs.append(decoded)
                } else {
                    issues.append("Digest objektu \(decoded) nezodpovedá signatúre.")
                }
            }
            if !references.contains(where: { $0.uri.hasPrefix("#xades-") }) {
                issues.append("Signatúra neobsahuje XAdES SignedProperties referenciu.")
            }
        }

        return Verification(isValid: issues.isEmpty,
                            issues: issues,
                            entryNames: names,
                            verifiedObjectURIs: verifiedURIs,
                            containsDemoSignature: names.contains("META-INF/demo-signature.json"))
    }

    static func extractAttributeValues(xml: String, element: String, attribute: String) -> [String] {
        var values: [String] = []
        var scanner = Substring(xml)
        while let range = scanner.range(of: "<\(element)") {
            scanner = scanner[range.upperBound...]
            guard let close = scanner.range(of: ">") else { break }
            let tag = scanner[..<close.lowerBound]
            if let valueRange = tag.range(of: "\(attribute)=\"") {
                let rest = tag[valueRange.upperBound...]
                if let end = rest.firstIndex(of: "\"") {
                    values.append(String(rest[..<end]))
                }
            }
        }
        return values
    }

    static func parseReferences(xml: String) -> [(uri: String, digestBase64: String)] {
        guard let document = try? XMLDocument(xmlString: xml,
                                              options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return [] }
        var result: [(String, String)] = []
        walk(element: root) { element in
            guard element.localName == "Reference",
                  let uri = element.attribute(forName: "URI")?.stringValue else { return }
            let digestNode = (element.children ?? []).compactMap { $0 as? XMLElement }
                .first { $0.localName == "DigestValue" }
            guard let digest = digestNode?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            result.append((uri, digest))
        }
        return result
    }

    private static func walk(element: XMLElement, visitor: (XMLElement) -> Void) {
        visitor(element)
        for child in element.children ?? [] {
            if let subelement = child as? XMLElement {
                walk(element: subelement, visitor: visitor)
            }
        }
    }
}
