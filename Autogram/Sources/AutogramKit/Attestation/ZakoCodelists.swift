import Foundation

public struct ZakoCodelistItem: Hashable, Sendable {
    public var code: String
    public var skName: String

    public init(code: String, skName: String) {
        self.code = code
        self.skName = skName
    }
}

public enum ZakoCodelists {
    public static let paperSize = 12
    public static let securityElementDescription = 15
    public static let securityElementLocation = 11
    public static let fingerprintMethod = 14
    public static let newDocumentFormat = 53
    public static let identifierType = 4001

    public static let sha256Item = ZakoCodelistItem(code: "SHA-256", skName: "SHA-256")
    public static let pdfa2FormatItem = ZakoCodelistItem(code: "PDFA2", skName: "PDF/A-2")
    public static let icoIdentifierItem = ZakoCodelistItem(
        code: "7",
        skName: "IČO (Identifikačné číslo organizácie)")

    public static func paperSizeItem(for classification: PaperClassification) -> ZakoCodelistItem? {
        switch classification {
        case .a4Portrait, .a4Landscape:
            return ZakoCodelistItem(code: "A4", skName: "Formát papiera A4")
        case .a3Portrait, .a3Landscape:
            return ZakoCodelistItem(code: "A3", skName: "Formát papiera A3")
        case .letterPortrait, .letterLandscape:
            return ZakoCodelistItem(code: "Letter", skName: "Formát papiera Letter")
        case .unknown:
            return nil
        }
    }

    public static func identifierURI(ico: String) -> String {
        let cleaned = ico.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        return "ico://sk/\(cleaned)"
    }

    public static func conversionRecordURI(evidenceNumber: String) -> String {
        let trimmed = evidenceNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        return "https://data.gov.sk/id/egov/conversion-record/\(trimmed)"
    }
}
