import AppKit
import Foundation
import Observation

struct QuickActionInstaller {
    static let workflowName = "Sign PDFs Autogram.workflow"
    static let legacyCLIWorkflowName = "Sign PDFs with Autogram.workflow"

    enum Status: Equatable {
        case notInstalled
        case updateRequired
        case current
    }

    private let fileManager: FileManager
    private let servicesURL: URL
    private let bundledWorkflowURL: URL?
    private let refreshServices: () throws -> Void

    init(
        fileManager: FileManager = .default,
        servicesURL: URL? = nil,
        bundledWorkflowURL: URL? = nil,
        refreshServices: @escaping () throws -> Void = Self.refreshSystemServices
    ) {
        self.fileManager = fileManager
        self.servicesURL = servicesURL ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Services", directoryHint: .isDirectory)
        self.bundledWorkflowURL = bundledWorkflowURL
        self.refreshServices = refreshServices
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: installedWorkflowURL.path)
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
        var resourceValues = URLResourceValues()
        resourceValues.hasHiddenExtension = true
        var workflowURL = installedWorkflowURL
        try workflowURL.setResourceValues(resourceValues)
        try validateFinderQuickAction(at: installedWorkflowURL)
        try refreshServices()
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: installedWorkflowURL.path) else { return }
        try fileManager.removeItem(at: installedWorkflowURL)
        try refreshServices()
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
        let version = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private func validateFinderQuickAction(at workflowURL: URL) throws {
        let documentURL = workflowURL.appending(path: "Contents/document.wflow")
        guard let data = try? Data(contentsOf: documentURL),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let metadata = root["workflowMetaData"] as? [String: Any],
              metadata["workflowTypeIdentifier"] as? String == "com.apple.Automator.servicesMenu",
              metadata["serviceApplicationBundleID"] as? String == "com.apple.finder",
              metadata["serviceInputTypeIdentifier"] as? String == "com.apple.Automator.fileSystemObject"
        else {
            throw QuickActionInstallerError.invalidFinderQuickAction
        }
    }

    private static func refreshSystemServices() throws {
        NSUpdateDynamicServices()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-update", Locale.current.language.languageCode?.identifier ?? "English"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw QuickActionInstallerError.serviceRegistrationFailed
        }
        NSUpdateDynamicServices()
    }

    private func workflowSourceURL() throws -> URL {
        if let bundledWorkflowURL {
            guard fileManager.fileExists(atPath: bundledWorkflowURL.path) else {
                throw QuickActionInstallerError.missingBundledWorkflow
            }
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
    case invalidFinderQuickAction
    case serviceRegistrationFailed

    var errorDescription: String? {
        switch self {
        case .missingBundledWorkflow:
            return "The Finder Quick Action is unavailable in this app bundle."
        case .invalidFinderQuickAction:
            return "The installed workflow is not a Finder Quick Action for PDF files."
        case .serviceRegistrationFailed:
            return "macOS could not activate the Finder Quick Action."
        }
    }
}

@MainActor @Observable
final class QuickActionMaintenanceState {
    private(set) var errorMessage: String?

    func maintain(using installer: QuickActionInstaller) {
        do {
            try installer.maintainIfInstalled()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
