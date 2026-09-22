import Foundation

enum DriverMiddleware: Sendable, Equatable {
    case icaSecureStore(version: String)
}

struct DriverCandidate: Sendable, Equatable {
    let url: URL
    let middleware: DriverMiddleware?

    init(url: URL, middleware: DriverMiddleware? = nil) {
        self.url = url
        self.middleware = middleware
    }

    static func icaSecureStore(url: URL, version: String) -> Self {
        Self(url: url, middleware: .icaSecureStore(version: version))
    }
}

enum DriverRequirementError: Error, Sendable, Equatable, LocalizedError {
    case arm64Required
    case icaSecureStoreUpdateRequired(minimum: String)
    case architectureInspectionFailed

    var errorDescription: String? {
        switch self {
        case .arm64Required:
            String(localized: "The selected signing component must include an ARM64 slice.")
        case .icaSecureStoreUpdateRequired(let minimum):
            String(localized: "I.CA SecureStore \(minimum) or newer is required.")
        case .architectureInspectionFailed:
            String(localized: "The selected signing component could not be inspected.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .arm64Required:
            String(localized: "Install an ARM64-compatible signing component and try again.")
        case .icaSecureStoreUpdateRequired(let minimum):
            String(localized: "Install I.CA SecureStore \(minimum) or newer and try again.")
        case .architectureInspectionFailed:
            String(localized: "Reinstall the signing component and try again.")
        }
    }
}

struct MiddlewareRequirementValidator: Sendable {
    static let icaMinimumVersion = "8.3.1"

    func validate(_ driver: DriverCandidate) throws {
        guard let middleware = driver.middleware else { return }
        let version: String
        switch middleware {
        case .icaSecureStore(let value): version = value
        }
        guard Self.isAtLeast(version, minimum: Self.icaMinimumVersion) else {
            throw DriverRequirementError.icaSecureStoreUpdateRequired(minimum: Self.icaMinimumVersion)
        }
    }

    private static func isAtLeast(_ version: String, minimum: String) -> Bool {
        let current = version.split(separator: ".").map { Int($0) ?? -1 }
        let required = minimum.split(separator: ".").compactMap { Int($0) }
        guard current.allSatisfy({ $0 >= 0 }) else { return false }
        for index in 0..<max(current.count, required.count) {
            let currentPart = current.indices.contains(index) ? current[index] : 0
            let requiredPart = required.indices.contains(index) ? required[index] : 0
            if currentPart != requiredPart { return currentPart > requiredPart }
        }
        return true
    }
}
