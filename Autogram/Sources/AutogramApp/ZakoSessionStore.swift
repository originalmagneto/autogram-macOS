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
    var evidenceNumberRequested = false
    var fetchingEvidenceNumber = false

    var validationErrors: [AttestationValidationError] = []
    var result: SignedConversionResult?
    var outputDirectory: URL?
    var lastError: String?
    var serverTimeUsed: Date?

    let settings: AppSettings
    let analysisEngine: PDFAnalysisEngine
    let detectionPipeline: DetectionPipeline
    let pdfaConverter: PDFAConverter
    let clauseGenerator: AttestationClauseGenerator
    let embeddedFileService: EmbeddedFileService
    let clauseRenderer: ClausePDFRenderer
    let ezzkService: any EZZKServicing
    let signingProvider: any QualifiedSigningProviding
    let evidenceStore: LocalEvidenceStore

    private(set) var currentRecordID = UUID()

    init(settings: AppSettings,
         ezzkService: any EZZKServicing,
         signingProvider: any QualifiedSigningProviding,
         evidenceStore: LocalEvidenceStore) {
        self.settings = settings
        self.analysisEngine = PDFAnalysisEngine()
        self.detectionPipeline = DetectionPipeline(builtin: BuiltInVisionProvider())
        self.pdfaConverter = PDFAConverter()
        self.clauseGenerator = AttestationClauseGenerator()
        self.embeddedFileService = EmbeddedFileService()
        self.clauseRenderer = ClausePDFRenderer()
        self.ezzkService = ezzkService
        self.signingProvider = signingProvider
        self.evidenceStore = evidenceStore
        self.currentRecordID = UUID()
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
        let engine = analysisEngine
        let baseAnalysis = await Task.detached(priority: .userInitiated) {
            engine.analyze(document: document)
        }.value

        analysisProgressText = "Detegujem bezpečnostné prvky…"
        let pipeline = detectionPipeline
        let elements = await Task.detached(priority: .userInitiated) {
            await pipeline.detect(in: document, pageAnalyses: baseAnalysis.pageAnalyses)
        }.value

        analysis = DocumentAnalysis(
            totalPages: baseAnalysis.totalPages,
            nonEmptyPages: baseAnalysis.nonEmptyPages,
            estimatedSheetsDuplex: baseAnalysis.estimatedSheetsDuplex,
            pageAnalyses: baseAnalysis.pageAnalyses,
            securityElements: elements,
            suggestedTitle: baseAnalysis.suggestedTitle,
            analyzedAt: Date())
        securityElements = enrich(elements)
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
        data.newDocumentName = (data.originalDocumentName.isEmpty ? "dokument" : data.originalDocumentName)
        data.numberOfSheets = effectiveSheetCount
        data.sheetCountingMethod = sheetMethod
        data.nonEmptyPageCount = analysis.nonEmptyPages
        data.originalDocumentTypeLabel = "Iný dokument"
        data.newDocumentFormatLabel = "PDF"
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
    }

    func removeSecurityElement(id: UUID) {
        securityElements.removeAll { $0.id == id }
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

    func refreshIdentities() async {
        identities = await signingProvider.availableIdentities()
        if selectedIdentityID == nil || !identities.contains(where: { $0.id == selectedIdentityID }) {
            selectedIdentityID = identities.first(where: { $0.isMandateCertificate })?.id
                ?? identities.first?.id
        }
    }

    func fetchEvidenceNumber() async {
        guard !fetchingEvidenceNumber else { return }
        fetchingEvidenceNumber = true
        defer { fetchingEvidenceNumber = false }
        do {
            let numbers = try await ezzkService.requestEvidenceNumbers(count: 1)
            guard let number = numbers.first else {
                throw EZZKError.invalidResponse
            }
            attestation.evidenceNumber = number
            evidenceNumberRequested = true
        } catch {
            lastError = error.localizedDescription
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
        lastError = nil
        validationErrors = []

        do {
            analysisProgressText = "Zisťujem dôveryhodný čas…"
            let conversionTime = try await ezzkService.serverTime()
            serverTimeUsed = conversionTime
            attestation.conversionExecutionDateTime = conversionTime

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

            analysisProgressText = "Pripájam osvedčovaciu doložku…"
            let withClausePage = Self.appendClausePage(to: pdfaData, using: clauseRenderer,
                                                       attestation: attestation,
                                                       elements: securityElements)

            let fingerprint = AttestationClauseGenerator.sha256Hex(of: withClausePage)
            let xmlInput = AttestationClauseGenerator.Input(
                attestation: attestation,
                securityElements: securityElements,
                newDocumentFingerprintSHA256Hex: fingerprint,
                qualifiedTimestampTime: nil)
            let xml = clauseGenerator.generateXML(input: xmlInput)

            analysisProgressText = "Vkladám XML doložku do dokumentu…"
            let finalPDF = try embeddedFileService.embed(
                .init(fileName: "osvedcovacia-dolozka.xml",
                      mimeType: "text+xml",
                      data: Data(xml.utf8)),
                into: withClausePage)

            analysisProgressText = "Autorizujem kvalifikovaným podpisom…"
            guard let identityID = selectedIdentityID else {
                throw SigningError.identityUnavailable
            }
            let signed = try await signingProvider.sign(pdf: finalPDF,
                                                        identityID: identityID,
                                                        includeTimestamp: includeQualifiedTimestamp)

            analysisProgressText = "Ukladám a zapisujem do evidencie…"
            let directory = Self.outputDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let baseName = sanitizedBaseName()
            let pdfTarget = directory.appendingPathComponent("\(baseName)-pdfa.pdf")
            try signed.pdfData.write(to: pdfTarget, options: [.atomic])
            let xmlTarget = directory.appendingPathComponent("\(baseName)-dolozka.xml")
            try Data(xml.utf8).write(to: xmlTarget, options: [.atomic])
            if let asic = signed.asicData {
                try asic.write(to: directory.appendingPathComponent("\(baseName).asice"),
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
            } catch {
                var queued = record
                queued.status = .queuedForSubmission
                queued.updatedAt = Date()
                evidenceStore.upsert(queued)
            }

            result = signed
            analysisProgressText = ""
            step = .done
        } catch {
            lastError = error.localizedDescription
            analysisProgressText = ""
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
        attestation.evidenceNumber = nil
        evidenceNumberRequested = false
    }

    func activeProfile() -> AdvocateProfile {
        if let id = settings.activeProfileID,
           let profile = settings.profiles.first(where: { $0.id == id }) {
            return profile
        }
        return settings.profiles.first ?? .empty
    }

    func resetSession(keepingProfile: Bool) {
        let profile = keepingProfile ? attestation.performingPerson : AdvocateProfile.empty
        step = .intake
        sourceURL = nil
        document = nil
        analysis = .empty()
        securityElements = []
        attestation = AttestationData(performingPerson: profile)
        sheetMethod = .duplexEstimate
        manualSheetCount = nil
        identities = []
        selectedIdentityID = nil
        evidenceNumberRequested = false
        validationErrors = []
        result = nil
        outputDirectory = nil
        lastError = nil
        serverTimeUsed = nil
        currentRecordID = UUID()
    }

    private func sanitizedBaseName() -> String {
        let raw = attestation.evidenceNumber ?? attestation.originalDocumentName
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.components(separatedBy: allowed.inverted).joined(separator: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: Date()))-\(cleaned.isEmpty ? "konverzia" : cleaned)"
    }

    static func appendClausePage(to pdfData: Data, using renderer: ClausePDFRenderer,
                                 attestation: AttestationData,
                                 elements: [SecurityElement]) -> Data {
        guard let mainDoc = PDFDocument(data: pdfData) else {
            return pdfData
        }
        let clauseData = renderer.render(
            title: "OSVEDČOVACIA DOLOŽKA ZARUČENEJ KONVERZIE",
            subtitle: "Podľa § 37 zákona č. 305/2013 Z. z. o e-Governmente a vyhlášky č. 70/2021 Z. z.",
            sections: [
                    .init(heading: "Pôvodný dokument v listinnej podobe", lines: [
                        ("Názov", attestation.originalDocumentName),
                        ("Druh", attestation.originalDocumentTypeLabel),
                        ("Počet listov", "\(attestation.numberOfSheets) (\(attestation.sheetCountingMethod.rawValue))"),
                        ("Počet neprázdnych strán", "\(attestation.nonEmptyPageCount)")
                    ]),
                    .init(heading: "Bezpečnostné prvky pôvodného dokumentu", lines:
                            elements.enumerated().map { index, element in
                                ("Prvek \(index + 1)", "\(element.kind.rawValue) — strana \(element.pageIndex + 1). \(element.verbalDescription)")
                            }),
                    .init(heading: "Novovzniknutý elektronický dokument", lines: [
                        ("Názov", attestation.newDocumentName),
                        ("Formát", attestation.newDocumentFormatLabel)
                    ]),
                    .init(heading: "Osoba vykonávajúca konverziu", lines: [
                        ("Meno", attestation.performingPerson.fullName),
                        ("Funkcia", attestation.performingPerson.position),
                        ("Evidenčné číslo advokáta", attestation.performingPerson.registrationNumber),
                        ("IČO kancelárie", attestation.performingPerson.ico)
                    ]),
                    .init(heading: "Evidencia konverzie", lines: [
                        ("Čas konverzie", AttestationClauseGenerator.isoFormatter.string(from: attestation.conversionExecutionDateTime)),
                        ("Evidenčné číslo", attestation.evidenceNumber ?? "—"),
                        ("Zariadenie", attestation.usedDeviceDescription)
                    ])
                ])

        guard let clauseDoc = PDFDocument(data: clauseData) else {
            return pdfData
        }

        for index in 0..<clauseDoc.pageCount {
            if let page = clauseDoc.page(at: index) {
                mainDoc.insert(page, at: mainDoc.pageCount)
            }
        }
        return mainDoc.dataRepresentation() ?? pdfData
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
