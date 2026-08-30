import Foundation

public struct EZZKOAuthConfiguration: Sendable, Equatable {
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
    ) {
        self.issuerURL = issuerURL
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.callbackScheme = callbackScheme
        self.scopes = scopes
    }

    public var isNativeCallbackConfigured: Bool {
        guard let redirectURI,
              let callbackScheme,
              !callbackScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return redirectURI.scheme != nil
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
