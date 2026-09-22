import Foundation

struct ProcessConfiguration: Sendable {
    let executableURL: URL
    let timeout: Duration?
    let environment: [String: String]
    let maxStdoutLineBytes: Int
    let maxStderrBytes: Int

    init(
        executableURL: URL,
        timeout: Duration? = nil,
        environment: [String: String] = [:],
        maxStdoutLineBytes: Int = 1_048_576,
        maxStderrBytes: Int = 65_536
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.environment = environment
        self.maxStdoutLineBytes = maxStdoutLineBytes
        self.maxStderrBytes = maxStderrBytes
    }

    static func signingHelperEnvironment(
        from source: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let allowedKeys = [
            "HOME",
            "TMPDIR",
            "USER",
            "LOGNAME",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "__CF_USER_TEXT_ENCODING"
        ]
        var environment = allowedKeys.reduce(into: [String: String]()) { result, key in
            guard let value = source[key], !value.isEmpty else { return }
            result[key] = value
        }
        if environment["HOME"] == nil {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        if environment["TMPDIR"] == nil {
            environment["TMPDIR"] = FileManager.default.temporaryDirectory.path
        }
        return environment
    }
}
