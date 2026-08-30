import Foundation
import Security
import XCTest
@testable import AutogramKit

final class EZZKTokenStoreTests: XCTestCase {
    func testSaveAndLoadRoundTripUsesDedicatedServiceNamespace() throws {
        let adapter = InMemoryEZZKKeychainAdapter()
        let store = EZZKTokenStore(adapter: adapter)
        let tokenSet = makeTokenSet()

        try store.save(tokenSet, environment: .sandbox)

        XCTAssertEqual(try store.load(environment: .sandbox), tokenSet)
        XCTAssertNotEqual(adapter.service, KeychainStore.service)
    }

    func testSandboxAndProductionTokensUseSeparateAccounts() throws {
        let adapter = InMemoryEZZKKeychainAdapter()
        let store = EZZKTokenStore(adapter: adapter)
        let sandboxToken = makeTokenSet(accessToken: "sandbox-access")
        let productionToken = makeTokenSet(accessToken: "production-access")

        try store.save(sandboxToken, environment: .sandbox)
        try store.save(productionToken, environment: .production)

        XCTAssertEqual(try store.load(environment: .sandbox), sandboxToken)
        XCTAssertEqual(try store.load(environment: .production), productionToken)
        XCTAssertEqual(Set(adapter.accounts), ["ezzk.oauth.sandbox", "ezzk.oauth.production"])
    }

    func testDeleteRemovesOnlySelectedEnvironment() throws {
        let adapter = InMemoryEZZKKeychainAdapter()
        let store = EZZKTokenStore(adapter: adapter)

        try store.save(makeTokenSet(accessToken: "sandbox"), environment: .sandbox)
        try store.save(makeTokenSet(accessToken: "production"), environment: .production)
        try store.delete(environment: .sandbox)

        XCTAssertNil(try store.load(environment: .sandbox))
        XCTAssertEqual(try store.load(environment: .production)?.accessToken, "production")
    }

    func testMalformedStoredDataFailsClosedWithTypedError() {
        let adapter = InMemoryEZZKKeychainAdapter()
        let store = EZZKTokenStore(adapter: adapter)
        adapter.dataByAccount["ezzk.oauth.sandbox"] = Data("not-json".utf8)

        XCTAssertThrowsError(try store.load(environment: .sandbox)) { error in
            XCTAssertEqual(error as? EZZKTokenStoreError, .malformedData)
        }
    }

    func testKeychainFailureIsMappedToTypedStorageError() {
        let adapter = InMemoryEZZKKeychainAdapter()
        let store = EZZKTokenStore(adapter: adapter)
        adapter.failure = .status(Int32(errSecAuthFailed))

        XCTAssertThrowsError(try store.load(environment: .sandbox)) { error in
            XCTAssertEqual(error as? EZZKTokenStoreError,
                           .keychainFailure(status: Int32(errSecAuthFailed)))
        }
    }

    private func makeTokenSet(accessToken: String = "access") -> EZZKTokenSet {
        EZZKTokenSet(accessToken: accessToken,
                     refreshToken: "refresh",
                     expiration: Date(timeIntervalSince1970: 1_750_000_000),
                     tokenType: "Bearer")
    }
}

private final class InMemoryEZZKKeychainAdapter: EZZKKeychainAdapter, @unchecked Sendable {
    var dataByAccount: [String: Data] = [:]
    var failure: EZZKKeychainAdapterError?
    private(set) var service: String?

    var accounts: [String] { Array(dataByAccount.keys) }

    func read(service: String, account: String) throws -> Data? {
        self.service = service
        try failIfNeeded()
        return dataByAccount[account]
    }

    func write(_ data: Data, service: String, account: String) throws {
        self.service = service
        try failIfNeeded()
        dataByAccount[account] = data
    }

    func delete(service: String, account: String) throws {
        self.service = service
        try failIfNeeded()
        dataByAccount.removeValue(forKey: account)
    }

    private func failIfNeeded() throws {
        if let failure { throw failure }
    }
}
