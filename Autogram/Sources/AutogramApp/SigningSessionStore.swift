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
    var signingPIN = "" {
        didSet {
            guard oldValue != signingPIN, batchPhase == .ready else { return }
            batchSettingsSnapshot = nil
            batchPIN = nil
            batchPhase = .idle
            lastError = "PIN sa zmenil. Dávku znova skontrolujte pred spustením."
        }
    }
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

    var batchPhase: BatchPhase = .idle
    var batchItems: [BatchItem] = []
    var batchCompletedCount = 0
    var batchFailedCount = 0
    var batchCurrentIndex: Int?
    var batchErrorDecisionRequest: BatchFailureDecisionRequest?
    private(set) var batchSettingsSnapshot: BatchSettingsSnapshot?
    private var batchPIN: String?
    private var batchGeneration = UUID()
    private var batchDecisionContinuation: CheckedContinuation<BatchFailureDecision, Never>?

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
    enum BatchPhase: Equatable {
        case idle
        case preflighting
        case ready
        case signing
        case completed
        case cancelled
    }

    enum BatchFailureDecision {
        case continueBatch
        case stopBatch
    }

    enum BatchItemState: Equatable {
        case pending
        case signing
        case signed
        case failed
        case skipped
        case cancelled
    }

    struct BatchItem: Identifiable, Hashable {
        let id: UUID
        let displayName: String
        let url: URL
        var state: BatchItemState
        var errorMessage: String?
        var outputURL: URL?
        var plannedOutputURL: URL?
        var inputSignatureState: InputSignatureInspectionResult.State?
        var inputSignatureDetail: String?

        init(
            id: UUID,
            displayName: String,
            url: URL,
            state: BatchItemState = .pending,
            errorMessage: String? = nil,
            outputURL: URL? = nil,
            plannedOutputURL: URL? = nil,
            inputSignatureState: InputSignatureInspectionResult.State? = nil,
            inputSignatureDetail: String? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.url = url
            self.state = state
            self.errorMessage = errorMessage
            self.outputURL = outputURL
            self.plannedOutputURL = plannedOutputURL
            self.inputSignatureState = inputSignatureState
            self.inputSignatureDetail = inputSignatureDetail
        }

        var plannedOutputLabel: String? {
            plannedOutputURL?.lastPathComponent
        }
    }

    struct BatchFailureDecisionRequest: Identifiable, Equatable {
        let itemID: UUID
        let displayName: String
        let errorMessage: String

        var id: UUID { itemID }
    }

    struct BatchSettingsSnapshot: Sendable, Equatable {
        let outputFormat: SigningOutputFormat
        let includeQualifiedTimestamp: Bool
        let tsaURL: String?
        let convertToPDFA: Bool
        let pdfaMode: PDFAConversionMode
        let selectedIdentityID: String
        let identityLabel: String
        let identityIsQualified: Bool
        let includeVisibleSignature: Bool
        let selectedVisualAppearanceID: String
        let visualArtworkOverride: Data?
        let visualPlacement: VisibleSignaturePlacement?
        let signaturePage: Int
        let signatureRect: NormalizedRect
    }

    let signingProvider: any QualifiedSigningProviding
    let settingsStore: AppSettingsStore
    let recentDocumentStore: RecentDocumentStore
    let outputService = OutputService()
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

    init(
        signingProvider: any QualifiedSigningProviding,
        settingsStore: AppSettingsStore,
        recentDocumentStore: RecentDocumentStore
    ) {
        self.signingProvider = signingProvider
        self.settingsStore = settingsStore
        self.recentDocumentStore = recentDocumentStore
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
            recentDocumentStore.record(url: url)
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
        signedPreviewDocument = item.signedOutputURL.flatMap { previewDocument(for: $0) }
        resultSignatures = []
        let secured = item.url.startAccessingSecurityScopedResource()
        defer { if secured { item.url.stopAccessingSecurityScopedResource() } }
        guard let document = previewDocument(for: item.url) else {
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
        guard batchPhase != .preflighting, batchPhase != .ready, batchPhase != .signing else { return }
        queue.removeAll { $0.id == id }
        if selectedQueueID == id {
            selectedQueueID = nil
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
            // Pôvodné bajty súboru (ako v originálnom Autograme): PDFKit rewrite až keď je nutný.
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
            var visualStampWasPreapplied = false
            if convertToPDFA, includeVisibleSignature, outputFormat == .attachedASIC {
                let imageData = visualArtworkOverride
                    ?? VisualSignatureStore.imageData(for: selectedVisualAppearanceID)
                let stamp = VisibleSignatureStamper.StampData(
                    fullName: displayName(),
                    timestamp: Date(),
                    pageIndex: min(signaturePage, analysis.totalPages - 1),
                    normalizedRect: signatureRect,
                    imagePNG: imageData,
                    certificateName: identities.first(where: { $0.id == selectedIdentityID })?.label,
                    certificateQualification: identities.first(where: { $0.id == selectedIdentityID })?.isQualified == true
                        ? "Kvalifikovaný elektronický podpis" : nil,
                    timestampAuthorityName: includeQualifiedTimestamp ? settings.activeTSA.name : nil)
                let stampedData = await Self.stampPDFData(
                    pdfData,
                    stamp: stamp,
                    includeTimestamp: includeQualifiedTimestamp,
                    stamper: stamper,
                    flattenAnnotations: true)
                visualStampWasPreapplied = stampedData != pdfData
                pdfData = stampedData
            }


            if convertToPDFA, !pdfData.isEmpty {
                statusText = "Konvertujem do PDF/A…"
                let title = sourceURL?.deletingPathExtension().lastPathComponent ?? ""
                // PAdES DSS rozbije vektorový incremental PDF/A: raster je jediný spoľahlivý vstup.
                let mode: PDFAConversionMode =
                    outputFormat == .embeddedPAdES || visualStampWasPreapplied
                    ? .rasterGuaranteed
                    : pdfaMode
                let pdfaDocument = PDFDocument(data: pdfData) ?? document
                pdfData = try PDFAConverter().convert(document: pdfaDocument, mode: mode, title: title)
                var pdfaCheck = PDFAValidator().validate(pdfData)
                if !pdfaCheck.isValid {
                    pdfData = try PDFAConverter().convert(
                        document: PDFDocument(data: pdfData) ?? pdfaDocument,
                        mode: .rasterGuaranteed,
                        title: title)
                    pdfaCheck = PDFAValidator().validate(pdfData)
                }
                guard pdfaCheck.isValid else {
                    throw SigningError.signingFailed(
                        "Konverzia do PDF/A zlyhala: \(pdfaCheck.issues.joined(separator: "; ")).")
                }
                pdfaPrepared = true
                statusText = "PDF/A je pripravené, podpisujem…"
            }
            if !convertToPDFA, includeVisibleSignature, outputFormat == .attachedASIC {
                let imageData = visualArtworkOverride
                    ?? VisualSignatureStore.imageData(for: selectedVisualAppearanceID)
                let stamp = VisibleSignatureStamper.StampData(
                    fullName: displayName(),
                    timestamp: Date(),
                    pageIndex: min(signaturePage, analysis.totalPages - 1),
                    normalizedRect: signatureRect,
                    imagePNG: imageData,
                    certificateName: identities.first(where: { $0.id == selectedIdentityID })?.label,
                    certificateQualification: identities.first(where: { $0.id == selectedIdentityID })?.isQualified == true
                        ? "Kvalifikovaný elektronický podpis" : nil,
                    timestampAuthorityName: includeQualifiedTimestamp ? settings.activeTSA.name : nil)
                pdfData = await Self.stampPDFData(
                    pdfData,
                    stamp: stamp,
                    includeTimestamp: includeQualifiedTimestamp,
                    stamper: stamper,
                    flattenAnnotations: true)
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
                    // Po PDF/A rasteri sú iné rozmery strany: vždy mapovať z normalizovaného rectu na aktuálne PDF.
                    pdfPageRect: convertToPDFA ? nil : visualPlacement?.pageRect,
                    rotationDegrees: visualPlacement?.rotationDegrees ?? 0,
                    qualification: identities.first(where: { $0.id == identityID })?.isQualified == true
                        ? "Kvalifikovaný elektronický podpis" : nil,
                    certificateName: identities.first(where: { $0.id == identityID })?.label,
                    timestampAuthorityName: includeQualifiedTimestamp ? settings.activeTSA.name : nil)
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
                signedPreviewDocument = PDFDocument(data: signed.pdfData)
                    ?? previewDocument(for: signedURL)
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

    func prepareBatch(ids: [UUID]) async {
        guard batchPhase != .preflighting, batchPhase != .signing else { return }
        invalidateBatchWork()
        let generation = batchGeneration
        batchPhase = .preflighting
        batchItems = []
        batchCompletedCount = 0
        batchFailedCount = 0
        batchCurrentIndex = nil
        batchErrorDecisionRequest = nil
        batchSettingsSnapshot = nil
        batchPIN = nil
        lastError = nil

        var seenURLs = Set<URL>()
        var selectedItems: [SigningQueueItem] = []
        var inputErrors: [String] = []
        for id in ids {
            guard let item = queue.first(where: { $0.id == id }) else {
                inputErrors.append("Dokument s identifikátorom \(id.uuidString) sa nenachádza vo fronte.")
                continue
            }
            guard item.status == .ready || item.status == .failed else {
                inputErrors.append("Dokument \(item.displayName) nie je pripravený na podpis.")
                continue
            }
            let standardizedURL = item.url.standardizedFileURL
            guard seenURLs.insert(standardizedURL).inserted else { continue }
            selectedItems.append(item)
        }

        guard !selectedItems.isEmpty, inputErrors.isEmpty else {
            if selectedItems.isEmpty, inputErrors.isEmpty {
                inputErrors.append("Na podpisovanie nebol vybraný žiadny dokument.")
            }
            batchItems = selectedItems.map {
                BatchItem(id: $0.id, displayName: $0.displayName, url: $0.url,
                          state: .failed, errorMessage: inputErrors.first)
            }
            batchFailedCount = batchItems.count
            batchPhase = .idle
            lastError = inputErrors.joined(separator: " ")
            return
        }

        batchItems = selectedItems.map {
            BatchItem(id: $0.id, displayName: $0.displayName, url: $0.url)
        }

        var blockingErrors: [String] = inputErrors
        guard batchGeneration == generation else { return }
        var documents: [UUID: PDFDocument] = [:]
        for item in selectedItems {
            let secured = item.url.startAccessingSecurityScopedResource()
            defer { if secured { item.url.stopAccessingSecurityScopedResource() } }
            guard item.url.isFileURL,
                  FileManager.default.isReadableFile(atPath: item.url.path),
                  let document = PDFDocument(url: item.url),
                  document.pageCount > 0 else {
                let message = "Dokument \(item.displayName) sa nepodarilo načítať ako PDF."
                if let batchIndex = batchItems.firstIndex(where: { $0.id == item.id }) {
                    batchItems[batchIndex].state = .failed
                    batchItems[batchIndex].errorMessage = message
                }
                continue
            }
            documents[item.id] = document
        }

        if documents.isEmpty {
            let messages = batchItems.compactMap(\.errorMessage)
            batchFailedCount = batchItems.count
            batchPhase = .idle
            lastError = messages.joined(separator: " ")
            return
        }

        let discovered = await signingProvider.availableIdentities()
        guard batchGeneration == generation else { return }
        identities = discovered
        if selectedIdentityID == nil {
            selectedIdentityID = discovered.first(where: { $0.isMandateCertificate })?.id
                ?? discovered.first?.id
        }
        guard batchGeneration == generation else { return }
        guard let discoveredIdentityID = selectedIdentityID,
              var identity = discovered.first(where: { $0.id == discoveredIdentityID }) else {
            blockingErrors.append("Nie je dostupný podpisový certifikát.")
            finishBatchPreflight(blockingErrors: blockingErrors)
            return
        }
        guard identity.hasPrivateKey else {
            blockingErrors.append("Vybraný certifikát nemá dostupný súkromný kľúč.")
            finishBatchPreflight(blockingErrors: blockingErrors)
            return
        }

        for item in selectedItems {
            guard documents[item.id] != nil else { continue }
            let secured = item.url.startAccessingSecurityScopedResource()
            defer { if secured { item.url.stopAccessingSecurityScopedResource() } }
            let inspection = await signingProvider.inspectInputSignatures(in: item.url)
            guard batchGeneration == generation else { return }
            guard let batchIndex = batchItems.firstIndex(where: { $0.id == item.id }) else {
                continue
            }
            batchItems[batchIndex].inputSignatureState = inspection.state
            batchItems[batchIndex].inputSignatureDetail = inspection.detail
            guard inspection.state == .valid else {
                batchItems[batchIndex].state = .failed
                batchItems[batchIndex].errorMessage = inspection.detail
                continue
            }
        }

        let pin = signingPIN
        let requiresCertificateResolution = identity.requiresPIN
            || discoveredIdentityID.hasPrefix(EngineBridgeSigningProvider.syntheticIdentityIDPrefix)
        guard !identity.requiresPIN || !pin.isEmpty else {
            blockingErrors.append("Pre vybraný certifikát je potrebný PIN.")
            finishBatchPreflight(blockingErrors: blockingErrors)
            return
        }
        if requiresCertificateResolution {
            let resolved = await signingProvider.resolveIdentities(pin: pin)
            guard batchGeneration == generation else { return }
            if let resolved, !resolved.isEmpty {
                identities = resolved
                if let matching = resolved.first(where: { $0.id == discoveredIdentityID }) {
                    identity = matching
                } else if discoveredIdentityID.hasPrefix(
                    EngineBridgeSigningProvider.syntheticIdentityIDPrefix) {
                    guard let authoritative = resolved.first(where: { $0.isMandateCertificate })
                        ?? resolved.first else {
                        blockingErrors.append("Po overení PIN nie je dostupný podpisový certifikát.")
                        finishBatchPreflight(blockingErrors: blockingErrors)
                        return
                    }
                    identity = authoritative
                    selectedIdentityID = authoritative.id
                } else {
                    blockingErrors.append("Vybraný certifikát sa po overení PIN nedal nájsť.")
                    finishBatchPreflight(blockingErrors: blockingErrors)
                    return
                }
            } else {
                identities = []
                blockingErrors.append("Po overení PIN nie je dostupný podpisový certifikát.")
            }
        }

        let identityID = identity.id
        let effectiveVisualPage = visualPlacement?.pageIndex ?? signaturePage
        let snapshot = BatchSettingsSnapshot(
            outputFormat: outputFormat,
            includeQualifiedTimestamp: includeQualifiedTimestamp,
            tsaURL: includeQualifiedTimestamp ? selectedTSAURL : nil,
            convertToPDFA: convertToPDFA,
            pdfaMode: pdfaMode,
            selectedIdentityID: identityID,
            identityLabel: identity.label,
            identityIsQualified: identity.isQualified,
            includeVisibleSignature: includeVisibleSignature,
            selectedVisualAppearanceID: selectedVisualAppearanceID,
            visualArtworkOverride: visualArtworkOverride,
            visualPlacement: visualPlacement,
            signaturePage: effectiveVisualPage,
            signatureRect: signatureRect)

        if snapshot.includeQualifiedTimestamp,
           snapshot.tsaURL.flatMap({ URL(string: $0)?.scheme }) == nil {
            blockingErrors.append("Adresa služby časovej pečiatky nie je platná.")
        }

        if snapshot.includeVisibleSignature {
            if let placementError = Self.validateBatchVisualPlacement(
                placement: snapshot.visualPlacement,
                normalizedRect: snapshot.signatureRect,
                pageCount: nil) {
                blockingErrors.append(placementError)
            } else if let placement = snapshot.visualPlacement {
                for item in selectedItems {
                    guard let document = documents[item.id] else { continue }
                    guard let placementError = Self.validateBatchVisualPlacement(
                        placement: placement,
                        normalizedRect: snapshot.signatureRect,
                        pageCount: document.pageCount,
                        pageBounds: document.page(at: placement.pageIndex)?.bounds(for: .cropBox)) else {
                        continue
                    }
                    guard let batchIndex = batchItems.firstIndex(where: { $0.id == item.id }) else {
                        continue
                    }
                    batchItems[batchIndex].state = .failed
                    batchItems[batchIndex].errorMessage = placementError
                }
            }
            if !signingProviderIsDemo && snapshot.selectedIdentityID.isEmpty {
                blockingErrors.append("Certifikát pre vizuálny podpis nie je dostupný.")
            }
        }

        var plannedURLs = Set<URL>()
        let outputExtension = snapshot.outputFormat == .embeddedPAdES ? "pdf" : "asice"
        for item in selectedItems {
            guard documents[item.id] != nil else { continue }
            guard let batchIndex = batchItems.firstIndex(where: { $0.id == item.id }) else {
                continue
            }
            let location = outputLocation(for: item.url)
            do {
                let planned = try outputService.previewUniqueSibling(
                    for: item.url,
                    in: location.directory,
                    stemSuffix: "_podpisane",
                    outputExtension: outputExtension,
                    occupiedURLs: plannedURLs)
                batchItems[batchIndex].plannedOutputURL = planned
                plannedURLs.insert(planned.standardizedFileURL)
            } catch {
                batchItems[batchIndex].state = .failed
                batchItems[batchIndex].errorMessage = "Cieľový výstup sa nepodarilo pripraviť."
            }
        }

        guard blockingErrors.isEmpty else {
            finishBatchPreflight(blockingErrors: blockingErrors)
            return
        }

        batchSettingsSnapshot = snapshot
        batchPIN = pin.isEmpty ? nil : pin
        batchPhase = .ready
        }
    private func finishBatchPreflight(blockingErrors: [String]) {
        guard !blockingErrors.isEmpty else {
            batchPhase = .ready
            return
        }
        let message = blockingErrors.joined(separator: " ")
        for index in batchItems.indices {
            batchItems[index].state = .failed
            batchItems[index].errorMessage = message
        }
        batchFailedCount = batchItems.count
        batchPhase = .idle
        lastError = message
        batchSettingsSnapshot = nil
        batchPIN = nil
    }

    func startBatch() async {
        guard batchPhase == .ready,
              let snapshot = batchSettingsSnapshot,
              !batchItems.isEmpty else { return }

        let generation = UUID()
        batchGeneration = generation
        batchErrorDecisionRequest = nil
        batchPhase = .signing
        lastError = nil
        let pin = batchPIN

        for index in batchItems.indices {
            guard batchGeneration == generation else { return }
            guard batchItems[index].state == .pending else { continue }
            batchCurrentIndex = index
            batchItems[index].state = .signing
            batchItems[index].errorMessage = nil
            if let queueIndex = queue.firstIndex(where: { $0.id == batchItems[index].id }) {
                queue[queueIndex].status = .signing
            }

            do {
                let output = try await signBatchItem(
                    batchItems[index], snapshot: snapshot, pin: pin, generation: generation)
                guard batchGeneration == generation else { return }
                batchItems[index].state = .signed
                batchItems[index].outputURL = output.outputURL
                batchItems[index].errorMessage = nil
                if let queueIndex = queue.firstIndex(where: { $0.id == batchItems[index].id }) {
                    queue[queueIndex].status = .signed
                    queue[queueIndex].signedOutputURL = output.outputURL
                    queue[queueIndex].errorMessage = nil
                }
                batchCompletedCount = batchItems.filter { $0.state == .signed }.count
                batchFailedCount = batchItems.filter { $0.state == .failed }.count
            } catch is BatchCancellationError {
                return
            } catch {
                guard batchGeneration == generation, batchPhase == .signing else { return }
                let message = error.localizedDescription
                batchItems[index].state = .failed
                batchItems[index].errorMessage = message
                if let queueIndex = queue.firstIndex(where: { $0.id == batchItems[index].id }) {
                    queue[queueIndex].status = .failed
                    queue[queueIndex].errorMessage = message
                }
                batchFailedCount = batchItems.filter { $0.state == .failed }.count
                batchErrorDecisionRequest = BatchFailureDecisionRequest(
                    itemID: batchItems[index].id,
                    displayName: batchItems[index].displayName,
                    errorMessage: message)
                let decision = await withCheckedContinuation { continuation in
                    batchDecisionContinuation = continuation
                }
                guard batchGeneration == generation else { return }
                batchErrorDecisionRequest = nil
                if decision == .stopBatch {
                    for remaining in (index + 1)..<batchItems.count
                    where batchItems[remaining].state == .pending {
                        batchItems[remaining].state = .skipped
                    }
                    break
                }
            }
        }

        guard batchGeneration == generation else { return }
        batchCurrentIndex = nil
        batchPhase = .completed
        batchCompletedCount = batchItems.filter { $0.state == .signed }.count
        batchFailedCount = batchItems.filter { $0.state == .failed }.count
        batchPIN = nil
    }

    func decideBatchFailure(_ decision: BatchFailureDecision) {
        guard batchErrorDecisionRequest != nil else { return }
        batchErrorDecisionRequest = nil
        batchDecisionContinuation?.resume(returning: decision)
        batchDecisionContinuation = nil
    }

    func cancelBatch() {
        guard batchPhase == .preflighting || batchPhase == .ready || batchPhase == .signing else { return }
        invalidateBatchWork()
        var cancelledIDs = Set<UUID>()
        for index in batchItems.indices where batchItems[index].state == .pending
            || batchItems[index].state == .signing {
            cancelledIDs.insert(batchItems[index].id)
            batchItems[index].state = .cancelled
        }
        for index in queue.indices where cancelledIDs.contains(queue[index].id)
            && queue[index].status != .signed {
            queue[index].status = .ready
            queue[index].errorMessage = nil
        }
        batchCurrentIndex = nil
        batchErrorDecisionRequest = nil
        batchPIN = nil
        batchPhase = .cancelled
        batchCompletedCount = batchItems.filter { $0.state == .signed }.count
        batchFailedCount = batchItems.filter { $0.state == .failed }.count
    }

    func retryFailedBatchItems() async {
        guard batchPhase == .completed || batchPhase == .cancelled else { return }
        let previousItems = batchItems
        let failedIDs = previousItems.filter { $0.state == .failed }.map(\.id)
        guard !failedIDs.isEmpty else { return }
        await prepareBatch(ids: failedIDs)
        guard batchPhase == .ready else { return }
        let preparedByID = Dictionary(uniqueKeysWithValues: batchItems.map { ($0.id, $0) })
        batchItems = previousItems.map { preparedByID[$0.id] ?? $0 }
        batchCompletedCount = batchItems.filter { $0.state == .signed }.count
        batchFailedCount = batchItems.filter { $0.state == .failed }.count
        await startBatch()
    }

    private func invalidateBatchWork() {
        batchGeneration = UUID()
        batchDecisionContinuation?.resume(returning: .stopBatch)
        batchDecisionContinuation = nil
    }

    private struct BatchCancellationError: Error {}

    private struct BatchSigningOutput {
        let result: SignedConversionResult
        let outputURL: URL
        let outputDirectory: URL
        let pdfaPrepared: Bool
        let pdfaAfterSign: Bool
    }

    private func signBatchItem(
        _ item: BatchItem,
        snapshot: BatchSettingsSnapshot,
        pin: String?,

        generation: UUID
    ) async throws -> BatchSigningOutput {
        try checkBatchGeneration(generation)
        let secured = item.url.startAccessingSecurityScopedResource()
        defer { if secured { item.url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: item.url) else {
            throw SigningError.signingFailed("Súbor sa nepodarilo otvoriť ako PDF.")
        }
        var pdfData: Data
        if let original = try? Data(contentsOf: item.url), !original.isEmpty {
            pdfData = original
        } else {
            let doc = UncheckedSendable(document)
            pdfData = try await Task.detached(priority: .userInitiated) {
                doc.value.dataRepresentation()
            }.get() ?? Data()
        }
        guard !pdfData.isEmpty else {
            throw SigningError.signingFailed("PDF dokument neobsahuje žiadne dáta.")
        }
        let originalPDFData = pdfData
        var didPreparePDFA = false
        var didFallbackToOriginal = false
        var visualStampWasPreapplied = false
        var attachedStamp: VisibleSignatureStamper.StampData?
        if snapshot.convertToPDFA,
           snapshot.includeVisibleSignature,
           snapshot.outputFormat == .attachedASIC {
            let stamp = VisibleSignatureStamper.StampData(
                fullName: snapshot.identityLabel,
                timestamp: Date(),
                pageIndex: snapshot.visualPlacement?.pageIndex ?? snapshot.signaturePage,
                normalizedRect: snapshot.signatureRect,
                imagePNG: snapshot.visualArtworkOverride
                    ?? VisualSignatureStore.imageData(for: snapshot.selectedVisualAppearanceID),
                certificateName: snapshot.identityLabel,
                certificateQualification: snapshot.identityIsQualified
                    ? "Kvalifikovaný elektronický podpis" : nil,
                timestampAuthorityName: snapshot.includeQualifiedTimestamp
                    ? (settings.availableTSAServers.first { $0.url == snapshot.tsaURL }?.name ?? snapshot.tsaURL)
                    : nil)
            try checkBatchGeneration(generation)
            let stampedData = await Self.stampPDFData(
                pdfData,
                stamp: stamp,
                includeTimestamp: snapshot.includeQualifiedTimestamp,
                stamper: stamper,
                flattenAnnotations: true)
            visualStampWasPreapplied = stampedData != pdfData
            if snapshot.outputFormat == .attachedASIC {
                attachedStamp = stamp
            }
            pdfData = stampedData
        }
        

        if snapshot.convertToPDFA {
            let mode: PDFAConversionMode =
                snapshot.outputFormat == .embeddedPAdES || visualStampWasPreapplied
                ? .rasterGuaranteed
                : snapshot.pdfaMode
            let pdfaDocument = PDFDocument(data: pdfData) ?? document
            pdfData = try PDFAConverter().convert(
                document: pdfaDocument, mode: mode,
                title: item.url.deletingPathExtension().lastPathComponent)
            var check = PDFAValidator().validate(pdfData)
            if !check.isValid {
                pdfData = try PDFAConverter().convert(
                    document: PDFDocument(data: pdfData) ?? pdfaDocument,
                    mode: .rasterGuaranteed,
                    title: item.url.deletingPathExtension().lastPathComponent)
                check = PDFAValidator().validate(pdfData)
            }
            guard check.isValid else {
                throw SigningError.signingFailed(
                    "Konverzia do PDF/A zlyhala: \(check.issues.joined(separator: "; ")).")
            }
            didPreparePDFA = true
        }
        if !snapshot.convertToPDFA,
           snapshot.includeVisibleSignature,
           snapshot.outputFormat == .attachedASIC {
            let imageData = snapshot.visualArtworkOverride
                ?? VisualSignatureStore.imageData(for: snapshot.selectedVisualAppearanceID)
            let stamp = VisibleSignatureStamper.StampData(
                fullName: snapshot.identityLabel,
                timestamp: Date(),
                pageIndex: snapshot.signaturePage,
                normalizedRect: snapshot.signatureRect,
                imagePNG: imageData,
                certificateName: snapshot.identityLabel,
                certificateQualification: snapshot.identityIsQualified
                    ? "Kvalifikovaný elektronický podpis" : nil,
                timestampAuthorityName: snapshot.includeQualifiedTimestamp
                    ? (settings.availableTSAServers.first { $0.url == snapshot.tsaURL }?.name ?? snapshot.tsaURL)
                    : nil)
            attachedStamp = stamp
            try checkBatchGeneration(generation)
            pdfData = await Self.stampPDFData(
                pdfData,
                stamp: stamp,
                includeTimestamp: snapshot.includeQualifiedTimestamp,
                stamper: stamper,
                flattenAnnotations: true)
        }

        let visualStamp: VisualStampSpec?
        if snapshot.includeVisibleSignature,
           snapshot.outputFormat == .embeddedPAdES {
            visualStamp = VisualStampSpec(
                fullName: snapshot.identityLabel,
                timestamp: Date(),
                pageIndex: snapshot.visualPlacement?.pageIndex ?? snapshot.signaturePage,
                normalizedRect: snapshot.signatureRect,
                imagePNG: snapshot.visualArtworkOverride
                    ?? VisualSignatureStore.imageData(for: snapshot.selectedVisualAppearanceID),
                // Batch placement is always relative to the current target page.
                pdfPageRect: nil,
                rotationDegrees: snapshot.visualPlacement?.rotationDegrees ?? 0,
                qualification: snapshot.identityIsQualified
                    ? "Kvalifikovaný elektronický podpis" : nil,
                certificateName: snapshot.identityLabel,
                timestampAuthorityName: snapshot.includeQualifiedTimestamp
                    ? (settings.availableTSAServers.first { $0.url == snapshot.tsaURL }?.name ?? snapshot.tsaURL)
                    : nil)
        } else {
            visualStamp = nil
        }
        let request = SigningRequest(
            pdfData: pdfData,
            identityID: snapshot.selectedIdentityID,
            includeTimestamp: snapshot.includeQualifiedTimestamp,
            tsaURL: snapshot.tsaURL,
            outputFormat: snapshot.outputFormat,
            pin: pin,
            extraFiles: [ASiCEPackager.Entry(path: item.url.lastPathComponent, data: pdfData)],
            visualStamp: visualStamp)
        var signed: SignedConversionResult
        do {
            try checkBatchGeneration(generation)
            signed = try await signingProvider.sign(request)
            try checkBatchGeneration(generation)
        } catch {
            let text = error.localizedDescription
            if snapshot.convertToPDFA, didPreparePDFA,
               text.contains("SIGNING_UNAVAILABLE") || text.contains("SIGNING_FAILED") {
                didFallbackToOriginal = true
                var fallbackPDFData = originalPDFData
                if let attachedStamp {
                    try checkBatchGeneration(generation)
                    fallbackPDFData = await Self.stampPDFData(
                        fallbackPDFData, stamp: attachedStamp,
                        includeTimestamp: snapshot.includeQualifiedTimestamp,
                        stamper: stamper)
                }
                try checkBatchGeneration(generation)
                signed = try await signingProvider.sign(SigningRequest(
                    pdfData: fallbackPDFData,
                    identityID: snapshot.selectedIdentityID,
                    includeTimestamp: snapshot.includeQualifiedTimestamp,
                    tsaURL: snapshot.tsaURL,
                    outputFormat: snapshot.outputFormat,
                    pin: pin,
                    extraFiles: [ASiCEPackager.Entry(
                        path: item.url.lastPathComponent, data: fallbackPDFData)],
                    visualStamp: visualStamp))
                try checkBatchGeneration(generation)
            } else {
                throw error
            }
        }

        try checkBatchGeneration(generation)
        let directory = outputLocation(for: item.url).directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try checkBatchGeneration(generation)
        let outputData: Data
        let outputExtension: String
        if snapshot.outputFormat == .embeddedPAdES {
            outputData = signed.pdfData
            outputExtension = "pdf"
        } else if let asic = signed.asicData {
            outputData = asic
            outputExtension = "asice"
        } else {
            outputData = signed.pdfData
            outputExtension = "pdf"
        }
        let reservation = try outputService.reserveUniqueSibling(
            for: item.url,
            in: directory,
            stemSuffix: "_podpisane",
            outputExtension: outputExtension)
        do {
            try checkBatchGeneration(generation)
            try outputData.write(to: reservation.temporaryURL, options: [.atomic])
            try checkBatchGeneration(generation)
            try outputService.finalize(reservation)
        } catch {
            try? FileManager.default.removeItem(at: reservation.temporaryURL)
            throw error
        }
        return BatchSigningOutput(
            result: signed,
            outputURL: reservation.finalURL,
            outputDirectory: directory,
            pdfaPrepared: didPreparePDFA && !didFallbackToOriginal,
            pdfaAfterSign: PDFAValidator().validate(signed.pdfData).isValid
                || (signed.asicData != nil && didPreparePDFA && !didFallbackToOriginal))
    }

    static func validateBatchVisualPlacement(
        placement: VisibleSignaturePlacement?,
        normalizedRect: NormalizedRect,
        pageCount: Int?,
        pageBounds: CGRect? = nil
    ) -> String? {
        guard let placement else {
            return "Vizuálny podpis vyžaduje explicitné umiestnenie."
        }
        guard placement.pageIndex >= 0,
              placement.rotationDegrees.isFinite else {
            return "Vizuálny podpis nemá platné umiestnenie."
        }
        guard normalizedRect.x.isFinite,
              normalizedRect.y.isFinite,
              normalizedRect.width.isFinite,
              normalizedRect.height.isFinite,
              normalizedRect.x >= 0,
              normalizedRect.y >= 0,
              normalizedRect.width > 0,
              normalizedRect.height > 0,
              normalizedRect.x + normalizedRect.width <= 1,
              normalizedRect.y + normalizedRect.height <= 1 else {
            return "Vizuálny podpis nemá platné relatívne umiestnenie."
        }
        if let pageCount, placement.pageIndex >= pageCount {
            return "Umiestnenie vizuálneho podpisu nie je dostupné na tejto strane."
        }
        if pageCount != nil {
            guard let pageBounds,
                  pageBounds.width.isFinite,
                  pageBounds.height.isFinite,
                  pageBounds.width > 0,
                  pageBounds.height > 0 else {

                return "Cieľová strana PDF nemá platné rozmery."
            }
        }
        return nil
    }
    private func previewDocument(for url: URL) -> PDFDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if url.pathExtension.lowercased() != "asice" {
            return PDFDocument(data: data)
        }
        guard let pdfData = ASiCEContainerVerifier.extractPDFData(data) else {
            return nil
        }
        return PDFDocument(data: pdfData)
    }

    private func checkBatchGeneration(_ generation: UUID) throws {
        guard batchGeneration == generation else { throw BatchCancellationError() }
    }

    static func stampPDFData(
        _ data: Data,
        stamp: VisibleSignatureStamper.StampData,
        includeTimestamp: Bool,
        stamper: VisibleSignatureStamper,
        flattenAnnotations: Bool = false
    ) async -> Data {
        guard let source = PDFDocument(data: data) else { return data }
        let sendableSource = UncheckedSendable(source)
        return await Task.detached(priority: .userInitiated) {
            if flattenAnnotations {
                return stamper.flattenedStamp(
                    document: sendableSource.value,
                    stamp: stamp,
                    includeTimestamp: includeTimestamp)
            }
            return stamper.stamp(
                document: sendableSource.value,
                stamp: stamp,
                includeTimestamp: includeTimestamp)
        }.value ?? data
    }

    private func outputLocation(for url: URL) -> (directory: URL, stem: String) {
        let directory = FileManager.default.isWritableFile(
            atPath: url.deletingLastPathComponent().path)
            ? url.deletingLastPathComponent() : Self.outputDirectoryURL()
        return (directory, "\(url.deletingPathExtension().lastPathComponent)_podpisane")
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
        selectedQueueID = nil
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
