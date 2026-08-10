import CoreGraphics
import Foundation

struct SignatureAsset: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case png
        case pdf
    }

    let id: UUID
    let kind: Kind
    let fileURL: URL
}

struct VisibleSignaturePlacement: Sendable, Equatable {
    var pageIndex: Int
    var pageRect: CGRect
    var rotationDegrees: Double
}

struct VisibleSignatureCardContent: Sendable, Equatable {
    var signerName: String
    var certificateQualification: String?
    var profile: String
    var timestampStatus: String
}
