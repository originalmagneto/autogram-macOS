import Foundation
import PDFKit
import SwiftUI
import AutogramKit

@MainActor
@Observable
final class ZakoSessionStore {
    enum Step: Int, CaseIterable { case intake = 0, analysis = 1, attestation = 2, authorize = 3, done = 4 }

    var step: Step = .intake
    var sourceURL: URL?
    var document: PDFDocument?
    var documentData: Data?
    let exampleBank: ExampleBank
    var bankRecorderFactory: (ExampleBank, String) -> ExampleBankRecorder = { bank, version in
        ExampleBankRecorder(bank: bank, detectorVersion: version)
    }
    private(set) var detectorIdentifier: String = LayeredDetectionProvider(
        classifier: TwoStageClassifier(primary: NoOpClassifier(), secondary: nil)).identifier
    private var bankWriteTasks: [UUID: Task<Void, Never>] = [:]
    private var bankWarningShown = false
    var analysis: DocumentAnalysis = .empty()
    var securityElements: [SecurityElement] = []
    var reviewedNonEmptyPages: Set<Int> = []
    var attestation = AttestationData()
    var sheetMethod: SheetCountingMethod = .duplexEstimate
    var manualSheetCount: Int?

    var isAnalyzing = false
    var analysisProgressText = ""

    enum AIVisionReadiness: Equatable, Sendable {
        case builtInOnly(mode: AppSettings.AIMode)
        case ready(provider: AppSettings.AIMode)
        case unavailable(provider: AppSettings.AIMode, reason: String)

        var message: String {
            switch self {
            case .builtInOnly:
                return "Používa sa iba vstavaná on-device detekcia."
            case .ready(let provider):
                return "Konfigurácia \(provider.rawValue) je pripravená."
            case .unavailable(let provider, let reason):
                return "LLM \(provider.rawValue) nie je dostupné: \(reason) Vstavaná detekcia zostáva aktívna."
            }
        }
    }

    var aiVisionReadiness: AIVisionReadiness {
        Self.aiVisionReadiness(for: settings)
    }

    var analysisWarning: String?

    var identities: [SigningIdentityInfo] = []
    var selectedIdentityID: String?
    var includeQualifiedTimestamp = true
    var allowNonMandateOverride = false
    private var mandateOverrideIdentityID: String?
    var signingPIN = ""
    private var isRefreshingIdentities = false
    private(set) var isResolvingCertificate = false
    var certificateLoadError: String?
    private var lastCertificateLoadPIN: String?
    var evidenceNumberRequested = false
    var fetchingEvidenceNumber = false
    var evidenceNumberError: String?
    var isAuthorizing = false
    private var reviewUpdatedAt: Date?

    var activeTool: SecurityElement.Kind?
    var previewPageIndex: Int = 0
    var lastDeletedElement: (SecurityElement, Int)?
    var selectedElementID: UUID?

    var snapper: any SegmentationSnapping = SegmentationSnapper()
    var snapAssetProgress: Double?
    var snapUnavailableReason: String?
    private var snapAssetsReady = false

    var validationErrors: [AttestationValidationError] = []
    var preflightErrors: [AttestationValidationError] = []
    var result: SignedConversionResult?
    var submissionStatus: EvidenceRecord.Status?
    var outputDirectory: URL?
    var lastError: String?
    let mobileSigning: MobileSigningCoordinator
    private(set) var isAuthorizingViaMobile = false

    static let mobileMandateRefusalMessage =
        "Podpis z mobilu nebol vytvorený mandátnym certifikátom. Zaručená konverzia vyžaduje mandátny certifikát advokáta, konverzia nebola autorizovaná a do evidencie sa nič nezapísalo."

    var isMobileSigningAvailable: Bool {
        settings.mobileSigningEnabled && !signingProviderIsDemo
    }

