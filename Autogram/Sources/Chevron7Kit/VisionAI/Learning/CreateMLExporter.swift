import Foundation
import CoreGraphics
import ImageIO

public struct CreateMLCoordinates: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct CreateMLBox: Codable, Equatable, Sendable {
    public var label: String
    public var coordinates: CreateMLCoordinates
    public init(label: String, coordinates: CreateMLCoordinates) { self.label = label; self.coordinates = coordinates }
}

public struct CreateMLImageAnnotation: Codable, Equatable, Sendable {
    public var image: String
    public var annotations: [CreateMLBox]
    public init(image: String, annotations: [CreateMLBox]) { self.image = image; self.annotations = annotations }
}

public struct CreateMLDocumentSplit: Codable, Equatable, Sendable {
    public var documentSHA256: String
    public var partition: String
    public var images: [String]
}

/// Writes complete page reviews to a fresh folder in Create ML object-detector format.
public enum CreateMLExporter {
    public static func export(bank: ExampleBank, to folder: URL) async throws -> URL {
        let datasetFolder = folder.appendingPathComponent("dataset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: datasetFolder, withIntermediateDirectories: true)
        try await bank.load()
        let pages = try await bank.reviewedPages()
        let pagesDirectory = await bank.pagesDirectory
        var sizes: [String: CGSize] = [:]
        for name in Set(pages.map(\.pageImageFileName)) {
            let source = pagesDirectory.appendingPathComponent(name)
            guard let size = imageSize(at: source) else { continue }
            sizes[name] = size
            try FileManager.default.copyItem(at: source, to: datasetFolder.appendingPathComponent(name))
        }
        let availablePages = pages.filter { sizes[$0.pageImageFileName] != nil }
        let annotations = self.annotations(for: availablePages, imageSizes: sizes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = datasetFolder.appendingPathComponent("annotations.json")
        try encoder.encode(annotations).write(to: url, options: .atomic)
        try encoder.encode(documentSplits(for: availablePages))
            .write(to: datasetFolder.appendingPathComponent("splits.json"), options: .atomic)
        return url
    }

    public static func annotations(for pages: [ReviewedBankPage], imageSizes: [String: CGSize]) -> [CreateMLImageAnnotation] {
        pages.sorted { $0.pageImageFileName < $1.pageImageFileName }.compactMap { page in
            let image = page.pageImageFileName
            guard let size = imageSizes[image] else { return nil }
            let boxes: [CreateMLBox] = page.boxes.compactMap { box in
                guard let kind = box.kind.visualKind else { return nil }
                let rect = PageCrop.pixelRect(for: box.box, imageWidth: Int(size.width), imageHeight: Int(size.height), margin: 0)
                return CreateMLBox(label: kind.trainingLabel,
                                   coordinates: .init(x: rect.midX, y: rect.midY, width: rect.width, height: rect.height))
            }
            return CreateMLImageAnnotation(image: image, annotations: boxes)
        }
    }

    public static func documentSplits(for pages: [ReviewedBankPage]) -> [CreateMLDocumentSplit] {
        let documents = Dictionary(grouping: pages, by: \.documentSHA256)
        return documents.keys.sorted().map { hash in
            // Hash only document identity: adding pages cannot leak a document across partitions.
            let digest = AttestationClauseGenerator.sha256Hex(of: Data(hash.utf8))
            let bucket = UInt64(digest.prefix(8), radix: 16)! % 10
            return CreateMLDocumentSplit(documentSHA256: hash,
                                          partition: bucket < 8 ? "train" : bucket == 8 ? "validation" : "test",
                                          images: documents[hash]!.map(\.pageImageFileName).sorted())
        }
    }

    public static func imageSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        return CGSize(width: w, height: h)
    }
}
