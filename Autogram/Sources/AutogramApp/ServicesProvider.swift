import Foundation

enum FinderQuickActionService {
    static let menuTitle = "Podpísať s QES + QTS (Autogram)"
    static let workflowResourceName = "Autogram Finder Quick Action"
    static let workflowInstallName = "Autogram Finder Quick Action.workflow"

    @discardableResult
    static func installQuickAction() -> Bool {
        guard let source = Bundle.main.url(
            forResource: workflowResourceName,
            withExtension: "workflow"
        ) else {
            return false
        }

        let servicesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
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
