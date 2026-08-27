import Foundation

enum HelperArchitecture: String, Sendable, Equatable {
    case arm64
}

struct ResolvedDriver: Sendable, Equatable {
    let helperURL: URL
    let driverURL: URL
    let architecture: HelperArchitecture
    let middlewareVersion: String?
}

struct DriverResolver: Sendable {
    private let inspector: MachOInspector
    private let middlewareValidator: MiddlewareRequirementValidator

    init(
        lipo: any LipoProcess = SystemLipoProcess(),
        middlewareValidator: MiddlewareRequirementValidator = .init()
    ) {
        inspector = MachOInspector(lipo: lipo)
        self.middlewareValidator = middlewareValidator
    }

    func resolve(helperURL: URL, driver: DriverCandidate) throws -> ResolvedDriver {
        guard try inspector.containsArm64Slice(at: helperURL),
              try inspector.containsArm64Slice(at: driver.url) else {
            throw DriverRequirementError.arm64Required
        }
        try middlewareValidator.validate(driver)
        return ResolvedDriver(
            helperURL: helperURL,
            driverURL: driver.url,
            architecture: .arm64,
            middlewareVersion: middlewareVersion(of: driver)
        )
    }

    private func middlewareVersion(of driver: DriverCandidate) -> String? {
        guard case let .icaSecureStore(version)? = driver.middleware else { return nil }
        return version
    }
}
