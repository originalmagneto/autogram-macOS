import Foundation
import PDFKit
import SwiftUI
import AutogramKit

@MainActor
@Observable
final class SigningSessionStore {
    enum Step: Int, CaseIterable { case intake = 0, prepare = 1, done = 2 }

    var step: Step = .intake
    var sourceURL: URL?
    var sourceBookmark: Data?
    var document: PDFDocument?
    var analysis: DocumentAnalysis = .empty()
    var isAnalyzing = false

    var identities: [SigningIdentityInfo] = []
    var selectedIdentityID: String?

    var includeQualifiedTimestamp = true
    var includeVisibleSignature = false
    var selectedVisualAppearanceID = VisualSignatureAppearance.textID
    var convertToPDFA = false
    var outputFormat: SigningOutputFormat = .attachedASIC
    var signingPIN = ""
    var signaturePage: Int = 0
    var signatureRect = NormalizedRect(x: 0.58, y: 0.80, width: 0.30, height: 0.09)

    var isSigning = false
    var statusText = ""
    var result: SignedConversionResult?
    var outputDirectory: URL?
    var lastError: String?
    var existingSignatures: [DocumentSignatureInfo] = []
    var isInspectingSignatures = false
    var signedOutputURL: URL?
    var resultSignatures: [DocumentSignatureInfo] = []
    var signedPreviewDocument: PDFDocument?
    var pdfaPrepared = false
    var pdfaAfterSign = false

    /// Grafika zvolená v novej knižnici vizuálnych podpisov (Autogram macOS 2 štýl).
    var visualArtworkOverride: Data?
    var visualPlacement: VisibleSignaturePlacement?

    var queue: [SigningQueueItem] = []
    var selectedQueueID: UUID?

    struct SigningQueueItem: Identifiable, Hashable {
        enum Status: Hashable {
            case ready
            case signing
            case signed
            case failed
        }
        let id: UUID
        var url: URL
        var displayName: String
        var status: Status
        var signedOutputURL: URL?
        var errorMessage: String?

        init(id: UUID = UUID(), url: URL, displayName: String? = nil,
             status: Status = .ready, signedOutputURL: URL? = nil, errorMessage: String? = nil) {
            self.id = id
            self.url = url
            self.displayName = displayName ?? url.lastPathComponent
            self.status = status
            self.signedOutputURL = signedOutputURL
            self.errorMessage = errorMessage
        }
    }

    let signingProvider: any QualifiedSigningProviding
    let settingsStore: AppSettingsStore
    let stamper = VisibleSignatureStamper()

    var settings: AppSettings { settingsStore.settings }

    var selectedTSAURL: String {
        get { settingsStore.settings.selectedTSAURL }
        set {
            var next = settingsStore.settings
            next.selectedTSAURL = newValue
            settingsStore.settings = next
        }
    }

    var pdfaMode: PDFAConversionMode {
        get { settingsStore.settings.pdfaMode }
        set {
            var next = settingsStore.settings
            next.pdfaMode = newValue
            settingsStore.settings = next
        }
    }

    init(signingProvider: any QualifiedSigningProviding, settingsStore: AppSettingsStore) {
        self.signingProvider = signingProvider
        self.settingsStore = settingsStore
    }

    func loadDocument(at url: URL) async {
        await addDocuments(at: [url], selectLast: true)
    }

    func addDocuments(at urls: [URL], selectLast: Bool = true) async {
        lastError = nil
        var lastID: UUID?
        for url in urls {
            let standardized = url.standardizedFileURL
            if let existing = queue.first(where: { $0.url.standardizedFileURL == standardized }) {
                lastID = existing.id
                continue
            }
            let item = SigningQueueItem(url: url)
            queue.append(item)
            lastID = item.id
        }
        if selectLast, let lastID {
            await selectQueueItem(lastID)
        }
    }

