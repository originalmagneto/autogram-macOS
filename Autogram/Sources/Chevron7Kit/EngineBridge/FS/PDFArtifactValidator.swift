import Foundation

enum PDFArtifactValidationError: Error {
    case invalidPDF
}

struct PDFArtifactValidator {
    func validate(at url: URL, fileExtension: String = "pdf") throws {
        let data = try Data(contentsOf: url)
        if fileExtension.lowercased() == "asice" {
            guard data.starts(with: Data([0x50, 0x4B, 0x03, 0x04])) else {
                throw PDFArtifactValidationError.invalidPDF
            }
            return
        }
        guard data.starts(with: Data("%PDF-".utf8)) else {
            throw PDFArtifactValidationError.invalidPDF
        }

        var index = data.endIndex
        while index > data.startIndex {
            let previous = data.index(before: index)
            guard data[previous].isPDFWhitespace else { break }
            index = previous
        }
        guard Array(data[..<index].suffix(5)) == Array("%%EOF".utf8) else {
            throw PDFArtifactValidationError.invalidPDF
        }
    }
}

private extension UInt8 {
    var isPDFWhitespace: Bool {
        self == 0x09 || self == 0x0A || self == 0x0C || self == 0x0D || self == 0x20
    }
}
