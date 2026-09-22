import CryptoKit
import Foundation

/// Structural and digest validation for the observed P2E ASiC artifacts.
/// It does not replace certificate, trusted-list, or VeraPDF validation.
public struct P2EConformanceValidator: Sendable {
    public struct Context: Sendable {
        public let expectedPDFData: Data?
        public let expectedEvidenceNumber: String?
        public let expectedConversionTime: Date?

        public init(expectedPDFData: Data? = nil,
                    expectedEvidenceNumber: String? = nil,
                    expectedConversionTime: Date? = nil) {
            self.expectedPDFData = expectedPDFData
            self.expectedEvidenceNumber = expectedEvidenceNumber
            self.expectedConversionTime = expectedConversionTime
        }
    }

    public struct ArtifactResult: Sendable {
        public let isValid: Bool
        public let issues: [String]
        public let entryNames: [String]
        public let documentEntryName: String?
        public let xdcfEntryName: String?
        public let evidenceURI: String?
        public let fingerprintBase64: String?
        public let conversionTime: Date?
        public let hasTimestamp: Bool

        fileprivate init(isValid: Bool,
                         issues: [String],
                         entryNames: [String] = [],
                         documentEntryName: String? = nil,
                         xdcfEntryName: String? = nil,
                         evidenceURI: String? = nil,
                         fingerprintBase64: String? = nil,
                         conversionTime: Date? = nil,
                         hasTimestamp: Bool = false) {
            self.isValid = isValid
            self.issues = issues
            self.entryNames = entryNames
            self.documentEntryName = documentEntryName
            self.xdcfEntryName = xdcfEntryName
            self.evidenceURI = evidenceURI
            self.fingerprintBase64 = fingerprintBase64
            self.conversionTime = conversionTime
            self.hasTimestamp = hasTimestamp
        }
    }

    public struct Result: Sendable {
        public let isValid: Bool
        public let issues: [String]
        public let clause: ArtifactResult?
        public let record: ArtifactResult?

        fileprivate init(isValid: Bool,
                         issues: [String],
                         clause: ArtifactResult?,
                         record: ArtifactResult?) {
            self.isValid = isValid
            self.issues = issues
            self.clause = clause
            self.record = record
        }
    }

    public init() {}

    public func validate(
        clauseASiC: Data,
        recordASiC: Data? = nil,
        context: Context = .init(),
        profile: P2EConformanceProfile = .targetV1_3) -> Result {
        let clause = validateClause(clauseASiC, context: context, profile: profile)
        var issues = clause.issues
        var record: ArtifactResult?

        if let recordASiC {
            let validatedRecord = validateRecord(recordASiC, profile: profile)
            record = validatedRecord
            issues.append(contentsOf: validatedRecord.issues)

            if let clauseEvidence = clause.evidenceURI,
               let recordEvidence = validatedRecord.evidenceURI,
               clauseEvidence != recordEvidence {
                issues.append("Evidenčné číslo doložky a záznamu sa nezhoduje.")
            }
            if let clauseFingerprint = clause.fingerprintBase64,
               let recordFingerprint = validatedRecord.fingerprintBase64,
               clauseFingerprint != recordFingerprint {
                issues.append("Fingerprint doložky a záznamu sa nezhoduje.")
            }
            if let clauseTime = clause.conversionTime,
               let recordTime = validatedRecord.conversionTime,
               abs(clauseTime.timeIntervalSince(recordTime)) > 1 {
                issues.append("Čas konverzie doložky a záznamu sa nezhoduje.")
            }
        }

        let uniqueIssues = sortedUnique(issues)
        return Result(isValid: uniqueIssues.isEmpty,
                      issues: uniqueIssues,
                      clause: clause,
                      record: record)
    }

