import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class WorkspaceModel {
    private(set) var items: [PDFItem] = []
    var selection: PDFItem.ID?
    let credentialCertificates: [SigningCertificate]
    private let engine: any SigningEngine
    @ObservationIgnored private var coordinator: SigningCoordinator?

    init(
        engine: any SigningEngine = FakeSigningEngine.launchEngine(),
        items: [PDFItem] = [],
        credentialCertificates: [SigningCertificate] = []
    ) {
        self.engine = engine
        self.items = items
        self.credentialCertificates = credentialCertificates
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
        let credentialCertificates: [SigningCertificate]
        if fixtureMode == "credential-flow" {
            credentialCertificates = [
                SigningCertificate(serialNumber: "TEST-CERTIFICATE-1", displayName: "Test Certificate")
            ]
        } else {
            credentialCertificates = []
        }
        return WorkspaceModel(engine: engine, items: items, credentialCertificates: credentialCertificates)
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

    func sign(driverID: String, certificateSerial: String, pin: Secret) async {
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
            for item in items {
                updateStatus(for: item.descriptor.id, to: .failed)
            }
        }
    }
}
