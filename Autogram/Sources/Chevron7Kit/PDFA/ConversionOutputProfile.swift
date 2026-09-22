import Foundation

public struct ConversionOutputProfile: Codable, Hashable, Identifiable, Sendable {
    public enum Container: String, Codable, Sendable {
        case pdf
        case png
    }

    public enum VerificationState: String, Codable, Sendable {
        case pilotOnly
        case externallyVerified
        case notImplemented
    }

    public let id: String
    public let label: String
    public let container: Container
    public let pdfaPart: Int?
    public let pdfaConformance: String?
    public let requiresTaggedStructure: Bool
    public let requiresUnicodeMapping: Bool
    public let requiresOCRTextLayer: Bool
    public let verificationState: VerificationState

    public init(
        id: String,
        label: String,
        container: Container,
        pdfaPart: Int? = nil,
        pdfaConformance: String? = nil,
        requiresTaggedStructure: Bool = false,
        requiresUnicodeMapping: Bool = false,
        requiresOCRTextLayer: Bool = false,
        verificationState: VerificationState
    ) {
        self.id = id
        self.label = label
        self.container = container
        self.pdfaPart = pdfaPart
        self.pdfaConformance = pdfaConformance
        self.requiresTaggedStructure = requiresTaggedStructure
        self.requiresUnicodeMapping = requiresUnicodeMapping
        self.requiresOCRTextLayer = requiresOCRTextLayer
        self.verificationState = verificationState
    }

    public var isImplemented: Bool {
        verificationState != .notImplemented
    }

    public var isExternallyVerified: Bool {
        verificationState == .externallyVerified
    }

    /// Existing runtime output retained as an explicitly named pilot profile.
    public static let pilotPDFA2b = ConversionOutputProfile(
        id: "pdfa-2b-pilot",
        label: "PDF/A-2b (pilot)",
        container: .pdf,
        pdfaPart: 2,
        pdfaConformance: "B",
        verificationState: .pilotOnly)

    /// Reserved until an authoritative format matrix and independent validator
    /// confirm the required PDF/A-1a tagging and Unicode semantics.
    public static let proposedPDFA1a = ConversionOutputProfile(
        id: "pdfa-1a-proposed",
        label: "PDF/A-1a (proposed)",
        container: .pdf,
        pdfaPart: 1,
        pdfaConformance: "A",
        requiresTaggedStructure: true,
        requiresUnicodeMapping: true,
        requiresOCRTextLayer: true,
        verificationState: .notImplemented)

    /// Reserved for the constrained single-page graphical output scenario.
    public static let proposedSinglePagePNG = ConversionOutputProfile(
        id: "png-single-page-proposed",
        label: "PNG (single page, proposed)",
        container: .png,
        verificationState: .notImplemented)
}