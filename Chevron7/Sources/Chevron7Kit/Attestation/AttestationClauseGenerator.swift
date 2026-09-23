// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import CryptoKit

public struct AttestationXMLConstants: Sendable {
    public static let namespaceP2E = "https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0"
    public static let eFormIdentifier = "50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0"
    public static let conversionRecordURIBase = "https://data.gov.sk/id/egov/conversion-record/"
}

public enum AttestationGenerationError: LocalizedError, Equatable, Sendable {
    case invalidFingerprint
    case incompletePhysicalSecurityElement
    case invalidSecurityElementPage
    case missingEvidenceNumber
    case invalidOriginalLocation
    case incompletePersonName

    public var errorDescription: String? {
        switch self {
        case .invalidFingerprint:
            return "SHA-256 otlačok musí obsahovať presne 64 hexadecimálnych znakov."
        case .incompletePhysicalSecurityElement:
            return "Prvok skontrolovaný na origináli musí mať uvedené miesto na origináli a stranu v novom dokumente."
        case .invalidSecurityElementPage:
            return "Bezpečnostný prvok nemá platné číslo strany alebo nie je na uvedenej neprázdnej strane originálu."
        case .missingEvidenceNumber:
            return "Chýba evidenčné číslo záznamu z EZZK."
        case .invalidOriginalLocation:
            return "Pri prvku skontrolovanom na origináli vyberte umiestnenie zo zoznamu."
        case .incompletePersonName:
            return "Zadajte meno aj priezvisko osoby, ktorá vykonáva konverziu (napríklad Ján Novák). Záznam pre EZZK ich vyžaduje."
        }
    }
}

