import Foundation

struct PDFInspection: Sendable, Equatable {
    let files: [InspectedPDF]

    init(files: [InspectedPDF]) {
        self.files = files
    }
}

struct InspectedPDF: Sendable, Equatable, Identifiable {
    let id: String
    let isSignable: Bool
    let signatures: [ExistingPDFSignature]
    let documents: [String]

    init(id: String, isSignable: Bool, signatures: [ExistingPDFSignature] = [], documents: [String] = []) {
        self.id = id
        self.isSignable = isSignable
        self.signatures = signatures
        self.documents = documents
    }
}

struct ExistingPDFSignature: Sendable, Equatable, Identifiable {
    let id: String
    let signerDisplayName: String?
    let validationState: SignatureValidationState
    let signingTime: Date?
    let format: String?
    let hasQualifiedTimestamp: Bool
    let documents: [String]

    init(
        id: String,
        signerDisplayName: String?,
        validationState: SignatureValidationState,
        signingTime: Date?,
        format: String?,
        hasQualifiedTimestamp: Bool,
        documents: [String] = []
    ) {
        self.id = id
        self.signerDisplayName = signerDisplayName
        self.validationState = validationState
        self.signingTime = signingTime
        self.format = format
        self.hasQualifiedTimestamp = hasQualifiedTimestamp
        self.documents = documents
    }
}

enum SignatureValidationState: Sendable, Equatable {
    case valid
    case invalid
    case indeterminate
}