    private func validateClause(
        _ asic: Data,
        context: Context,
        profile: P2EConformanceProfile) -> ArtifactResult {
        var issues: [String] = []
        guard let entries = ASiCEContainerVerifier.readEntries(asic) else {
            return ArtifactResult(isValid: false,
                                  issues: ["Kontajner doložky nie je čitateľný ASiC-E ZIP."])
        }

        let structure = ASiCEContainerVerifier().verify(asic)
        issues.append(contentsOf: structure.issues)
        if structure.containsDemoSignature {
            issues.append("ASiC obsahuje demo podpisový marker.")
        }
        let dataEntries = entries.filter { $0.name != "mimetype" && !$0.name.hasPrefix("META-INF/") }
        let xdcfEntries = dataEntries.filter { ASiCEPackager.mediaType(forPath: $0.name) == profile.xdcfMimeType }
        let pdfEntries = dataEntries.filter { ASiCEPackager.mediaType(forPath: $0.name) == profile.pdfMimeType }
        if xdcfEntries.count != 1 {
            issues.append("ASiC doložky musí obsahovať práve jeden XDCF objekt.")
        }
        if pdfEntries.count != 1 {
            issues.append("ASiC doložky obsahuje neplatný počet PDF objektov.")
        }
        guard let xdcf = xdcfEntries.first else {
            issues.append("Chýba P2E XDCF doložky.")
            return artifactResult(issues: issues,
                                  structure: structure,
                                  documentEntryName: pdfEntries.first?.name,
                                  xdcfEntryName: nil)
        }
        guard let pdf = pdfEntries.first else {
            issues.append("Chýba PDF objekt doložky.")
            return artifactResult(issues: issues,
                                  structure: structure,
                                  documentEntryName: nil,
                                  xdcfEntryName: xdcf.name)
        }
        guard let parsed = parseContainer(xdcf.data) else {
            issues.append("P2E XDCF sa nepodarilo parsovať.")
            return artifactResult(issues: issues,
                                  structure: structure,
                                  documentEntryName: pdf.name,
                                  xdcfEntryName: xdcf.name)
        }
        if parsed.root.uri != profile.xdcfNamespace {
            issues.append("P2E XDCF nemá očakávaný namespace.")
        }
        if parsed.identifier != profile.clauseIdentifier || parsed.version != profile.clauseVersion {
            issues.append("P2E XDCF nemá očakávaný identifikátor alebo verziu doložky.")
        }
        if parsed.payload.localName != profile.clauseRoot || parsed.payload.uri != profile.clauseNamespace {
            issues.append("P2E XML nemá očakávaný namespace doložky.")
        }
        let fields = extractFields(from: parsed.payload)
        validateClauseFields(fields, issues: &issues, profile: profile)
        let actualFingerprint = P2EConformanceProfile.sha256Base64(pdf.data)
        if fields.fingerprintBase64 != actualFingerprint {
            issues.append("Fingerprint PDF v kontajneri nezodpovedá doložke.")
        }
        if let expectedPDFData = context.expectedPDFData,
           P2EConformanceProfile.sha256Base64(expectedPDFData) != actualFingerprint {
            issues.append("Fingerprint embedded PDF nezodpovedá očakávanému dokumentu.")
        }
        compareContext(fields: fields,
                       context: context,
                       profile: profile,
                       issues: &issues)
        let hasTimestamp = hasSignatureTimestamp(entries)
        if !hasTimestamp {
            issues.append("ASiC neobsahuje XAdES SignatureTimeStamp.")
        }
        return artifactResult(issues: issues,
                              structure: structure,
                              documentEntryName: pdf.name,
                              xdcfEntryName: xdcf.name,
                              evidenceURI: fields.evidenceURI,
                              fingerprintBase64: fields.fingerprintBase64,
                              conversionTime: fields.conversionTime,
                              hasTimestamp: hasTimestamp)
    }

    private func validateRecord(
        _ asic: Data,
        profile: P2EConformanceProfile) -> ArtifactResult {
        var issues: [String] = []
        guard let entries = ASiCEContainerVerifier.readEntries(asic) else {
            return ArtifactResult(isValid: false,
                                  issues: ["Kontajner záznamu nie je čitateľný ASiC-E ZIP."])
        }
        let structure = ASiCEContainerVerifier().verify(asic)
        issues.append(contentsOf: structure.issues)
        if structure.containsDemoSignature {
            issues.append("ASiC obsahuje demo podpisový marker.")
        }
        let dataEntries = entries.filter { $0.name != "mimetype" && !$0.name.hasPrefix("META-INF/") }
        let xdcfEntries = dataEntries.filter { ASiCEPackager.mediaType(forPath: $0.name) == profile.xdcfMimeType }
        let pdfEntries = dataEntries.filter { ASiCEPackager.mediaType(forPath: $0.name) == profile.pdfMimeType }
        if xdcfEntries.count != 1 {
            issues.append("ASiC záznamu musí obsahovať práve jeden XDCF objekt.")
        }
        if !pdfEntries.isEmpty {
            issues.append("ASiC záznamu nesmie obsahovať PDF objekt.")
        }
        guard let xdcf = xdcfEntries.first else {
            issues.append("Chýba XDCF konverzného záznamu.")
            return artifactResult(issues: issues, structure: structure, xdcfEntryName: nil)
        }
        guard let parsed = parseContainer(xdcf.data) else {
            issues.append("Konverzný záznam XDCF sa nepodarilo parsovať.")
            return artifactResult(issues: issues, structure: structure, xdcfEntryName: xdcf.name)
        }
        if parsed.root.uri != profile.xdcfNamespace {
            issues.append("XDCF konverzného záznamu nemá očakávaný namespace.")
        }
        if parsed.identifier != profile.recordIdentifier || parsed.version != profile.recordVersion {
            issues.append("XDCF konverzného záznamu nemá očakávaný identifikátor alebo verziu.")
        }
        if parsed.payload.localName != profile.recordRoot || parsed.payload.uri != profile.recordNamespace {
            issues.append("Konverzný záznam nemá očakávaný namespace.")
        }
        let fields = extractFields(from: parsed.payload)
        validateRecordFields(fields, issues: &issues, profile: profile)
        let hasTimestamp = hasSignatureTimestamp(entries)
        if !hasTimestamp {
            issues.append("ASiC konverzného záznamu neobsahuje XAdES SignatureTimeStamp.")
        }
        return artifactResult(issues: issues,
                              structure: structure,
                              xdcfEntryName: xdcf.name,
                              evidenceURI: fields.evidenceURI,
                              fingerprintBase64: fields.fingerprintBase64,
                              conversionTime: fields.conversionTime,
                              hasTimestamp: hasTimestamp)
    }

