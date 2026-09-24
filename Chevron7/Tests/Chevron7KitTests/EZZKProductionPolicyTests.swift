// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7Kit

final class EZZKProductionPolicyTests: XCTestCase {
    private let person = EZZKPerson(corporateBodyFullName: "Advokát", ico: "12345678")

    /// Every suite name this class has handed out, so the class-level teardown below can
    /// clean up exactly those and nothing else. A lock, not a plain static var, because
    /// XCTest may run this class's tests concurrently with another instance's.
    private static let suiteNamesLock = NSLock()
    private nonisolated(unsafe) static var suiteNames: [String] = []

    /// `addTeardownBlock` captures only the suite name (a `String`), never the `UserDefaults`
    /// instance itself: `UserDefaults` is not `Sendable`, so a captured instance fails to
    /// compile under Swift 6. `removePersistentDomain` clears the value from memory
    /// immediately (so a value such as the owner switch never reaches disk), but the
    /// preferences daemon (`cfprefsd`) still persists the now-empty domain to
    /// `~/Library/Preferences/<name>.plist` some short, unpredictable time later, out of
    /// process: neither `removePersistentDomain` nor the deprecated `synchronize()` can be
    /// made to wait for or cancel that. The class-level teardown below is what actually
    /// deletes the file, once every test in this class (and its own instance teardown) has
    /// had a chance to run and `cfprefsd` has had a moment to catch up.
    private func defaults() -> UserDefaults {
        let name = "EZZKProductionPolicyTests-\(UUID().uuidString)"
        Self.suiteNamesLock.withLock { Self.suiteNames.append(name) }
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    /// Deletes this run's own suite files by the exact name `defaults()` recorded above,
    /// never touching a file this test class did not itself create in this run (in
    /// particular, never the pre-existing `EZZKProductionPolicyTests-*.plist` files the
    /// controller is responsible for). `cfprefsd` writes each removed domain out at its own
    /// pace, anywhere from under a second to a few seconds later, so this polls and deletes
    /// on sight for a while rather than trusting one fixed delay to be long enough.
    override class func tearDown() {
        let names = suiteNamesLock.withLock { suiteNames }
        if !names.isEmpty {
            let preferencesDirectory = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences", isDirectory: true)
            let paths = names.map { preferencesDirectory.appendingPathComponent("\($0).plist") }
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 0.5)
                for path in paths {
                    try? FileManager.default.removeItem(at: path)
                }
            }
        }
        super.tearDown()
    }

    /// Production is open for everyone: no owner switch is needed any more.
    func testProductionIsAllowedWithoutTheOwnerSwitch() {
        let policy = EZZKProductionPolicy.current(defaults: defaults())
        XCTAssertTrue(EZZKProductionPolicy.enabledForEveryone)
        XCTAssertEqual(policy, .allowed)
        XCTAssertNil(policy.refusal(environment: .production, submitting: true))
    }

    /// The refusal itself still works for code that builds `.refused` (tests, `ezzk-probe`).
    func testARefusedPolicyStillRefusesProduction() {
        let policy = EZZKProductionPolicy.refused
        XCTAssertEqual(policy.refusal(environment: .production, submitting: false), .productionAllocationDisabled)
        XCTAssertEqual(policy.refusal(environment: .production, submitting: true), .submissionUnavailable)
        XCTAssertNil(policy.refusal(environment: .sandbox, submitting: true))
    }

    func testTheOwnerSwitchAllowsProduction() {
        let store = defaults()
        store.set(true, forKey: EZZKProductionPolicy.ownerSwitchKey)
        let policy = EZZKProductionPolicy.current(defaults: store)
        XCTAssertEqual(policy, .allowed)
        XCTAssertNil(policy.refusal(environment: .production, submitting: true))
    }

    func testClientDefaultsToRefusedAndSendsNothingOnProduction() async throws {
        let transport = SOAPScriptedTransport([])
        let client = EZZKSOAPClient(environment: .production, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "a", password: "b") })
        XCTAssertEqual(client.productionPolicy, .refused)
        do {
            _ = try await client.evidenceNumbers(for: person)
            XCTFail("production allocation must be refused")
        } catch {
            XCTAssertEqual(error as? EZZKError, .productionAllocationDisabled)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAllowedClientReachesProductionForAllocation() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["260917-A"]))
        ])
        let client = EZZKSOAPClient(environment: .production, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "a", password: "b") },
                                    productionPolicy: .allowed)
        let numbers = try await client.evidenceNumbers(for: person)
        XCTAssertEqual(numbers, ["260917-A"])
        XCTAssertEqual(transport.requests.count, 2)
    }
}
