import AppKit
import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers

@MainActor @Observable
final class WorkspaceModel {
    private(set) var items: [PDFItem] = []
    var selection: PDFItem.ID? {
        didSet {
            guard selection != oldValue else { return }
            closeEmbeddedPreview()
            disableVisibleSignatureComposition()
        }
    }
    var selectedOutputFormat: SigningOutputFormat = .automatic
    var visibleSignatureAsset: SignatureAsset?
    private(set) var visibleSignatureAssets: [SignatureAsset] = []
    var visibleSignatureEnabled = false
    var visibleSignaturePlacement: VisibleSignaturePlacement?
    private(set) var visibleSignaturePageCount = 0
    private(set) var visibleSignatureCardContent: VisibleSignatureCardContent?
    private(set) var visibleSignatureCardPreview: NSImage?
    private(set) var availableDrivers: [SigningDriver] = []
    private(set) var selectedDriverID: String?
    private(set) var discoveredCertificates: [SigningCertificate] = []
    private(set) var rememberedTokens: [RememberedSigningToken] = []
    private(set) var signingEnvironment: EngineCapabilities?
    private(set) var isLoadingSigningEnvironment = false
    private(set) var isLoadingCertificates = false
    private(set) var credentialError: String?
    private(set) var signingError: String?
    private(set) var signingActivityPhase: SigningActivityPhase?
    private(set) var embeddedPreview: EmbeddedDocumentPreview?
    private(set) var signatureValidationProgress: SignatureValidationProgress = .provisional
    private let engine: any SigningEngine
    private let certificateDefaultStore: any CertificateDefaultStoring
    private let signatureAssetStore: SignatureAssetStore
    private let visibleSignatureRenderer: VisibleSignatureRenderer
    private let defaults: UserDefaults
    @ObservationIgnored private var coordinator: SigningCoordinator?
    @ObservationIgnored private var pendingSigningPIN: Secret?
    @ObservationIgnored private var discoveredToken: SigningToken?
    @ObservationIgnored private var inspectionRequestGeneration = 0
    @ObservationIgnored private var previewRequestGeneration = 0
    @ObservationIgnored private var embeddedPreviewSourceItemID: PDFItem.ID?
    @ObservationIgnored private var embeddedPreviewDirectory: URL?
    @ObservationIgnored private var completeValidationTask: Task<Void, Never>?

    init(
        engine: any SigningEngine = FakeSigningEngine.launchEngine(),
        items: [PDFItem] = [],
        certificateDefaultStore: any CertificateDefaultStoring = UserDefaultsCertificateDefaultStore(),
        signatureAssetStore: SignatureAssetStore = SignatureAssetStore(),
        visibleSignatureRenderer: VisibleSignatureRenderer? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.engine = engine
        self.items = items
        self.certificateDefaultStore = certificateDefaultStore
        self.signatureAssetStore = signatureAssetStore
        self.visibleSignatureRenderer = visibleSignatureRenderer ?? VisibleSignatureRenderer(assetStore: signatureAssetStore)
        self.defaults = defaults
        rememberedTokens = certificateDefaultStore.rememberedTokens
        self.selection = items.first?.id
        refreshVisibleSignatureAssets()
        restoreVisibleSignaturePreferences()
        updateVisibleSignatureDocument()
        self.coordinator = SigningCoordinator(engine: engine, workspace: self)
    }

    static func launchWorkspace(engine: any SigningEngine, fixtureMode: String? = nil) -> WorkspaceModel {
        let items: [PDFItem]
        if fixtureMode == "partial-failure" {
            items = [
                PDFItem(descriptor: PDFItemDescriptor(id: "agreement", sourceURL: URL(fileURLWithPath: "/tmp/Agreement.pdf"))),
                PDFItem(descriptor: PDFItemDescriptor(id: "invoice", sourceURL: URL(fileURLWithPath: "/tmp/Invoice.pdf")))
            ]
        } else if fixtureMode == "credential-flow" {
            items = [
                PDFItem(descriptor: PDFItemDescriptor(id: "credential-flow", sourceURL: URL(fileURLWithPath: "/tmp/Document.pdf")))
            ]
        } else {
            items = []
        }
        return WorkspaceModel(engine: engine, items: items)
    }