public struct AttestationClauseGenerator: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var attestation: AttestationData
        public var securityElements: [SecurityElement]
        public var newDocumentFingerprintSHA256Hex: String
        /// PDF page indices in original document order, excluding blank pages.
        /// Nil preserves legacy page numbering for callers without analysis.
        public var originalNonEmptyPageIndices: [Int]?

        public init(attestation: AttestationData,
                    securityElements: [SecurityElement],
                    newDocumentFingerprintSHA256Hex: String,
                    originalNonEmptyPageIndices: [Int]? = nil) {
            self.attestation = attestation
            self.securityElements = securityElements
            self.newDocumentFingerprintSHA256Hex = newDocumentFingerprintSHA256Hex
            self.originalNonEmptyPageIndices = originalNonEmptyPageIndices
        }
    }

    public func generateXML(input: Input) -> String {
        renderXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)
    }

    /// Generates a clause using the selected form pack. The legacy overload
    /// above remains source-compatible for existing pilot callers, while new
    /// conversion code must provide explicit pack provenance.
    public func generateXML(input: Input, formPack: ConversionFormPack) throws -> String {
        guard formPack.direction == .paperToElectronic else {
            throw FormPackError.unsupportedDirection(formPack.direction)
        }
        guard formPack.renderer == .legacySwift else {
            throw FormPackError.unsupportedRenderer(formPack.renderer)
        }
        let fingerprint = input.newDocumentFingerprintSHA256Hex
        guard fingerprint.count == 64,
              fingerprint.allSatisfy({ $0.isHexDigit }) else {
            throw AttestationGenerationError.invalidFingerprint
        }
        for element in input.securityElements {
            _ = try Self.securityElementPages(element, originalNonEmptyPageIndices: input.originalNonEmptyPageIndices)
        }
        return renderXML(input: input, formPack: formPack)
    }

    private func renderXML(input: Input, formPack: ConversionFormPack) -> String {
        let ns = formPack.namespace
        let d = input.attestation

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ConversionRecord xmlns="\(ns)">
          <OriginalDocumentInfo>
            <OriginalDocumentOrder>\(d.originalDocumentOrder)</OriginalDocumentOrder>
            <OriginalDocumentName>\(Self.escape(d.originalDocumentName))</OriginalDocumentName>
        """
        if !d.originalDocumentTypeLabel.trimmingCharacters(in: .whitespaces).isEmpty {
            xml += """

                <OriginalDocumentType>\(Self.escape(d.originalDocumentTypeLabel))</OriginalDocumentType>
            """
        }
        xml += """

            <OriginalDocumentNumberOfSheets>\(d.numberOfSheets)</OriginalDocumentNumberOfSheets>
            <OriginalDocumentNonEmptyPageCount>\(d.nonEmptyPageCount)</OriginalDocumentNonEmptyPageCount>
        """

        for group in d.paperSizeBreakdown {
            guard let item = ZakoCodelists.paperSizeItem(for: group.sizeClass) else { continue }
            xml += """

                <OriginalDocumentPaperSize>
                  <PaperSize>\(Self.codelist(ZakoCodelists.paperSize, item: item))</PaperSize>
                  <PaperSizeNumberOfSheets>\(group.sheets)</PaperSizeNumberOfSheets>
                </OriginalDocumentPaperSize>
            """
        }

        // The nonthrowing legacy API omits incomplete details. The explicit pack
        // API validates every element before rendering and never silently omits one.
        let descriptions = input.securityElements.compactMap { element in
            Self.securityElementDetails(element, sheetMethod: d.sheetCountingMethod,
                                        originalNonEmptyPageIndices: input.originalNonEmptyPageIndices)
        }
        if !descriptions.isEmpty {
            xml += "\n" + descriptions.joined(separator: "\n")
        }
        xml += """

          </OriginalDocumentInfo>

          <NewDocumentInfo>
            <NewDocumentName>\(Self.escape(d.newDocumentName))</NewDocumentName>
            <NewDocumentFormat>\(Self.codelist(ZakoCodelists.newDocumentFormat,
                                               item: formPack.newDocumentFormatItem))</NewDocumentFormat>
            <ElectronicFingerprintValue>\(Self.fingerprintBase64(hex: input.newDocumentFingerprintSHA256Hex))</ElectronicFingerprintValue>
            <ElectronicFingerprintCalculationMethod>\(Self.codelist(ZakoCodelists.fingerprintMethod,
                                                                    item: formPack.fingerprintMethodItem))</ElectronicFingerprintCalculationMethod>
          </NewDocumentInfo>
        """

        xml += Self.personBlock(for: d.performingPerson)

        let timestampISO = Self.localOffsetFormatter.string(from: d.conversionExecutionDateTime)
        let evidenceURI = ZakoCodelists.conversionRecordURI(
            evidenceNumber: d.evidenceNumber ?? "")

        xml += """

          <UsedDevice>\(Self.escape(d.usedDeviceDescription))</UsedDevice>
          <ConversionExecutionDateTime>\(timestampISO)</ConversionExecutionDateTime>
          <ConversionRecordEvidenceNumber>\(Self.escape(evidenceURI))</ConversionRecordEvidenceNumber>
        </ConversionRecord>
        """

        return xml
    }

    static func securityElementPages(_ element: SecurityElement,
                                     originalNonEmptyPageIndices: [Int]?) throws -> (original: Int, new: Int) {
        let newPageIndex: Int
        if element.observation == .physicalOriginal {
            guard !element.originalLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let outputPage = element.newDocumentPageIndex, outputPage >= 0 else {
                throw AttestationGenerationError.incompletePhysicalSecurityElement
            }
            newPageIndex = outputPage
        } else {
            newPageIndex = element.pageIndex
        }
        guard (0..<99_999).contains(element.pageIndex), (0..<99_999).contains(newPageIndex) else {
            throw AttestationGenerationError.invalidSecurityElementPage
        }
        let originalPage: Int
        if let originalNonEmptyPageIndices {
            guard let ordinal = originalNonEmptyPageIndices.firstIndex(of: element.pageIndex), ordinal < 99_999 else {
                throw AttestationGenerationError.invalidSecurityElementPage
            }
            originalPage = ordinal + 1
        } else {
            originalPage = element.pageIndex + 1
        }
        return (originalPage, newPageIndex + 1)
    }

    /// Only this security subsection follows the verified record 1.0 schema.
    /// The remaining legacy renderer and its form pack remain unverified.
    static func securityElementDetails(_ element: SecurityElement,
                                       sheetMethod: SheetCountingMethod,
                                       originalNonEmptyPageIndices: [Int]? = nil) -> String? {
        guard let pages = try? securityElementPages(element, originalNonEmptyPageIndices: originalNonEmptyPageIndices) else {
            return nil
        }
        let location = element.observation == .physicalOriginal
            ? element.originalLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            : element.locationCodelist11Item.skName
        return """
            <DocumentSecurityElementsDetails>
              <OriginalDocumentSecurityElementsDescription>\(Self.escape(element.descriptionForRecord))</OriginalDocumentSecurityElementsDescription>
              <OriginalDocumentSecurityElementsPage>\(pages.original)</OriginalDocumentSecurityElementsPage>
              <OriginalDocumentSecurityElementsSheet>\(element.sheetNumber(sheetMethod: sheetMethod))</OriginalDocumentSecurityElementsSheet>
              <OriginalDocumentSecurityElementsLocation>\(Self.escape(location))</OriginalDocumentSecurityElementsLocation>
              <NewDocumentSecurityElementsPage>\(pages.new)</NewDocumentSecurityElementsPage>
            </DocumentSecurityElementsDetails>
        """
    }

    static func personBlock(for person: AdvocateProfile) -> String {
        var block = "\n\n          <PersonPerformingConversion>\n            <PersonData>"
        let nameParts = person.fullName.split(separator: " ").map(String.init)
        let nonTitles = nameParts.filter { !$0.hasSuffix(".") }
        let family = nonTitles.last ?? ""
        let given = nonTitles.dropLast().joined(separator: " ")
        if !person.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            block += """

              <PhysicalPerson>
                <PersonName>
                  <GivenName>\(escape(given))</GivenName>
                  <FamilyName>\(escape(family))</FamilyName>
                </PersonName>
                <Position>\(escape(person.position))</Position>
              </PhysicalPerson>
            """
        }
        let officeName = person.officeName.trimmingCharacters(in: .whitespaces)
        if person.isLegalEntity || !officeName.isEmpty {
            block += """

              <LegalSubject>
                <Name>\(escape(officeName.isEmpty ? person.fullName : officeName))</Name>
              </LegalSubject>
            """
        }
        let ico = person.ico.trimmingCharacters(in: .whitespaces)
        if !ico.isEmpty {
            block += """

              <ID>
                <IdentifierType>\(codelist(ZakoCodelists.identifierType,
                                           item: ZakoCodelists.icoIdentifierItem))</IdentifierType>
                <IdentifierValue>\(escape(ZakoCodelists.identifierURI(ico: ico)))</IdentifierValue>
              </ID>
            """
        }
        block += """

            </PersonData>
          </PersonPerformingConversion>
        """
        return block
    }

    static func codelist(_ code: Int, item: ZakoCodelistItem) -> String {
        """
        <Codelist><CodelistCode>\(code)</CodelistCode><CodelistItem><ItemCode>\(escape(item.code))</ItemCode><ItemName Language="sk">\(escape(item.skName))</ItemName></CodelistItem></Codelist>
        """
    }

    public static func fingerprintBase64(hex: String) -> String {
        let chars = Array(hex.lowercased())
        var bytes: [UInt8] = []
        var index = chars.startIndex
        while index + 1 < chars.endIndex,
              let high = chars[index].hexDigitValue,
              let low = chars[index + 1].hexDigitValue {
            bytes.append(UInt8(high * 16 + low))
            index += 2
        }
        return Data(bytes).base64EncodedString()
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public nonisolated(unsafe) static let localOffsetFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        f.timeZone = .current
        return f
    }()

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