    func selectQueueItem(_ id: UUID) async {
        guard let item = queue.first(where: { $0.id == id }) else { return }
        selectedQueueID = id
        lastError = item.errorMessage
        signedOutputURL = item.signedOutputURL
        signedPreviewDocument = item.signedOutputURL.flatMap { PDFDocument(url: $0) }
        resultSignatures = []
        let secured = item.url.startAccessingSecurityScopedResource()
        defer { if secured { item.url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: item.url) else {
            lastError = "Súbor sa nepodarilo otvoriť ako PDF."
            return
        }
        self.document = document
        self.sourceURL = item.url
        self.sourceBookmark = try? item.url.bookmarkData(options: .withSecurityScope,
                                                         includingResourceValuesForKeys: nil,
                                                         relativeTo: nil)
        if item.status == .signed, item.signedOutputURL != nil {
            step = .done
            if let signed = item.signedOutputURL {
                resultSignatures = await signingProvider.inspectSignatures(in: signed)
            }
            return
        }
        step = .prepare
        isAnalyzing = true
        let doc = UncheckedSendable(document)
        analysis = await Task.detached(priority: .userInitiated) {
            let engine = PDFAnalysisEngine()
            return engine.analyze(document: doc.value)
        }.value ?? .empty()
        signaturePage = max(analysis.totalPages - 1, 0)
        isAnalyzing = false
        await refreshIdentities()
        await inspectExistingSignatures()
    }

    func removeQueueItem(_ id: UUID) {
        queue.removeAll { $0.id == id }
        if selectedQueueID == id {
            selectedQueueID = queue.first?.id
            document = nil
            sourceURL = nil
            if queue.isEmpty {
                step = .intake
            }
        }
    }

    func inspectExistingSignatures() async {
        guard let sourceURL else {
            existingSignatures = []
            return
        }
        isInspectingSignatures = true
        existingSignatures = await signingProvider.inspectSignatures(in: sourceURL)
        isInspectingSignatures = false
    }

    private var isRefreshingIdentities = false
    private(set) var isResolvingCertificate = false
    var certificateLoadError: String?
    private var lastCertificateLoadPIN: String?

    var signingProviderIsDemo: Bool {
        signingProvider is DemoSigningProvider
    }

    var hasResolvedCertificate: Bool {
        signingProviderIsDemo || identities.contains {
            $0.id.hasPrefix(EngineBridgeSigningProvider.certificateIdentityPrefix)
        }
    }

    /// Certifikát musí byť známy pred vykreslením grafického podpisu.
    func resolveCertificateForPreview(force: Bool = false) async {
        guard !signingProviderIsDemo, !signingPIN.isEmpty, !isResolvingCertificate else { return }
        guard force || !hasResolvedCertificate else { return }
        guard force || lastCertificateLoadPIN != signingPIN else { return }

        isResolvingCertificate = true
        lastCertificateLoadPIN = signingPIN
        defer { isResolvingCertificate = false }

        if let resolved = await signingProvider.resolveIdentities(pin: signingPIN), !resolved.isEmpty {
            identities = resolved
            selectedIdentityID = resolved.first(where: { $0.isMandateCertificate })?.id
                ?? resolved.first?.id
            certificateLoadError = nil
        } else {
            certificateLoadError = (signingProvider as? EngineBridgeSigningProvider)?.lastResolveError
                ?? "Načítanie certifikátu zlyhalo."
        }
    }

    func refreshIdentities() async {
        guard !isSigning, !isRefreshingIdentities else { return }
        isRefreshingIdentities = true
        defer { isRefreshingIdentities = false }
        identities = await signingProvider.availableIdentities()
        // Karta vybratá → vynúť nové overenie PIN (každá karta má iný PIN).
        if identities.isEmpty {
            if !signingPIN.isEmpty { signingPIN = "" }
            certificateLoadError = nil
            lastCertificateLoadPIN = nil
            selectedIdentityID = nil
            return
        }
        if selectedIdentityID == nil || !identities.contains(where: { $0.id == selectedIdentityID }) {
            selectedIdentityID = identities.first(where: { $0.isMandateCertificate })?.id
                ?? identities.first?.id
        }
    }

    var canSign: Bool {
        document != nil && selectedIdentityID != nil && !isSigning
    }

    func sign() async {
        guard let document else { return }
        lastError = nil
        isSigning = true
        statusText = includeVisibleSignature ? "Pripravujem vizuálny podpis…" : "Podpisujem…"

        do {
            if includeVisibleSignature, !signingProviderIsDemo, !hasResolvedCertificate {
                statusText = "Načítavam certifikát pre vizuálny podpis…"
                await resolveCertificateForPreview(force: true)
                guard hasResolvedCertificate else {
                    throw SigningError.signingFailed(
                        certificateLoadError ?? "Pred vizuálnym podpisom sa nepodarilo načítať certifikát.")
                }
            }
            // Pôvodné bajty súboru (ako v originálnom Autograme) — PDFKit rewrite až keď je nutný.
            var pdfData: Data
            if let sourceURL, let original = try? Data(contentsOf: sourceURL), !original.isEmpty {
                pdfData = original
            } else {
                let doc = UncheckedSendable(document)
                pdfData = try await Task.detached(priority: .userInitiated) {
                    doc.value.dataRepresentation()
                }.get() ?? Data()
            }
            let originalPdfData = pdfData
            pdfaPrepared = false
            pdfaAfterSign = false

            if convertToPDFA, !pdfData.isEmpty {
                statusText = "Konvertujem do PDF/A…"
                let title = sourceURL?.deletingPathExtension().lastPathComponent ?? ""
                // PAdES DSS rozbije vektorový incremental PDF/A — raster je jediný spoľahlivý vstup.
                let mode: PDFAConversionMode = outputFormat == .embeddedPAdES
                    ? .rasterGuaranteed
                    : pdfaMode
                pdfData = try PDFAConverter().convert(document: document, mode: mode, title: title)
                var pdfaCheck = PDFAValidator().validate(pdfData)
                if !pdfaCheck.isValid {
                    pdfData = try PDFAConverter().convert(document: document, mode: .rasterGuaranteed, title: title)
                    pdfaCheck = PDFAValidator().validate(pdfData)
                }
                guard pdfaCheck.isValid else {
                    throw SigningError.signingFailed(
                        "Konverzia do PDF/A zlyhala: \(pdfaCheck.issues.joined(separator: "; ")).")
                }
                pdfaPrepared = true
                statusText = "PDF/A je pripravené, podpisujem…"
            }

            if includeVisibleSignature, !pdfData.isEmpty, outputFormat == .attachedASIC {
                statusText = "Vkladám vizuálny podpis…"
                let imageData = visualArtworkOverride
                    ?? VisualSignatureStore.imageData(for: selectedVisualAppearanceID)
                let stamp = VisibleSignatureStamper.StampData(
                    fullName: displayName(),
                    timestamp: Date(),
                    pageIndex: min(signaturePage, analysis.totalPages - 1),
                    normalizedRect: signatureRect,
                    imagePNG: imageData)
                let includeStamp = includeQualifiedTimestamp
                if let stampedSource = PDFDocument(data: pdfData) {
                    let stampedDoc = UncheckedSendable(stampedSource)
                    let stampedData = await Task.detached(priority: .userInitiated) { [stamper, stampedDoc] in
                        stamper.stamp(document: stampedDoc.value,
                                      stamp: stamp,
                                      includeTimestamp: includeStamp)
                    }.value
                    if let finalData = stampedData {
                        pdfData = finalData
                    }
                }
            }

            statusText = "Podpisujem kvalifikovaným podpisom…"
            guard let identityID = selectedIdentityID else {
                throw SigningError.identityUnavailable
            }
            let pdfName = sourceURL?.lastPathComponent ?? "dokument.pdf"
            let artworkPNG = visualArtworkOverride ?? VisualSignatureStore.imageData(for: selectedVisualAppearanceID)
            let visualStamp: VisualStampSpec?
            if includeVisibleSignature, outputFormat == .embeddedPAdES {
                visualStamp = VisualStampSpec(
                    fullName: displayName(),
                    timestamp: Date(),
                    pageIndex: visualPlacement?.pageIndex ?? min(signaturePage, analysis.totalPages - 1),
                    normalizedRect: signatureRect,
                    imagePNG: artworkPNG,
                    // Po PDF/A rasteri sú iné rozmery strany — vždy mapovať z normalizovaného rectu na aktuálne PDF.
                    pdfPageRect: convertToPDFA ? nil : visualPlacement?.pageRect,
                    rotationDegrees: visualPlacement?.rotationDegrees ?? 0,
                    qualification: identities.first(where: { $0.id == identityID })?.isQualified == true
                        ? "Kvalifikovaný elektronický podpis" : nil)
            } else {
                visualStamp = nil
            }
            func makeRequest(with data: Data) -> SigningRequest {
                SigningRequest(pdfData: data,
                               identityID: identityID,
                               includeTimestamp: includeQualifiedTimestamp,
                               tsaURL: includeQualifiedTimestamp ? selectedTSAURL : nil,
                               outputFormat: outputFormat,
                               pin: signingPIN.isEmpty ? nil : signingPIN,
                               extraFiles: [ASiCEPackager.Entry(path: pdfName, data: data)],
                               visualStamp: visualStamp)
            }
            let signed: SignedConversionResult
            do {
                signed = try await signingProvider.sign(makeRequest(with: pdfData))
            } catch {
                let text = error.localizedDescription
                if convertToPDFA, pdfaPrepared,
                   text.contains("SIGNING_UNAVAILABLE") || text.contains("SIGNING_FAILED") {
                    statusText = "PDF/A sa nepodarilo podpísať, skúšam pôvodný dokument…"
                    pdfaPrepared = false
                    signed = try await signingProvider.sign(makeRequest(with: originalPdfData))
                } else {
                    throw error
                }
            }

            statusText = "Ukladám…"
            let (directory, stem) = resolveOutputLocation()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if outputFormat == .embeddedPAdES {
                try signed.pdfData.write(to: directory.appendingPathComponent("\(stem).pdf"),
                                         options: [.atomic])
            }
            if let asic = signed.asicData {
                try asic.write(to: directory.appendingPathComponent("\(stem).asice"),
                               options: [.atomic])
            }
            outputDirectory = directory
            if outputFormat == .embeddedPAdES {
                signedOutputURL = directory.appendingPathComponent("\(stem).pdf")
            } else if signed.asicData != nil {
                signedOutputURL = directory.appendingPathComponent("\(stem).asice")
            } else {
                signedOutputURL = directory.appendingPathComponent("\(stem).pdf")
            }
            if let index = queue.firstIndex(where: { $0.id == selectedQueueID }) {
                queue[index].status = .signed
                queue[index].signedOutputURL = signedOutputURL
                queue[index].errorMessage = nil
            }
            if let signedURL = signedOutputURL {
                signedPreviewDocument = PDFDocument(url: signedURL)
                resultSignatures = await signingProvider.inspectSignatures(in: signedURL)
                pdfaAfterSign = PDFAValidator().validate(signed.pdfData).isValid
                    || (signed.asicData != nil && pdfaPrepared)
            }

            result = signed
            statusText = ""
            step = .done
        } catch {
            lastError = error.localizedDescription
            statusText = ""
            if let index = queue.firstIndex(where: { $0.id == selectedQueueID }) {
                queue[index].status = .failed
                queue[index].errorMessage = error.localizedDescription
            }
        }
        isSigning = false
    }

    var unsignedQueueItems: [SigningQueueItem] {
        queue.filter { $0.status == .ready || $0.status == .failed }
    }

    func signAllUnsigned() async {
        let ids = unsignedQueueItems.map(\.id)
        for id in ids {
            await selectQueueItem(id)
            if let index = queue.firstIndex(where: { $0.id == id }) {
                queue[index].status = .signing
            }
            await sign()
            if queue.first(where: { $0.id == id })?.status != .signed {
                break
            }
        }
    }

    var stampDisplayName: String {
        displayName()
    }

    private func displayName() -> String {
        if let identity = identities.first(where: { $0.id == selectedIdentityID }),
           identity.label != "DEMO podpis (vývojový režim)" {
            return identity.label
        }
        return "Elektronický podpis Autogram"
    }

    func addCustomTSA(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = settingsStore.settings
        if !next.customTSAServers.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            next.customTSAServers.append(trimmed)
        }
        next.selectedTSAURL = trimmed
        settingsStore.settings = next
    }

