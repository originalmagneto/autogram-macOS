// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Turns a review decision into a bank entry: crops the element, embeds it, and
/// persists everything. The stored page and crop images use `pageRenderWidth`
/// (training export); the feature vector uses `featureRenderWidth`, the width the
/// detector renders at, because a crop from a 1200 px render lies as far from the
/// same crop at 760 px as two different elements do.
public struct ExampleBankRecorder: Sendable {
    public let bank: ExampleBank
    public let featurePrints: any FeaturePrintProviding
    public let pageRenderWidth: Int
    public let featureRenderWidth: Int
    public let detectorVersion: String

    public init(bank: ExampleBank, featurePrints: any FeaturePrintProviding = VisionFeaturePrintProvider(),
                pageRenderWidth: Int = 1200,
                featureRenderWidth: Int = LayeredDetectionProvider.defaultRenderTargetWidth,
                detectorVersion: String) {
        self.bank = bank
        self.featurePrints = featurePrints
        self.pageRenderWidth = pageRenderWidth
        self.featureRenderWidth = featureRenderWidth
        self.detectorVersion = detectorVersion
    }

    public func record(document: PDFDocument, documentData: Data, element: SecurityElement, label: BankLabel) async throws {
        let documentHash = AttestationClauseGenerator.sha256Hex(of: documentData)
        try await bank.invalidateReviewedPage(documentSHA256: documentHash, pageIndex: element.pageIndex)
        guard element.hasScanRegion else {
            try await bank.remove(id: element.id)
            return
        }
        let canonicalLabel: BankLabel
        switch label {
        case .negative: canonicalLabel = .negative
        case .kind:
            guard let kind = element.trainingKind else {
                try await bank.remove(id: element.id)
                return
            }
            canonicalLabel = .kind(kind)
        }
        guard let page = document.page(at: element.pageIndex),
              let rendered = BuiltInVisionProvider.render(page: page, targetWidth: pageRenderWidth) else {
            throw RecorderError.renderFailed
        }
        let image = rendered.cgImage
        guard let crop = PageCrop.crop(image, to: element.boundingBox) else { throw RecorderError.cropFailed }
        guard let detectorRender = BuiltInVisionProvider.render(page: page, targetWidth: featureRenderWidth) else {
            throw RecorderError.renderFailed
        }
        guard let detectorCrop = PageCrop.crop(detectorRender.cgImage, to: element.boundingBox) else {
            throw RecorderError.cropFailed
        }
        let vector = try await featurePrints.featureVector(for: detectorCrop)
        let entry = BankEntry(id: element.id, label: canonicalLabel,
                              documentSHA256: documentHash,
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

    public func recordReviewedPage(document: PDFDocument, documentData: Data, pageIndex: Int,
                                   elements: [SecurityElement]) async throws {
        let documentHash = AttestationClauseGenerator.sha256Hex(of: documentData)
        try await bank.invalidateReviewedPage(documentSHA256: documentHash, pageIndex: pageIndex)
        guard elements.allSatisfy({ $0.pageIndex == pageIndex }) else { throw RecorderError.wrongPage }
        guard !elements.contains(where: { $0.reviewState == .pending }) else { throw RecorderError.pendingReview }
        guard !elements.contains(where: { $0.reviewState == .confirmed && $0.observation == .physicalOriginal }) else {
            throw RecorderError.unlocalizedPhysicalElement
        }
        var boxes: [ReviewedPageBox] = []
        for element in elements where element.reviewState == .confirmed && element.observation == .scanRegion {
            guard let kind = element.trainingKind else { throw RecorderError.unsupportedVisibleElement(element.kind) }
            let box = element.boundingBox
            guard [box.x, box.y, box.width, box.height].allSatisfy(\.isFinite),
                  box.x >= 0, box.y >= 0, box.width > 0, box.height > 0,
                  box.x + box.width <= 1, box.y + box.height <= 1 else { throw RecorderError.cropFailed }
            boxes.append(.init(kind: kind, box: box))
        }
        guard let page = document.page(at: pageIndex),
              let rendered = BuiltInVisionProvider.render(page: page, targetWidth: pageRenderWidth) else {
            throw RecorderError.renderFailed
        }
        let snapshot = ReviewedBankPage(documentSHA256: documentHash, pageIndex: pageIndex, boxes: boxes,
                                        reviewedAt: Date(), detectorVersion: detectorVersion)
        try Self.writePNG(rendered.cgImage, to: await bank.pagesDirectory.appendingPathComponent(snapshot.pageImageFileName))
        try await bank.saveReviewedPage(snapshot)
    }

    /// Writes to a sibling temporary file and swaps it in, so a concurrent writer
    /// of the same page image can never leave a truncated PNG behind.
    static func writePNG(_ image: CGImage, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).png-partial")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RecorderError.writeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            throw RecorderError.writeFailed
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                do {
                    try FileManager.default.moveItem(at: temporary, to: url)
                } catch {
                    // Another writer won the race between the check and the move.
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw RecorderError.writeFailed
        }
    }

    public enum RecorderError: LocalizedError {
        case renderFailed, cropFailed, writeFailed, wrongPage, pendingReview, unlocalizedPhysicalElement
        case unsupportedVisibleElement(SecurityElement.Kind)

        public var errorDescription: String? {
            switch self {
            case .renderFailed: return "Stranu sa nepodarilo vykresliť pre učenie."
            case .cropFailed: return "Oblasť prvku nie je platnou oblasťou skenu."
            case .writeFailed: return "Obrázok pre učenie sa nepodarilo uložiť."
            case .wrongPage: return "Kontrola obsahuje prvky z inej strany."
            case .pendingReview: return "Pred uložením strany pre učenie rozhodnite o všetkých prvkoch."
            case .unlocalizedPhysicalElement:
                return "Strana sa nedá použiť na učenie: prvok originálu nemá vyznačenú oblasť v skene."
            case .unsupportedVisibleElement(let kind):
                return "Strana sa nedá použiť na učenie: viditeľný prvok „\(kind.rawValue)“ nemá podporovanú obrazovú triedu."
            }
        }
    }
}
