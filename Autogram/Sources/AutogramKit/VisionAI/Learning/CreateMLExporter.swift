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

/// Writes the bank in the Create ML object-detector folder format:
/// <folder>/annotations.json plus one PNG per page.
public enum CreateMLExporter {
    public static func export(bank: ExampleBank, to folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await bank.load()
        let entries = await bank.entries()
        let pagesDirectory = await bank.pagesDirectory
        var sizes: [String: CGSize] = [:]
        for name in Set(entries.map(\.pageImageFileName)) {
            let source = pagesDirectory.appendingPathComponent(name)
            guard let size = imageSize(at: source) else { continue }
            sizes[name] = size
            let destination = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
        let annotations = self.annotations(for: entries, imageSizes: sizes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = folder.appendingPathComponent("annotations.json")
        try encoder.encode(annotations).write(to: url, options: .atomic)
        return url
    }

    public static func annotations(for entries: [BankEntry], imageSizes: [String: CGSize]) -> [CreateMLImageAnnotation] {
        let grouped = Dictionary(grouping: entries, by: \.pageImageFileName)
        return grouped.keys.sorted().compactMap { image in
            guard let size = imageSizes[image], let group = grouped[image] else { return nil }
            let boxes: [CreateMLBox] = group.compactMap { entry in
                guard case .kind = entry.label else { return nil }
                let rect = PageCrop.pixelRect(for: entry.box, imageWidth: Int(size.width), imageHeight: Int(size.height), margin: 0)
                return CreateMLBox(label: entry.label.exportLabel,
                                   coordinates: .init(x: rect.midX, y: rect.midY, width: rect.width, height: rect.height))
            }
            return CreateMLImageAnnotation(image: image, annotations: boxes)
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
