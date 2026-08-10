import Foundation
import Testing
@testable import Autogram

@Test func sessionReusesHealthyProcessAndRestartsAfterUnexpectedExit() async throws {
    let helper = try SessionHelper()
    defer { try? helper.remove() }
    let session = MachineSessionProcess()

    _ = try await session.send(.capabilities(requestID: "first"), configuration: helper.configuration())
    _ = try await session.send(.capabilities(requestID: "second"), configuration: helper.configuration())
    #expect(try helper.launchCount() == 1)

    do {
        _ = try await session.send(.inspect(requestID: "unexpected-exit"), configuration: helper.configuration())
        Issue.record("Expected the active request to fail when the helper exits unexpectedly")
    } catch let failure as MachineSessionProcessFailure {
        guard case .helperExited(let status) = failure else {
            Issue.record("Expected an unexpected helper exit failure")
            return
        }
        #expect(status == 70)
    }

    _ = try await session.send(.capabilities(requestID: "after-exit"), configuration: helper.configuration())
    #expect(try helper.launchCount() == 2)
    await session.stop()
}

private struct SessionHelper {
    let directoryURL: URL
    let executableURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "MachineSessionProcessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        executableURL = directoryURL.appending(path: "machine-v2-helper")
        let script = """
        #!/bin/sh
        printf 'launch\n' >> "$AUTOGRAM_TEST_DIRECTORY/launches"
        while IFS= read -r line; do
            case "$line" in
            *\"operation\":\"INSPECT\"*) exit 70 ;;
            esac
            request_id=$(printf '%s\n' "$line" | sed -n 's/.*"requestId":"\\([^"]*\\)".*/\\1/p')
            printf '{"protocolVersion":2,"requestId":"%s","type":"request.completed","emittedAt":"2026-08-10T00:00:00Z","payload":{}}\\n' "$request_id"
        done
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
    }

    func configuration() -> ProcessConfiguration {
        ProcessConfiguration(
            executableURL: executableURL,
            environment: ["AUTOGRAM_TEST_DIRECTORY": directoryURL.path]
        )
    }

    func launchCount() throws -> Int {
        let launches = try String(contentsOf: directoryURL.appending(path: "launches"), encoding: .utf8)
        return launches.split(whereSeparator: \.isNewline).count
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }
}
