import AppKit
import Foundation

struct QuickActionInstaller {
    static let workflowName = "Sign PDFs with Autogram.workflow"

    private let fileManager: FileManager
    private let servicesURL: URL

    init(fileManager: FileManager = .default, servicesURL: URL? = nil) {
        self.fileManager = fileManager
        self.servicesURL = servicesURL ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Services", directoryHint: .isDirectory)
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: installedWorkflowURL.path)
    }

    func install() throws {
        let sourceURL = try bundledWorkflowURL()
        try fileManager.createDirectory(at: servicesURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: installedWorkflowURL.path) {
            try fileManager.removeItem(at: installedWorkflowURL)
        }
        try fileManager.copyItem(at: sourceURL, to: installedWorkflowURL)
        NSUpdateDynamicServices()
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: installedWorkflowURL.path) else { return }
        try fileManager.removeItem(at: installedWorkflowURL)
        NSUpdateDynamicServices()
    }

    private var installedWorkflowURL: URL {
        servicesURL.appending(path: Self.workflowName, directoryHint: .isDirectory)
    }

    private func bundledWorkflowURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "Sign PDFs with Autogram", withExtension: "workflow") else {
            throw QuickActionInstallerError.missingBundledWorkflow
        }
        return url
    }
}

enum QuickActionInstallerError: LocalizedError {
    case missingBundledWorkflow

    var errorDescription: String? {
        switch self {
        case .missingBundledWorkflow:
            return "The Finder Quick Action is unavailable in this app bundle."
        }
    }
}
