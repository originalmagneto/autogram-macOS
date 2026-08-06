import Foundation

struct PDFItemDescriptor: Sendable, Equatable, Identifiable {
    let id: String
    let sourceURL: URL

    var redactedDisplayName: String {
        sourceURL.lastPathComponent
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

    init(id: UUID = UUID(), descriptor: PDFItemDescriptor, status: PDFItemStatus = .pending) {
        self.id = id
        self.descriptor = descriptor
        self.status = status
    }

    func updatingStatus(to status: PDFItemStatus) -> PDFItem {
        PDFItem(id: id, descriptor: descriptor, status: status)
    }
}

enum PDFItemStatus: Sendable, Equatable {
    case pending
    case inspected
    case signing
    case completed
    case failed
}
