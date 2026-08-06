import AppKit
import Foundation

@MainActor
final class OpenEventHandler {
    private let workspace: WorkspaceModel

    init(workspace: WorkspaceModel) {
        self.workspace = workspace
    }

    func handle(_ urls: [URL]) async {
        guard workspace.addFiles(urls) else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class OpenDocumentAppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    @MainActor var openEventHandler: OpenEventHandler? {
        didSet {
            guard let openEventHandler, !pendingURLs.isEmpty else { return }
            let urls = pendingURLs
            pendingURLs.removeAll()
            Task { @MainActor in
                await openEventHandler.handle(urls)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            guard let openEventHandler else {
                pendingURLs.append(contentsOf: urls)
                return
            }
            await openEventHandler.handle(urls)
        }
    }
}
