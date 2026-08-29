import Foundation

public struct ComplianceValidationError: LocalizedError, Sendable {
    public var domain: String
    public var issues: [String]

    public init(domain: String, issues: [String]) {
        self.domain = domain
        self.issues = issues
    }

    public var errorDescription: String? {
        let list = issues.map { "• " + $0 }.joined(separator: "\n")
        return "\(domain): validácia zlyhala.\n\(list)"
    }
}

public struct AttestationXMLValidator: Sendable {
    public init() {}

    public struct Context: Sendable {
        public var fingerprintSHA256Hex: String
        public var securityElementCount: Int

        public init(fingerprintSHA256Hex: String, securityElementCount: Int) {
            self.fingerprintSHA256Hex = fingerprintSHA256Hex
            self.securityElementCount = securityElementCount
        }
    }

    public func validate(_ xml: String, context: Context) -> [String] {
        validate(xml,
                 context: context,
                 formPack: FormPackRepository.currentLegacyUnverified)
    }

    public func validate(_ xml: String,
                         context: Context,
                         formPack: ConversionFormPack) -> [String] {
        var issues: [String] = []
        guard let document = try? XMLDocument(xmlString: xml,
                                              options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else {
            return ["XML sa nepodarilo parsovať."]
        }

        if root.localName != "ConversionRecord" {
            issues.append("Koreňový element má byť ConversionRecord, je \(root.localName ?? "?").")
        }
        let expectedNamespace = formPack.namespace
        if root.uri != expectedNamespace {
            issues.append("Chýba očakávaný namespace form packu \(formPack.id).")
        }

        guard let info = child(root, "OriginalDocumentInfo") else {
            issues.append("Chýba OriginalDocumentInfo.")
            return sortedUnique(issues)
        }
        for required in ["OriginalDocumentName",
                         "OriginalDocumentNumberOfSheets",
                         "OriginalDocumentNonEmptyPageCount"] where value(info, required)?.isEmpty ?? true {
            issues.append("OriginalDocumentInfo.\(required) je prázdne alebo chýba.")
        }
        if let sheets = value(info, "OriginalDocumentNumberOfSheets"),
           (Int(sheets) ?? 0) < 1 {
            issues.append("OriginalDocumentNumberOfSheets musí byť aspoň 1.")
        }

        let paperSizeBlocks = children(info, "OriginalDocumentPaperSize")
        if paperSizeBlocks.isEmpty || paperSizeBlocks.allSatisfy({ block in
            value(block, "PaperSizeNumberOfSheets")?.isEmpty ?? true
        }) {
            issues.append("Chýba OriginalDocumentPaperSize (formát listiny).")
        }

        let elementDetails = children(info, "DocumentSecurityElementsDetails")
        if elementDetails.isEmpty {
            issues.append("Doložka neuvádza žiadne bezpečnostné prvky.")
        }
        for (index, detail) in elementDetails.enumerated() {
            if child(detail, "OriginalDocumentSecurityElementsDescription") == nil {
                issues.append("Prvok \(index + 1): chýba popis (codelist 15).")
            }
            let pageText = value(detail, "OriginalDocumentSecurityElementsPage")
            if (pageText.flatMap(Int.init) ?? 0) < 1 {
                issues.append("Prvok \(index + 1): neplatná strana.")
            }
        }
        if elementDetails.count != context.securityElementCount {
            issues.append("Počet prvkov v XML (\(elementDetails.count)) nezodpovedá vstupu (\(context.securityElementCount)).")
        }

        guard let newInfo = child(root, "NewDocumentInfo") else {
            issues.append("Chýba NewDocumentInfo.")
            return sortedUnique(issues)
        }
        if value(newInfo, "NewDocumentName")?.isEmpty ?? true {
            issues.append("NewDocumentName je prázdne.")
        }
        if child(newInfo, "NewDocumentFormat") == nil {
            issues.append("Chýba NewDocumentFormat (codelist 53).")
        }
        let fingerprint = value(newInfo, "ElectronicFingerprintValue") ?? ""
        let expectedFingerprint = AttestationClauseGenerator.fingerprintBase64(hex: context.fingerprintSHA256Hex)
        if fingerprint.isEmpty {
            issues.append("Chýba ElectronicFingerprintValue.")
        } else if fingerprint != expectedFingerprint {
            issues.append("ElectronicFingerprintValue nezodpovedá SHA-256 dokumentu.")
        }
        if child(newInfo, "ElectronicFingerprintCalculationMethod") == nil {
            issues.append("Chýba ElectronicFingerprintCalculationMethod (codelist 14).")
        }

        if let person = child(root, "PersonPerformingConversion") {
            let physical = descendant(person, "PhysicalPerson")
            let legal = descendant(person, "LegalSubject")
            if physical == nil && legal == nil {
                issues.append("PersonPerformingConversion neobsahuje PhysicalPerson ani LegalSubject.")
            }
            if let physical {
                let personName = child(physical, "PersonName")
                for field in ["GivenName", "FamilyName"] {
                    let fieldValue = personName.flatMap { value($0, field) } ?? ""
                    if fieldValue.isEmpty {
                        issues.append("PhysicalPerson.\(field) je prázdne.")
                    }
                }
            }
            if let legal, value(legal, "Name")?.isEmpty ?? true {
                issues.append("LegalSubject.Name je prázdne.")
            }
        } else {
            issues.append("Chýba PersonPerformingConversion.")
        }

        if value(root, "UsedDevice")?.isEmpty ?? true {
            issues.append("UsedDevice je prázdne.")
        }

        if let execution = value(root, "ConversionExecutionDateTime") {
            if AttestationClauseGenerator.localOffsetFormatter.date(from: execution) == nil,
               AttestationClauseGenerator.isoFormatter.date(from: execution) == nil {
                issues.append("ConversionExecutionDateTime nie je platný ISO8601 čas: \(execution).")
            }
        } else {
            issues.append("Chýba ConversionExecutionDateTime.")
        }

        if let evidence = value(root, "ConversionRecordEvidenceNumber") {
            let base = AttestationXMLConstants.conversionRecordURIBase
            if !evidence.hasPrefix(base) || evidence.count <= base.count {
                issues.append("ConversionRecordEvidenceNumber má byť URI \(base){{číslo}}.")
            }
        } else {
            issues.append("Chýba ConversionRecordEvidenceNumber.")
        }

        return sortedUnique(issues)
    }

    private func sortedUnique(_ issues: [String]) -> [String] {
        Array(Set(issues)).sorted()
    }

    private func child(_ element: XMLElement, _ name: String) -> XMLElement? {
        (element.children ?? []).compactMap { $0 as? XMLElement }.first { $0.localName == name }
    }

    private func children(_ element: XMLElement, _ name: String) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name }
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