    var connectedDrivers: [SigningDriver] {
        availableDrivers.filter { $0.tokenPresent == true }
    }

    var tokenPresenceIsKnown: Bool {
        availableDrivers.contains { $0.tokenPresent != nil }
    }

    var selectableDrivers: [SigningDriver] {
        tokenPresenceIsKnown ? connectedDrivers : availableDrivers
    }

    var canStartSigning: Bool {
        !items.isEmpty && signingActivityPhase == nil && items.allSatisfy { $0.inspection.isComplete }
    }

    var selectedItem: PDFItem? {
        guard let selection else { return items.first }
        return items.first { $0.id == selection }
    }

    func refreshInspections() async {
        let descriptors = items.map(\.descriptor)
        guard !descriptors.isEmpty else { return }

        cancelCompleteValidation()
        inspectionRequestGeneration += 1
        let requestGeneration = inspectionRequestGeneration
        signingActivityPhase = .inspectingDocuments
        updateInspection(for: descriptors.map(\.id), to: .pending)

        do {
            let inspections = try await engine.inspect(files: descriptors)
            applyInspectionResults(inspections, for: descriptors, requestGeneration: requestGeneration)
            signingActivityPhase = nil
            startCompleteValidation(
                for: descriptorsWithElectronicSignatures(in: inspections, matching: descriptors),
                requestGeneration: requestGeneration
            )
        } catch {
            guard requestGeneration == inspectionRequestGeneration else { return }
            updateInspection(for: descriptors.map(\.id), to: .failed)
            signingActivityPhase = nil
        }
    }

    func previewEmbeddedDocument(named name: String) async {
        guard let item = selectedItem else { return }
        previewRequestGeneration += 1
        let requestGeneration = previewRequestGeneration
        discardEmbeddedPreview()
        do {
            let preview = try await engine.previewEmbeddedDocument(sourceURL: item.descriptor.sourceURL, named: name)
            guard requestGeneration == previewRequestGeneration,
                  selectedItem?.id == item.id,
                  selectedItem?.descriptor == item.descriptor else {
                discardEmbeddedPreviewDirectory(for: preview)
                return
            }
            embeddedPreview = preview
            embeddedPreviewSourceItemID = item.id
            embeddedPreviewDirectory = preview.url.deletingLastPathComponent()
        } catch {
            guard requestGeneration == previewRequestGeneration else { return }
        }
    }

    func closeEmbeddedPreview() {
        previewRequestGeneration += 1
        discardEmbeddedPreview()
    }

    func verifySelectedDocumentAgain() async {
        guard let selectedItem else { return }
        cancelCompleteValidation()
        inspectionRequestGeneration += 1
        await completeValidation(for: [selectedItem.descriptor], requestGeneration: inspectionRequestGeneration)
    }

    func refreshSigningEnvironment() async {
        isLoadingSigningEnvironment = true
        signingActivityPhase = .readingSigningCard
        credentialError = nil
        discoveredCertificates = []

        defer {
            isLoadingSigningEnvironment = false
            if signingActivityPhase == .readingSigningCard {
                signingActivityPhase = nil
            }
        }

        do {
            signingEnvironment = try await engine.capabilities()
            availableDrivers = try await engine.drivers()
            if selectableDrivers.count == 1 {
                selectedDriverID = selectableDrivers[0].id
            } else if !selectableDrivers.contains(where: { $0.id == selectedDriverID }) {
                selectedDriverID = nil
            }
        } catch {
            signingEnvironment = nil
            availableDrivers = []
            selectedDriverID = nil
            credentialError = error.localizedDescription
        }
    }

    func selectDriver(id: String?) {
        guard let id, selectableDrivers.contains(where: { $0.id == id }) else {
            selectedDriverID = nil
            credentialError = nil
            cancelCredentialFlow()
            return
        }

        guard selectedDriverID != id else { return }
        selectedDriverID = id
        credentialError = nil
        cancelCredentialFlow()
    }

