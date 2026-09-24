// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import AppKit
import Foundation

enum FinderQuickActionService {
    static let menuTitle = "Podpísať s QES + QTS (Chevron7)"
    static let workflowResourceName = "Chevron7 Finder Quick Action"
    static let workflowInstallName = "Chevron7 Finder Quick Action.workflow"

    /// Autogram macOS, this app's name before Chevron7, installed its own Quick Action
    /// ("Podpísať s QES + QTS (Autogram)"). Once that app is gone the workflow stays in
    /// Finder's menu and fails with "Autogram macOS ARM64 helper was not found".
    static let legacyWorkflowNames = ["Autogram Finder Quick Action.workflow"]
    /// Only a workflow carrying Autogram's own script is the one Autogram macOS installed.
    static let legacyWorkflowMarker = "Contents/Resources/autogram-cli-sign.sh"
    static let legacyBundleIdentifier = "sk.autogram.Autogram"

    @discardableResult
    static func installQuickAction() -> Bool {
        retireLegacyQuickActions(in: servicesDirectory)
        return installChevron7QuickAction()
    }

    private static var servicesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
    }

    /// Moves Autogram macOS's Quick Action to the Trash when no Autogram macOS is left
    /// to run it. The Trash keeps it restorable; a workflow without Autogram's script,
    /// or one Autogram macOS can still run, is never touched.
    @discardableResult
    static func retireLegacyQuickActions(
        in servicesDirectory: URL,
        legacyAppInstalled: Bool = legacyAppIsInstalled(),
        moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> [URL] {
        guard !legacyAppInstalled else { return [] }
        var retired: [URL] = []
        for name in legacyWorkflowNames {
            let workflow = servicesDirectory.appendingPathComponent(name, isDirectory: true)
            let marker = workflow.appendingPathComponent(legacyWorkflowMarker)
            guard FileManager.default.fileExists(atPath: marker.path) else { continue }
            do {
                try moveToTrash(workflow)
                retired.append(workflow)
            } catch {
                continue
            }
        }
        return retired
    }

    static func legacyAppIsInstalled() -> Bool {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: legacyBundleIdentifier)
            .contains { !$0.path.contains("/.Trash/") && FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func installChevron7QuickAction() -> Bool {
        guard let source = Bundle.main.url(
            forResource: workflowResourceName,
            withExtension: "workflow"
        ) else {
            return false
        }

        let destination = servicesDirectory.appendingPathComponent(workflowInstallName)
        do {
            try FileManager.default.createDirectory(
                at: servicesDirectory,
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            enableInstalledWorkflow()
            return refreshServicesCache()
        } catch {
            return false
        }
    }

    private static func enableInstalledWorkflow() {
        guard let defaults = UserDefaults(suiteName: "pbs") else { return }
        var statuses = defaults.dictionary(forKey: "NSServicesStatus") ?? [:]
        statuses["(null) - \(menuTitle) - runWorkflowAsService"] = [
            "enabled_context_menu": NSNumber(value: 1),
            "enabled_services_menu": NSNumber(value: 1)
        ]
        defaults.set(statuses, forKey: "NSServicesStatus")
    }

    @discardableResult
    static func refreshServicesCache() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-update"]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
