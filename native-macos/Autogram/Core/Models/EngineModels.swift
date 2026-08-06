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

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
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
