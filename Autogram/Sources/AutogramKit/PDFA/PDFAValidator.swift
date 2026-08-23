import Foundation

public struct PDFAValidator: Sendable {
    public struct Result: Sendable, Equatable {
        public var isValid: Bool
        public var issues: [String]

        public static let valid = Result(isValid: true, issues: [])
    }

    public init() {}

    public func validate(_ data: Data, expectedPart: Int = 2, expectedConformance: String = "B") -> Result {
        var issues: [String] = []
        let bytes = [UInt8](data)

        guard data.count > 16 else {
            return .init(isValid: false, issues: ["Súbor je príliš malý na PDF."])
        }
        let header = String(decoding: bytes.prefix(1024), as: UTF8.self)
        if !header.hasPrefix("%PDF-") {
            issues.append("Chýba hlavička %PDF.")
        }

        let tail = String(decoding: bytes.suffix(2048), as: UTF8.self)
        if !tail.contains("%%EOF") {
            issues.append("Chýba ukončovací marker %%EOF.")
        }
        let text = String(decoding: data, as: UTF8.self)
        if !text.contains("startxref") {
            issues.append("Chýba tabuľka krížových odkazov (startxref).")
        }

        let document = String(decoding: data, as: UTF8.self)
        if !Self.containsXPMPart(document, part: expectedPart) {
            issues.append("Chýba XMP metadata pdfaid:part=\(expectedPart).")
        }
        if !Self.containsXMPConformance(document, conformance: expectedConformance) {
            issues.append("Chýba XMP metadata pdfaid:conformance=\(expectedConformance).")
        }
        if !document.contains("/OutputIntent") {
            issues.append("Chýba OutputIntent.")
        }
        if !document.contains("/GTS_PDFA1") && !document.contains("/GTS_PDFA2") {
            issues.append("OutputIntent nie je typu GTS_PDFA (chýba ICC OutputIntent pre PDF/A).")
        }
        if !document.contains("/DestOutputProfile") && !document.contains("/ICCBased") {
            issues.append("Chýba ICC profil (/DestOutputProfile).")
        }
        if Self.containsUnbalancedEncrypt(document) || document.range(of: "/Encrypt") != nil {
            issues.append("Dokument je zašifrovaný — PDF/A neumožňuje šifrovanie.")
        }
        if document.contains("/JavaScript") {
            issues.append("Dokument obsahuje JavaScript — zakázané v PDF/A.")
        }
        if document.contains("/EmbeddedFile") && !document.contains("/AF") {
            // povolené v PDF/A-2/3, len informatívne
        }
        return .init(isValid: issues.isEmpty, issues: issues)
    }

    static func containsXPMPart(_ document: String, part: Int) -> Bool {
        if document.contains("<pdfaid:part>\(part)</pdfaid:part>") { return true }
        if document.contains("pdfaid:part=\"\(part)\"") { return true }
        if document.contains("pdfaid:part {\(part)}") { return true }
        return false
    }

    static func containsXMPConformance(_ document: String, conformance: String) -> Bool {
        if document.contains("<pdfaid:conformance>\(conformance)</pdfaid:conformance>") { return true }
        if document.contains("pdfaid:conformance=\"\(conformance)\"") { return true }
        if document.contains("pdfaid:conformance {\(conformance)}") { return true }
        return false
    }

    static func containsUnbalancedEncrypt(_ document: String) -> Bool {
        document.contains("/Filter /Standard")
    }

    static func lastOccurrence(of needle: String, in data: Data) -> Range<String.Index>? {
        let text = String(decoding: data.suffix(4096), as: UTF8.self)
        return text.range(of: needle)
    }
}
