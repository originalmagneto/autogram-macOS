import Foundation

/// Keeps ZaKo output files next to the source document and makes every
/// generated artifact traceable to that source.
public enum ConversionOutputNaming {
    public static func pdfFileName(originalDocumentName: String,
                                   requestedDocumentName: String) -> String {
        let original = documentStem(originalDocumentName, fallback: "dokument")
        let requested = documentStem(requestedDocumentName, fallback: "")

        guard !requested.isEmpty else {
            return "\(original)-konvertovane.pdf"
        }

        if requested.caseInsensitiveCompare(original) == .orderedSame {
            return "\(original)-konvertovane.pdf"
        }
        if requested.range(of: original, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return "\(requested)-konvertovane.pdf"
        }
        return "\(original)-\(requested).pdf"
    }

    public static func xdcfFileName(originalDocumentName: String,
                                    pdfFileName: String,
                                    evidenceNumber: String?) -> String {
        let original = documentStem(originalDocumentName, fallback: "dokument")
        let pdfStem = documentStem(pdfFileName, fallback: original)
        let evidence = evidenceNumber.map(ASiCEPackager.sanitizedFileName) ?? ""
        if evidence.isEmpty {
            return "\(pdfStem)-dolozka.xml.xdcf"
        }
        return "\(pdfStem)-\(evidence).xml.xdcf"
    }

    public static func asicFileName(pdfFileName: String) -> String {
        "\(documentStem(pdfFileName, fallback: "konverzia")).asice"
    }

    public static func deliveryPDFFileName(in directory: URL,
                                           preferredName: String,
                                           fileManager: FileManager = .default) -> String {
        uniqueURL(in: directory, fileName: preferredName, fileManager: fileManager).lastPathComponent
    }

    public static func outputDirectory(sourceURL: URL?,
                                       fallback: URL,
                                       fileManager: FileManager = .default) -> URL {
        if let sourceURL {
            let directory = sourceURL.standardizedFileURL.deletingLastPathComponent()
            if fileManager.isWritableFile(atPath: directory.path) {
                return directory
            }
        }
        return fallback
    }

    public static func outputDirectory(sourceURL: URL?,
                                       preferredDirectory: URL?,
                                       fallback: URL,
                                       fileManager: FileManager = .default) -> URL {
        if let preferredDirectory,
           fileManager.isWritableFile(atPath: preferredDirectory.path) {
            return preferredDirectory
        }
        return outputDirectory(sourceURL: sourceURL, fallback: fallback, fileManager: fileManager)
    }

    public static func uniqueURL(in directory: URL,
                                 fileName: String,
                                 fileManager: FileManager = .default) -> URL {
        let base = documentStem(fileName, fallback: "konverzia")
        let ext = (fileName as NSString).pathExtension
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " (\(index))"
            let candidate = directory.appendingPathComponent("\(base)\(suffix)")
                .appendingPathExtension(ext.isEmpty ? "pdf" : ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func documentStem(_ name: String, fallback: String) -> String {
        var sanitized = ASiCEPackager.sanitizedFileName(name)
        if sanitized.isEmpty {
            sanitized = fallback
        }
        let pathExtension = (sanitized as NSString).pathExtension
        if !pathExtension.isEmpty {
            sanitized = (sanitized as NSString).deletingPathExtension
        }
        return sanitized.isEmpty ? fallback : sanitized
    }
}