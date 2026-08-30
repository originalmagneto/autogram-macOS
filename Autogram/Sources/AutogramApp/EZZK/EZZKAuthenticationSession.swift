import AuthenticationServices
import AutogramKit
import Foundation

@MainActor
protocol EZZKAuthenticationSessionRunning: AnyObject {
    func authenticate(configuration: EZZKOAuthConfiguration) async throws -> EZZKTokenSet
}

enum EZZKAuthenticationError: Error, Equatable, Sendable {
    case nativeCallbackNotConfigured
    case authenticationInProgress
    case discoveryFailed
    case issuerMismatch
    case insecureEndpoint
    case invalidAuthorizationEndpoint
    case sessionUnavailable
    case cancelled
    case authenticationFailed
    case callback(EZZKOAuthCallbackError)
    case tokenExchangeFailed
    case malformedTokenResponse
}

private final class EZZKRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let issuer: URL

    init(issuer: URL) {
        self.issuer = issuer
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @Sendable @escaping (URLRequest?) -> Void
    ) {
        guard let destination = request.url,
              destination.scheme?.caseInsensitiveCompare("https") == .orderedSame,
              destination.host == issuer.host,
              destination.user == nil,
              destination.password == nil,
              normalizedPort(destination) == normalizedPort(issuer) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private func normalizedPort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.caseInsensitiveCompare("https") == .orderedSame ? 443 : nil)
    }
}

@MainActor
final class EZZKAuthenticationSession: NSObject, EZZKAuthenticationSessionRunning, ASWebAuthenticationPresentationContextProviding {
    private struct DiscoveryDocument: Decodable {
        let issuer: String
        let authorizationEndpoint: URL
        let tokenEndpoint: URL

        enum CodingKeys: String, CodingKey {
            case issuer
            case authorizationEndpoint = "authorization_endpoint"
            case tokenEndpoint = "token_endpoint"
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }

    private var webSession: ASWebAuthenticationSession?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var authenticationInProgress = false

    func authenticate(configuration: EZZKOAuthConfiguration) async throws -> EZZKTokenSet {
        guard !authenticationInProgress else {
            throw EZZKAuthenticationError.authenticationInProgress
        }
        guard configuration.isNativeCallbackConfigured,
              let redirectURI = configuration.redirectURI,
              let callbackScheme = configuration.callbackScheme?.trimmingCharacters(in: .whitespacesAndNewlines),
              !callbackScheme.isEmpty else {
            throw EZZKAuthenticationError.nativeCallbackNotConfigured
        }

        authenticationInProgress = true
        defer {
            authenticationInProgress = false
            webSession = nil
            callbackContinuation = nil
        }
        let discovery = try await discover(configuration: configuration)
        let pkce = EZZKPKCEChallenge.generate()
        let authorizationURL = try makeAuthorizationURL(
            endpoint: discovery.authorizationEndpoint,
            configuration: configuration,
            redirectURI: redirectURI,
            pkce: pkce
        )
        let callbackURL = try await startWebSession(
            authorizationURL: authorizationURL,
            callbackScheme: callbackScheme
        )
        let callback: EZZKOAuthCallback
        do {
            callback = try EZZKOAuthCallback.parse(url: callbackURL, expectedState: pkce.state)
        } catch let error as EZZKOAuthCallbackError {
            throw EZZKAuthenticationError.callback(error)
        } catch {
            throw EZZKAuthenticationError.authenticationFailed
        }

        return try await exchange(
            code: callback.authorizationCode,
            verifier: pkce.verifier,
            configuration: configuration,
            redirectURI: redirectURI,
            tokenEndpoint: discovery.tokenEndpoint
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: true
        )
    }

