import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Turns a review decision into a bank entry: renders the page once,
/// crops the element, embeds it, and persists everything.
public struct ExampleBankRecorder: Sendable {
    public let bank: ExampleBank
    public let featurePrints: any FeaturePrintProviding
    public let pageRenderWidth: Int
    public let detectorVersion: String

    public init(bank: ExampleBank, featurePrints: any FeaturePrintProviding = VisionFeaturePrintProvider(),
                pageRenderWidth: Int = 1200, detectorVersion: String) {
        self.bank = bank
        self.featurePrints = featurePrints
        self.pageRenderWidth = pageRenderWidth
        self.detectorVersion = detectorVersion
    }

    public func record(document: PDFDocument, documentData: Data, element: SecurityElement, label: BankLabel) async throws {
        guard let page = document.page(at: element.pageIndex),
              let rendered = BuiltInVisionProvider.render(page: page, targetWidth: pageRenderWidth) else {
            throw RecorderError.renderFailed
        }
        let image = rendered.cgImage
        guard let crop = PageCrop.crop(image, to: element.boundingBox) else { throw RecorderError.cropFailed }
        let vector = try await featurePrints.featureVector(for: crop)
        let entry = BankEntry(id: element.id, label: label,
                              documentSHA256: AttestationClauseGenerator.sha256Hex(of: documentData),
                              pageIndex: element.pageIndex, box: element.boundingBox,
                              featureVector: vector, detectorVersion: detectorVersion)
        try await bank.load()
        let pageURL = await bank.pagesDirectory.appendingPathComponent(entry.pageImageFileName)
        if !FileManager.default.fileExists(atPath: pageURL.path) {
            try Self.writePNG(image, to: pageURL)
        }
        try Self.writePNG(crop, to: await bank.cropsDirectory.appendingPathComponent(entry.cropImageFileName))
        try await bank.add(entry)
    }

    public func forget(elementID: UUID) async throws {
        try await bank.remove(id: elementID)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RecorderError.writeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RecorderError.writeFailed }
    }

    public enum RecorderError: Error { case renderFailed, cropFailed, writeFailed }
}
