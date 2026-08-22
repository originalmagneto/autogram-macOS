import Foundation
import PDFKit

public struct EmbeddedFileService: Sendable {
    public init() {}

    public struct Attachment: Sendable {
        public var fileName: String
        public var mimeType: String
        public var data: Data
        public init(fileName: String, mimeType: String, data: Data) {
            self.fileName = fileName
            self.mimeType = mimeType
            self.data = data
        }
    }

    public func embed(_ attachment: Attachment, into pdf: Data) throws -> Data {
        guard let root = PDFObjectScanner.rootObjectNumber(in: pdf) else {
            throw PDFAError.rootNotFound
        }
        guard let catalogDict = PDFObjectScanner.catalogDictionary(number: root.objectNumber, in: pdf) else {
            throw PDFAError.catalogNotFound(root.objectNumber)
        }
        guard !catalogDict.contains("/EmbeddedFiles") && !catalogDict.contains("/Names") else {
            return try appendAsUnreferencedAttachment(attachment, into: pdf, catalogDict: catalogDict,
                                                      root: root)
        }

        let maxNumber = max(PDFObjectScanner.maxObjectNumber(in: pdf), root.objectNumber)
        let fileNumber = maxNumber + 1
        let specNumber = maxNumber + 2
        let newCatalogNumber = maxNumber + 3

        var fileObj = Data("\n\(fileNumber) 0 obj\n<< /Type /EmbeddedFile /Subtype /\(attachment.mimeType) /Length \(attachment.data.count) >>\nstream\n".utf8)
        fileObj.append(attachment.data)
        fileObj.append(Data("\nendstream\nendobj\n".utf8))

        let nameASCII = attachment.fileName.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "").replacingOccurrences(of: "\\", with: "")
        let ufHex = attachment.fileName.utf16.map { String(format: "%04X", $0) }.joined()
        let escapedDesc = attachment.mimeType.replacingOccurrences(of: "(", with: "")

        let specBody = "<< /Type /Filespec /F (\(nameASCII)) /UF <FEFF\(ufHex)> /Desc (\(escapedDesc))" +
            " /EF << /F \(fileNumber) 0 R /UF \(fileNumber) 0 R >> >>"
        let specObj = Data("\n\(specNumber) 0 obj\n\(specBody)\nendobj\n".utf8)

        let namesSuffix = " /Names << /EmbeddedFiles << /Names [(\(nameASCII)) \(specNumber) 0 R] >> >>"

        var augmented = catalogDict
        augmented = PDFObjectScanner.augmentDictionary(augmented, appending: namesSuffix)
        let catalogObj = Data("\n\(newCatalogNumber) 0 obj\n\(augmented)\nendobj\n".utf8)

        var out = pdf
        var offsets: [(Int, Int)] = []
        func append(_ chunk: Data, number: Int) {
            offsets.append((number, out.count))
            out.append(chunk)
        }
        append(fileObj, number: fileNumber)
        append(specObj, number: specNumber)
        append(catalogObj, number: newCatalogNumber)

        let xrefOffset = out.count
        let byNumber = Dictionary(uniqueKeysWithValues: offsets.map { ($0.0, $0.1) })
        let firstNew = fileNumber
        let count = newCatalogNumber - firstNew + 1

        var xref = Data("xref\n\(firstNew) \(count)\n".utf8)
        for n in firstNew...newCatalogNumber {
            xref.append(Data(String(format: "%010d %05d n \n", byNumber[n] ?? 0, 0).utf8))
        }
        let trailer = """
        trailer
        << /Size \(newCatalogNumber + 1) /Root \(newCatalogNumber) 0 R /Prev \(root.xrefOffset) >>
        startxref
        \(xrefOffset)
        %%EOF

        """
        xref.append(Data(trailer.utf8))
        out.append(xref)
        return out
    }

    private func appendAsUnreferencedAttachment(_ attachment: Attachment,
                                                into pdf: Data,
                                                catalogDict: String,
                                                root: PDFObjectScanner.RootRef) throws -> Data {
        let maxNumber = max(PDFObjectScanner.maxObjectNumber(in: pdf), root.objectNumber)
        let fileNumber = maxNumber + 1

        var fileObj = Data("\n\(fileNumber) 0 obj\n<< /Type /EmbeddedFile /Subtype /\(attachment.mimeType) /Length \(attachment.data.count) >>\nstream\n".utf8)
        fileObj.append(attachment.data)
        fileObj.append(Data("\nendstream\nendobj\n".utf8))

        let xrefOffset = pdf.count + fileObj.count
        var out = pdf
        out.append(fileObj)

        var xref = Data("xref\n\(fileNumber) 1\n".utf8)
        xref.append(Data(String(format: "%010d %05d n \n", pdf.count, 0).utf8))
        xref.append(Data("""
        trailer
        << /Size \(fileNumber + 1) >>
        startxref
        \(xrefOffset)
        %%EOF

        """.utf8))
        out.append(xref)
        return out
    }
}
