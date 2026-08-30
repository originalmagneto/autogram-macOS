import CoreGraphics
import Foundation

public struct SignatureAsset: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case png
        case pdf
    }

    public let id: UUID
    public let kind: Kind
    public let managedFilename: String
}

public struct VisibleSignaturePlacement: Sendable, Equatable {
    public var pageIndex: Int
    public var pageRect: CGRect
    public var rotationDegrees: Double

    public init(pageIndex: Int, pageRect: CGRect, rotationDegrees: Double) {
        self.pageIndex = pageIndex
        self.pageRect = pageRect
        self.rotationDegrees = rotationDegrees
    }
}

public struct VisibleSignatureCardContent: Sendable, Equatable {
    public var signerName: String
    public var certificateQualification: String?
}
