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

    func testOAuthDefaultsRemainWebOnlyUntilNativeCallbackIsConfirmed() throws {
        let configuration = try EZZKOAuthConfiguration()

        XCTAssertEqual(configuration.issuerURL.absoluteString, "https://ezzk.iomo.sk/sso/auth/realms/ezzk")
        XCTAssertEqual(configuration.clientID, "login-app")
        XCTAssertNil(configuration.redirectURI)
        XCTAssertNil(configuration.callbackScheme)
        XCTAssertFalse(configuration.isNativeCallbackConfigured)
    }

    func testOAuthConfigurationRejectsNonCanonicalIssuer() {
        XCTAssertThrowsError(try EZZKOAuthConfiguration(
            issuerURL: URL(string: "https://evil.example/realm")!)) { error in
            XCTAssertEqual(error as? EZZKOAuthConfigurationError, .invalidIssuerURL)
        }
    }

    func testOAuthConfigurationRequiresBothNativeCallbackParts() throws {
        let redirectOnly = try EZZKOAuthConfiguration(
            redirectURI: URL(string: "autogram://ezzk/callback"))
        let schemeOnly = try EZZKOAuthConfiguration(callbackScheme: "autogram")
        let configured = try EZZKOAuthConfiguration(
            redirectURI: URL(string: "autogram://ezzk/callback"),
            callbackScheme: "autogram")

        XCTAssertFalse(redirectOnly.isNativeCallbackConfigured)
        XCTAssertFalse(schemeOnly.isNativeCallbackConfigured)
        XCTAssertTrue(configured.isNativeCallbackConfigured)
    }

    func testNativeCallbackRejectsObservedWebRedirectAndMismatchedScheme() throws {
        let observedWebRedirect = try EZZKOAuthConfiguration(
            redirectURI: URL(string: "https://ezzk.iomo.sk/portal"),
            callbackScheme: "https")
        let mismatchedScheme = try EZZKOAuthConfiguration(
            redirectURI: URL(string: "autogram://ezzk/callback"),
            callbackScheme: "other")

        XCTAssertFalse(observedWebRedirect.isNativeCallbackConfigured)
        XCTAssertFalse(mismatchedScheme.isNativeCallbackConfigured)
    }
}