    private func validateClauseFields(
        _ fields: Fields,
        issues: inout [String],
        profile: P2EConformanceProfile) {
        guard fields.originalDocumentInfo != nil else {
            issues.append("Doložka neobsahuje OriginalDocumentInfo.")
            return
        }
        guard fields.newDocumentInfo != nil else {
            issues.append("Doložka neobsahuje NewDocumentInfo.")
            return
        }
        if fields.documentName?.isEmpty != false {
            issues.append("NewDocumentName je prázdne alebo chýba.")
        }
        if fields.formatCode != profile.pdfa2Code || fields.formatName != profile.pdfa2Name {
            issues.append("NewDocumentFormat nemá hodnotu PDFA2/PDF/A-2.")
        }
        if fields.fingerprintMethodCode != profile.sha256Code || fields.fingerprintMethodName != profile.sha256Name {
            issues.append("ElectronicFingerprintCalculationMethod nemá hodnotu SHA-256.")
        }
        validateCommonFields(fields, issues: &issues, profile: profile)
    }

    private func validateRecordFields(
        _ fields: Fields,
        issues: inout [String],
        profile: P2EConformanceProfile) {
        if fields.formatCode != profile.pdfa2Code || fields.formatName != profile.pdfa2Name {
            issues.append("Záznam neobsahuje hodnotu PDFA2/PDF/A-2.")
        }
        if fields.fingerprintMethodCode != profile.sha256Code || fields.fingerprintMethodName != profile.sha256Name {
            issues.append("Záznam nemá metódu fingerprintu SHA-256.")
        }
        validateCommonFields(fields, issues: &issues, profile: profile)
    }

    private func validateCommonFields(
        _ fields: Fields,
        issues: inout [String],
        profile: P2EConformanceProfile) {
        if fields.evidenceURI?.hasPrefix(profile.evidenceURIBase) != true || fields.evidenceURI == profile.evidenceURIBase {
            issues.append("ConversionRecordEvidenceNumber nemá platný EZZK URI formát.")
        }
        if fields.fingerprintBase64?.isEmpty != false {
            issues.append("ElectronicFingerprintValue je prázdny alebo chýba.")
        }
        if fields.conversionTime == nil {
            issues.append("ConversionExecutionDateTime nie je platný ISO8601 čas alebo chýba.")
        }
    }

    private func compareContext(
        fields: Fields,
        context: Context,
        profile: P2EConformanceProfile,
        issues: inout [String]) {
        if let expectedEvidenceNumber = context.expectedEvidenceNumber,
           let actualEvidenceURI = fields.evidenceURI {
            let expectedURI = expectedEvidenceNumber.hasPrefix(profile.evidenceURIBase)
                ? expectedEvidenceNumber
                : profile.evidenceURIBase + expectedEvidenceNumber
            if actualEvidenceURI != expectedURI {
                issues.append("Evidenčné číslo doložky nezodpovedá očakávaniu.")
            }
        }
        if let expectedConversionTime = context.expectedConversionTime,
           let actualConversionTime = fields.conversionTime,
           abs(actualConversionTime.timeIntervalSince(expectedConversionTime)) > 1 {
            issues.append("Čas konverzie doložky nezodpovedá očakávanému serverovému času.")
        }
    }