    private func discover(configuration: EZZKOAuthConfiguration) async throws -> DiscoveryDocument {
        let discoveryURL = configuration.issuerURL.appendingPathComponent(".well-known/openid-configuration")
        guard isHTTPS(discoveryURL), discoveryURL.host == configuration.issuerURL.host else {
            throw EZZKAuthenticationError.insecureEndpoint
        }

        do {
            let (data, response) = try await requestData(
                URLRequest(url: discoveryURL),
                issuer: configuration.issuerURL
            )
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw EZZKAuthenticationError.discoveryFailed
            }
            let document = try JSONDecoder().decode(DiscoveryDocument.self, from: data)
            guard let metadataIssuer = URL(string: document.issuer), metadataIssuer == configuration.issuerURL else {
                throw EZZKAuthenticationError.issuerMismatch
            }
            guard validEndpoint(document.authorizationEndpoint, issuer: configuration.issuerURL),
                  validEndpoint(document.tokenEndpoint, issuer: configuration.issuerURL) else {
                throw EZZKAuthenticationError.insecureEndpoint
            }
            return document
        } catch let error as EZZKAuthenticationError {
            throw error
        } catch {
            throw EZZKAuthenticationError.discoveryFailed
        }
    }
    private func requestData(
        _ request: URLRequest,
        issuer: URL
    ) async throws -> (Data, URLResponse) {
        let policy = EZZKRedirectPolicy(issuer: issuer)
        let session = URLSession(
            configuration: .ephemeral,
            delegate: policy,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }


    private func startWebSession(
        authorizationURL: URL,
        callbackScheme: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor [weak self] in
                    self?.finishWebSession(callbackURL: callbackURL, error: error)
                }
            }
            session.presentationContextProvider = self
            webSession = session
            guard session.start() else {
                webSession = nil
                callbackContinuation = nil
                continuation.resume(throwing: EZZKAuthenticationError.sessionUnavailable)
                return
            }
        }
    }

    private func finishWebSession(callbackURL: URL?, error: Error?) {
        guard let continuation = callbackContinuation else { return }
        callbackContinuation = nil
        webSession = nil

        if let error {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                continuation.resume(throwing: EZZKAuthenticationError.cancelled)
            } else {
                continuation.resume(throwing: EZZKAuthenticationError.authenticationFailed)
            }
            return
        }
        guard let callbackURL else {
            continuation.resume(throwing: EZZKAuthenticationError.authenticationFailed)
            return
        }
        continuation.resume(returning: callbackURL)
    }

    private func makeAuthorizationURL(
        endpoint: URL,
        configuration: EZZKOAuthConfiguration,
        redirectURI: URL,
        pkce: EZZKPKCEChallenge
    ) throws -> URL {
        guard validEndpoint(endpoint, issuer: configuration.issuerURL) else {
            throw EZZKAuthenticationError.invalidAuthorizationEndpoint
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.fragment == nil else {
            throw EZZKAuthenticationError.invalidAuthorizationEndpoint
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state)
        ]
        guard let url = components.url else {
            throw EZZKAuthenticationError.invalidAuthorizationEndpoint
        }
        return url
    }

    private func exchange(
        code: String,
        verifier: String,
        configuration: EZZKOAuthConfiguration,
        redirectURI: URL,
        tokenEndpoint: URL
    ) async throws -> EZZKTokenSet {
        guard validEndpoint(tokenEndpoint, issuer: configuration.issuerURL) else {
            throw EZZKAuthenticationError.insecureEndpoint
        }
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            ("grant_type", "authorization_code"),
            ("client_id", configuration.clientID),
            ("code", code),
            ("redirect_uri", redirectURI.absoluteString),
            ("code_verifier", verifier)
        ])

        do {
            let (data, response) = try await requestData(request, issuer: configuration.issuerURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw EZZKAuthenticationError.tokenExchangeFailed
            }
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard isValidTokenValue(token.accessToken),
                  isValidTokenValue(token.tokenType),
                  token.expiresIn > 0,
                  token.refreshToken.map(isValidTokenValue) ?? true else {
                throw EZZKAuthenticationError.malformedTokenResponse
            }
            return EZZKTokenSet(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiration: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                tokenType: token.tokenType
            )
        } catch let error as EZZKAuthenticationError {
            throw error
        } catch is DecodingError {
            throw EZZKAuthenticationError.malformedTokenResponse
        } catch {
            throw EZZKAuthenticationError.tokenExchangeFailed
        }
    }

    private func isValidTokenValue(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
        }
    }

    private func formEncoded(_ values: [(String, String)]) -> Data? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let string = values.map { name, value in
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(encodedName)=\(encodedValue)"
        }.joined(separator: "&")
        return string.data(using: .utf8)
    }

    private func validEndpoint(_ endpoint: URL, issuer: URL) -> Bool {
        guard isHTTPS(endpoint),
              endpoint.host == issuer.host,
              endpoint.user == nil,
              endpoint.password == nil,
              normalizedPort(endpoint) == normalizedPort(issuer),
              endpoint.fragment == nil else {
            return false
        }
        return true
    }

    private func normalizedPort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.caseInsensitiveCompare("https") == .orderedSame ? 443 : nil)
    }

    private func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame && url.host != nil
    }
}
