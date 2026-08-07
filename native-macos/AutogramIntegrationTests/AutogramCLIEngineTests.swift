import Foundation
import Testing
@testable import Autogram

@Test func signingTranslatesToQualifiedTimestampRequestAndFinalizesValidatedOutput() async throws {
    let fixture = try SigningMachineFixture()
    defer { try? fixture.remove() }

    let source = fixture.directoryURL.appending(path: "agreement.pdf")
    try Data("%PDF-1.7\nsource\n%%EOF\n".utf8).write(to: source)
    let engine = AutogramCLIEngine(configuration: fixture.configuration())
    let request = SigningRequest(
        sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        driverID: "token-1",
        certificateSerial: "certificate-1",
        pin: Secret("1234"),
        files: [SigningFile(id: "agreement", sourceURL: source)]
    )

    var events: [SigningEvent] = []
    for try await event in engine.sign(request: request) {
        events.append(event)
    }

    let requestJSON = try fixture.requestJSON()
    #expect(requestJSON["requestId"] as? String == "00000000-0000-0000-0000-000000000001")
    #expect(requestJSON["operation"] as? String == "SIGN")
    let payload = try #require(requestJSON["payload"] as? [String: Any])
    #expect(payload["signatureLevel"] as? String == "PAdES_BASELINE_T")
    #expect((payload["timestamp"] as? [String: Any])?["required"] as? Bool == true)
    #expect((payload["files"] as? [[String: Any]])?.map { $0["id"] as? String } == ["agreement"])
    #expect(events == [.started, .fileSigning("agreement"), .completed("agreement")])
    #expect(try fixture.finalizedOutput().starts(with: Data("%PDF-".utf8)))
}

@Test func fakeEngineRequiresAnExplicitSupportedDebugLaunchFlag() {
    let production = AppLaunchDependencies.make(environment: [:])
    #expect(production.fixtureMode == nil)
    #expect(production.engine is AutogramCLIEngine)

    let unsupported = AppLaunchDependencies.make(environment: ["AUTOGRAM_FAKE_ENGINE": "unsupported"])
    #expect(unsupported.fixtureMode == nil)
    #expect(unsupported.engine is AutogramCLIEngine)

    #if DEBUG
    let fixture = AppLaunchDependencies.make(environment: ["AUTOGRAM_FAKE_ENGINE": "partial-failure"])
    #expect(fixture.fixtureMode == "partial-failure")
    #expect(fixture.engine is FakeSigningEngine)
    #endif
}

@Test func signingHelperEnvironmentKeepsRequiredDirectoriesWithoutForwardingSecrets() {
    let environment = ProcessConfiguration.signingHelperEnvironment(from: [
        "HOME": "/Users/example",
        "TMPDIR": "/private/tmp/example",
        "AUTOGRAM_PRIVATE_TEST_VALUE": "must-not-be-forwarded"
    ])

    #expect(environment["HOME"] == "/Users/example")
    #expect(environment["TMPDIR"] == "/private/tmp/example")
    #expect(environment["AUTOGRAM_PRIVATE_TEST_VALUE"] == nil)
}

private struct SigningMachineFixture {
    let directoryURL: URL
    let executableURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "AutogramCLIEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        executableURL = directoryURL.appending(path: "machine-helper")
        let script = """
        #!/bin/sh
        input="$AUTOGRAM_TEST_DIRECTORY/request.json"
        cat > "$input"
        printf '%%PDF-1.7\\n%%%%EOF\\n' > "$AUTOGRAM_TEST_DIRECTORY/agreement_signed.pdf"
        printf '%s\\n' '{"protocolVersion":1,"type":"session.started","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:00.123456Z","fileId":null,"payload":{}}'
        printf '%s\\n' '{"protocolVersion":1,"type":"file.signingStarted","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:01Z","fileId":"agreement","payload":{}}'
        printf '%s\\n' '{"protocolVersion":1,"type":"file.completed","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:02Z","fileId":"agreement","payload":{}}'
        printf '%s\\n' '{"protocolVersion":1,"type":"session.completed","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:03Z","fileId":null,"payload":{}}'
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

    func requestJSON() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: directoryURL.appending(path: "request.json"))) as! [String: Any]
    }

    func finalizedOutput() throws -> Data {
        try Data(contentsOf: directoryURL.appending(path: "agreement_signed.pdf"))
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }
}
