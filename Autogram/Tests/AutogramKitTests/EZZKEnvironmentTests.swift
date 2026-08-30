import XCTest
@testable import AutogramKit

final class EZZKEnvironmentTests: XCTestCase {
    func testSandboxIdentityUsesFixedPortalAndAPIURLs() {
        let environment = EZZKEnvironment.sandbox

        XCTAssertEqual(environment.portalBaseURL.absoluteString, "https://ezzk-test.iomo.sk")
        XCTAssertEqual(environment.apiBaseURL.absoluteString, "https://ezzk-test.iomo.sk/api/zzkservice/v1")
        XCTAssertEqual(environment.authorityID, "ezzk-sandbox")
    }

    func testProductionIdentityUsesFixedPortalAndAPIURLs() {
        let environment = EZZKEnvironment.production

        XCTAssertEqual(environment.portalBaseURL.absoluteString, "https://ezzk.iomo.sk")
        XCTAssertEqual(environment.apiBaseURL.absoluteString, "https://ezzk.iomo.sk/api/zzkservice/v1")
        XCTAssertEqual(environment.authorityID, "ezzk-production")
    }

    func testEnvironmentIdentitiesAreDistinctAndCodable() throws {
        XCTAssertEqual(Set(EZZKEnvironment.allCases).count, 2)
        XCTAssertNotEqual(EZZKEnvironment.sandbox.authorityID, EZZKEnvironment.production.authorityID)
        XCTAssertNotEqual(EZZKEnvironment.sandbox.portalBaseURL, EZZKEnvironment.production.portalBaseURL)

        let data = try JSONEncoder().encode(EZZKEnvironment.sandbox)
        XCTAssertEqual(try JSONDecoder().decode(EZZKEnvironment.self, from: data), .sandbox)
    }

    func testOAuthDefaultsRemainWebOnlyUntilNativeCallbackIsConfirmed() {
        let configuration = EZZKOAuthConfiguration()

        XCTAssertEqual(configuration.issuerURL.absoluteString, "https://ezzk.iomo.sk/sso/auth/realms/ezzk")
        XCTAssertEqual(configuration.clientID, "login-app")
        XCTAssertNil(configuration.redirectURI)
        XCTAssertNil(configuration.callbackScheme)
        XCTAssertFalse(configuration.isNativeCallbackConfigured)
    }

    func testOAuthConfigurationRequiresBothNativeCallbackParts() {
        let redirectOnly = EZZKOAuthConfiguration(
            redirectURI: URL(string: "autogram://ezzk/callback"))
        let schemeOnly = EZZKOAuthConfiguration(callbackScheme: "autogram")
        let configured = EZZKOAuthConfiguration(
            redirectURI: URL(string: "autogram://ezzk/callback"),
            callbackScheme: "autogram")

        XCTAssertFalse(redirectOnly.isNativeCallbackConfigured)
        XCTAssertFalse(schemeOnly.isNativeCallbackConfigured)
        XCTAssertTrue(configured.isNativeCallbackConfigured)
    }
}
