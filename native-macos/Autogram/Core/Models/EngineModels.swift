import Foundation

struct EngineCapabilities: Sendable, Equatable {
    let protocolVersion: Int
    let supportsQualifiedTimestamp: Bool

    init(protocolVersion: Int, supportsQualifiedTimestamp: Bool) {
        self.protocolVersion = protocolVersion
        self.supportsQualifiedTimestamp = supportsQualifiedTimestamp
    }
}

struct SigningDriver: Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let middlewareVersion: String?
    let tokenPresent: Bool?

    init(id: String, displayName: String, middlewareVersion: String? = nil, tokenPresent: Bool? = nil) {
        self.id = id
        self.displayName = displayName
        self.middlewareVersion = middlewareVersion
        self.tokenPresent = tokenPresent
    }
}

struct SigningCertificate: Sendable, Equatable, Identifiable {
    let serialNumber: String
    let displayName: String

    var id: String {
        serialNumber
    }

    init(serialNumber: String, displayName: String) {
        self.serialNumber = serialNumber
        self.displayName = displayName
    }
}