    func resolveCertificates(using submission: PINSubmission) async -> CertificateResolution {
        cancelCredentialFlow()
        credentialError = nil
        signingError = nil
        guard let selectedDriverID else {
            credentialError = "Choose a signing driver before continuing."
            return .failed
        }

        isLoadingCertificates = true
        signingActivityPhase = .loadingCertificates
        pendingSigningPIN = submission.signingPIN

        do {
            let discovery = try await engine.certificateDiscovery(
                driverID: selectedDriverID,
                pin: submission.certificatePIN
            )
            discoveredToken = discovery.token
            certificateDefaultStore.remember(discovery.token)
            refreshRememberedTokens()
            discoveredCertificates = discovery.certificates
            refreshVisibleSignatureArtworkPreview()
        } catch {
            isLoadingCertificates = false
            signingActivityPhase = nil
            credentialError = error.localizedDescription
            clearPendingSigningPIN()
            return .failed
        }

        isLoadingCertificates = false
        signingActivityPhase = nil
        guard !discoveredCertificates.isEmpty else {
            credentialError = "No signing certificates were found for the selected driver."
            clearPendingSigningPIN()
            return .failed
        }

        guard let discoveredToken else {
            credentialError = "The signing helper returned incomplete certificate discovery metadata."
            clearPendingSigningPIN()
            return .failed
        }

        switch CertificateDefaultSelector.select(
            from: CertificateDiscovery(token: discoveredToken, certificates: discoveredCertificates),
            remembered: certificateDefaultStore.default(for: discoveredToken.tokenKey),
            now: .now
        ) {
        case .selected(let certificate):
            startSigning(with: certificate)
            return .signingStarted
        case .pickerRequired:
            return .certificateSelectionRequired
        }
    }

    func selectCertificateForSigning(_ certificate: SigningCertificate, rememberAsDefault: Bool) {
        if rememberAsDefault, let discoveredToken {
            certificateDefaultStore.saveDefault(for: discoveredToken, certificate: certificate)
            refreshRememberedTokens()
        }
        startSigning(with: certificate)
    }

    func resolveCertificatesForDefaultChange(
        using submission: PINSubmission,
        expectedTokenKey: String
    ) async -> CertificateDefaultChangeResolution {
        cancelCredentialFlow()
        credentialError = nil
        signingError = nil
        guard let selectedDriverID else {
            credentialError = "Choose a signing driver before continuing."
            return .failed
        }

        isLoadingCertificates = true
        signingActivityPhase = .loadingCertificates
        defer {
            isLoadingCertificates = false
            if signingActivityPhase == .loadingCertificates {
                signingActivityPhase = nil
            }
        }

        do {
            let discovery = try await engine.certificateDiscovery(
                driverID: selectedDriverID,
                pin: submission.certificatePIN
            )
            discoveredToken = discovery.token
            certificateDefaultStore.remember(discovery.token)
            refreshRememberedTokens()
            guard discovery.token.tokenKey == expectedTokenKey else {
                credentialError = "Connect the selected signing token before changing its default."
                return .failed
            }
            guard !discovery.certificates.isEmpty else {
                credentialError = "No signing certificates were found for the selected driver."
                return .failed
            }
            discoveredCertificates = discovery.certificates
            refreshVisibleSignatureArtworkPreview()
            return .certificateSelectionRequired
        } catch {
            credentialError = error.localizedDescription
            return .failed
        }
    }

    func saveDefault(for certificate: SigningCertificate) {
        guard let discoveredToken else {
            credentialError = "Certificate discovery is no longer available. Unlock the signing card again."
            return
        }
        certificateDefaultStore.saveDefault(for: discoveredToken, certificate: certificate)
        refreshRememberedTokens()
    }

    func clearDefault(for tokenKey: String) {
        certificateDefaultStore.clearDefault(for: tokenKey)
        refreshRememberedTokens()
    }

    func forgetToken(for tokenKey: String) {
        certificateDefaultStore.forgetToken(for: tokenKey)
        refreshRememberedTokens()
    }

    func startSigning(with certificate: SigningCertificate) {
        guard let driverID = selectedDriverID, let signingPIN = pendingSigningPIN else {
            credentialError = "Signing credentials are no longer available. Enter your PIN again."
            return
        }

        clearPendingSigningPIN()
        signingError = nil
        signingActivityPhase = .preparingSignatures
        coordinator = SigningCoordinator(engine: engine, workspace: self)
        Task { [weak self] in
            await self?.sign(
                driverID: driverID,
                certificate: certificate,
                pin: signingPIN
            )
        }
    }

