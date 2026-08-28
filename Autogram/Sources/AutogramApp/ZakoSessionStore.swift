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
    var analysis: DocumentAnalysis = .empty()
    var securityElements: [SecurityElement] = []
    var attestation = AttestationData()
    var sheetMethod: SheetCountingMethod = .duplexEstimate
    var manualSheetCount: Int?

    var isAnalyzing = false
    var analysisProgressText = ""

    var identities: [SigningIdentityInfo] = []
    var selectedIdentityID: String?
    var includeQualifiedTimestamp = true
    var allowNonMandateOverride = false
    var signingPIN = ""
    var evidenceNumberRequested = false
    var fetchingEvidenceNumber = false
    var evidenceNumberError: String?
    var isAuthorizing = false

    var activeTool: SecurityElement.Kind?
    var previewPageIndex: Int = 0
    var lastDeletedElement: (SecurityElement, Int)?
    var selectedElementID: UUID?

    var validationErrors: [AttestationValidationError] = []
    var preflightErrors: [AttestationValidationError] = []
    var result: SignedConversionResult?
    var submissionStatus: EvidenceRecord.Status?
    var outputDirectory: URL?
    var lastError: String?
    var serverTimeUsed: Date?

    var isPreflightComplete: Bool {
        let result = AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: selectedIdentityID != nil,
            mandateRequirementSatisfied: mandateRequirementSatisfied
                || allowNonMandateOverride
                || isCertificateTypePending)
        return result.isComplete && preflightErrors.isEmpty && evidenceNumberError == nil
    }
    var hasUnresolvedPreflightErrors: Bool {
        !AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: selectedIdentityID != nil,
            mandateRequirementSatisfied: mandateRequirementSatisfied
        ).errors.isEmpty || evidenceNumberError != nil
    }

    let settingsStore: AppSettingsStore
    var settings: AppSettings { settingsStore.settings }
    let analysisEngine: PDFAnalysisEngine
    let detectionPipeline: DetectionPipeline
    let pdfaConverter: PDFAConverter
    let clauseGenerator: AttestationClauseGenerator
    let embeddedFileService: EmbeddedFileService
    var ezzkService: any EZZKServicing { settingsStore.ezzkService }
    var signingProvider: any QualifiedSigningProviding { settingsStore.signingProvider }
    var evidenceStore: LocalEvidenceStore { settingsStore.evidenceStore }

    private var evidenceRequestID: UUID?
    var profilePersister: ((AdvocateProfile) -> Void)?
    private(set) var currentRecordID = UUID()

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        self.analysisEngine = PDFAnalysisEngine()
        self.detectionPipeline = Self.buildPipeline(settings: settingsStore.settings)
        self.pdfaConverter = PDFAConverter()
        self.clauseGenerator = AttestationClauseGenerator()
        self.embeddedFileService = EmbeddedFileService()
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

    static func buildPipeline(settings: AppSettings) -> DetectionPipeline {
        let llmProvider: (any SecurityElementsProviding)?
        switch settings.aiMode {
        case .omlxLocal:
            llmProvider = OpenAIVisionProvider(
                baseURL: URL(string: settings.omlxURL) ?? URL(string: "http://localhost:8000/v1")!,
                model: settings.omlxModel,
                apiKey: "",
                promptOverride: settings.aiPrompt)
        case .ollamaLocal:
            llmProvider = OllamaVisionProvider(
                endpoint: URL(string: settings.ollamaURL) ?? URL(string: "http://localhost:11434")!,
                model: settings.ollamaModel,
                promptOverride: settings.aiPrompt)
        case .customAPIKey:
            if let apiKey = KeychainStore.load(account: "ai.apikey"), !apiKey.isEmpty {
                llmProvider = OpenAIVisionProvider(
                    baseURL: URL(string: settings.openAICompatibleBaseURL)
                        ?? URL(string: "https://api.openai.com/v1")!,
                    model: settings.openAICompatibleModel,
                    apiKey: apiKey,
                    promptOverride: settings.aiPrompt)
            } else {
                llmProvider = nil
            }
        case .builtInOnDevice, .disabled:
            llmProvider = nil
        }
        return DetectionPipeline(builtin: BuiltInVisionProvider(), llmProvider: llmProvider)
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

    func loadDocument(at url: URL) async {
        lastError = nil
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            lastError = "Súbor sa nepodarilo otvoriť ako PDF."
            return
        }
        resetSession(keepingProfile: true)
        self.document = document
        self.sourceURL = url
        step = .analysis
        await runAnalysis()
    }

    func runAnalysis() async {
        guard let document else { return }
        isAnalyzing = true
        analysisProgressText = "Analyzujem stránky…"
        let doc = UncheckedSendable(document)
        let baseAnalysis = await Task.detached(priority: .userInitiated) {
            let engine = PDFAnalysisEngine()
            return engine.analyze(document: doc.value)
        }.value ?? .empty()

        analysisProgressText = "Detegujem bezpečnostné prvky…"
        let pipeline = detectionPipeline
        let detected = await Task.detached(priority: .userInitiated) { [doc, pipeline] in
            await pipeline.detect(in: doc.value, pageAnalyses: baseAnalysis.pageAnalyses)
        }.value

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
        sheetMethod = .duplexEstimate
        manualSheetCount = nil
        prepareAttestationPrefill()
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
        data.originalDocumentName = sourceURL?.deletingPathExtension().lastPathComponent
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
            detectedByAI: false)
        securityElements.append(enrich([element]).first!)
        selectedElementID = element.id
    }

    @discardableResult
    func duplicateElement(id: UUID) -> UUID? {
        guard let source = securityElements.first(where: { $0.id == id }),
              let index = securityElements.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.detectedByAI = false
        copy.boundingBox = ElementGeometry.moved(copy.boundingBox, center:
            NormalizedPoint(x: copy.boundingBox.midX + 0.04,
                            y: copy.boundingBox.midY + 0.06))
        securityElements.insert(copy, at: index + 1)
        selectedElementID = copy.id
        return copy.id
    }

    func removeSecurityElement(id: UUID) {
        if lastDeletedElement == nil, let removed = securityElements.first(where: { $0.id == id }) {
            lastDeletedElement = (removed, securityElements.firstIndex(where: { $0.id == id }) ?? 0)
        }
        securityElements.removeAll { $0.id == id }
    }

    func undoDelete() {
        guard let (element, index) = lastDeletedElement else { return }
        var restored = element
        if !securityElements.contains(where: { $0.id == restored.id }) {
            let insertAt = min(index, securityElements.count)
            securityElements.insert(restored, at: insertAt)
        }
        lastDeletedElement = nil
    }

    func placeElement(kind: SecurityElement.Kind, at center: NormalizedPoint, pageIndex: Int? = nil) -> UUID {
        let targetPage = pageIndex ?? previewPageIndex
        let element = SecurityElement(
            kind: kind,
            pageIndex: targetPage,
            boundingBox: ElementGeometry.clampedCentered(center: center),
            confidence: 1.0,
            verbalDescription: "",
            detectedByAI: false)
        securityElements.append(enrich([element]).first!)
        selectedElementID = element.id
        return element.id
    }

    func drawElement(id: UUID, from anchor: NormalizedPoint, to corner: NormalizedPoint) {
        guard let index = securityElements.firstIndex(where: { $0.id == id }) else { return }
        securityElements[index].boundingBox = ElementGeometry.resized(from: anchor, to: corner)
    }

    func moveElement(id: UUID, center: NormalizedPoint) {
        guard let index = securityElements.firstIndex(where: { $0.id == id }) else { return }
        securityElements[index].boundingBox =
            ElementGeometry.moved(securityElements[index].boundingBox, center: center)
        securityElements[index].verbalDescription = securityElements[index]
            .locationDescription(pageSizePt: .zero) + "."
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
        }
    }

    func updateElementKind(id: UUID, kind: SecurityElement.Kind) {
        if let index = securityElements.firstIndex(where: { $0.id == id }) {
            securityElements[index].kind = kind
        }
    }

    func updateElementDescription(id: UUID, text: String) {
        if let index = securityElements.firstIndex(where: { $0.id == id }) {
            securityElements[index].verbalDescription = text
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
        identities = await signingProvider.availableIdentities()
        if identities.isEmpty {
            if !signingPIN.isEmpty { signingPIN = "" }
            selectedIdentityID = nil
            return
        }
        if selectedIdentityID == nil || !identities.contains(where: { $0.id == selectedIdentityID }) {
            selectedIdentityID = identities.first(where: { $0.isMandateCertificate })?.id
                ?? identities.first?.id
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
        guard !signingProviderIsDemo else { return !allowNonMandateOverride }
        if isCertificateTypePending { return false }
        return !mandateRequirementSatisfied && !allowNonMandateOverride
    }

    var signingProviderIsDemo: Bool {
        signingProvider is DemoSigningProvider
    }

    func recomputePreflight() {
        let result = AttestationPreflight.evaluate(
            attestation,
            securityElements: securityElements,
            hasSelectedIdentity: selectedIdentityID != nil,
            mandateRequirementSatisfied: mandateRequirementSatisfied)
        preflightErrors = result.errors
        validationErrors = result.errors
    }

    func preparePreflight() async {
        evidenceNumberError = nil
        if attestation.evidenceNumber?.trimmingCharacters(in: .whitespaces).isEmpty != false {
            await fetchEvidenceNumber()
        }
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
                                                   securityElements: securityElements,
                                                   qualifiedTimestampTime: stampTime)
        validationErrors = errors
        return errors
    }
    func authorizeAndSign() async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        defer {
            isAuthorizing = false
            analysisProgressText = ""
        }

        lastError = nil
        validationErrors = []
        await preparePreflight()
        guard isPreflightComplete else { return }

        do {
            analysisProgressText = "Zisťujem dôveryhodný čas…"
            let conversionTime = try await ezzkService.serverTime()
            serverTimeUsed = conversionTime
            attestation.conversionExecutionDateTime = conversionTime

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
                                                     mode: settings.pdfaMode,
                                                     title: attestation.newDocumentName)

            let pdfaCheck = PDFAValidator().validate(pdfaData)
            guard pdfaCheck.isValid else {
                throw ComplianceValidationError(domain: "PDF/A-2b", issues: pdfaCheck.issues)
            }

            let fingerprint = AttestationClauseGenerator.sha256Hex(of: pdfaData)
            let xmlInput = AttestationClauseGenerator.Input(
                attestation: attestation,
                securityElements: securityElements,
                newDocumentFingerprintSHA256Hex: fingerprint)
            let xml = clauseGenerator.generateXML(input: xmlInput)

            let xmlIssues = AttestationXMLValidator().validate(
                xml,
                context: .init(fingerprintSHA256Hex: fingerprint,
                               securityElementCount: securityElements.count))
            guard xmlIssues.isEmpty else {
                throw ComplianceValidationError(domain: "Osvedčovacia doložka", issues: xmlIssues)
            }

            analysisProgressText = "Vkladám XML doložku do dokumentu…"
            let finalPDF = try embeddedFileService.embed(
                .init(fileName: "osvedcovacia-dolozka.xml",
                      mimeType: "application#2Fxml",
                      data: Data(xml.utf8)),
                into: pdfaData)

            analysisProgressText = "Autorizujem kvalifikovaným podpisom…"
            if isCertificateTypePending {
                analysisProgressText = "Overujem certifikát na karte…"
                let resolved = await signingProvider.resolveIdentities(pin: signingPIN)
                guard let resolved, !resolved.isEmpty else {
                    throw SigningError.identityUnavailable
                }
                identities = resolved
                selectedIdentityID = resolved.first(where: { $0.isMandateCertificate })?.id
                    ?? resolved.first?.id
            }
            guard let identityID = selectedIdentityID else {
                throw SigningError.identityUnavailable
            }
            if requiresMandateOverride {
                lastError = "Zvolený certifikát nie je mandátnym certifikátom pre zaručenú konverziu. Pokračovanie je možné len s výslovným override (audit záznam)."
                return
            }
            if includeQualifiedTimestamp,
               settings.selectedTSAURL.trimmingCharacters(in: .whitespaces).isEmpty {
                throw SigningError.timestampFailed
            }
            let packager = ASiCEPackager()
            let docFileName = outputPDFFileName()
            let xdcfFileName = Self.outputXDCFFileName(evidenceNumber: attestation.evidenceNumber,
                                                       fallbackDocBase: docFileName)
            let containerFiles = packager.zakoContainer(pdfData: finalPDF,
                                                        pdfFileName: docFileName,
                                                        dolozkaXML: Data(xml.utf8),
                                                        dolozkaFileName: xdcfFileName)
            let signed = try await signingProvider.sign(SigningRequest(
                pdfData: finalPDF,
                identityID: identityID,
                includeTimestamp: includeQualifiedTimestamp,
                tsaURL: includeQualifiedTimestamp ? settings.selectedTSAURL : nil,
                pin: signingPIN.isEmpty ? nil : signingPIN,
                extraFiles: containerFiles))

            if let asic = signed.asicData {
                let containerCheck = ASiCEContainerVerifier().verify(asic)
                guard containerCheck.isValid else {
                    throw ComplianceValidationError(domain: "ASiC-E kontajner",
                                                    issues: containerCheck.issues)
                }
            }

            analysisProgressText = "Ukladám a zapisujem do evidencie…"
            let directory = Self.outputDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let pdfTarget = directory.appendingPathComponent(docFileName)
            try signed.pdfData.write(to: pdfTarget, options: [.atomic])
            let xmlTarget = directory.appendingPathComponent(xdcfFileName)
            try Data(xml.utf8).write(to: xmlTarget, options: [.atomic])
            if let asic = signed.asicData {
                try asic.write(to: directory.appendingPathComponent("\(xdcfFileName).asice"),
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
                securityElementCount: securityElements.count,
                totalPages: analysis.totalPages,
                totalSheets: attestation.numberOfSheets,
                pdfFileName: pdfTarget.lastPathComponent)
            evidenceStore.upsert(record)

            let envelope = ConversionRecordEnvelope(
                evidenceNumber: attestation.evidenceNumber ?? "",
                direction: .paperToElectronic,
                originalName: attestation.originalDocumentName,
                newDocumentName: attestation.newDocumentName,
                attestationXML: xml,
                fingerprintSHA256Hex: fingerprint,
                conversionTime: conversionTime)
            do {
                try await ezzkService.submit(envelope)
                var updated = record
                updated.status = .submitted
                updated.updatedAt = Date()
                evidenceStore.upsert(updated)
                submissionStatus = .submitted
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
            lastError = error.localizedDescription
        }
    }

    func retryQueuedSubmission() async {
        guard let record = evidenceStore.record(id: currentRecordID),
              record.status != .submitted else { return }
        do {
            try await ezzkService.submit(record.envelope())
            var updated = record
            updated.status = .submitted
            updated.updatedAt = Date()
            evidenceStore.upsert(updated)
            submissionStatus = .submitted
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
        if let data = try? JSONEncoder.pretty.encode(attestation) {
            try? data.write(to: url, options: [.atomic])
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
        analysis.pageAnalyses.filter { page in
            !page.isEmpty &&
            !securityElements.contains(where: { $0.pageIndex == page.pageIndex })
        }.map(\.pageIndex)
    }

func resetSession(keepingProfile: Bool) {
        let profile = keepingProfile ? attestation.performingPerson : AdvocateProfile.empty
        step = .intake
        sourceURL = nil
        document = nil
        analysis = .empty()
        securityElements = []
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
        evidenceNumberRequested = false
        evidenceNumberError = nil
        fetchingEvidenceNumber = false
        evidenceRequestID = nil
        isAuthorizing = false
        preflightErrors = []
        validationErrors = []
        submissionStatus = nil
        result = nil
        outputDirectory = nil
        lastError = nil
        serverTimeUsed = nil
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
        var base = sanitizedBaseName()
        if (base as NSString).pathExtension.lowercased() == "pdf" {
            base = (base as NSString).deletingPathExtension
        }
        return "\(base).pdf"
    }

    static func outputXDCFFileName(evidenceNumber: String?, fallbackDocBase: String) -> String {
        let cleanedEvidence = evidenceNumber.map { ASiCEPackager.sanitizedFileName($0) } ?? ""
        if !cleanedEvidence.isEmpty {
            return "\(cleanedEvidence).xml.xdcf"
        }
        return "\((fallbackDocBase as NSString).deletingPathExtension)-dolozka.xml.xdcf"
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
