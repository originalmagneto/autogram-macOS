import Foundation
import CryptoKit

public struct AttestationXMLConstants: Sendable {
    public static let namespaceP2E = "https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0"
    public static let eFormIdentifier = "50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0"
    public static let conversionRecordURIBase = "https://data.gov.sk/id/egov/conversion-record/"
}

public struct AttestationClauseGenerator: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var attestation: AttestationData
        public var securityElements: [SecurityElement]
        public var newDocumentFingerprintSHA256Hex: String
        public var qualifiedTimestampTime: Date?

        public init(attestation: AttestationData,
                    securityElements: [SecurityElement],
                    newDocumentFingerprintSHA256Hex: String,
                    qualifiedTimestampTime: Date? = nil) {
            self.attestation = attestation
            self.securityElements = securityElements
            self.newDocumentFingerprintSHA256Hex = newDocumentFingerprintSHA256Hex
            self.qualifiedTimestampTime = qualifiedTimestampTime
        }
    }

    public func generateXML(input: Input) -> String {
        let ns = AttestationXMLConstants.namespaceP2E
        let d = input.attestation

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ConversionRecord xmlns="\(ns)">
          <eFormIdentifier>\(AttestationXMLConstants.eFormIdentifier)</eFormIdentifier>

          <OriginalDocumentInfo>
            <OriginalDocumentOrder>\(d.originalDocumentOrder)</OriginalDocumentOrder>
            <OriginalDocumentName>\(Self.escape(d.originalDocumentName))</OriginalDocumentName>
            <OriginalDocumentType>\(Self.escape(d.originalDocumentTypeLabel))</OriginalDocumentType>
            <OriginalDocumentNumberOfSheets>\(d.numberOfSheets)</OriginalDocumentNumberOfSheets>
            <OriginalDocumentNonEmptyPageCount>\(d.nonEmptyPageCount)</OriginalDocumentNonEmptyPageCount>
        """

        for group in d.paperSizeBreakdown {
            xml += """
            <OriginalDocumentPaperSize>
              <PaperSize>\(group.sizeClass.rawValue)</PaperSize>
              <PaperSizeNumberOfSheets>\(group.sheets)</PaperSizeNumberOfSheets>
            </OriginalDocumentPaperSize>
            """
        }

        let descriptions = input.securityElements.map { element -> String in
            let location = element.locationDescription(pageSizePt: .zero)
            let verbal = element.verbalDescription.isEmpty ? location : element.verbalDescription
            return """
              <DocumentSecurityElementsDetails>
                <SecurityElementType>\(element.kind.rawValue)</SecurityElementType>
                <SecurityElementsPage>\(element.pageIndex + 1)</SecurityElementsPage>
                <SecurityElementDescription>\(Self.escape(verbal))</SecurityElementDescription>
                <BoundingBox x="\((element.boundingBox.x * 10000).rounded() / 10000)" y="\((element.boundingBox.y * 10000).rounded() / 10000)" w="\((element.boundingBox.width * 10000).rounded() / 10000)" h="\((element.boundingBox.height * 10000).rounded() / 10000)"/>
              </DocumentSecurityElementsDetails>
            """
        }
        xml += "\n" + descriptions.joined(separator: "\n")
        xml += """

          </OriginalDocumentInfo>

          <NewDocumentInfo>
            <NewDocumentName>\(Self.escape(d.newDocumentName))</NewDocumentName>
            <NewDocumentFormat>\(Self.escape(d.newDocumentFormatLabel))</NewDocumentFormat>
            <ElectronicFingerprintValue algorithm="sha-256">\(input.newDocumentFingerprintSHA256Hex.lowercased())</ElectronicFingerprintValue>
          </NewDocumentInfo>
        """

        let person = d.performingPerson
        if person.isLegalEntity {
            xml += """

              <PersonPerformingConversion>
                <PersonData>
                  <LegalSubject>
                    <Name>\(Self.escape(person.officeName.isEmpty ? person.fullName : person.officeName))</Name>
                    <Identifier ico="\(Self.escape(person.ico))"/>
                  </LegalSubject>
                </PersonData>
              </PersonPerformingConversion>
            """
        } else {
            let nameParts = person.fullName.split(separator: " ").map(String.init)
            let nonTitles = nameParts.filter { !$0.hasSuffix(".") }
            let family = nonTitles.last ?? nameParts.last ?? ""
            let given = nonTitles.dropLast().joined(separator: " ")
            xml += """

              <PersonPerformingConversion>
                <PersonData>
                  <PhysicalPerson>
                    <PersonName>
                      <GivenName>\(Self.escape(given))</GivenName>
                      <FamilyName>\(Self.escape(family))</FamilyName>
                    </PersonName>
                    <Position>\(Self.escape(person.position))</Position>
                  </PhysicalPerson>
                </PersonData>
              </PersonPerformingConversion>
            """
        }

        let timestampISO = Self.isoFormatter.string(from: d.conversionExecutionDateTime)
        let stampISO = input.qualifiedTimestampTime.map { Self.isoFormatter.string(from: $0) } ?? ""

        xml += """

          <UsedDevice>\(Self.escape(d.usedDeviceDescription))</UsedDevice>
          <ConversionExecutionDateTime>\(timestampISO)</ConversionExecutionDateTime>
          <QualifiedTimestampTime>\(stampISO)</QualifiedTimestampTime>
          <ConversionRecordEvidenceNumber>\(Self.escape(d.evidenceNumber ?? ""))</ConversionRecordEvidenceNumber>
          <EvidenceRecordURI>\(AttestationXMLConstants.conversionRecordURIBase)\(Self.escape(d.evidenceNumber ?? ""))</EvidenceRecordURI>
        </ConversionRecord>
        """

        return xml
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
