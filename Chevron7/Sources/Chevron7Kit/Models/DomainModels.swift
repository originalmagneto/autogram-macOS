// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public enum ConversionDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case paperToElectronic = "P→E"
    case electronicToPaper = "E→P"
    case electronicToElectronic = "E→E"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paperToElectronic: return "Z listinnej do elektronickej podoby"
        case .electronicToPaper: return "Z elektronickej do listinnej podoby"
        case .electronicToElectronic: return "Z elektronickej do elektronickej podoby"
        }
    }
}

public enum PaperClassification: String, Codable, CaseIterable, Sendable {
    case a4Portrait = "A4 na výšku"
    case a4Landscape = "A4 na šírku"
    case a3Portrait = "A3 na výšku"
    case a3Landscape = "A3 na šírku"
    case letterPortrait = "Letter na výšku"
    case letterLandscape = "Letter na šírku"
    case unknown = "Neznámy formát"

    public var isKnownFormat: Bool { self != .unknown }
}

public struct PageAnalysis: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { pageIndex }
    public var pageIndex: Int
    public var widthPt: Double
    public var heightPt: Double
    public var sizeClass: PaperClassification
    public var inkCoverage: Double
    public var isEmpty: Bool

    public init(pageIndex: Int, widthPt: Double, heightPt: Double,
                sizeClass: PaperClassification, inkCoverage: Double, isEmpty: Bool) {
        self.pageIndex = pageIndex
        self.widthPt = widthPt
        self.heightPt = heightPt
        self.sizeClass = sizeClass
        self.inkCoverage = inkCoverage
        self.isEmpty = isEmpty
    }
}

public enum SecurityElementReviewState: String, Codable, CaseIterable, Sendable {
    case pending
    case confirmed
    case rejected

    public var label: String {
        switch self {
        case .pending: return "Čaká na kontrolu"
        case .confirmed: return "Potvrdený"
        case .rejected: return "Odmietnutý"
        }
    }
}

public struct SecurityReviewElement: Codable, Hashable, Sendable {
    public let id: UUID
    public let state: SecurityElementReviewState
    public let kind: SecurityElement.Kind
    public let pageIndex: Int
    public let boundingBox: NormalizedRect
    public let observation: SecurityElement.Observation?
    public let verbalDescription: String?
    public let originalLocation: String?
    public let newDocumentPageIndex: Int?

    public init(id: UUID, state: SecurityElementReviewState,
                kind: SecurityElement.Kind, pageIndex: Int,
                boundingBox: NormalizedRect, observation: SecurityElement.Observation? = nil,
                verbalDescription: String? = nil, originalLocation: String? = nil, newDocumentPageIndex: Int? = nil) {
        self.id = id
        self.state = state
        self.kind = kind
        self.pageIndex = pageIndex
        self.boundingBox = boundingBox
        self.observation = observation
        self.verbalDescription = verbalDescription
        self.originalLocation = originalLocation
        self.newDocumentPageIndex = newDocumentPageIndex
    }
}

public struct SecurityReviewStamp: Codable, Hashable, Sendable {
    public let checkedNonEmptyPageIndices: [Int]
    public let confirmedElementCount: Int
    public let rejectedElementCount: Int
    public let elementDecisions: [SecurityReviewElement]
    public let detectorIdentifier: String
    public let reviewedAt: Date
    public let noElementsConfirmed: Bool?

    public init(checkedNonEmptyPageIndices: [Int],
                confirmedElementCount: Int,
                rejectedElementCount: Int,
                elementDecisions: [SecurityReviewElement] = [],
                detectorIdentifier: String = "BuiltInVisionProvider",
                reviewedAt: Date = Date(), noElementsConfirmed: Bool? = nil) {
        self.checkedNonEmptyPageIndices = checkedNonEmptyPageIndices.sorted()
        self.confirmedElementCount = confirmedElementCount
        self.rejectedElementCount = rejectedElementCount
        self.elementDecisions = elementDecisions
        self.detectorIdentifier = detectorIdentifier
        self.reviewedAt = reviewedAt
        self.noElementsConfirmed = noElementsConfirmed
    }
}

