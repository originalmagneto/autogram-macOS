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
    private(set) var signingEnvironment: EngineCapabilities?
    private(set) var isLoadingSigningEnvironment = false
    private(set) var isLoadingCertificates = false
    private(set) var credentialError: String?
    private let engine: any SigningEngine
    @ObservationIgnored private var coordinator: SigningCoordinator?
    @ObservationIgnored private var pendingSigningPIN: Secret?

    init(
        engine: any SigningEngine = FakeSigningEngine.launchEngine(),
        items: [PDFItem] = []
    ) {
        self.engine = engine
        self.items = items
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
        guard let selectedDriverID else {
            credentialError = "Choose a signing driver before continuing."
            return .failed
        }

        isLoadingCertificates = true
        pendingSigningPIN = submission.signingPIN

        do {
            discoveredCertificates = try await engine.certificates(
                driverID: selectedDriverID,
                pin: submission.certificatePIN
            )
        } catch {
            isLoadingCertificates = false
            credentialError = "Certificates could not be loaded. Check your PIN and try again."
            clearPendingSigningPIN()
            return .failed
        }

        isLoadingCertificates = false
        guard !discoveredCertificates.isEmpty else {
            credentialError = "No signing certificates were found for the selected driver."
            clearPendingSigningPIN()
            return .failed
        }

        if let certificate = discoveredCertificates.only {
            startSigning(with: certificate)
            return .signingStarted
        }
        return .certificateSelectionRequired
    }

    func startSigning(with certificate: SigningCertificate) {
        guard let driverID = selectedDriverID, let signingPIN = pendingSigningPIN else {
            credentialError = "Signing credentials are no longer available. Enter your PIN again."
            return
        }

        clearPendingSigningPIN()
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

    func selectPDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
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
                  (try? standardizedURL.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true,
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
            credentialError = "Signing could not be completed."
            for item in items {
                updateStatus(for: item.descriptor.id, to: .failed)
            }
        }
    }

    private func clearPendingSigningPIN() {
        pendingSigningPIN = nil
    }
}

enum CertificateResolution: Sendable, Equatable {
    case certificateSelectionRequired
    case signingStarted
    case failed
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
