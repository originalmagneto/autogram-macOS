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

    public var authorityID: String {
        switch self {
        case .sandbox:
            "ezzk-sandbox"
        case .production:
            "ezzk-production"
        }
    }
}
