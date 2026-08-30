import CryptoKit
import Foundation

public struct EZZKPKCEChallenge: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let state: String

    public init() {
        var generator = SystemRandomNumberGenerator()
        let verifier = Self.base64URL(Self.randomData(count: 32, using: &generator))
        let state = Self.base64URL(Self.randomData(count: 32, using: &generator))
        self.init(verifier: verifier, state: state)
    }

    public init(verifier: String, state: String) {
        self.verifier = verifier
        self.challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        self.state = state
    }

    public init(verifier: String, challenge: String, state: String) {
        self.verifier = verifier
        self.challenge = challenge
        self.state = state
    }

    public static func generate() -> Self {
        Self()
    }

    private static func randomData<G: RandomNumberGenerator>(
        count: Int,
        using generator: inout G
    ) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum EZZKOAuthCallbackError: Error, Equatable, Sendable {
    case malformedURL
    case malformedParameter
    case duplicateParameter
    case missingCode
    case missingState
    case stateMismatch
    case cancelled
    case authenticationFailed
}

public struct EZZKOAuthCallback: Equatable, Sendable {
    public let authorizationCode: String
    public let state: String

    public init(authorizationCode: String, state: String) {
        self.authorizationCode = authorizationCode
        self.state = state
    }

    public static func parse(url: URL, expectedState: String) throws -> Self {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              !scheme.isEmpty,
              components.fragment == nil || components.fragment?.isEmpty == true,
              !expectedState.isEmpty,
              isValidValue(expectedState) else {
            throw EZZKOAuthCallbackError.malformedURL
        }

        let parameters = try parseQuery(components.percentEncodedQuery)
        guard let state = parameters["state"] else {
            throw EZZKOAuthCallbackError.missingState
        }
        guard constantTimeEqual(state, expectedState) else {
            throw EZZKOAuthCallbackError.stateMismatch
        }

        if let error = parameters["error"] {
            guard parameters["code"] == nil else {
                throw EZZKOAuthCallbackError.malformedParameter
            }
            switch error {
            case "access_denied", "user_cancelled", "cancelled":
                throw EZZKOAuthCallbackError.cancelled
            default:
                throw EZZKOAuthCallbackError.authenticationFailed
            }
        }

        guard let code = parameters["code"] else {
            throw EZZKOAuthCallbackError.missingCode
        }
        guard isValidValue(code) else {
            throw EZZKOAuthCallbackError.malformedParameter
        }
        return Self(authorizationCode: code, state: state)
    }

    private static func parseQuery(_ query: String?) throws -> [String: String] {
        guard let query, !query.isEmpty else {
            throw EZZKOAuthCallbackError.malformedURL
        }

        var parameters: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            guard let separator = pair.firstIndex(of: "=") else {
                throw EZZKOAuthCallbackError.malformedParameter
            }
            let encodedName = String(pair[..<separator])
            let encodedValue = String(pair[pair.index(after: separator)...])
            guard let name = formDecode(encodedName),
                  let value = formDecode(encodedValue),
                  !name.isEmpty,
                  !value.isEmpty,
                  ["code", "state", "error", "error_description", "error_uri"].contains(name),
                  parameters[name] == nil else {
                if let name = formDecode(encodedName), parameters[name] != nil {
                    throw EZZKOAuthCallbackError.duplicateParameter
                }
                throw EZZKOAuthCallbackError.malformedParameter
            }
            parameters[name] = value
        }
        return parameters
    }

    private static func formDecode(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsData = Data(lhs.utf8)
        let rhsData = Data(rhs.utf8)
        guard lhsData.count == rhsData.count else { return false }

        var difference: UInt8 = 0
        for index in lhsData.indices {
            difference |= lhsData[index] ^ rhsData[index]
        }
        return difference == 0
    }

    private static func isValidValue(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
        }
    }
}
