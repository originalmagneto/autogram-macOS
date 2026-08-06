import Foundation

struct UserPreferences: Codable, Sendable, Equatable {
    var driverID: String?
    var certificateSerial: String?
    var outputPolicy: OutputPolicy
    var destinationBehavior: DestinationBehavior
    var revealInFinderAfterSigning: Bool

    static let fixture = UserPreferences(
        driverID: "fixture-driver",
        certificateSerial: "fixture-certificate",
        outputPolicy: .signedSuffix,
        destinationBehavior: .besideSource,
        revealInFinderAfterSigning: true
    )
}

enum OutputPolicy: String, Codable, Sendable, CaseIterable, Identifiable {
    case signedSuffix

    var id: Self { self }
}

enum DestinationBehavior: String, Codable, Sendable, CaseIterable, Identifiable {
    case besideSource
    case askEachTime

    var id: Self { self }
}

enum LocalizedMessage {
    static func resolve(messageKey: String, fallback: String) -> String {
        let resolved = NSLocalizedString(messageKey, bundle: .main, value: messageKey, comment: "")
        return resolved == messageKey ? fallback : resolved
    }
}
