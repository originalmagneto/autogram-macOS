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
}
