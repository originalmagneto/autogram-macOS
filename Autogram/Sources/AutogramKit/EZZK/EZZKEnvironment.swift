import Foundation

public enum EZZKEnvironment: String, Codable, CaseIterable, Sendable {
    case sandbox
    case production

    public var portalBaseURL: URL {
        switch self {
        case .sandbox:
            URL(string: "https://ezzk-test.iomo.sk")!
        case .production:
            URL(string: "https://ezzk.iomo.sk")!
        }
    }

    public var apiBaseURL: URL {
        portalBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("zzkservice")
            .appendingPathComponent("v1")
    }

    public var soapLoginURL: URL {
        portalBaseURL
            .appendingPathComponent("Iam.Core3.Svc.Wcf")
            .appendingPathComponent("LogInService.svc")
    }

    public var soapServiceURL: URL {
        portalBaseURL
            .appendingPathComponent("EZZK.Svc.Wcf")
            .appendingPathComponent("EZZKService.svc")
    }

    /// SHA-256 of the leaf certificate this environment must present, lowercase hex.
    /// Test uses a self-signed certificate (valid until 2026-10-20); production uses system trust.
    public var pinnedCertificateSHA256: String? {
        switch self {
        case .sandbox:
            "d16f5b61720a595308565dd84e32935e7a7de83a6c2fa8f0e6413451ed2b12e2"
        case .production:
            nil
        }
    }

    public var authorityID: String {
        switch self {
        case .sandbox:
            "ezzk-sandbox"
        case .production:
            "ezzk-production"
        }
    }
}
