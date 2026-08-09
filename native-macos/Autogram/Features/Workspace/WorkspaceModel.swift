import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class WorkspaceModel {
    private(set) var items: [PDFItem] = []
    var selection: PDFItem.ID?
    private(set) var availableDrivers: [SigningDriver] = []
    private(set) var selectedDriverID: String?
    private(set) var discoveredCertificates: [SigningCertificate] = []
    private(set) var rememberedTokens: [RememberedSigningToken] = []
    private(set) var signingEnvironment: EngineCapabilities?
    private(set) var isLoadingSigningEnvironment = false
    private(set) var isLoadingCertificates = false
    private(set) var credentialError: String?
    private(set) var signingError: String?
    private let engine: any SigningEngine
    private let certificateDefaultStore: any CertificateDefaultStoring
    @ObservationIgnored private var coordinator: SigningCoordinator?
    @ObservationIgnored private var pendingSigningPIN: Secret?
    @ObservationIgnored private var discoveredToken: SigningToken?
    @ObservationIgnored private var inspectionRequestGeneration = 0

    init(
        engine: any SigningEngine = FakeSigningEngine.launchEngine(),
        items: [PDFItem] = [],
        certificateDefaultStore: any CertificateDefaultStoring = UserDefaultsCertificateDefaultStore()
    ) {
        self.engine = engine
        self.items = items
        self.certificateDefaultStore = certificateDefaultStore
        rememberedTokens = certificateDefaultStore.rememberedTokens
        self.selection = items.first?.id
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
        !items.isEmpty && items.allSatisfy { $0.inspection.isComplete }
    }

    func refreshInspections() async {
        let descriptors = items.map(\.descriptor)
        guard !descriptors.isEmpty else { return }

        inspectionRequestGeneration += 1
        let requestGeneration = inspectionRequestGeneration
        updateInspection(for: descriptors.map(\.id), to: .pending)

        do {
            let inspections = try await engine.inspect(files: descriptors)
            applyInspectionResults(inspections, for: descriptors, requestGeneration: requestGeneration)
        } catch {
            guard requestGeneration == inspectionRequestGeneration else { return }
            updateInspection(for: descriptors.map(\.id), to: .failed)
        }
    }

    func refreshSigningEnvironment() async {
        isLoadingSigningEnvironment = true
        credentialError = nil
        discoveredCertificates = []

        defer { isLoadingSigningEnvironment = false }

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
        } catch {
            isLoadingCertificates = false
            credentialError = error.localizedDescription
            clearPendingSigningPIN()
            return .failed
        }

        isLoadingCertificates = false
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
        defer { isLoadingCertificates = false }

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
        Task { [weak self] in
            await self?.sign(
                driverID: driverID,
                certificateSerial: certificate.serialNumber,
                pin: signingPIN
            )
        }
    }

    func cancelCredentialFlow() {
        discoveredCertificates = []
        discoveredToken = nil
        isLoadingCertificates = false
        clearPendingSigningPIN()
    }

    func setItems(_ items: [PDFItem]) {
        self.items = items
        if let selection, !items.contains(where: { $0.id == selection }) {
            self.selection = items.first?.id
        } else if selection == nil {
            self.selection = items.first?.id
        }
    }

    func updateStatus(for fileID: String, to status: PDFItemStatus) {
        items = items.map { item in
            item.descriptor.id == fileID ? item.updatingStatus(to: status) : item
        }
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
                return item.updatingInspection(to: .failed)
            }
            return item.updatingInspection(to: .completed(result))
        }
    }

    func markInspectionFailed(for fileIDs: [String]) {
        updateInspection(for: fileIDs, to: .failed)
    }

    private func updateInspection(for fileIDs: [String], to inspection: PDFItemInspection) {
        let inspectedIDs = Set(fileIDs)
        items = items.map { item in
            inspectedIDs.contains(item.descriptor.id) ? item.updatingInspection(to: inspection) : item
        }
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
        items.append(contentsOf: newItems)
        if selection == nil {
            selection = newItems.first?.id
        }
        if !newItems.isEmpty {
            Task { await refreshInspections() }
        }
        return !newItems.isEmpty
    }

    @discardableResult
    func addPDFs(_ urls: [URL]) -> Bool {
        addFiles(urls)
    }

    func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func removeItems(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        if let selection, !items.contains(where: { $0.id == selection }) {
            self.selection = items.first?.id
        }
    }

    func removeSelectedItem() {
        guard let selection, let index = items.firstIndex(where: { $0.id == selection }) else { return }
        removeItems(atOffsets: IndexSet(integer: index))
    }

    private func sign(driverID: String, certificateSerial: String, pin: Secret) async {
        guard !items.isEmpty,
              !driverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !certificateSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let coordinator else {
            return
        }

        signingError = nil

        let descriptors = items.map(\.descriptor)
        let request = SigningRequest(
            sessionID: UUID(),
            driverID: driverID,
            certificateSerial: certificateSerial,
            pin: pin,
            files: descriptors.map { SigningFile(id: $0.id, sourceURL: $0.sourceURL) }
        )

        do {
            try await coordinator.inspect(descriptors)
            try await coordinator.beginSigning(request: request)
        } catch {
            signingError = error.localizedDescription
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
