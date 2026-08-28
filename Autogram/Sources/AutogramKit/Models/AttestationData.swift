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
    public var originConfirmed: Bool
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

    private enum CodingKeys: String, CodingKey {
        case originalDocumentOrder, originalDocumentName, originalDocumentTypeCode,
             originalDocumentTypeLabel, originConfirmed, numberOfSheets,
             sheetCountingMethod, nonEmptyPageCount, paperSizeBreakdown,
             newDocumentName, newDocumentFormatLabel, conversionExecutionDateTime,
             evidenceNumber, performingPerson, usedDeviceDescription
    }

    public init(originalDocumentOrder: Int = 1,
                originalDocumentName: String = "",
                originalDocumentTypeCode: String = "",
                originalDocumentTypeLabel: String = "",
                originConfirmed: Bool = false,
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
        self.originConfirmed = originConfirmed
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalDocumentOrder = try container.decode(Int.self, forKey: .originalDocumentOrder)
        originalDocumentName = try container.decode(String.self, forKey: .originalDocumentName)
        originalDocumentTypeCode = try container.decode(String.self, forKey: .originalDocumentTypeCode)
        originalDocumentTypeLabel = try container.decode(String.self, forKey: .originalDocumentTypeLabel)
        originConfirmed = try container.decodeIfPresent(Bool.self, forKey: .originConfirmed) ?? false
        numberOfSheets = try container.decode(Int.self, forKey: .numberOfSheets)
        sheetCountingMethod = try container.decode(SheetCountingMethod.self, forKey: .sheetCountingMethod)
        nonEmptyPageCount = try container.decode(Int.self, forKey: .nonEmptyPageCount)
        paperSizeBreakdown = try container.decode([PaperSizeGroup].self, forKey: .paperSizeBreakdown)
        newDocumentName = try container.decode(String.self, forKey: .newDocumentName)
        newDocumentFormatLabel = try container.decode(String.self, forKey: .newDocumentFormatLabel)
        conversionExecutionDateTime = try container.decode(Date.self, forKey: .conversionExecutionDateTime)
        evidenceNumber = try container.decodeIfPresent(String.self, forKey: .evidenceNumber)
        performingPerson = try container.decode(AdvocateProfile.self, forKey: .performingPerson)
        usedDeviceDescription = try container.decode(String.self, forKey: .usedDeviceDescription)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalDocumentOrder, forKey: .originalDocumentOrder)
        try container.encode(originalDocumentName, forKey: .originalDocumentName)
        try container.encode(originalDocumentTypeCode, forKey: .originalDocumentTypeCode)
        try container.encode(originalDocumentTypeLabel, forKey: .originalDocumentTypeLabel)
        try container.encode(originConfirmed, forKey: .originConfirmed)
        try container.encode(numberOfSheets, forKey: .numberOfSheets)
        try container.encode(sheetCountingMethod, forKey: .sheetCountingMethod)
        try container.encode(nonEmptyPageCount, forKey: .nonEmptyPageCount)
        try container.encode(paperSizeBreakdown, forKey: .paperSizeBreakdown)
        try container.encode(newDocumentName, forKey: .newDocumentName)
        try container.encode(newDocumentFormatLabel, forKey: .newDocumentFormatLabel)
        try container.encode(conversionExecutionDateTime, forKey: .conversionExecutionDateTime)
        try container.encodeIfPresent(evidenceNumber, forKey: .evidenceNumber)
        try container.encode(performingPerson, forKey: .performingPerson)
        try container.encode(usedDeviceDescription, forKey: .usedDeviceDescription)
    }
}

public enum AttestationValidationError: LocalizedError, Equatable, Sendable {
    case originNotConfirmed
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
        case .originNotConfirmed:
            return "Potvrďte, že vstupný dokument je originál alebo úradne osvedčená kópia."
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
        if !data.originConfirmed {
            errors.append(.originNotConfirmed)
        }
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


