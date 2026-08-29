import Foundation
import CryptoKit

public struct AttestationXMLConstants: Sendable {
    public static let namespaceP2E = "https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0"
    public static let eFormIdentifier = "50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0"
    public static let conversionRecordURIBase = "https://data.gov.sk/id/egov/conversion-record/"
}

public enum AttestationGenerationError: LocalizedError, Equatable, Sendable {
    case invalidFingerprint

    public var errorDescription: String? {
        switch self {
        case .invalidFingerprint:
            return "SHA-256 otlačok musí obsahovať presne 64 hexadecimálnych znakov."
        }
    }
}

public struct AttestationClauseGenerator: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var attestation: AttestationData
        public var securityElements: [SecurityElement]
        public var newDocumentFingerprintSHA256Hex: String

        public init(attestation: AttestationData,
                    securityElements: [SecurityElement],
                    newDocumentFingerprintSHA256Hex: String) {
            self.attestation = attestation
            self.securityElements = securityElements
            self.newDocumentFingerprintSHA256Hex = newDocumentFingerprintSHA256Hex
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

        let descriptions = input.securityElements.map { element -> String in
            Self.securityElementDetails(element, sheetMethod: d.sheetCountingMethod)
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

    static func securityElementDetails(_ element: SecurityElement,
                                       sheetMethod: SheetCountingMethod) -> String {
        let location = element.verbalDescription.isEmpty
            ? element.locationDescription(pageSizePt: .zero) + "."
            : element.verbalDescription
        return """
            <DocumentSecurityElementsDetails>
              <OriginalDocumentSecurityElementsDescription>\(Self.codelist(
                ZakoCodelists.securityElementDescription,
                item: element.kind.codelist15Item))</OriginalDocumentSecurityElementsDescription>
              <SecurityElementVerbalDescription>\(Self.escape(location))</SecurityElementVerbalDescription>
              <OriginalDocumentSecurityElementsPage>\(element.pageIndex + 1)</OriginalDocumentSecurityElementsPage>
              <OriginalDocumentSecurityElementsSheet>\(element.sheetNumber(sheetMethod: sheetMethod))</OriginalDocumentSecurityElementsSheet>
              <OriginalDocumentSecurityElementsLocation>\(Self.codelist(
                ZakoCodelists.securityElementLocation,
                item: element.locationCodelist11Item))</OriginalDocumentSecurityElementsLocation>
              <NewDocumentSecurityElementsPage>\(element.pageIndex + 1)</NewDocumentSecurityElementsPage>
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
