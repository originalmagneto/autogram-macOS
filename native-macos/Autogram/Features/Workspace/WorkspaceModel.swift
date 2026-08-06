import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class WorkspaceModel {
    private(set) var items: [PDFItem] = []
    var selection: PDFItem.ID?
    private let engine: any SigningEngine
    @ObservationIgnored private var coordinator: SigningCoordinator?

    init(engine: any SigningEngine = FakeSigningEngine.launchEngine(), items: [PDFItem] = []) {
        self.engine = engine
        self.items = items
        self.selection = items.first?.id
        self.coordinator = SigningCoordinator(engine: engine, workspace: self)
    }

    static func launchWorkspace(environment: [String: String] = ProcessInfo.processInfo.environment) -> WorkspaceModel {
        let engine = FakeSigningEngine.launchEngine(environment: environment)
        let items: [PDFItem]
        if environment["AUTOGRAM_FAKE_ENGINE"] == "partial-failure" {
            items = [
                PDFItem(descriptor: PDFItemDescriptor(id: "agreement", sourceURL: URL(fileURLWithPath: "/tmp/Agreement.pdf"))),
                PDFItem(descriptor: PDFItemDescriptor(id: "invoice", sourceURL: URL(fileURLWithPath: "/tmp/Invoice.pdf")))
            ]
        } else {
            items = []
        }
        return WorkspaceModel(engine: engine, items: items)
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
                _ = self?.addPDFs(urls)
            }
        }
    }

    @discardableResult
    func addPDFs(_ urls: [URL]) -> Bool {
        let existingURLs = Set(items.map { $0.descriptor.sourceURL.standardizedFileURL })
        var acceptedURLs = Set<URL>()
        let validURLs = urls.filter { url in
            let standardizedURL = url.standardizedFileURL
            guard url.isFileURL,
                  url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame,
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

    func sign() async {
        guard !items.isEmpty, let coordinator else { return }

        let descriptors = items.map(\.descriptor)
        let request = SigningRequest(
            sessionID: UUID(),
            driverID: "workspace",
            certificateSerial: "workspace",
            pin: Secret(""),
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