public struct SecurityElement: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: Kind
    public var pageIndex: Int
    public var boundingBox: NormalizedRect
    public var confidence: Double
    public var verbalDescription: String
    public var detectedByAI: Bool
    public var reviewState: SecurityElementReviewState
    /// Audit string naming the candidate sources and the deciding classifier,
    /// for example "builtIn+contour; kNN(n=12)". Nil for manual or legacy elements.
    public var detectionSource: String?
    public var observation: Observation
    public var originalLocation: String
    public var newDocumentPageIndex: Int?

    public enum Observation: String, Codable, Sendable { case scanRegion, physicalOriginal }
    public var hasScanRegion: Bool { observation == .scanRegion && boundingBox.width > 0 && boundingBox.height > 0 }
    public var trainingKind: Kind? { hasScanRegion ? kind.visualKind : nil }

    private enum CodingKeys: String, CodingKey {
        case id, kind, pageIndex, boundingBox, confidence, verbalDescription,
             detectedByAI, reviewState, detectionSource, observation, originalLocation, newDocumentPageIndex
    }

    public init(id: UUID = UUID(), kind: Kind, pageIndex: Int,
                boundingBox: NormalizedRect, confidence: Double,
                 verbalDescription: String = "", detectedByAI: Bool = true,
                 reviewState: SecurityElementReviewState? = nil,
                 detectionSource: String? = nil,
                 observation: Observation = .scanRegion, originalLocation: String = "",
                 newDocumentPageIndex: Int? = nil) {
        self.id = id
        self.kind = kind
        self.pageIndex = pageIndex
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.verbalDescription = verbalDescription
        self.detectedByAI = detectedByAI
        self.reviewState = reviewState ?? (detectedByAI ? .pending : .confirmed)
        self.detectionSource = detectionSource
        self.observation = observation
        self.originalLocation = originalLocation
        self.newDocumentPageIndex = newDocumentPageIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        self.boundingBox = try container.decode(NormalizedRect.self, forKey: .boundingBox)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.verbalDescription = try container.decodeIfPresent(String.self, forKey: .verbalDescription) ?? ""
        self.detectedByAI = try container.decodeIfPresent(Bool.self, forKey: .detectedByAI) ?? true
        // Old session/register data has no human-review decision. Treat it as
        // pending regardless of provenance so it cannot bypass the new gate.
        self.reviewState = try container.decodeIfPresent(SecurityElementReviewState.self,
                                                         forKey: .reviewState) ?? .pending
        self.detectionSource = try container.decodeIfPresent(String.self, forKey: .detectionSource)
        self.observation = try container.decodeIfPresent(Observation.self, forKey: .observation) ?? .scanRegion
        self.originalLocation = try container.decodeIfPresent(String.self, forKey: .originalLocation) ?? ""
        self.newDocumentPageIndex = try container.decodeIfPresent(Int.self, forKey: .newDocumentPageIndex)
    }

    public func locationDescription(pageSizePt: CGSize) -> String {
        if observation == .physicalOriginal { return "\(kind.label), strana \(pageIndex + 1): \(originalLocation) (skontrolované na origináli)" }
        let horizontalZone = boundingBox.midX < 0.33 ? "v ľavej tretine" :
                             boundingBox.midX < 0.67 ? "v strede" : "v pravej tretine"
        let verticalZone = boundingBox.midY < 0.33 ? "v dolnej časti" :
                           boundingBox.midY < 0.67 ? "v strede výšky" : "v hornej časti"
        return "\(kind.label) na strane \(pageIndex + 1), \(verticalZone), \(horizontalZone)"
    }

    /// One element in item 5 of the live clause preview: its kind and place once, then the
    /// advocate's own words if they wrote any. The automatic description is the place itself,
    /// so it is not added a second time.
    public var clausePreviewLine: String {
        let location = locationDescription(pageSizePt: .zero)
        let detail = verbalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty || detail == location || detail == location + "." { return location }
        return "\(location): \(detail)"
    }

    public var locationCodelist11Item: ZakoCodelistItem {
        let vertical: String
        switch boundingBox.midY {
        case ..<0.33: vertical = "down"
        case ..<0.67: vertical = "middle"
        default: vertical = "up"
        }
        let horizontal: String
        switch boundingBox.midX {
        case ..<0.33: horizontal = "left"
        case ..<0.67: horizontal = "center"
        default: horizontal = "right"
        }
        let code: String
        switch (vertical, horizontal) {
        case ("down", "left"): code = "Left down"
        case ("down", "center"): code = "Down"
        case ("down", "right"): code = "Right down"
        case ("middle", "left"): code = "Left"
        case ("middle", "center"): code = "Mid"
        case ("middle", "right"): code = "Right"
        case ("up", "left"): code = "Left up"
        case ("up", "center"): code = "Up"
        default: code = "Right up"
        }
        return ZakoCodelists.locationItem(code: code)!
    }

    public func sheetNumber(sheetMethod: SheetCountingMethod) -> Int {
        let page = pageIndex + 1
        switch sheetMethod {
        case .oneSheetPerPage:
            return page
        case .duplexEstimate, .manual:
            return (page + 1) / 2
        }
    }
}

public struct NormalizedPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = NormalizedPoint(x: 0, y: 0)
}

public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = NormalizedRect(x: 0, y: 0, width: 0, height: 0)
}

public struct DocumentAnalysis: Codable, Hashable, Sendable {
    public var totalPages: Int
    public var nonEmptyPages: Int
    public var estimatedSheetsDuplex: Int
    public var pageAnalyses: [PageAnalysis]
    public var securityElements: [SecurityElement]
    public var suggestedTitle: String?
    public var analyzedAt: Date

    public init(totalPages: Int, nonEmptyPages: Int, estimatedSheetsDuplex: Int,
                pageAnalyses: [PageAnalysis], securityElements: [SecurityElement],
                suggestedTitle: String?, analyzedAt: Date) {
        self.totalPages = totalPages
        self.nonEmptyPages = nonEmptyPages
        self.estimatedSheetsDuplex = estimatedSheetsDuplex
        self.pageAnalyses = pageAnalyses
        self.securityElements = securityElements
        self.suggestedTitle = suggestedTitle
        self.analyzedAt = analyzedAt
    }

    public static func empty() -> DocumentAnalysis {
        DocumentAnalysis(totalPages: 0, nonEmptyPages: 0, estimatedSheetsDuplex: 0,
                         pageAnalyses: [], securityElements: [], suggestedTitle: nil,
                         analyzedAt: Date())
    }

    public var paperSizeSummary: [PaperClassification: Int] {
        Dictionary(grouping: pageAnalyses, by: \.sizeClass)
            .mapValues(\.count)
    }
}

public enum SheetCountingMethod: String, Codable, CaseIterable, Sendable {
    case duplexEstimate = "Obojstranná tlač (odhad)"
    case oneSheetPerPage = "Jednostranná tlač (1 strana = 1 list)"
    case manual = "Manuálne zadané"

    public var id: String { rawValue }
}
