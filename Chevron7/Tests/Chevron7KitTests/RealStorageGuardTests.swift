// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Identity
import Chevron7TestSupport
import Foundation
import XCTest

/// `RealStorageGuard` installs itself when the test bundle loads; these pin that and the
/// folders it watches. The App target has the same checks, except the source scan.
final class RealStorageGuardTests: XCTestCase {
    func testGuardIsInstalledBeforeTestsRun() {
        XCTAssertTrue(RealStorageGuard.isInstalled)
    }

    func testGuardWatchesTheProductDataRoots() {
        XCTAssertEqual(RealStorageGuard.watchedRoots,
                       [ProductIdentity.applicationSupportDirectory(), ProductIdentity.cachesDirectory()])
    }

    /// The guard sees writes only; a store opened on a default root would still read the
    /// real evidence register. Every store a test builds must name its own directory.
    func testNoTestOpensAStoreOnTheRealDataRoot() throws {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        let testsDirectory = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        // makeSettingsStore() is the one place that builds an AppSettingsStore, with a temporary root.
        let helper = testsDirectory.appendingPathComponent("Chevron7AppTests/TestSettingsStore.swift").standardizedFileURL
        let forbidden = try [
            #"AppSettingsStore\("#,
            #"LocalEvidenceStore\(\s*\)"#,
            #"ExampleBank\(directory:\s*ExampleBank\.defaultDirectory"#,
            #"SignatureAssetStore\(\s*\)"#,
            #"SignaturePlacementState\(\s*\)"#,
            #"VisibleSignatureRenderer\((?![^)]*cacheRoot)"#
        ].map { try NSRegularExpression(pattern: $0) }

        var offenders: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: testsDirectory, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator
        where file.pathExtension == "swift" && ![thisFile, helper].contains(file.standardizedFileURL) {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if forbidden.contains(where: { $0.firstMatch(in: line, range: range) != nil }) {
                    offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertEqual(offenders, [], "Pass a temporary directory (makeSettingsStore(), directory:, cacheRoot:, applicationSupportRoot:)")
    }
}
