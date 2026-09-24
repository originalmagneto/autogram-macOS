// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7App

final class FinderQuickActionServiceTests: XCTestCase {
    private var services: URL!
    private var retired: [URL] = []

    override func setUpWithError() throws {
        services = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickActionServices-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: services, withIntermediateDirectories: true)
        retired = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: services)
    }

    private func makeWorkflow(_ name: String, script: String?) throws -> URL {
        let workflow = services.appendingPathComponent(name, isDirectory: true)
        let resources = workflow.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        if let script {
            try Data("#!/usr/bin/env bash\n".utf8).write(to: resources.appendingPathComponent(script))
        }
        return workflow
    }

    private func retire(legacyAppInstalled: Bool) -> [URL] {
        FinderQuickActionService.retireLegacyQuickActions(
            in: services,
            legacyAppInstalled: legacyAppInstalled,
            moveToTrash: { self.retired.append($0) }
        )
    }

    func testAutogramWorkflowIsRetiredWhenAutogramMacOSIsGone() throws {
        let legacy = try makeWorkflow("Autogram Finder Quick Action.workflow", script: "autogram-cli-sign.sh")

        XCTAssertEqual(retire(legacyAppInstalled: false), [legacy])
        XCTAssertEqual(retired, [legacy])
    }

    func testAutogramWorkflowStaysWhileAutogramMacOSCanStillRunIt() throws {
        _ = try makeWorkflow("Autogram Finder Quick Action.workflow", script: "autogram-cli-sign.sh")

        XCTAssertEqual(retire(legacyAppInstalled: true), [])
        XCTAssertEqual(retired, [])
    }

    func testWorkflowWithoutAutogramScriptIsNeverTouched() throws {
        // Same name, but not the workflow Autogram macOS installed: the person's own.
        _ = try makeWorkflow("Autogram Finder Quick Action.workflow", script: "something-else.sh")
        _ = try makeWorkflow("Sign with Autogram.workflow", script: nil)

        XCTAssertEqual(retire(legacyAppInstalled: false), [])
        XCTAssertEqual(retired, [])
    }

    func testChevron7WorkflowIsNeverRetired() throws {
        _ = try makeWorkflow(FinderQuickActionService.workflowInstallName, script: "chevron7-cli-sign.sh")

        XCTAssertEqual(retire(legacyAppInstalled: false), [])
    }

    func testMissingServicesFolderRetiresNothing() throws {
        try FileManager.default.removeItem(at: services)

        XCTAssertEqual(retire(legacyAppInstalled: false), [])
    }
}
