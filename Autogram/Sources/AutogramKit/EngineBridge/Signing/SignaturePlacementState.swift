import AppKit
import PDFKit
import Foundation
import Observation

/// Stav grafického podpisu – port logiky WorkspaceModel z Autogram macOS 2.
@MainActor
@Observable
public final class SignaturePlacementState {
    @ObservationIgnored public private(set) var assets: [SignatureAsset] = []
    public private(set) var selectedAsset: SignatureAsset?
    public var isEnabled = false
    public var placement: VisibleSignaturePlacement?
    public private(set) var pageCount = 0
    public private(set) var cardContent: VisibleSignatureCardContent?
    public private(set) var cardPreview: NSImage?
    public private(set) weak var document: PDFDocument?

    public let assetStore: SignatureAssetStore

    public init(assetStore: SignatureAssetStore = SignatureAssetStore(),
                document: PDFDocument? = nil) {
        self.assetStore = assetStore
        self.document = document
        refreshAssets()
        restorePreferences()
        updateDocument(document)
    }

    // MARK: - Document

    public func updateDocument(_ document: PDFDocument?) {
        self.document = document
        pageCount = document?.pageCount ?? 0
        guard var current = placement, pageCount > 0 else { return }
        let clamped = min(max(current.pageIndex, 0), pageCount - 1)
        guard current.pageIndex != clamped else { return }
        current.pageIndex = clamped
        placement = current
    }

    public var pageIndices: [Int] { Array(0..<max(pageCount, 0)) }

    public func artworkURL(for asset: SignatureAsset) -> URL {
        assetStore.fileURL(for: asset)
    }

    // MARK: - Selection & editing

    public func importArtwork(from sourceURL: URL, pdfPageIndex: Int = 0) throws {
        let asset: SignatureAsset
        if sourceURL.pathExtension.lowercased() == "pdf" {
            asset = try assetStore.importPDF(sourceURL, pageIndex: pdfPageIndex)
        } else {
            asset = try assetStore.importPNG(sourceURL)
        }
        refreshAssets()
        select(asset)
    }

    public func select(_ asset: SignatureAsset) {
        guard assets.contains(where: { $0.id == asset.id }) else { return }
        selectedAsset = asset
        isEnabled = true
        placement = defaultPlacement()
        refreshPreview()
        persistPreferences()
    }

    public func delete(_ asset: SignatureAsset) throws {
        try assetStore.delete(asset)
        refreshAssets()
        guard selectedAsset?.id == asset.id else { return }
        clearComposition()
        persistPreferences()
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled, placement == nil {
            placement = defaultPlacement()
        }
        persistPreferences()
    }

    public func update(placement newValue: VisibleSignaturePlacement?) {
        placement = newValue
        persistPreferences()
    }

    public func selectPage(_ pageIndex: Int) {
        guard var current = placement, pageCount > 0 else { return }
        current.pageIndex = min(max(pageIndex, 0), pageCount - 1)
        update(placement: current)
    }

    public func resetRotation() {
        guard var current = placement else { return }
        current.rotationDegrees = 0
        update(placement: current)
    }

    /// Sets the signer, certificate, and timestamp content shown in the card.
    public func setContent(
        signerName: String,
        certificateName: String? = nil,
        qualification: String? = nil,
        timestampAuthorityName: String? = nil
    ) {
        cardContent = VisibleSignatureCardContent(
            signerName: signerName,
            certificateName: certificateName,
            certificateQualification: qualification,
            timestampAuthorityName: timestampAuthorityName)
        refreshPreview()
    }

    public func clearComposition() {
        isEnabled = false
        placement = nil
        cardContent = nil
        cardPreview = nil
    }

    // MARK: - Rendering

    public func defaultPlacement() -> VisibleSignaturePlacement? {
        guard pageCount > 0, let page = document?.page(at: pageCount - 1),
              let boundsCandidate = document?.page(at: 0) else { return nil }
        _ = boundsCandidate
        let cropBox = page.bounds(for: .cropBox)
        guard cropBox.width > 0, cropBox.height > 0 else { return nil }
        let scale = min(1, cropBox.width / 420, cropBox.height / 260, 0.55)
        let size = CGSize(width: 420 * scale, height: 260 * scale)
        return VisibleSignaturePlacement(
            pageIndex: pageCount - 1,
            pageRect: CGRect(x: (cropBox.width - size.width) / 2,
                             y: (cropBox.height - size.height) / 2,
                             width: size.width,
                             height: size.height),
            rotationDegrees: 0)
    }

    @discardableResult
    public func refreshPreview() -> Bool {
        guard let asset = selectedAsset else {
            cardContent = nil
            cardPreview = nil
            return false
        }
        if cardContent == nil {
            cardContent = VisibleSignatureCardContent(
                signerName: "Certificate details pending")
        }
        guard let content = cardContent,
              let previewURL = try? VisibleSignatureRenderer(assetStore: assetStore).render(
                asset: asset, content: content, signingTime: .now, rotationDegrees: 0, isPreview: true) else {
            cardPreview = nil
            return false
        }
        defer { try? FileManager.default.removeItem(at: previewURL) }
        cardPreview = NSImage(contentsOf: previewURL)
        return cardPreview != nil
    }

    // MARK: - Persistence

    public func refreshAssets() {
        assets = (try? assetStore.listAssets()) ?? []
    }

    func restorePreferences() {
        guard let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
              let preferences = try? JSONDecoder().decode(StoredPreferences.self, from: data) else { return }
        selectedAsset = preferences.assetID.flatMap { id in assets.first { $0.id == id } }
        isEnabled = false
        refreshPreview()
    }

    func persistPreferences() {
        let preferences = StoredPreferences(assetID: selectedAsset?.id)
        UserDefaults.standard.set(try? JSONEncoder().encode(preferences), forKey: Self.preferencesKey)
    }

    struct StoredPreferences: Codable {
        let assetID: UUID?
    }

    static let preferencesKey = "sk.autogram.macos.visibleSignature"
}
