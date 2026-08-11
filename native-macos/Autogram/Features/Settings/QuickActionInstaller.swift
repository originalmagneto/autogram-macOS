import AppKit
import Foundation

struct QuickActionInstaller {
    static let workflowName = "Sign PDFs Autogram.workflow"
    static let legacyCLIWorkflowName = "Sign PDFs with Autogram.workflow"

    enum Status: Equatable {
        case nativeInstalled
        case legacyCLIInstalled
        case notInstalled

        static let updateRequired = Status.legacyCLIInstalled
        static let current = Status.nativeInstalled
    }

    private let fileManager: FileManager
    private let servicesURL: URL
    private let bundledWorkflowURL: URL?

    init(
        fileManager: FileManager = .default,
        servicesURL: URL? = nil,
        bundledWorkflowURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.servicesURL = servicesURL ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Services", directoryHint: .isDirectory)
        self.bundledWorkflowURL = bundledWorkflowURL
    }

    var isInstalled: Bool {
        status == .current
    }

    var status: Status {
        guard fileManager.fileExists(atPath: installedWorkflowURL.path) else {
            return .notInstalled
        }
        guard let bundledWorkflowURL = try? workflowSourceURL(),
              let installedVersion = managedVersion(at: installedWorkflowURL),
              let bundledVersion = managedVersion(at: bundledWorkflowURL)
        else {
            return .updateRequired
        }
        return installedVersion == bundledVersion ? .current : .updateRequired
    }

    var hasLegacyCLIWorkflow: Bool {
        fileManager.fileExists(atPath: legacyWorkflowURL.path)
    }

    func install() throws {
        let sourceURL = try workflowSourceURL()
        try fileManager.createDirectory(at: servicesURL, withIntermediateDirectories: true)
        let temporaryWorkflowURL = servicesURL.appending(
            path: ".\(Self.workflowName).\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: temporaryWorkflowURL) }

        try fileManager.copyItem(at: sourceURL, to: temporaryWorkflowURL)
        if fileManager.fileExists(atPath: installedWorkflowURL.path) {
            _ = try fileManager.replaceItemAt(installedWorkflowURL, withItemAt: temporaryWorkflowURL)
        } else {
            try fileManager.moveItem(at: temporaryWorkflowURL, to: installedWorkflowURL)
        }
        NSUpdateDynamicServices()
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: installedWorkflowURL.path) else { return }
        try fileManager.removeItem(at: installedWorkflowURL)
        NSUpdateDynamicServices()
    }

    func maintainIfInstalled() throws {
        guard status != .notInstalled else { return }
        guard status == .updateRequired else { return }
        try install()
    }

    private var installedWorkflowURL: URL {
        servicesURL.appending(path: Self.workflowName, directoryHint: .isDirectory)
    }

    private var legacyWorkflowURL: URL {
        servicesURL.appending(path: Self.legacyCLIWorkflowName, directoryHint: .isDirectory)
    }

    private func managedVersion(at workflowURL: URL) -> String? {
        let markerURL = workflowURL.appending(path: "Contents/Resources/managed-version")
        guard let marker = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return nil
        }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func workflowSourceURL() throws -> URL {
        if let bundledWorkflowURL {
            return bundledWorkflowURL
        }
        guard let url = Bundle.main.url(forResource: "Sign PDFs Autogram", withExtension: "workflow") else {
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
