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
    let issuer: String
    let validFrom: Date
    let validUntil: Date
    let certificateKey: String
    let holderKey: String
    let certificateQualification: String?

    var id: String {
        certificateKey.isEmpty ? serialNumber : certificateKey
    }

    init(serialNumber: String, displayName: String) {
        self.serialNumber = serialNumber
        self.displayName = displayName
        issuer = ""
        validFrom = .distantPast
        validUntil = .distantFuture
        certificateKey = ""
        holderKey = ""
        certificateQualification = nil
    }

    init(
        serialNumber: String,
        displayName: String,
        issuer: String,
        validFrom: Date,
        validUntil: Date,
        certificateKey: String,
        holderKey: String,
        certificateQualification: String? = nil
    ) {
        self.serialNumber = serialNumber
        self.displayName = displayName
        self.issuer = issuer
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.certificateKey = certificateKey
        self.holderKey = holderKey
        self.certificateQualification = certificateQualification
    }
}
