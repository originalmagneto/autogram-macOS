import Foundation

public enum EZZKOAuthConfigurationError: Error, Equatable, Sendable {
    case invalidIssuerURL
}

public struct EZZKOAuthConfiguration: Sendable, Equatable {
    private static let fixedIssuerURL = URL(string: "https://ezzk.iomo.sk/sso/auth/realms/ezzk")!
    private static let observedWebRedirect = URL(string: "https://ezzk.iomo.sk/portal")!

    public let issuerURL: URL
    public let clientID: String
    public let redirectURI: URL?
    public let callbackScheme: String?
    public let scopes: [String]

    public init(
        issuerURL: URL = URL(string: "https://ezzk.iomo.sk/sso/auth/realms/ezzk")!,
        clientID: String = "login-app",
        redirectURI: URL? = nil,
        callbackScheme: String? = nil,
        scopes: [String] = ["openid"]
    ) throws {
        guard issuerURL == Self.fixedIssuerURL,
              issuerURL.scheme?.caseInsensitiveCompare("https") == .orderedSame else {
            throw EZZKOAuthConfigurationError.invalidIssuerURL
        }
        self.issuerURL = issuerURL
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.callbackScheme = callbackScheme
        self.scopes = scopes
    }

    public var isNativeCallbackConfigured: Bool {
        guard let redirectURI,
              redirectURI != Self.observedWebRedirect,
              let redirectScheme = redirectURI.scheme,
              let callbackScheme else {
            return false
        }
        let normalizedCallbackScheme = callbackScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCallbackScheme.isEmpty else { return false }
        return redirectScheme.caseInsensitiveCompare(normalizedCallbackScheme) == .orderedSame
    }
}

public struct EZZKTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiration: Date
    public let tokenType: String

    public init(
        accessToken: String,
        refreshToken: String?,
        expiration: Date,
        tokenType: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiration = expiration
        self.tokenType = tokenType
    }
}
public protocol EZZKTokenStoring: Sendable {
    func load(environment: EZZKEnvironment) throws -> EZZKTokenSet?
    func save(_ tokenSet: EZZKTokenSet, environment: EZZKEnvironment) throws
    func delete(environment: EZZKEnvironment) throws
}