    func reset(keepingIdentity: Bool = true) {
        let identity = keepingIdentity ? selectedIdentityID : nil
        step = queue.isEmpty ? .intake : .prepare
        sourceURL = nil
        sourceBookmark = nil
        document = nil
        analysis = .empty()
        result = nil
        outputDirectory = nil
        lastError = nil
        isAnalyzing = false
        visualArtworkOverride = nil
        visualPlacement = nil
        existingSignatures = []
        resultSignatures = []
        signedOutputURL = nil
        signedPreviewDocument = nil
        pdfaPrepared = false
        pdfaAfterSign = false
        certificateLoadError = nil
        lastCertificateLoadPIN = nil
        selectedIdentityID = identity
    }

    func resolveOutputLocation() -> (directory: URL, stem: String) {
        let fallback = Self.outputDirectoryURL()
        let originalName = sourceURL?.deletingPathExtension().lastPathComponent ?? "dokument"
        let stem = "\(originalName)_podpisane"
        if let scoped = resolvedSourceURL() {
            let directory = scoped.deletingLastPathComponent()
            if FileManager.default.isWritableFile(atPath: directory.path) {
                return (directory, stem)
            }
        }
        return (fallback, stem)
    }

    private func resolvedSourceURL() -> URL? {
        if let bookmark = sourceBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        return sourceURL
    }

    static func outputDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Autogram/Output", isDirectory: true)
    }
}
