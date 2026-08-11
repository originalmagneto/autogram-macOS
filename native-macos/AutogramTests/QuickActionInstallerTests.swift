import Foundation
import Testing
@testable import Autogram

@Suite struct QuickActionInstallerTests {
@Test func quickActionIsNotInstalledWhenServicesDirectoryIsEmpty() throws {
    try withQuickActionDirectories { bundled, services in
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )

        #expect(installer.status == .notInstalled)
    }
}

@Test func installCopiesBundledWorkflowAndMarksItCurrent() throws {
    try withQuickActionDirectories { bundled, services in
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )

        try installer.install()

        #expect(installer.status == .current)
        #expect(FileManager.default.fileExists(atPath: installedWorkflow(in: services).path))
    }
}

@Test func staleWorkflowIsUpdatedFromBundledVersion() throws {
    try withQuickActionDirectories { bundled, services in
        try writeManagedVersion("1", to: installedWorkflow(in: services))
        try writeManagedVersion("2", to: bundled)
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )

        #expect(installer.status == .updateRequired)
        #expect(installer.isInstalled)
        try installer.maintainIfInstalled()

        #expect(installer.status == .current)
    }
}

@Test func emptyBundledVersionMarkerRequiresAnUpdate() throws {
    try withQuickActionDirectories { bundled, services in
        try writeManagedVersion("   ", to: bundled)
        try writeManagedVersion("1", to: installedWorkflow(in: services))
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )

        #expect(installer.status == .updateRequired)
        #expect(installer.isInstalled)
    }
}

@Test func emptyInstalledVersionMarkerRequiresAnUpdate() throws {
    try withQuickActionDirectories { bundled, services in
        try writeManagedVersion("   ", to: installedWorkflow(in: services))
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )

        #expect(installer.status == .updateRequired)
        #expect(installer.isInstalled)
    }
}

@Test func maintenanceLeavesCurrentWorkflowUntouched() throws {
    try withQuickActionDirectories { bundled, services in
        let installed = installedWorkflow(in: services)
        try writeManagedVersion("1", to: installed)
        let sentinel = installed.appending(path: "sentinel")
        try Data("present".utf8).write(to: sentinel)
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )

        try installer.maintainIfInstalled()

        #expect(installer.status == .current)
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }
}

@Test func reinstallReplacesAnAlreadyCurrentWorkflow() throws {
    try withQuickActionDirectories { bundled, services in
        try writeManagedVersion("1", to: bundled)
        let installed = installedWorkflow(in: services)
        try writeManagedVersion("1", to: installed)
        let obsoleteFile = installed.appending(path: "obsolete-resource")
        try Data("obsolete".utf8).write(to: obsoleteFile)
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )

        try installer.install()

        #expect(installer.status == .current)
        #expect(!FileManager.default.fileExists(atPath: obsoleteFile.path))
    }
}

@Test func removeDeletesInstalledWorkflow() throws {
    try withQuickActionDirectories { bundled, services in
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )
        try installer.install()

        try installer.remove()

        #expect(installer.status == .notInstalled)
    }
}

@Test func maintenanceDoesNotReinstallRemovedWorkflow() throws {
    try withQuickActionDirectories { bundled, services in
        let installer = QuickActionInstaller(
            fileManager: .default,
            servicesURL: services,
            bundledWorkflowURL: bundled
        )
        try installer.install()
        try installer.remove()

        try installer.maintainIfInstalled()

        #expect(installer.status == .notInstalled)
    }
}
}

private func withQuickActionDirectories(
    _ body: (URL, URL) throws -> Void
) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let bundled = root.appending(path: "Sign PDFs Autogram.workflow", directoryHint: .isDirectory)
    let services = root.appending(path: "Services", directoryHint: .isDirectory)
    try writeManagedVersion("1", to: bundled)
    try body(bundled, services)
}

private func installedWorkflow(in services: URL) -> URL {
    services.appending(path: "Sign PDFs Autogram.workflow", directoryHint: .isDirectory)
}

private func writeManagedVersion(_ version: String, to workflow: URL) throws {
    let resources = workflow.appending(path: "Contents/Resources", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try Data((version + "\n").utf8).write(to: resources.appending(path: "managed-version"))
}
