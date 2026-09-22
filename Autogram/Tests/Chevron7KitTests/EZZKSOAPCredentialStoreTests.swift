import Foundation
import Security
import XCTest
@testable import Chevron7Kit

final class EZZKSOAPCredentialStoreTests: XCTestCase {
    func testRoundTripUsesDedicatedServiceAndEnvironmentAccounts() throws {
        let keychain = SOAPMemoryKeychain()
        let store = EZZKSOAPCredentialStore(adapter: keychain)
        let test = EZZKSOAPCredentials(login: "ucet-test", password: "heslo-test")
        let production = EZZKSOAPCredentials(login: "ucet", password: "heslo")

        try store.save(test, environment: .sandbox)
        try store.save(production, environment: .production)

        XCTAssertEqual(try store.load(environment: .sandbox), test)
        XCTAssertEqual(try store.load(environment: .production), production)
        XCTAssertEqual(keychain.services, ["app.slovensko.chevron7.ezzk.soap"])
        XCTAssertEqual(Set(keychain.items.keys), ["test", "production"])
    }

    func testMissingItemLoadsNilAndDeleteRemovesOnlyThatEnvironment() throws {
        let keychain = SOAPMemoryKeychain()
        let store = EZZKSOAPCredentialStore(adapter: keychain)
        XCTAssertNil(try store.load(environment: .sandbox))

        try store.save(EZZKSOAPCredentials(login: "a", password: "b"), environment: .sandbox)
        try store.save(EZZKSOAPCredentials(login: "c", password: "d"), environment: .production)
        try store.delete(environment: .sandbox)

        XCTAssertNil(try store.load(environment: .sandbox))
        XCTAssertNotNil(try store.load(environment: .production))
    }

    func testMalformedItemAndKeychainFailureAreReported() {
        let keychain = SOAPMemoryKeychain()
        keychain.items["test"] = Data("not json".utf8)
        let store = EZZKSOAPCredentialStore(adapter: keychain)
        XCTAssertThrowsError(try store.load(environment: .sandbox)) { error in
            XCTAssertEqual(error as? EZZKTokenStoreError, .malformedData)
        }

        keychain.failure = .status(errSecInteractionNotAllowed)
        XCTAssertThrowsError(try store.load(environment: .sandbox)) { error in
            XCTAssertEqual(error as? EZZKTokenStoreError, .keychainFailure(status: errSecInteractionNotAllowed))
        }
    }

    func testKeychainErrorsAreDescribedInSlovakWithTheStatusCode() {
        XCTAssertEqual(EZZKTokenStoreError.keychainFailure(status: errSecInteractionNotAllowed).localizedDescription,
                       "Bezpečné úložisko (Keychain) nie je dostupné (kód \(errSecInteractionNotAllowed)).")
        for error in [EZZKTokenStoreError.malformedData, .encodingFailure] {
            let text = error.errorDescription ?? ""
            XCTAssertTrue(text.contains("Keychain"), "\(error): \(text)")
            XCTAssertFalse(text.contains("\u{2014}"), "\(error)")
        }
    }

    func testDescriptionNeverShowsThePassword() {
        let credentials = EZZKSOAPCredentials(login: "ucet", password: "tajne-heslo")
        XCTAssertFalse(String(describing: credentials).contains("tajne-heslo"))
        XCTAssertFalse(String(reflecting: credentials).contains("tajne-heslo"))
        XCTAssertTrue(String(describing: credentials).contains("ucet"))
    }
}

private final class SOAPMemoryKeychain: EZZKKeychainAdapter, @unchecked Sendable {
    var items: [String: Data] = [:]
    var services: Set<String> = []
    var failure: EZZKKeychainAdapterError?

    func read(service: String, account: String) throws -> Data? {
        services.insert(service)
        if let failure { throw failure }
        return items[account]
    }

    func write(_ data: Data, service: String, account: String) throws {
        services.insert(service)
        if let failure { throw failure }
        items[account] = data
    }

    func delete(service: String, account: String) throws {
        services.insert(service)
        if let failure { throw failure }
        items.removeValue(forKey: account)
    }
}