    /// Preflight for the mobile path: the certificate is known only after the phone
    /// signs, so identity and mandate checks move to the post-signature refusal.
    var isMobilePreflightComplete: Bool {
        let result = AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: true,
            inputSignatureInspection: inputSignatureInspection,
            unreviewedNonEmptyPages: unreviewedNonEmptyPages)
        return result.isComplete && preflightErrors.isEmpty && evidenceNumberError == nil
    }
    var serverTimeUsed: Date?
    var inputSignatureInspection = InputSignatureInspectionResult.unavailable(
        detail: "Kontrola podpisov ešte neprebehla.")

    var isPreflightComplete: Bool {
        let result = AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: selectedIdentityID != nil,
            mandateRequirementSatisfied: mandateRequirementSatisfied
                || hasValidMandateOverride
                || isCertificateTypePending,
            inputSignatureInspection: inputSignatureInspection,
            unreviewedNonEmptyPages: unreviewedNonEmptyPages)
        return result.isComplete && preflightErrors.isEmpty && evidenceNumberError == nil
    }
    var hasUnresolvedPreflightErrors: Bool {
        !AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: selectedIdentityID != nil,
            mandateRequirementSatisfied: mandateRequirementSatisfied,
            inputSignatureInspection: inputSignatureInspection,
            unreviewedNonEmptyPages: unreviewedNonEmptyPages
        ).errors.isEmpty || evidenceNumberError != nil
    }

    var pendingSecurityElementCount: Int {
        securityElements.filter { $0.reviewState == .pending }.count
    }

    var confirmedSecurityElements: [SecurityElement] {
        securityElements.filter { $0.reviewState == .confirmed }
    }

    var securityReviewStamp: SecurityReviewStamp {
        SecurityReviewStamp(
            checkedNonEmptyPageIndices: Array(reviewedNonEmptyPages),
            confirmedElementCount: confirmedSecurityElements.count,
            rejectedElementCount: securityElements.filter { $0.reviewState == .rejected }.count,
            elementDecisions: securityElements.map {
                SecurityReviewElement(id: $0.id, state: $0.reviewState,
                                      kind: $0.kind, pageIndex: $0.pageIndex,
                                      boundingBox: $0.boundingBox)
            },
            detectorIdentifier: detectorIdentifier,
            reviewedAt: reviewUpdatedAt ?? Date())
    }

    var unreviewedNonEmptyPages: [Int] {
        analysis.pageAnalyses
            .filter { !$0.isEmpty && !reviewedNonEmptyPages.contains($0.pageIndex) }
            .map(\.pageIndex)
    }

    let settingsStore: AppSettingsStore
    var settings: AppSettings { settingsStore.settings }
    let pdfaConverter: PDFAConverter
    let clauseGenerator: AttestationClauseGenerator
    let embeddedFileService: EmbeddedFileService
    let formPackRepository: FormPackRepository
    private(set) var selectedFormPack: ConversionFormPack
    var ezzkService: any EZZKServicing { settingsStore.ezzkService }
    var signingProvider: any QualifiedSigningProviding { settingsStore.signingProvider }
    var evidenceStore: LocalEvidenceStore { settingsStore.evidenceStore }

    private var evidenceRequestID: UUID?
    private var sourceAccessIsActive = false
    private var outputDirectoryOverride: URL?
    private var sourceNameOverride: String?
    var profilePersister: ((AdvocateProfile) -> Void)?
    private(set) var currentRecordID = UUID()

    init(settingsStore: AppSettingsStore,
         formPackRepository: FormPackRepository = FormPackRepository(),
         exampleBank: ExampleBank = ExampleBank(directory: ExampleBank.defaultDirectory)) {
        self.settingsStore = settingsStore
        self.mobileSigning = MobileSigningCoordinator(settingsStore: settingsStore)
        self.pdfaConverter = PDFAConverter()
        self.clauseGenerator = AttestationClauseGenerator()
        self.embeddedFileService = EmbeddedFileService()
        self.formPackRepository = formPackRepository
        self.exampleBank = exampleBank
        self.selectedFormPack = formPackRepository.packs.first {
            $0.direction == .paperToElectronic && $0.isActive(at: Date())
        } ?? FormPackRepository.currentLegacyUnverified
        self.currentRecordID = UUID()
        self.profilePersister = { [weak settingsStore] profile in
            guard let settingsStore else { return }
            if let index = settingsStore.settings.profiles.firstIndex(where: { $0.id == profile.id }) {
                settingsStore.settings.profiles[index] = profile
            } else {
                settingsStore.settings.profiles.append(profile)
                settingsStore.settings.activeProfileID = profile.id
            }
        }
    }

    static func aiVisionReadiness(for settings: AppSettings) -> AIVisionReadiness {
        func validEndpoint(_ rawValue: String) -> Bool {
            guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else {
                return false
            }
            return true
        }

        func missing(_ values: [(String, Bool)]) -> String? {
            values.first(where: { !$0.1 })?.0
        }

        switch settings.aiMode {
        case .builtInOnDevice, .disabled:
            return .builtInOnly(mode: settings.aiMode)
        case .omlxLocal:
            if let reason = missing([
                ("URL", validEndpoint(settings.omlxURL)),
                ("model", !settings.omlxModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]) {
                return .unavailable(provider: .omlxLocal, reason: "Doplňte \(reason).")
            }
            return .ready(provider: .omlxLocal)
        case .ollamaLocal:
            if let reason = missing([
                ("URL", validEndpoint(settings.ollamaURL)),
                ("model", !settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]) {
                return .unavailable(provider: .ollamaLocal, reason: "Doplňte \(reason).")
            }
            return .ready(provider: .ollamaLocal)
        case .customAPIKey:
            if let reason = missing([
                ("Base URL", validEndpoint(settings.openAICompatibleBaseURL)),
                ("model", !settings.openAICompatibleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("API kľúč v Kľúčenke", !(KeychainStore.load(account: "ai.apikey") ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]) {
                return .unavailable(provider: .customAPIKey, reason: "Doplňte \(reason).")
            }
            return .ready(provider: .customAPIKey)
        }
    }

    static func buildPipeline(settings: AppSettings, bank: ExampleBank) -> DetectionPipeline {
        let llmProvider: (any SecurityElementsProviding)?
        switch settings.aiMode {
        case .omlxLocal:
            if case .ready = aiVisionReadiness(for: settings),
               let endpoint = URL(string: settings.omlxURL) {
                llmProvider = OpenAIVisionProvider(
                    baseURL: endpoint,
                    model: settings.omlxModel,
                    apiKey: "",
                    promptOverride: settings.aiPrompt)
            } else {
                llmProvider = nil
            }
        case .ollamaLocal:
            if case .ready = aiVisionReadiness(for: settings),
               let endpoint = URL(string: settings.ollamaURL) {
                llmProvider = OllamaVisionProvider(
                    endpoint: endpoint,
                    model: settings.ollamaModel,
                    promptOverride: settings.aiPrompt)
            } else {
                llmProvider = nil
            }
        case .customAPIKey:
            if case .ready = aiVisionReadiness(for: settings),
               let apiKey = KeychainStore.load(account: "ai.apikey"),
               let baseURL = URL(string: settings.openAICompatibleBaseURL) {
                llmProvider = OpenAIVisionProvider(
                    baseURL: baseURL,
                    model: settings.openAICompatibleModel,
                    apiKey: apiKey,
                    promptOverride: settings.aiPrompt)
            } else {
                llmProvider = nil
            }
        case .builtInOnDevice, .disabled:
            llmProvider = nil
        }
        let layered = LayeredDetectionProvider.makeDefault(bank: bank, useFoundationModel: settings.useFoundationModelClassifier)
        return DetectionPipeline(builtin: layered, llmProvider: llmProvider)
    }

    var effectiveSheetCount: Int {
        switch sheetMethod {
        case .manual:
            return max(manualSheetCount ?? 0, 0)
        case .oneSheetPerPage:
            return analysis.nonEmptyPages
        case .duplexEstimate:
            return analysis.estimatedSheetsDuplex
        }
    }

    func loadDocument(at url: URL,
                      outputDirectory: URL? = nil,
                      sourceName: String? = nil) async {
        lastError = nil
        resetSession(keepingProfile: true)
        sourceAccessIsActive = url.startAccessingSecurityScopedResource()
        outputDirectoryOverride = outputDirectory
        sourceNameOverride = sourceName

        let document: PDFDocument?
        if url.pathExtension.lowercased() == "asice",
           let data = try? Data(contentsOf: url),
           let pdfData = ASiCEContainerVerifier.extractPDFData(data) {
            document = PDFDocument(data: pdfData)
        } else {
            document = PDFDocument(url: url)
        }
        guard let document else {
            if sourceAccessIsActive {
                url.stopAccessingSecurityScopedResource()
                sourceAccessIsActive = false
            }
            lastError = "Súbor sa nepodarilo otvoriť ako PDF."
            return
        }
        self.document = document
        self.documentData = (try? Data(contentsOf: url)).flatMap {
            url.pathExtension.lowercased() == "asice" ? ASiCEContainerVerifier.extractPDFData($0) : $0
        }
        self.sourceURL = url
        step = .analysis
        await runAnalysis()
    }

    func runAnalysis() async {
        guard let document else { return }
        let analysisRecordID = currentRecordID
        isAnalyzing = true
        analysisProgressText = "Analyzujem stránky…"
        let doc = UncheckedSendable(document)
        let baseAnalysis = await Task.detached(priority: .userInitiated) {
            let engine = PDFAnalysisEngine()
            return engine.analyze(document: doc.value)
        }.value ?? .empty()
        guard analysisRecordID == currentRecordID, !Task.isCancelled else { return }

        analysisProgressText = "Detegujem bezpečnostné prvky…"
        let selectedSettings = settings
        let readiness = Self.aiVisionReadiness(for: selectedSettings)
        analysisWarning = {
            if case .unavailable = readiness {
                return readiness.message
            }
            return nil
        }()
        var pipeline = Self.buildPipeline(settings: selectedSettings, bank: exampleBank)
        if let layered = pipeline.builtin as? LayeredDetectionProvider {
            detectorIdentifier = layered.identifier
            // `buildPipeline` is static and cannot capture the store, so the
            // per-page progress hook is attached here on a copy.
            var reporting = layered
            reporting.progress = { [weak self] processed, total in
                Task { @MainActor in
                    self?.analysisProgressText =
                        "Detegujem bezpečnostné prvky… strana \(processed) z \(total)"
                }
            }
            pipeline = DetectionPipeline(builtin: reporting, llmProvider: pipeline.llmProvider)
        }
        let detectionOutcome = await Task.detached(priority: .userInitiated) { [doc, pipeline] in
            await pipeline.detectWithStatus(in: doc.value, pageAnalyses: baseAnalysis.pageAnalyses)
        }.value
        guard analysisRecordID == currentRecordID, !Task.isCancelled else { return }
        if let failureMessage = detectionOutcome.failureMessage {
            analysisWarning = "\(failureMessage) Vstavaná detekcia zostáva aktívna."
        }
        if let bankLoadError = await exampleBank.loadError, !bankWarningShown {
            showBankWarningOnce(bankLoadError)
        }
        let detected = detectionOutcome.elements


        let manualElements = securityElements.filter { !$0.detectedByAI }
        var merged = enrich(detected)
        for manual in manualElements where !merged.contains(where: { $0.id == manual.id }) {
            merged.append(manual)
        }

        analysis = DocumentAnalysis(
            totalPages: baseAnalysis.totalPages,
            nonEmptyPages: baseAnalysis.nonEmptyPages,
            estimatedSheetsDuplex: baseAnalysis.estimatedSheetsDuplex,
            pageAnalyses: baseAnalysis.pageAnalyses,
            securityElements: merged,
            suggestedTitle: baseAnalysis.suggestedTitle,
            analyzedAt: Date())
        securityElements = merged
        reviewedNonEmptyPages = []
        reviewUpdatedAt = nil
        sheetMethod = .duplexEstimate
        manualSheetCount = nil
        prepareAttestationPrefill()
        inputSignatureInspection = .unavailable(
            detail: "Kontrola vstupných elektronických podpisov prebieha.")
        if let sourceURL {
            let inspection = await InputSignatureVerificationService(
                provider: signingProvider).inspect(inputURL: sourceURL)
            guard SessionResultGuard.accepts(
                resultFor: analysisRecordID,
                currentRecordID: currentRecordID,
                taskIsCancelled: Task.isCancelled) else { return }
            inputSignatureInspection = inspection
            recomputePreflight()
        }
        isAnalyzing = false
        analysisProgressText = ""
    }

    private func enrich(_ elements: [SecurityElement]) -> [SecurityElement] {
        elements.map { element in
            var copy = element
            if copy.verbalDescription.isEmpty {
                copy.verbalDescription = copy.locationDescription(pageSizePt: .zero) + "."
            }
            return copy
        }
    }

    func prepareAttestationPrefill() {
        let profile = activeProfile()
        var data = attestation
        data.performingPerson = profile
        data.originalDocumentOrder = 1
        data.originalDocumentName = sourceNameOverride
            ?? sourceURL?.deletingPathExtension().lastPathComponent
            ?? analysis.suggestedTitle ?? ""
        data.newDocumentName = (data.originalDocumentName.isEmpty ? "dokument" : data.originalDocumentName) + ".pdf"
        data.numberOfSheets = effectiveSheetCount
        data.sheetCountingMethod = sheetMethod
        data.nonEmptyPageCount = analysis.nonEmptyPages
        data.originalDocumentTypeLabel = "Iný dokument"
        data.newDocumentFormatLabel = "PDF/A-2"
        data.usedDeviceDescription = "Skenovanie / import do aplikácie Autogram"
        var breakdown: [AttestationData.PaperSizeGroup] = []
        for (sizeClass, pages) in analysis.paperSizeSummary.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            breakdown.append(.init(sizeClass: sizeClass, sheets: Int(ceil(Double(pages) / 2.0))))
        }
        data.paperSizeBreakdown = breakdown
        attestation = data
    }

    func applySheetMethodChange() {
        attestation.numberOfSheets = effectiveSheetCount
        attestation.sheetCountingMethod = sheetMethod
        var breakdown: [AttestationData.PaperSizeGroup] = []
        for (sizeClass, pages) in analysis.paperSizeSummary.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let sheets: Int
            switch sheetMethod {
            case .manual: sheets = manualSheetCount ?? Int(ceil(Double(pages) / 2.0))
            case .oneSheetPerPage: sheets = pages
            case .duplexEstimate: sheets = Int(ceil(Double(pages) / 2.0))
            }
            breakdown.append(.init(sizeClass: sizeClass, sheets: sheets))
        }
        attestation.paperSizeBreakdown = breakdown
    }

    func addSecurityElement(kind: SecurityElement.Kind, pageIndex: Int, rect: NormalizedRect) {
        let element = SecurityElement(
            kind: kind,
            pageIndex: pageIndex,
            boundingBox: rect,
            confidence: 1.0,
            verbalDescription: "",
            detectedByAI: false,
            reviewState: .pending)
        securityElements.append(enrich([element]).first!)
        touchReview()
        unmarkPageReviewed(pageIndex)
        selectedElementID = element.id
    }

    func confirmSecurityElement(id: UUID) {
        updateReviewState(id: id, state: .confirmed)
    }

    func rejectSecurityElement(id: UUID) {
        updateReviewState(id: id, state: .rejected)
    }

    func returnSecurityElementToReview(id: UUID) {
        updateReviewState(id: id, state: .pending)
    }

    func markPageReviewed(_ pageIndex: Int) {
        guard analysis.pageAnalyses.contains(where: { $0.pageIndex == pageIndex && !$0.isEmpty }) else {
            return
        }
        reviewedNonEmptyPages.insert(pageIndex)
        touchReview()
        recomputePreflight()
    }

    /// Marks the page reviewed and moves the preview to the next page that still
    /// needs a look, so a long document is one click per page.
    func markPageReviewedAndAdvance(_ pageIndex: Int) {
        markPageReviewed(pageIndex)
        let remaining = unconfirmedNonEmptyPages
        if let next = remaining.first(where: { $0 > pageIndex }) ?? remaining.first {
            previewPageIndex = next
        }
    }

    /// Confirms every pending finding on one page after the advocate checked
    /// them on the canvas. Rejection stays per element on purpose.
    func confirmAllPendingElements(onPage pageIndex: Int) {
        for element in securityElements where element.pageIndex == pageIndex && element.reviewState == .pending {
            confirmSecurityElement(id: element.id)
        }
    }

    func unmarkPageReviewed(_ pageIndex: Int) {
        reviewedNonEmptyPages.remove(pageIndex)
        touchReview()
        recomputePreflight()
    }

    private func updateReviewState(id: UUID, state: SecurityElementReviewState) {
        guard let index = securityElements.firstIndex(where: { $0.id == id }) else { return }
        securityElements[index].reviewState = state
        touchReview()
        recomputePreflight()
        recordReviewDecision(securityElements[index], state: state)
    }

    private func recordReviewDecision(_ element: SecurityElement, state: SecurityElementReviewState) {
        guard settings.learnFromReviews, let document, let documentData else { return }
        let recorder = bankRecorderFactory(exampleBank, detectorIdentifier)
        let doc = UncheckedSendable(document)
        // Writes for one element run strictly in decision order: each task waits for the
        // previous one, so a fast confirm followed by return-to-review cannot interleave.
        let previous = bankWriteTasks[element.id]
        let task = Task.detached(priority: .utility) { [weak self, recorder, doc, documentData, element] in
            _ = await previous?.value
            do {
                switch state {
                case .confirmed:
                    try await recorder.record(document: doc.value, documentData: documentData,
                                              element: element, label: .kind(element.kind))
                case .rejected:
                    try await recorder.record(document: doc.value, documentData: documentData,
                                              element: element, label: .negative)
                case .pending:
                    try await recorder.forget(elementID: element.id)
                }
            } catch {
                await MainActor.run { self?.showBankWarningOnce(error) }
            }
        }
        bankWriteTasks[element.id] = task
        Task { @MainActor [weak self] in
            _ = await task.value
            // Prune only if no newer write replaced this one.
            if let self, self.bankWriteTasks[element.id] == task { self.bankWriteTasks[element.id] = nil }
        }
    }

    private func showBankWarningOnce(_ error: Error) {
        guard !bankWarningShown else { return }
        bankWarningShown = true
        analysisWarning = "Lokálny dataset sa nepodarilo aktualizovať (\(error.localizedDescription)). Kontrola pokračuje."
    }

    /// Test hook: wait for outstanding bank writes.
    func waitForBankWrites() async {
        let tasks = Array(bankWriteTasks.values)
        for task in tasks { await task.value }
        bankWriteTasks = [:]
    }

    private func invalidateReview(for index: Int) {
        guard securityElements.indices.contains(index) else { return }
        securityElements[index].reviewState = .pending
        touchReview()
        recomputePreflight()
    }

    private func touchReview() {
        reviewUpdatedAt = Date()
    }

    @discardableResult
    func duplicateElement(id: UUID) -> UUID? {
        guard let source = securityElements.first(where: { $0.id == id }),
              let index = securityElements.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.detectedByAI = false
        copy.reviewState = .pending
        copy.boundingBox = ElementGeometry.moved(copy.boundingBox, center:
            NormalizedPoint(x: copy.boundingBox.midX + 0.04,
                            y: copy.boundingBox.midY + 0.06))
        securityElements.insert(copy, at: index + 1)
        unmarkPageReviewed(copy.pageIndex)
        selectedElementID = copy.id
        return copy.id
    }

    func removeSecurityElement(id: UUID) {
        if lastDeletedElement == nil, let removed = securityElements.first(where: { $0.id == id }) {
            lastDeletedElement = (removed, securityElements.firstIndex(where: { $0.id == id }) ?? 0)
        }
        securityElements.removeAll { $0.id == id }
        touchReview()
        recomputePreflight()
    }

    func undoDelete() {
        guard let (element, index) = lastDeletedElement else { return }
        var restored = element
        if !securityElements.contains(where: { $0.id == restored.id }) {
            let insertAt = min(index, securityElements.count)
            securityElements.insert(restored, at: insertAt)
            touchReview()
            unmarkPageReviewed(restored.pageIndex)
        }
        lastDeletedElement = nil
        recomputePreflight()
    }

    private func ensureSnapAssets() async -> Bool {
        if snapAssetsReady { return true }
        snapAssetProgress = 0
        defer { snapAssetProgress = nil }
        do {
            try await snapper.ensureAssets { fraction in
                Task { @MainActor in self.snapAssetProgress = fraction }
            }
            snapAssetsReady = true
            snapUnavailableReason = nil
            return true
        } catch {
            snapUnavailableReason = "Presný výber prvku nie je dostupný (model sa nepodarilo stiahnuť). Rámec nakreslite ručne."
            return false
        }
    }

    private func renderedPage(_ pageIndex: Int) -> CGImage? {
        guard let document, let page = document.page(at: pageIndex) else { return nil }
        return BuiltInVisionProvider.render(page: page, targetWidth: 1200)?.cgImage
    }

    /// Click without drag on a freshly placed element: segment at the point and
    /// tighten that element's box in place. On failure the placeholder stays so
    /// the advocate can adjust it by hand.
    @discardableResult
    func snapPlacedElement(id: UUID, at point: NormalizedPoint) async -> Bool {
        guard let element = securityElements.first(where: { $0.id == id }),
              await ensureSnapAssets(), let image = renderedPage(element.pageIndex) else { return false }
        let box = UncheckedSendableImage(image)
        guard let rect = try? await snapper.snap(pageImage: box.image, seed: point) else { return false }
        updateElementBoundingBox(id: id, boundingBox: rect)
        return true
    }

    func refineElement(id: UUID) async {
        guard let element = securityElements.first(where: { $0.id == id }),
              await ensureSnapAssets(), let image = renderedPage(element.pageIndex) else { return }
        let box = UncheckedSendableImage(image)
        guard let rect = try? await snapper.refine(pageImage: box.image, box: element.boundingBox) else { return }
        updateElementBoundingBox(id: id, boundingBox: rect)
    }

    func placeElement(kind: SecurityElement.Kind, at center: NormalizedPoint, pageIndex: Int? = nil) -> UUID {
        let targetPage = pageIndex ?? previewPageIndex
        let element = SecurityElement(
            kind: kind,
            pageIndex: targetPage,
            boundingBox: ElementGeometry.clampedCentered(center: center),
            confidence: 1.0,
            verbalDescription: "",
            detectedByAI: false,
            reviewState: .pending)
        securityElements.append(enrich([element]).first!)
        touchReview()
        unmarkPageReviewed(targetPage)
        selectedElementID = element.id
        return element.id
    }

    func drawElement(id: UUID, from anchor: NormalizedPoint, to corner: NormalizedPoint) {
        guard let index = securityElements.firstIndex(where: { $0.id == id }) else { return }
        securityElements[index].boundingBox = ElementGeometry.resized(from: anchor, to: corner)
        invalidateReview(for: index)
    }

    func moveElement(id: UUID, center: NormalizedPoint) {
        guard let index = securityElements.firstIndex(where: { $0.id == id }) else { return }
        securityElements[index].boundingBox =
            ElementGeometry.moved(securityElements[index].boundingBox, center: center)
        securityElements[index].verbalDescription = securityElements[index]
            .locationDescription(pageSizePt: .zero) + "."
        invalidateReview(for: index)
    }

    func elementID(at point: NormalizedPoint, pageIndex: Int) -> UUID? {
        ElementGeometry.hitTest(
            elements: securityElements.map { ($0.id, $0.pageIndex, $0.boundingBox) },
            point: point,
            pageIndex: pageIndex)
    }

    func isResizeHandle(_ id: UUID, at point: NormalizedPoint) -> Bool {
        guard let element = securityElements.first(where: { $0.id == id }) else { return false }
        return ElementGeometry.isInResizeHandle(element.boundingBox, point)
    }

    func updateElementPage(id: UUID, pageIndex: Int) {
        if let index = securityElements.firstIndex(where: { $0.id == id }) {
            securityElements[index].pageIndex = pageIndex
            securityElements[index].verbalDescription = securityElements[index]
                .locationDescription(pageSizePt: .zero) + "."
            invalidateReview(for: index)
        }
    }

    func updateElementKind(id: UUID, kind: SecurityElement.Kind) {
        if let index = securityElements.firstIndex(where: { $0.id == id }) {
            securityElements[index].kind = kind
            invalidateReview(for: index)
        }
    }

    func updateElementDescription(id: UUID, text: String) {
        if let index = securityElements.firstIndex(where: { $0.id == id }) {
            securityElements[index].verbalDescription = text
            invalidateReview(for: index)
        }
    }

    func updateElementBoundingBox(id: UUID, boundingBox: NormalizedRect) {
        guard let index = securityElements.firstIndex(where: { $0.id == id }) else { return }
        let clamped = NormalizedRect(
            x: min(max(boundingBox.x, 0), 1),
            y: min(max(boundingBox.y, 0), 1),
            width: min(max(boundingBox.width, 0.01), 1),
            height: min(max(boundingBox.height, 0.01), 1))
        securityElements[index].boundingBox = NormalizedRect(
            x: min(clamped.x, 1 - clamped.width),
            y: min(clamped.y, 1 - clamped.height),
            width: min(clamped.width, 1),
            height: min(clamped.height, 1))
    }

    func refreshIdentities() async {
        guard !isRefreshingIdentities else { return }
        isRefreshingIdentities = true
        defer { isRefreshingIdentities = false }

        identities = await signingProvider.availableIdentities()
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
        if !signingPIN.isEmpty, !hasResolvedCertificate {
            await resolveCertificateForAuthorization()
        }
    }

    var hasResolvedCertificate: Bool {
        signingProviderIsDemo || identities.contains {
            $0.id.hasPrefix(EngineBridgeSigningProvider.certificateIdentityPrefix)
        }
    }

    func resolveCertificateForAuthorization(force: Bool = false) async {
        guard !signingProviderIsDemo, !signingPIN.isEmpty, !isResolvingCertificate else { return }
        guard force || !hasResolvedCertificate else { return }
        guard force || lastCertificateLoadPIN != signingPIN else { return }

        let pin = signingPIN
        isResolvingCertificate = true
        lastCertificateLoadPIN = pin
        let resolved = await signingProvider.resolveIdentities(pin: pin)
        isResolvingCertificate = false

        guard !Task.isCancelled else { return }
        guard pin == signingPIN else {
            lastCertificateLoadPIN = nil
            guard !signingPIN.isEmpty else { return }
            await resolveCertificateForAuthorization(force: true)
            return
        }

        if let resolved, !resolved.isEmpty {
            identities = resolved
            selectedIdentityID = resolved.first(where: { $0.isMandateCertificate })?.id
                ?? resolved.first?.id
            certificateLoadError = nil
        } else {
            certificateLoadError = "Načítanie certifikátov z karty zlyhalo."
        }
    }

    /// Synthetic identita = typ certifikátu ešte nie je overený (čaká na PIN).
    var isCertificateTypePending: Bool {
        selectedIdentity?.id.hasPrefix("engine:") == true
    }

    var selectedIdentity: SigningIdentityInfo? {
        identities.first(where: { $0.id == selectedIdentityID })
    }

    var mandateRequirementSatisfied: Bool {
        guard let identity = selectedIdentity else { return false }
        return identity.isMandateCertificate && identity.isQualified && identity.hasPrivateKey
    }

    var requiresMandateOverride: Bool {
        guard !signingProviderIsDemo else { return !hasValidMandateOverride }
        if isCertificateTypePending { return false }
        return !mandateRequirementSatisfied && !hasValidMandateOverride
    }

    var hasValidMandateOverride: Bool {
        allowNonMandateOverride && mandateOverrideIdentityID == selectedIdentityID
    }

    func setMandateOverride(_ enabled: Bool) {
        allowNonMandateOverride = enabled
        mandateOverrideIdentityID = enabled ? selectedIdentityID : nil
        recomputePreflight()
    }

    var signingProviderIsDemo: Bool {
        signingProvider is DemoSigningProvider
    }

    func recomputePreflight() {
        let result = AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: selectedIdentityID != nil,
            mandateRequirementSatisfied: mandateRequirementSatisfied
                || hasValidMandateOverride
                || isCertificateTypePending,
            inputSignatureInspection: inputSignatureInspection,
            unreviewedNonEmptyPages: unreviewedNonEmptyPages)
        preflightErrors = result.errors
        validationErrors = result.errors
    }

    func preparePreflight() {
        evidenceNumberError = nil
        recomputePreflight()
    }

    func fetchEvidenceNumber() async {
        guard !fetchingEvidenceNumber else { return }
        let requestID = currentRecordID
        evidenceRequestID = requestID
        evidenceNumberError = nil
        fetchingEvidenceNumber = true
        defer {
            if evidenceRequestID == requestID {
                fetchingEvidenceNumber = false
                evidenceRequestID = nil
            }
        }
        do {
            let numbers = try await ezzkService.requestEvidenceNumbers(count: 1)
            guard requestID == currentRecordID, !Task.isCancelled else { return }
            guard let number = numbers.first else {
                throw EZZKError.invalidResponse
            }
            attestation.evidenceNumber = number
            evidenceNumberRequested = true
            lastError = nil
            evidenceNumberError = nil
            recomputePreflight()
        } catch {
            guard requestID == currentRecordID, !Task.isCancelled else { return }
            evidenceNumberError = error.localizedDescription
            lastError = error.localizedDescription
            recomputePreflight()
        }
    }

    func validate() -> [AttestationValidationError] {
        let stampTime: Date? = includeQualifiedTimestamp ? serverTimeUsed : nil
        let errors = AttestationValidator.validate(attestation,
                                                   securityElements: confirmedSecurityElements,
                                                   qualifiedTimestampTime: stampTime)
        let reviewResult = AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: selectedIdentityID != nil,
            mandateRequirementSatisfied: mandateRequirementSatisfied,
            inputSignatureInspection: inputSignatureInspection,
            unreviewedNonEmptyPages: unreviewedNonEmptyPages)
        let reviewErrors = reviewResult.errors.filter { !errors.contains($0) }
        let allErrors = errors + reviewErrors
        validationErrors = allErrors
        return allErrors
    }
    func authorizeAndSign(viaMobile: Bool = false) async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        isAuthorizingViaMobile = viaMobile
        defer {
            isAuthorizing = false
            isAuthorizingViaMobile = false
            analysisProgressText = ""
        }

        lastError = nil
        validationErrors = []
        preparePreflight()
        guard viaMobile ? isMobilePreflightComplete : isPreflightComplete else { return }
        let confirmedElementsSnapshot = confirmedSecurityElements
        let securityReviewSnapshot = securityReviewStamp

        do {
            analysisProgressText = "Zisťujem dôveryhodný čas…"
            let conversionTime = try await ezzkService.serverTime()
            serverTimeUsed = conversionTime
            attestation.conversionExecutionDateTime = conversionTime
            selectedFormPack = try formPackRepository.pack(
                for: .paperToElectronic,
                at: conversionTime,
                policy: .allowUnverifiedPilot)

            // § 3 vyhlášky č. 70/2021 Z. z.: formát listiny je povinnou náležitosťou doložky.
            // Ak klasifikácia analýzy nevyplnila rozpad (napr. netypická veľkosť strany),
            // doplň A4 na výšku s odhadom počtu listov, aby validácia neprepadla.
            if attestation.paperSizeBreakdown.isEmpty {
                attestation.paperSizeBreakdown = [AttestationData.PaperSizeGroup(
                    sizeClass: .a4Portrait,
                    sheets: max(effectiveSheetCount, 1))]
            }
            let errors = validate()
            guard errors.isEmpty else {
                analysisProgressText = ""
                return
            }

            analysisProgressText = "Konvertujem do PDF/A…"
            guard let document else { throw PDFAError.emptyDocument }
            let pdfaData = try pdfaConverter.convert(document: document,
                                                     profile: selectedFormPack.outputProfile,
                                                     mode: settings.pdfaMode,
                                                     title: attestation.newDocumentName)

            let fingerprint = AttestationClauseGenerator.sha256Hex(of: pdfaData)
            let xmlInput = AttestationClauseGenerator.Input(
                attestation: attestation,
                securityElements: confirmedElementsSnapshot,
                newDocumentFingerprintSHA256Hex: fingerprint)
            let xml = try clauseGenerator.generateXML(input: xmlInput,
                                                      formPack: selectedFormPack)

            let xmlIssues = AttestationXMLValidator().validate(
                xml,
                context: .init(fingerprintSHA256Hex: fingerprint,
                               securityElementCount: confirmedElementsSnapshot.count),
                formPack: selectedFormPack)
            guard xmlIssues.isEmpty else {
                throw ComplianceValidationError(domain: "Osvedčovacia doložka", issues: xmlIssues)
            }

            analysisProgressText = "Vkladám XML doložku do dokumentu…"
            var finalPDF = try embeddedFileService.embed(
                .init(fileName: "osvedcovacia-dolozka.xml",
                      mimeType: "application/xml",
                      data: Data(xml.utf8)),
                into: pdfaData)

            // Normalize once more after adding the XML attachment. PDFBox
            // writes a fresh page tree and preserves the attachment name tree,
            // which is the artifact external validators actually inspect.
            finalPDF = try pdfaConverter.normalizeForDelivery(
                finalPDF,
                title: attestation.newDocumentName)

            // Validate the actual artifact that will be signed and written. The
            // XML attachment is part of the final PDF/A deliverable, so checking
            // only the pre-attachment bytes can produce a false green result.
            let pdfaCheck = PDFAValidator().validate(finalPDF,
                                                     profile: selectedFormPack.outputProfile)
            guard pdfaCheck.isValid else {
                throw ComplianceValidationError(domain: "PDF/A-2b", issues: pdfaCheck.issues)
            }

            analysisProgressText = viaMobile ? "Čakám na podpis z mobilu…" : "Autorizujem kvalifikovaným podpisom…"
            if !viaMobile, isCertificateTypePending {
                analysisProgressText = "Overujem certifikát na karte…"
                let resolved = await signingProvider.resolveIdentities(pin: signingPIN)
                guard let resolved, !resolved.isEmpty else {
                    throw SigningError.identityUnavailable
                }
                identities = resolved
                selectedIdentityID = resolved.first(where: { $0.isMandateCertificate })?.id
                    ?? resolved.first?.id
            }
            if !viaMobile, requiresMandateOverride {
                lastError = "Zvolený certifikát nie je mandátnym certifikátom pre zaručenú konverziu. Pokračovanie je možné len s výslovným override (audit záznam)."
                return
            }
            if includeQualifiedTimestamp,
               settings.selectedTSAURL.trimmingCharacters(in: .whitespaces).isEmpty {
                throw SigningError.timestampFailed
            }

            let directory = ConversionOutputNaming.outputDirectory(
                sourceURL: sourceURL,
                preferredDirectory: outputDirectoryOverride,
                fallback: Self.outputDirectoryURL())
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let packager = ASiCEPackager()
            let docFileName = ConversionOutputNaming.deliveryPDFFileName(
                in: directory,
                preferredName: outputPDFFileName())
            let preferredXDCFFileName = ConversionOutputNaming.xdcfFileName(
                originalDocumentName: attestation.originalDocumentName,
                pdfFileName: docFileName,
                evidenceNumber: attestation.evidenceNumber)
            let xdcfTarget = ConversionOutputNaming.uniqueURL(in: directory,
                                                              fileName: preferredXDCFFileName)
            let xdcfFileName = xdcfTarget.lastPathComponent
            let containerFiles = packager.zakoContainer(pdfData: finalPDF,
                                                        pdfFileName: docFileName,
                                                        dolozkaXML: Data(xml.utf8),
                                                        dolozkaFileName: xdcfFileName)
            let signed: SignedConversionResult
            if viaMobile {
                // The unsigned container goes to the AVM server; the phone signs every file in it.
                let containerData = try packager.package(files: containerFiles)
                let upload = AVMUploadRequest(
                    filename: ConversionOutputNaming.asicFileName(pdfFileName: docFileName),
                    data: containerData,
                    mimeType: AVMUploadRequest.asicEMimeType,
                    level: .xades(timestamp: includeQualifiedTimestamp))
                let document = try await mobileSigning.sign(upload)
                guard AVMResultMapper.isMandate(signers: document.signers ?? []) else {
                    lastError = Self.mobileMandateRefusalMessage
                    return
                }
                signed = try AVMResultMapper.conversionResult(from: document,
                                                              outputFormat: .attachedASIC,
                                                              uploadedPDF: finalPDF)
            } else {
                guard let identityID = selectedIdentityID else {
                    throw SigningError.identityUnavailable
                }
                signed = try await signingProvider.sign(SigningRequest(
                    pdfData: finalPDF,
                    identityID: identityID,
                    includeTimestamp: includeQualifiedTimestamp,
                    tsaURL: includeQualifiedTimestamp ? settings.selectedTSAURL : nil,
                    pin: signingPIN.isEmpty ? nil : signingPIN,
                    extraFiles: containerFiles))
            }

            if let asic = signed.asicData {
                let containerCheck = ASiCEContainerVerifier().verify(asic)
                guard containerCheck.isValid else {
                    throw ComplianceValidationError(domain: "ASiC-E kontajner",
                                                    issues: containerCheck.issues)
                }
            }

            analysisProgressText = "Ukladám a zapisujem do evidencie…"
            let pdfTarget = directory.appendingPathComponent(docFileName)
            try signed.pdfData.write(to: pdfTarget, options: [.atomic])
            try Data(xml.utf8).write(to: xdcfTarget, options: [.atomic])
            if let asic = signed.asicData {
                let asicFileName = ConversionOutputNaming.asicFileName(pdfFileName: pdfTarget.lastPathComponent)
                let asicTarget = ConversionOutputNaming.uniqueURL(in: directory,
                                                                   fileName: asicFileName)
                try asic.write(to: asicTarget,
                               options: [.atomic])
            }
            outputDirectory = directory

            let record = EvidenceRecord(
                id: currentRecordID,
                status: .signed,
                direction: .paperToElectronic,
                originalName: attestation.originalDocumentName,
                newDocumentName: attestation.newDocumentName,
                evidenceNumber: attestation.evidenceNumber,
                fingerprintSHA256Hex: fingerprint,
                attestationXML: xml,
                conversionTime: conversionTime,
                performingPersonName: attestation.performingPerson.fullName,
                securityElementCount: confirmedElementsSnapshot.count,
                totalPages: analysis.totalPages,
                totalSheets: attestation.numberOfSheets,
                pdfFileName: pdfTarget.lastPathComponent,
                formPack: FormPackStamp(pack: selectedFormPack),
                securityReview: securityReviewSnapshot)
            evidenceStore.upsert(record)

            let envelope = ConversionRecordEnvelope(
                evidenceNumber: attestation.evidenceNumber ?? "",
                direction: .paperToElectronic,
                originalName: attestation.originalDocumentName,
                newDocumentName: attestation.newDocumentName,
                attestationXML: xml,
                fingerprintSHA256Hex: fingerprint,
                conversionTime: conversionTime,
                formPack: FormPackStamp(pack: selectedFormPack),
                securityReview: securityReviewSnapshot)
            do {
                try await ezzkService.submit(envelope)
                if settingsStore.ezzkSessionController.isDemoMode {
                    var queued = record
                    queued.status = .queuedForSubmission
                    queued.updatedAt = Date()
                    evidenceStore.upsert(queued)
                    submissionStatus = .queuedForSubmission
                } else {
                    var updated = record
                    updated.status = .submitted
                    updated.updatedAt = Date()
                    evidenceStore.upsert(updated)
                    submissionStatus = .submitted
                }
            } catch {
                var queued = record
                queued.status = .queuedForSubmission
                queued.updatedAt = Date()
                evidenceStore.upsert(queued)
                submissionStatus = .queuedForSubmission
            }

            result = signed
            step = .done
        } catch {
            if let avmError = error as? AVMError, avmError == .cancelled {
                return
            }
            lastError = error.localizedDescription
        }
    }

    func retryQueuedSubmission() async {
        guard let record = evidenceStore.record(id: currentRecordID),
              record.status != .submitted else { return }
        do {
            try await ezzkService.submit(record.envelope())
            if settingsStore.ezzkSessionController.isDemoMode {
                var queued = record
                queued.status = .queuedForSubmission
                queued.updatedAt = Date()
                evidenceStore.upsert(queued)
                submissionStatus = .queuedForSubmission
            } else {
                var updated = record
                updated.status = .submitted
                updated.updatedAt = Date()
                evidenceStore.upsert(updated)
                submissionStatus = .submitted
            }
            lastError = nil
        } catch {
            var queued = record
            queued.status = .queuedForSubmission
            queued.updatedAt = Date()
            evidenceStore.upsert(queued)
            submissionStatus = .queuedForSubmission
            lastError = error.localizedDescription
        }
    }

    func saveTemplate() {
        let url = Self.templatesDirectory().appendingPathComponent("\(sanitizedBaseName()).zako-template.json")
        do {
            let data = try JSONEncoder.pretty.encode(attestation)
            try data.write(to: url, options: [.atomic])
        } catch {
            lastError = "Šablónu sa nepodarilo uložiť: \(error.localizedDescription)"
        }
    }

    func loadLatestTemplate() {
        let directory = Self.templatesDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: [.contentModificationDateKey]),
              let latest = files.filter({ $0.pathExtension == "json" })
                  .sorted(by: { lhs, rhs in
                      let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                      let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                      return l > r
                  }).first,
              let data = try? Data(contentsOf: latest),
              let template = try? JSONDecoder.standard.decode(AttestationData.self, from: data) else {
            return
        }
        attestation = template
        attestation.originConfirmed = false
        attestation.evidenceNumber = nil
        evidenceNumberRequested = false
        evidenceNumberError = nil
        preflightErrors = []
    }

    func saveProfileFromForm() {
        let profile = attestation.performingPerson
        profilePersister?(profile)
    }

    func activeProfile() -> AdvocateProfile {
        if let id = settings.activeProfileID,
           let profile = settings.profiles.first(where: { $0.id == id }) {
            return profile
        }
        return settings.profiles.first ?? .empty
    }

    var unconfirmedNonEmptyPages: [Int] {
        analysis.pageAnalyses
            .filter { !$0.isEmpty && !reviewedNonEmptyPages.contains($0.pageIndex) }
            .map(\.pageIndex)
    }

