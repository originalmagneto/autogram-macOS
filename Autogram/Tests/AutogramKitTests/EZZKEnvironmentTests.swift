import XCTest
import CryptoKit
import AutogramKit

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

    func testOAuthDefaultsUseNativeCallback() throws {
        let configuration = try EZZKOAuthConfiguration()

        XCTAssertEqual(configuration.issuerURL.absoluteString, "https://ezzk.iomo.sk/sso/auth/realms/ezzk")
        XCTAssertEqual(configuration.clientID, "login-app")
        XCTAssertEqual(configuration.redirectURI, EZZKOAuthConfiguration.nativeRedirectURI)
        XCTAssertEqual(configuration.callbackScheme, EZZKOAuthConfiguration.nativeCallbackScheme)
        XCTAssertTrue(configuration.isNativeCallbackConfigured)
        XCTAssertTrue(configuration.isAuthenticationCallbackConfigured)
    }

    func testOAuthConfigurationRejectsNonCanonicalIssuer() {
        XCTAssertThrowsError(try EZZKOAuthConfiguration(
            issuerURL: URL(string: "https://evil.example/realm")!)) { error in
            XCTAssertEqual(error as? EZZKOAuthConfigurationError, .invalidIssuerURL)
        }
    }

    func testOAuthConfigurationRequiresBothNativeCallbackParts() throws {
        let redirectOnly = try EZZKOAuthConfiguration(
            redirectURI: URL(string: "autogram://ezzk/callback"),
            callbackScheme: nil)
        let schemeOnly = try EZZKOAuthConfiguration(
            redirectURI: nil,
            callbackScheme: "autogram")
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
        XCTAssertFalse(observedWebRedirect.isAuthenticationCallbackConfigured)
        XCTAssertFalse(mismatchedScheme.isNativeCallbackConfigured)
        XCTAssertFalse(mismatchedScheme.isAuthenticationCallbackConfigured)
    }

    func testNativeCallbackRejectsHTTPAndHTTPSSchemes() throws {
        let httpsCallback = try EZZKOAuthConfiguration(
            redirectURI: URL(string: "https://client.example/callback"),
            callbackScheme: "https")
        let httpCallback = try EZZKOAuthConfiguration(
            redirectURI: URL(string: "http://client.example/callback"),
            callbackScheme: "http")

        XCTAssertFalse(httpsCallback.isNativeCallbackConfigured)
        XCTAssertFalse(httpCallback.isNativeCallbackConfigured)
    }
    func testPKCEChallengeUsesS256AndCryptographicallyRandomValues() {
        let first = EZZKPKCEChallenge.generate()
        let second = EZZKPKCEChallenge.generate()

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.verifier.isEmpty)
        XCTAssertFalse(first.challenge.isEmpty)
        XCTAssertFalse(first.state.isEmpty)
        XCTAssertFalse(first.verifier.contains("="))
        XCTAssertFalse(first.challenge.contains("="))
        XCTAssertFalse(first.state.contains("="))

        let expectedChallenge = Data(SHA256.hash(data: Data(first.verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        XCTAssertEqual(first.challenge, expectedChallenge)
    }

    func testOAuthCallbackParserRequiresCodeAndMatchingState() throws {
        let callback = try EZZKOAuthCallback.parse(
            url: URL(string: "autogram://ezzk/callback?code=abc%2F123&state=state-1")!,
            expectedState: "state-1"
        )

        XCTAssertEqual(callback.authorizationCode, "abc/123")
        XCTAssertEqual(callback.state, "state-1")
    }

    func testOAuthCallbackParserRejectsMissingDuplicateAndMismatchedValues() {
        let cases: [(String, EZZKOAuthCallbackError)] = [
            ("autogram://ezzk/callback?state=state-1", .missingCode),
            ("autogram://ezzk/callback?code=abc", .missingState),
            ("autogram://ezzk/callback?code=abc&state=state-2", .stateMismatch),
            ("autogram://ezzk/callback?code=abc&state=wrong", .stateMismatch),
            ("autogram://ezzk/callback?code=&state=state-1", .malformedParameter)
        ]

        for (urlString, expectedError) in cases {
            XCTAssertThrowsError(
                try EZZKOAuthCallback.parse(
                    url: URL(string: urlString)!,
                    expectedState: "state-1"
                )
            ) { error in
                XCTAssertEqual(error as? EZZKOAuthCallbackError, expectedError)
            }
        }
    }

    func testOAuthErrorCallbackMapsToTypedErrorWithoutReturningCode() {
        XCTAssertThrowsError(
            try EZZKOAuthCallback.parse(
                url: URL(string: "autogram://ezzk/callback?error=access_denied&state=state-1")!,
                expectedState: "state-1"
            )
        ) { error in
            XCTAssertEqual(error as? EZZKOAuthCallbackError, .cancelled)
        }

        XCTAssertThrowsError(
            try EZZKOAuthCallback.parse(
                url: URL(string: "autogram://ezzk/callback?error=server_error&state=state-1")!,
                expectedState: "state-1"
            )
        ) { error in
            XCTAssertEqual(error as? EZZKOAuthCallbackError, .authenticationFailed)
        }
    }

}
