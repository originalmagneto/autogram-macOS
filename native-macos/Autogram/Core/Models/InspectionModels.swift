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

    init(id: String, isSignable: Bool) {
        self.id = id
        self.isSignable = isSignable
    }
}
