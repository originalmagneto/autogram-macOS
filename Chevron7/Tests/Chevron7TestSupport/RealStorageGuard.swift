// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Identity
import Foundation
import XCTest

/// Fails any test that creates, changes or removes anything under the user's real
/// `~/Library/Application Support/Chevron7` or `~/Library/Caches/Chevron7`.
///
/// The evidence register there is a legal record, so tests must pass a temporary
/// directory to every store instead. The guard lists both folders (path, size and
/// modification date) when it is installed, checks them again at the end of every
/// test and records a failure on the test that changed them. A change made after the
/// last test ends the process with a non-zero status.
///
/// SwiftPM offers no `NSPrincipalClass` for the test bundle, so the guard installs
/// itself from a module initializer (`installRealStorageGuardAtLoad`) when the bundle is
/// loaded: before XCTest picks the tests, which covers `--filter` runs too.
/// Runs when the test bundle is loaded, like an Objective-C `+load`.
@used @section("__DATA,__mod_init_func")
let installRealStorageGuardAtLoad: @convention(c) () -> Void = { RealStorageGuard.install() }

public final class RealStorageGuard: NSObject, XCTestObservation, @unchecked Sendable {
    public static let watchedRoots = [
        ProductIdentity.applicationSupportDirectory(),
        ProductIdentity.cachesDirectory()
    ]

    private nonisolated(unsafe) static var shared: RealStorageGuard?
    private static let lock = NSLock()

    private let lock = NSLock()
    private var baseline: [String: String]

    private init(baseline: [String: String]) {
        self.baseline = baseline
    }

    /// Registers the observer once per process; later calls do nothing.
    public static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard shared == nil else { return }
        let observer = RealStorageGuard(baseline: snapshot())
        shared = observer
        XCTestObservationCenter.shared.addTestObserver(observer)
    }

    public static var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return shared != nil
    }

    // MARK: - XCTestObservation

    public func testCaseWillStart(_ testCase: XCTestCase) {
        // A teardown block runs inside the test, so the failure lands on this test.
        testCase.addTeardownBlock { [self] in
            let changes = takeChanges()
            if !changes.isEmpty {
                XCTFail(Self.message(changes))
            }
        }
    }

    public func testBundleDidFinish(_ testBundle: Bundle) {
        let changes = takeChanges()
        guard !changes.isEmpty else { return }
        FileHandle.standardError.write(Data(("error: " + Self.message(changes) + "\n").utf8))
        exit(EXIT_FAILURE)
    }

    // MARK: - Snapshots

    /// Differences since the last check; the new state becomes the baseline so one
    /// offender does not fail every later test.
    private func takeChanges() -> [String] {
        let current = Self.snapshot()
        lock.lock()
        defer { lock.unlock() }
        let changes = Set(baseline.keys).union(current.keys)
            .filter { baseline[$0] != current[$0] }
            .sorted()
        baseline = current
        return changes
    }

    private static func message(_ changes: [String]) -> String {
        "The test changed the user's real Chevron7 data; pass a temporary directory instead "
            + "(or quit Chevron7 if the app itself was writing there during the run):\n"
            + changes.map { "  \($0)" }.joined(separator: "\n")
    }

    /// Path to "size modification-date" for every item under the watched roots,
    /// including each root itself, so a created root counts as a change too.
    static func snapshot(fileManager: FileManager = .default) -> [String: String] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        var result: [String: String] = [:]
        for root in watchedRoots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            var items = [root]
            if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) {
                for case let url as URL in enumerator { items.append(url) }
            }
            // Finder writes .DS_Store whenever someone browses the folder.
            for url in items where url.lastPathComponent != ".DS_Store" {
                let values = try? url.resourceValues(forKeys: Set(keys))
                // Directory dates change whenever an entry does; the entries already show that.
                let date = values?.isDirectory == true ? "dir"
                    : values?.contentModificationDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "?"
                result[url.standardizedFileURL.path] = "\(values?.fileSize ?? 0) \(date)"
            }
        }
        return result
    }
}
