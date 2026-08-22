import Foundation

public struct AdvocateProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var fullName: String
    public var position: String
    public var registrationNumber: String
    public var ico: String
    public var officeName: String
    public var officeAddress: String
    public var isLegalEntity: Bool

    public init(id: UUID = UUID(), fullName: String = "", position: String = "advokát",
                registrationNumber: String = "", ico: String = "",
                officeName: String = "", officeAddress: String = "",
                isLegalEntity: Bool = false) {
        self.id = id
        self.fullName = fullName
        self.position = position
        self.registrationNumber = registrationNumber
        self.ico = ico
        self.officeName = officeName
        self.officeAddress = officeAddress
        self.isLegalEntity = isLegalEntity
    }

    public static let empty = AdvocateProfile()
}

public struct AttestationData: Codable, Hashable, Sendable {
    public var originalDocumentOrder: Int
    public var originalDocumentName: String
    public var originalDocumentTypeCode: String
    public var originalDocumentTypeLabel: String
    public var numberOfSheets: Int
    public var sheetCountingMethod: SheetCountingMethod
    public var nonEmptyPageCount: Int
    public var paperSizeBreakdown: [PaperSizeGroup]

    public var newDocumentName: String
    public var newDocumentFormatLabel: String

    public var conversionExecutionDateTime: Date
    public var evidenceNumber: String?

    public var performingPerson: AdvocateProfile
    public var usedDeviceDescription: String

    public struct PaperSizeGroup: Codable, Hashable, Sendable {
        public var sizeClass: PaperClassification
        public var sheets: Int
        public init(sizeClass: PaperClassification, sheets: Int) {
            self.sizeClass = sizeClass
            self.sheets = sheets
        }
    }

    public init(originalDocumentOrder: Int = 1,
                originalDocumentName: String = "",
                originalDocumentTypeCode: String = "",
                originalDocumentTypeLabel: String = "",
                numberOfSheets: Int = 0,
                sheetCountingMethod: SheetCountingMethod = .duplexEstimate,
                nonEmptyPageCount: Int = 0,
                paperSizeBreakdown: [PaperSizeGroup] = [],
                newDocumentName: String = "",
                newDocumentFormatLabel: String = "PDF",
                conversionExecutionDateTime: Date = Date(),
                evidenceNumber: String? = nil,
                performingPerson: AdvocateProfile = .empty,
                usedDeviceDescription: String = "") {
        self.originalDocumentOrder = originalDocumentOrder
        self.originalDocumentName = originalDocumentName
        self.originalDocumentTypeCode = originalDocumentTypeCode
        self.originalDocumentTypeLabel = originalDocumentTypeLabel
        self.numberOfSheets = numberOfSheets
        self.sheetCountingMethod = sheetCountingMethod
        self.nonEmptyPageCount = nonEmptyPageCount
        self.paperSizeBreakdown = paperSizeBreakdown
        self.newDocumentName = newDocumentName
        self.newDocumentFormatLabel = newDocumentFormatLabel
        self.conversionExecutionDateTime = conversionExecutionDateTime
        self.evidenceNumber = evidenceNumber
        self.performingPerson = performingPerson
        self.usedDeviceDescription = usedDeviceDescription
    }
}

public enum AttestationValidationError: LocalizedError, Equatable, Sendable {
    case missingOriginalName
    case missingNewDocumentName
    case missingPerformingPerson
    case missingRegistrationNumber
    case invalidSheetCount
    case noSecurityElementsConfirmed
    case missingEvidenceNumber
    case timestampBeforeConversionTime(conversionTime: Date, stampTime: Date)

    public var errorDescription: String? {
        switch self {
        case .missingOriginalName:
            return "Chýba názov pôvodného listinného dokumentu."
        case .missingNewDocumentName:
            return "Chýba názov novovzniknutého elektronického dokumentu."
        case .missingPerformingPerson:
            return "Chýbajú údaje osoby vykonávajúcej konverziu."
        case .missingRegistrationNumber:
            return "Chýba evidenčné číslo advokáta (SAK)."
        case .invalidSheetCount:
            return "Počet listov musí byť aspoň 1."
        case .noSecurityElementsConfirmed:
            return "Potvrďte bezpečnostné prvky pôvodného dokumentu."
        case .missingEvidenceNumber:
            return "Získajte evidenčné číslo záznamu z evidencie záznamov (EZZK)."
        case .timestampBeforeConversionTime(let c, let t):
            return "Časová pečiatka (\(t)) predchádza času konverzie (\(c)). Zápis by bol v EZZK zamietnutý."
        }
    }
}

public enum AttestationValidator {
    public static func validate(_ data: AttestationData,
                                securityElements: [SecurityElement],
                                qualifiedTimestampTime: Date?) -> [AttestationValidationError] {
        var errors: [AttestationValidationError] = []
        if data.originalDocumentName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.missingOriginalName)
        }
        if data.newDocumentName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.missingNewDocumentName)
        }
        if data.performingPerson.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.missingPerformingPerson)
        }
        if data.performingPerson.registrationNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.missingRegistrationNumber)
        }
        if data.numberOfSheets < 1 {
            errors.append(.invalidSheetCount)
        }
        if securityElements.isEmpty {
            errors.append(.noSecurityElementsConfirmed)
        }
        if (data.evidenceNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.missingEvidenceNumber)
        }
        if let stamp = qualifiedTimestampTime, stamp < data.conversionExecutionDateTime.addingTimeInterval(-60) {
            errors.append(.timestampBeforeConversionTime(
                conversionTime: data.conversionExecutionDateTime, stampTime: stamp))
        }
        return errors
    }
}
