import Foundation

struct PDFItemDescriptor: Sendable, Equatable, Identifiable {
    let id: String
    let sourceURL: URL

    var redactedDisplayName: String {
        sourceURL.lastPathComponent
    }

    var isPDF: Bool {
        sourceURL.pathExtension.lowercased() == "pdf"
    }

    init(id: String, sourceURL: URL) {
        self.id = id
        self.sourceURL = sourceURL
    }
}

struct PDFItem: Sendable, Equatable, Identifiable {
    let id: UUID
    let descriptor: PDFItemDescriptor
    let status: PDFItemStatus
    let inspection: PDFItemInspection

    init(
        id: UUID = UUID(),
        descriptor: PDFItemDescriptor,
        status: PDFItemStatus = .pending,
        inspection: PDFItemInspection = .pending
    ) {
        self.id = id
        self.descriptor = descriptor
        self.status = status
        self.inspection = inspection
    }

    func updatingStatus(to status: PDFItemStatus) -> PDFItem {
        PDFItem(id: id, descriptor: descriptor, status: status, inspection: inspection)
    }

    func updatingInspection(to inspection: PDFItemInspection) -> PDFItem {
        PDFItem(id: id, descriptor: descriptor, status: status, inspection: inspection)
    }

    var workspaceLabel: String {
        switch status {
        case .pending: "Inspecting"
        case .inspected: "Ready"
        case .signing: "Signing"
        case .completed: "Signed"
        case .failed where inspection == .failed: "Inspection failed"
        case .failed: "Signing failed"
        }
    }
}

enum PDFItemInspection: Sendable, Equatable {
    case pending
    case completed(InspectedPDF)
    case failed

    var signatures: [ExistingPDFSignature] {
        guard case .completed(let inspection) = self else { return [] }
        return inspection.signatures
    }

    var isComplete: Bool {
        if case .completed = self { return true }
        return false
    }
}

enum PDFItemStatus: Sendable, Equatable {
    case pending
    case inspected
    case signing
    case completed
    case failed
}