    func cancelCredentialFlow() {
        discoveredCertificates = []
        discoveredToken = nil
        isLoadingCertificates = false
        clearPendingSigningPIN()
        if signingActivityPhase == .loadingCertificates {
            signingActivityPhase = nil
        }
    }

    func setItems(_ items: [PDFItem]) {
        invalidateCompleteValidation()
        disableVisibleSignatureComposition()
        self.items = items
        discardEmbeddedPreviewIfSourceWasRemoved()
        if let selection, !items.contains(where: { $0.id == selection }) {
            self.selection = items.first?.id
        } else if selection == nil {
            self.selection = items.first?.id
        }
        updateVisibleSignatureDocument()
    }

    func configureVisibleAppearance(asset: SignatureAsset?, enabled: Bool, placement: VisibleSignaturePlacement?) {
        visibleSignatureAsset = asset
        visibleSignatureEnabled = enabled
        visibleSignaturePlacement = placement
        refreshVisibleSignatureArtworkPreview()
        persistVisibleSignaturePreferences()
    }

    func setVisibleSignatureEnabled(_ enabled: Bool) {
        visibleSignatureEnabled = enabled
        persistVisibleSignaturePreferences()
    }

    func importVisibleSignatureArtwork(from sourceURL: URL, pdfPageIndex: Int = 0) throws {
        let asset: SignatureAsset
        if sourceURL.pathExtension.lowercased() == "pdf" {
            asset = try signatureAssetStore.importPDF(sourceURL, pageIndex: pdfPageIndex)
        } else {
            asset = try signatureAssetStore.importPNG(sourceURL)
        }
        refreshVisibleSignatureAssets()
        selectVisibleSignatureArtwork(asset)
    }

    func selectVisibleSignatureArtwork(_ asset: SignatureAsset) {
        guard visibleSignatureAssets.contains(asset) else { return }
        visibleSignatureAsset = asset
        visibleSignatureEnabled = true
        visibleSignaturePlacement = defaultVisibleSignaturePlacement()
        refreshVisibleSignatureArtworkPreview()
        persistVisibleSignaturePreferences()
    }

    func deleteVisibleSignatureArtwork(_ asset: SignatureAsset) throws {
        try signatureAssetStore.delete(asset)
        refreshVisibleSignatureAssets()
        guard visibleSignatureAsset == asset else { return }
        visibleSignatureAsset = nil
        visibleSignatureEnabled = false
        visibleSignaturePlacement = nil
        visibleSignatureCardContent = nil
        visibleSignatureCardPreview = nil
        persistVisibleSignaturePreferences()
    }

    func removeVisibleSignatureArtwork() {
        visibleSignatureAsset = nil
        visibleSignatureEnabled = false
        visibleSignaturePlacement = nil
        visibleSignatureCardContent = nil
        visibleSignatureCardPreview = nil
        persistVisibleSignaturePreferences()
    }

    var visibleSignatureArtworkURL: URL? {
        visibleSignatureAsset.map(signatureAssetStore.fileURL(for:))
    }

    func visibleSignatureArtworkURL(for asset: SignatureAsset) -> URL {
        signatureAssetStore.fileURL(for: asset)
    }

    func updateVisibleSignaturePlacement(_ placement: VisibleSignaturePlacement?) {
        visibleSignaturePlacement = placement
        persistVisibleSignaturePreferences()
    }

    var visibleSignaturePageIndices: [Int] {
        Array(0..<visibleSignaturePageCount)
    }

    func selectVisibleSignaturePage(_ pageIndex: Int) {
        guard var placement = visibleSignaturePlacement,
              visibleSignaturePageCount > 0 else {
            return
        }
        placement.pageIndex = min(max(pageIndex, 0), visibleSignaturePageCount - 1)
        updateVisibleSignaturePlacement(placement)
    }

    func updateVisibleSignatureDocument() {
        guard let selected = items.first(where: { $0.id == selection }), selected.descriptor.isPDF else {
            visibleSignaturePageCount = 0
            return
        }
        visibleSignaturePageCount = PDFDocument(url: selected.descriptor.sourceURL)?.pageCount ?? 0
        guard var placement = visibleSignaturePlacement, visibleSignaturePageCount > 0 else { return }
        let clampedPageIndex = min(max(placement.pageIndex, 0), visibleSignaturePageCount - 1)
        guard placement.pageIndex != clampedPageIndex else { return }
        placement.pageIndex = clampedPageIndex
        updateVisibleSignaturePlacement(placement)
    }