    private struct ParsedContainer {
        let root: XMLElement
        let payload: XMLElement
        let identifier: String
        let version: String
    }

    private struct Fields {
        var originalDocumentInfo: XMLElement?
        var newDocumentInfo: XMLElement?
        var documentName: String?
        var formatCode: String?
        var formatName: String?
        var fingerprintMethodCode: String?
        var fingerprintMethodName: String?
        var evidenceURI: String?
        var fingerprintBase64: String?
        var conversionTime: Date?
    }

    private func parseContainer(_ data: Data) -> ParsedContainer? {
        guard let document = try? XMLDocument(data: data,
                                              options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement(),
              root.localName == "XMLDataContainer",
              let xmlData = child(root, "XMLData"),
              let identifier = xmlData.attribute(forName: "Identifier")?.stringValue,
              let version = xmlData.attribute(forName: "Version")?.stringValue,
              let payload = (xmlData.children ?? []).compactMap({ $0 as? XMLElement }).first else {
            return nil
        }
        return ParsedContainer(root: root, payload: payload, identifier: identifier, version: version)
    }

    private func extractFields(from root: XMLElement) -> Fields {
        let originalDocumentInfo = child(root, "OriginalDocumentInfo")
        let newDocumentInfo = child(root, "NewDocumentInfo")
        let format = newDocumentInfo.flatMap { child($0, "NewDocumentFormat") }
        let fingerprintMethod = newDocumentInfo.flatMap { child($0, "ElectronicFingerprintCalculationMethod") }
        let conversionTimeText = value(root, "ConversionExecutionDateTime")
        return Fields(
            originalDocumentInfo: originalDocumentInfo,
            newDocumentInfo: newDocumentInfo,
            documentName: newDocumentInfo.flatMap { value($0, "NewDocumentName") },
            formatCode: codelistValue(format, name: "ItemCode"),
            formatName: codelistValue(format, name: "ItemName"),
            fingerprintMethodCode: codelistValue(fingerprintMethod, name: "ItemCode"),
            fingerprintMethodName: codelistValue(fingerprintMethod, name: "ItemName"),
            evidenceURI: value(root, "ConversionRecordEvidenceNumber"),
            fingerprintBase64: newDocumentInfo.flatMap { value($0, "ElectronicFingerprintValue") },
            conversionTime: conversionDate(conversionTimeText))
    }

    private func codelistValue(_ element: XMLElement?, name: String) -> String? {
        guard let element,
              let codelist = descendant(element, "CodelistItem") else { return nil }
        return value(codelist, name)
    }

    private func conversionDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }()
    }

    private func hasSignatureTimestamp(_ entries: [(name: String, data: Data)]) -> Bool {
        guard let signature = entries.first(where: { $0.name == "META-INF/signatures001.xml" }),
              let document = try? XMLDocument(data: signature.data,
                                              options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return false }
        return descendant(root, "SignatureTimeStamp") != nil
    }

    private func artifactResult(
        issues: [String],
        structure: ASiCEContainerVerifier.Verification,
        documentEntryName: String? = nil,
        xdcfEntryName: String? = nil,
        evidenceURI: String? = nil,
        fingerprintBase64: String? = nil,
        conversionTime: Date? = nil,
        hasTimestamp: Bool = false) -> ArtifactResult {
        let allIssues = sortedUnique(issues)
        return ArtifactResult(isValid: allIssues.isEmpty,
                              issues: allIssues,
                              entryNames: structure.entryNames,
                              documentEntryName: documentEntryName,
                              xdcfEntryName: xdcfEntryName,
                              evidenceURI: evidenceURI,
                              fingerprintBase64: fingerprintBase64,
                              conversionTime: conversionTime,
                              hasTimestamp: hasTimestamp)
    }

    private func sortedUnique(_ issues: [String]) -> [String] {
        Array(Set(issues)).sorted()
    }

    private func child(_ element: XMLElement, _ name: String) -> XMLElement? {
        (element.children ?? []).compactMap { $0 as? XMLElement }.first { $0.localName == name }
    }

    private func descendant(_ element: XMLElement, _ name: String) -> XMLElement? {
        for childNode in element.children ?? [] {
            guard let subelement = childNode as? XMLElement else { continue }
            if subelement.localName == name { return subelement }
            if let found = descendant(subelement, name) { return found }
        }
        return nil
    }

    private func value(_ element: XMLElement, _ name: String) -> String? {
        child(element, name)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