func resetSession(keepingProfile: Bool) {
        if sourceAccessIsActive, let sourceURL {
            sourceURL.stopAccessingSecurityScopedResource()
            sourceAccessIsActive = false
        }
        let profile = keepingProfile ? attestation.performingPerson : AdvocateProfile.empty
        step = .intake
        sourceURL = nil
        document = nil
        documentData = nil
        analysis = .empty()
        securityElements = []
        reviewedNonEmptyPages = []
        activeTool = nil
        previewPageIndex = 0
        lastDeletedElement = nil
        selectedElementID = nil
        attestation = AttestationData(performingPerson: profile)
        sheetMethod = .duplexEstimate
        manualSheetCount = nil
        identities = []
        selectedIdentityID = nil
        signingPIN = ""
        allowNonMandateOverride = false
        mandateOverrideIdentityID = nil
        evidenceNumberRequested = false
        evidenceNumberError = nil
        fetchingEvidenceNumber = false
        evidenceRequestID = nil
        isAuthorizing = false
        isAnalyzing = false
        analysisProgressText = ""
        preflightErrors = []
        validationErrors = []
        submissionStatus = nil
        result = nil
        outputDirectory = nil
        outputDirectoryOverride = nil
        sourceNameOverride = nil
        lastError = nil
        analysisWarning = nil
        serverTimeUsed = nil
        inputSignatureInspection = .unavailable(
            detail: "Kontrola podpisov ešte neprebehla.")
        reviewUpdatedAt = nil
        currentRecordID = UUID()
    }

    private func sanitizedBaseName() -> String {
        let raw = attestation.newDocumentName.isEmpty
            ? attestation.originalDocumentName
            : attestation.newDocumentName
        let cleaned = ASiCEPackager.sanitizedFileName(raw)
        return cleaned.isEmpty ? "konverzia" : cleaned
    }

    func outputPDFFileName() -> String {
        ConversionOutputNaming.pdfFileName(
            originalDocumentName: sourceNameOverride
                ?? sourceURL?.deletingPathExtension().lastPathComponent
                ?? attestation.originalDocumentName,
            requestedDocumentName: attestation.newDocumentName)
    }

    static func outputDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Autogram/Output", isDirectory: true)
    }

    static func templatesDirectory() -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Autogram/Templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Placeholder used only to compute the default identifier before the first analysis.
private struct NoOpClassifier: ElementClassifying {
    func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement { .unsure }
}