    func setVisibleSignatureError(_ error: Error) {
        signingError = error.localizedDescription
    }

    func resetVisibleSignaturePlacement() {
        guard var placement = visibleSignaturePlacement else { return }
        placement.rotationDegrees = 0
        updateVisibleSignaturePlacement(placement)
    }

    func updateStatus(for fileID: String, to status: PDFItemStatus) {
        items = items.map { item in
            item.descriptor.id == fileID ? item.updatingStatus(to: status) : item
        }
    }

    func updateSignedOutput(for fileID: String, to outputURL: URL) {
        invalidateCompleteValidation()
        disableVisibleSignatureComposition()
        persistVisibleSignaturePreferences()
        items = items.map { item in
            guard item.descriptor.id == fileID else { return item }
            return item.updatingDescriptor(to: PDFItemDescriptor(id: fileID, sourceURL: outputURL))
        }
    }

    func applyPostSigningInspectionResults(_ inspections: [PDFInspection], for descriptors: [PDFItemDescriptor]) {
        let requestedIDs = Set(descriptors.map(\.id))
        let results = Dictionary(
            inspections.flatMap(\.files)
                .filter { requestedIDs.contains($0.id) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        items = items.map { item in
            guard requestedIDs.contains(item.descriptor.id) else { return item }
            guard let result = results[item.descriptor.id], result.isSignable else {
                return item.updatingInspection(to: .failed)
            }
            return item.updatingInspection(to: .completed(result))
        }
        startCompleteValidation(
            for: descriptorsWithElectronicSignatures(in: inspections, matching: descriptors),
            requestGeneration: inspectionRequestGeneration
        )
    }

    func markPostSigningInspectionFailed(for fileIDs: [String]) {
        let failedIDs = Set(fileIDs)
        items = items.map { item in
            failedIDs.contains(item.descriptor.id) ? item.updatingInspection(to: .failed) : item
        }
        let descriptors = items
            .filter { failedIDs.contains($0.descriptor.id) }
            .map(\.descriptor)
        startCompleteValidation(
            for: descriptors,
            requestGeneration: inspectionRequestGeneration
        )
    }

    func applyInspectionResults(
        _ inspections: [PDFInspection],
        for descriptors: [PDFItemDescriptor],
        requestGeneration: Int? = nil
    ) {
        if let requestGeneration {
            guard requestGeneration == inspectionRequestGeneration else { return }
        } else {
            inspectionRequestGeneration += 1
        }

        let requestedIDs = Set(descriptors.map(\.id))
        let results = Dictionary(
            inspections.flatMap(\.files)
                .filter { requestedIDs.contains($0.id) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        items = items.map { item in
            guard requestedIDs.contains(item.descriptor.id) else { return item }
            guard let result = results[item.descriptor.id], result.isSignable else {
                return item
                    .updatingInspection(to: .failed)
                    .updatingStatus(to: .failed)
            }
            return item
                .updatingInspection(to: .completed(result))
                .updatingStatus(to: .inspected)
        }
    }

    func markInspectionFailed(for fileIDs: [String]) {
        updateInspection(for: fileIDs, to: .failed)
    }

    func setSigningActivityPhase(_ phase: SigningActivityPhase?) {
        signingActivityPhase = phase
    }

    private func updateInspection(for fileIDs: [String], to inspection: PDFItemInspection) {
        let inspectedIDs = Set(fileIDs)
        let status: PDFItemStatus = switch inspection {
        case .pending: .pending
        case .completed: .inspected
        case .failed: .failed
        }
        items = items.map { item in
            inspectedIDs.contains(item.descriptor.id)
                ? item.updatingInspection(to: inspection).updatingStatus(to: status)
                : item
        }
    }

    private func startCompleteValidation(for descriptors: [PDFItemDescriptor], requestGeneration: Int) {
        signatureValidationProgress = .provisional
        cancelCompleteValidation()
        guard !descriptors.isEmpty else { return }
        completeValidationTask = Task { [weak self] in
            await self?.completeValidation(for: descriptors, requestGeneration: requestGeneration)
        }
    }

    private func completeValidation(for descriptors: [PDFItemDescriptor], requestGeneration: Int) async {
        guard validationRequestIsCurrent(descriptors, requestGeneration: requestGeneration) else { return }
        signatureValidationProgress = .validating
        do {
            let inspections = try await engine.validate(files: descriptors)
            guard !Task.isCancelled,
                  validationRequestIsCurrent(descriptors, requestGeneration: requestGeneration) else {
                return
            }
            if applyCompleteValidationResults(inspections, for: descriptors) {
                signatureValidationProgress = .complete
            } else {
                signatureValidationProgress = .incomplete(validationIncompleteReason(for: descriptors))
            }
        } catch {
            guard !Task.isCancelled,
                  validationRequestIsCurrent(descriptors, requestGeneration: requestGeneration) else {
                return
            }
            signatureValidationProgress = .incomplete(error.localizedDescription)
        }
    }

    private func applyCompleteValidationResults(_ inspections: [PDFInspection], for descriptors: [PDFItemDescriptor]) -> Bool {
        let requestedIDs = Set(descriptors.map(\.id))
        let results = Dictionary(
            inspections.flatMap(\.files)
                .filter { requestedIDs.contains($0.id) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        guard descriptors.allSatisfy({ descriptor in
            results[descriptor.id]?.isSignable == true
        }) else {
            return false
        }
        items = items.map { item in
            guard descriptors.contains(item.descriptor), let result = results[item.descriptor.id] else { return item }
            return item
                .updatingInspection(to: .completed(result))
                .updatingStatus(to: .inspected)
        }
        return true
    }

    private func validationRequestIsCurrent(_ descriptors: [PDFItemDescriptor], requestGeneration: Int) -> Bool {
        requestGeneration == inspectionRequestGeneration
            && descriptors.allSatisfy { descriptor in
                items.contains(where: { $0.descriptor == descriptor })
            }
    }

    private func validationIncompleteReason(for descriptors: [PDFItemDescriptor]) -> String {
        let names = descriptors.map(\.redactedDisplayName).joined(separator: ", ")
        return "Complete validation returned no result for \(names)."
    }

    private func descriptorsWithElectronicSignatures(
        in inspections: [PDFInspection],
        matching descriptors: [PDFItemDescriptor]
    ) -> [PDFItemDescriptor] {
        let descriptorIDs = Set(descriptors.map(\.id))
        let signedIDs = Set(
            inspections.flatMap(\.files)
                .filter { descriptorIDs.contains($0.id) && !$0.signatures.isEmpty }
                .map(\.id)
        )
        return descriptors.filter { signedIDs.contains($0.id) }
    }

    private func cancelCompleteValidation() {
        completeValidationTask?.cancel()
        completeValidationTask = nil
    }

    private func invalidateCompleteValidation() {
        cancelCompleteValidation()
        inspectionRequestGeneration += 1
        signatureValidationProgress = .provisional
    }

    private func discardEmbeddedPreviewIfSourceWasRemoved() {
        guard let embeddedPreviewSourceItemID,
              !items.contains(where: { $0.id == embeddedPreviewSourceItemID }) else {
            return
        }
        closeEmbeddedPreview()
    }

    private func discardEmbeddedPreview() {
        if let embeddedPreviewDirectory {
            try? FileManager.default.removeItem(at: embeddedPreviewDirectory)
        }
        embeddedPreview = nil
        embeddedPreviewSourceItemID = nil
        embeddedPreviewDirectory = nil
    }

    private func discardEmbeddedPreviewDirectory(for preview: EmbeddedDocumentPreview) {
        try? FileManager.default.removeItem(at: preview.url.deletingLastPathComponent())
    }

    func selectPDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "asice")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Select"
        panel.begin { [weak self] response in
            let urls = panel.urls
            guard response == .OK else { return }
            Task { @MainActor in
                _ = self?.addFiles(urls)
            }
        }
    }

    @discardableResult
    func addFiles(_ urls: [URL]) -> Bool {
        let existingURLs = Set(items.map { $0.descriptor.sourceURL.resolvingSymlinksInPath().standardizedFileURL })
        var acceptedURLs = Set<URL>()
        let validURLs = urls.filter { url in
            let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard standardizedURL.isFileURL,
                  ["pdf", "asice"].contains(standardizedURL.pathExtension.lowercased()),
                  !existingURLs.contains(standardizedURL),
                  acceptedURLs.insert(standardizedURL).inserted else {
                return false
            }
            return true
        }

        let newItems = validURLs.map {
            PDFItem(descriptor: PDFItemDescriptor(id: UUID().uuidString, sourceURL: $0))
        }
        guard !newItems.isEmpty else { return false }
        invalidateCompleteValidation()
        items.append(contentsOf: newItems)
        if selection == nil {
            selection = newItems.first?.id
        }
        Task { await refreshInspections() }
        return true
    }

    @discardableResult
    func addPDFs(_ urls: [URL]) -> Bool {
        addFiles(urls)
    }

    func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func removeItems(atOffsets offsets: IndexSet) {
        invalidateCompleteValidation()
        items.remove(atOffsets: offsets)
        discardEmbeddedPreviewIfSourceWasRemoved()
        if let selection, !items.contains(where: { $0.id == selection }) {
            self.selection = items.first?.id
        }
    }

    func removeSelectedItem() {
        guard let selection, let index = items.firstIndex(where: { $0.id == selection }) else { return }
        removeItems(atOffsets: IndexSet(integer: index))
    }

    deinit {
        completeValidationTask?.cancel()
        if let embeddedPreviewDirectory {
            try? FileManager.default.removeItem(at: embeddedPreviewDirectory)
        }
    }

    private func sign(driverID: String, certificate: SigningCertificate, pin: Secret) async {
        guard !items.isEmpty,
              items.allSatisfy({ $0.inspection.isComplete }),
              !driverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !certificate.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let coordinator else {
            return
        }

        signingError = nil

        let descriptors = items.map(\.descriptor)
        do {
            let signingTime = Date()
            let files = try signingFiles(for: descriptors, certificate: certificate, signingTime: signingTime)
            let request = SigningRequest(
                sessionID: UUID(),
                driverID: driverID,
                certificateSerial: certificate.serialNumber,
                pin: pin,
                files: files,
                outputFormat: selectedOutputFormat
            )
            try await coordinator.seedCompletedInspection(for: descriptors)
            try await coordinator.beginSigning(request: request)
        } catch {
            signingError = error.localizedDescription
            signingActivityPhase = nil
            for item in items {
                updateStatus(for: item.descriptor.id, to: .failed)
            }
        }
    }

    private func clearPendingSigningPIN() {
        pendingSigningPIN = nil
    }

    private func refreshRememberedTokens() {
        rememberedTokens = certificateDefaultStore.rememberedTokens
    }

    private func signingFiles(
        for descriptors: [PDFItemDescriptor],
        certificate: SigningCertificate,
        signingTime: Date
    ) throws -> [SigningFile] {
        guard visibleSignatureEnabled, selectedOutputFormat != .asiceXAdES else {
            return descriptors.map { SigningFile(id: $0.id, sourceURL: $0.sourceURL) }
        }

        var renderedURLs: [URL] = []
        do {
            let files = try descriptors.map { descriptor -> SigningFile in
                guard descriptor.isPDF,
                      let asset = visibleSignatureAsset,
                      let placement = visibleSignaturePlacement,
                      placement.pageRect.width > 0,
                      placement.pageRect.height > 0,
                      let document = PDFDocument(url: descriptor.sourceURL),
                      let page = document.page(at: placement.pageIndex) else {
                    throw SigningFailure.engine("Choose readable artwork and place the graphic signature before signing.")
                }
                let content = VisibleSignatureCardContent(
                    signerName: certificate.displayName,
                    certificateQualification: certificate.certificateQualification
                )
                visibleSignatureCardContent = content
                let previewURL = try visibleSignatureRenderer.render(
                    asset: asset,
                    content: content,
                    signingTime: signingTime,
                    rotationDegrees: 0
                )
                defer { try? FileManager.default.removeItem(at: previewURL) }
                guard let cardPreview = NSImage(contentsOf: previewURL) else {
                    throw VisibleSignatureRendererError.unreadableArtwork
                }
                visibleSignatureCardPreview = cardPreview
                let renderedPNGURL = try visibleSignatureRenderer.render(
                    asset: asset,
                    content: content,
                    signingTime: signingTime,
                    rotationDegrees: placement.rotationDegrees
                )
                renderedURLs.append(renderedPNGURL)
                let field = PDFCoordinateConverter().dssField(
                    placement,
                    cropBox: page.bounds(for: .cropBox),
                    pageRotation: page.rotation
                )
                return SigningFile(
                    id: descriptor.id,
                    sourceURL: descriptor.sourceURL,
                    visibleAppearance: VisibleSignatureRequest(
                        renderedPNGURL: renderedPNGURL,
                        page: field.page,
                        originX: field.originX,
                        originY: field.originY,
                        width: field.width,
                        height: field.height,
                        signingTime: signingTime
                    )
                )
            }
            return files
        } catch {
            renderedURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }

    private func restoreVisibleSignaturePreferences() {
        guard let data = defaults.data(forKey: VisibleSignaturePreferences.storageKey),
              let preferences = try? JSONDecoder().decode(VisibleSignaturePreferences.self, from: data) else {
            return
        }
        visibleSignatureAsset = preferences.assetID.flatMap { id in
            visibleSignatureAssets.first { $0.id == id }
        }
        visibleSignatureEnabled = false
        refreshVisibleSignatureArtworkPreview()
    }

    private func persistVisibleSignaturePreferences() {
        let preferences = VisibleSignaturePreferences(
            assetID: visibleSignatureAsset?.id
        )
        defaults.set(try? JSONEncoder().encode(preferences), forKey: VisibleSignaturePreferences.storageKey)
    }

    private func disableVisibleSignatureComposition() {
        visibleSignatureEnabled = false
        visibleSignaturePlacement = nil
        visibleSignatureCardContent = nil
        visibleSignatureCardPreview = nil
    }

    private func defaultVisibleSignaturePlacement() -> VisibleSignaturePlacement? {
        guard let selected = selectedItem,
              selected.descriptor.isPDF,
              let document = PDFDocument(url: selected.descriptor.sourceURL),
              document.pageCount > 0,
              let page = document.page(at: document.pageCount - 1) else {
            return nil
        }
        let cropBox = page.bounds(for: .cropBox)
        guard cropBox.width > 0, cropBox.height > 0 else { return nil }
        let scale = min(1, cropBox.width / 250, cropBox.height / 150)
        let size = CGSize(width: 250 * scale, height: 150 * scale)
        return VisibleSignaturePlacement(
            pageIndex: document.pageCount - 1,
            pageRect: CGRect(
                x: (cropBox.width - size.width) / 2,
                y: (cropBox.height - size.height) / 2,
                width: size.width,
                height: size.height
            ),
            rotationDegrees: 0
        )
    }

    private func refreshVisibleSignatureAssets() {
        visibleSignatureAssets = (try? signatureAssetStore.listAssets()) ?? []
    }

    private func refreshVisibleSignatureArtworkPreview() {
        guard let asset = visibleSignatureAsset else {
            visibleSignatureCardContent = nil
            visibleSignatureCardPreview = nil
            return
        }
        let certificate = discoveredCertificates.first
        let content = VisibleSignatureCardContent(
            signerName: certificate?.displayName ?? "Certificate details pending",
            certificateQualification: certificate?.certificateQualification
        )
        visibleSignatureCardContent = content
        guard let previewURL = try? visibleSignatureRenderer.render(
            asset: asset,
            content: content,
            signingTime: .now,
            rotationDegrees: 0
        ) else {
            visibleSignatureCardPreview = nil
            return
        }
        defer { try? FileManager.default.removeItem(at: previewURL) }
        visibleSignatureCardPreview = NSImage(contentsOf: previewURL)
    }
}

private struct VisibleSignaturePreferences: Codable {
    static let storageKey = "preferences.visibleSignature"

    let assetID: UUID?
}

enum CertificateResolution: Sendable, Equatable {
    case certificateSelectionRequired
    case signingStarted
    case failed
}

enum CertificateDefaultChangeResolution: Sendable, Equatable {
    case certificateSelectionRequired
    case failed
}
