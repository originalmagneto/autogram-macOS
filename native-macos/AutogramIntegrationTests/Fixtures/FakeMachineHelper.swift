import Foundation
@testable import Autogram

struct FakeMachineHelper {
    enum Behavior: String {
        case splitEvent
        case captureInput
        case waits
        case terminalThenWaits
        case exitsWithError
        case exitsWithDiagnostic
    }

    let directoryURL: URL
    let executableURL: URL
    private let behavior: Behavior

    init(behavior: Behavior = .splitEvent) throws {
        self.behavior = behavior
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "AutogramIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        executableURL = directoryURL.appending(path: "fake-machine-helper")
        let script = """
        #!/bin/sh
        case "$AUTOGRAM_TEST_MODE" in
        splitEvent)
            printf '%s' '{\"protocolVersion\":1,\"type\":\"session.started\",'
            sleep 0.05
            printf '%s\\n' '\"sessionId\":\"session-1\",\"emittedAt\":\"2026-08-06T00:00:00Z\",\"fileId\":null,\"payload\":{}}'
            ;;
        captureInput)
            printf '%s\\n' "$@" > "$AUTOGRAM_TEST_DIRECTORY/arguments"
            env > "$AUTOGRAM_TEST_DIRECTORY/environment"
            cat > "$AUTOGRAM_TEST_DIRECTORY/standard-input"
            ;;
        waits)
            trap 'exit 0' TERM INT
            while :; do sleep 1; done
            ;;
        terminalThenWaits)
            cat > /dev/null
            printf '%s\n' '{"protocolVersion":1,"type":"session.completed","sessionId":"terminal-1","emittedAt":"2026-08-06T00:00:00Z","fileId":null,"payload":{}}'
            while :; do sleep 1; done
            ;;
        exitsWithError)
            cat > /dev/null
            printf '%s\\n' 'test-helper-sensitive-stderr' >&2
            exit 70
            ;;
        exitsWithDiagnostic)
            cat > /dev/null
            printf '%s\\n' 'Timestamp service unavailable [TIMESTAMP_UNAVAILABLE] for /private/var/tmp/source.pdf' >&2
            exit 70
            ;;
        esac
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
    }

    func configuration(timeout: Duration? = nil) -> ProcessConfiguration {
        ProcessConfiguration(
            executableURL: executableURL,
            timeout: timeout,
            environment: [
                "AUTOGRAM_TEST_MODE": behavior.rawValue,
                "AUTOGRAM_TEST_DIRECTORY": directoryURL.path
            ]
        )
    }

    func contents(of name: String) throws -> String {
        try String(contentsOf: directoryURL.appending(path: name), encoding: .utf8)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }
}
