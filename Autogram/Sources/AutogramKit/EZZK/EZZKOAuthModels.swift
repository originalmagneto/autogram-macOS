import Foundation

public enum EZZKOAuthConfigurationError: Error, Equatable, Sendable {
    case invalidIssuerURL
}

public struct EZZKOAuthConfiguration: Sendable, Equatable {
    private static let fixedIssuerURL = URL(string: "https://ezzk.iomo.sk/sso/auth/realms/ezzk")!
    private static let observedWebRedirect = URL(string: "https://ezzk.iomo.sk/portal")!
    public static let nativeRedirectURI = URL(string: "autogram://ezzk/callback")!
    public static let nativeCallbackScheme = "autogram"
    public let issuerURL: URL
    public let clientID: String
    public let redirectURI: URL?
    public let callbackScheme: String?
    public let scopes: [String]

    public init(
        issuerURL: URL = URL(string: "https://ezzk.iomo.sk/sso/auth/realms/ezzk")!,
        clientID: String = "login-app",
        redirectURI: URL? = EZZKOAuthConfiguration.nativeRedirectURI,
        callbackScheme: String? = EZZKOAuthConfiguration.nativeCallbackScheme,
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
        let normalizedRedirectScheme = redirectScheme.lowercased()
        let normalizedCallbackScheme = callbackScheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedCallbackScheme.isEmpty,
              !Self.webSchemes.contains(normalizedRedirectScheme),
              !Self.webSchemes.contains(normalizedCallbackScheme) else {
            return false
        }
        return normalizedRedirectScheme == normalizedCallbackScheme
    }

    public var isAuthenticationCallbackConfigured: Bool {
        isNativeCallbackConfigured
    }

    private static let webSchemes = Set(["http", "https"])
}

public struct EZZKTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiration: Date
    public let tokenType: String
    public let tokenEndpoint: URL?

    public init(
        accessToken: String,
        refreshToken: String?,
        expiration: Date,
        tokenType: String,
        tokenEndpoint: URL? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiration = expiration
        self.tokenType = tokenType
        self.tokenEndpoint = tokenEndpoint
    }
}
public protocol EZZKTokenStoring: Sendable {
    func load(environment: EZZKEnvironment) throws -> EZZKTokenSet?
    func save(_ tokenSet: EZZKTokenSet, environment: EZZKEnvironment) throws
    func delete(environment: EZZKEnvironment) throws
}
