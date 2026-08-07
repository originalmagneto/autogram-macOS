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

@Test func fileFailureCodeBecomesAnActionableSigningFailure() async throws {
    let fixture = try SigningMachineFixture(failureCode: "TIMESTAMP_FAILED")
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

    #expect(events == [
        .started,
        .fileSigning("agreement"),
        .failed("agreement", .engine("A qualified timestamp could not be obtained. [TIMESTAMP_FAILED]"))
    ])
}

@Test func inspectionMapsExistingSignatureDetailsFromTheMachinePayload() async throws {
    let fixture = try InspectionMachineFixture()
    defer { try? fixture.remove() }

    let source = fixture.directoryURL.appending(path: "agreement.pdf")
    try Data("%PDF-1.7\nsource\n%%EOF\n".utf8).write(to: source)
    let engine = AutogramCLIEngine(configuration: fixture.configuration())

    let inspections = try await engine.inspect(files: [
        PDFItemDescriptor(id: "agreement", sourceURL: source)
    ])

    let signature = try #require(inspections.first?.files.first?.signatures.first)
    #expect(signature.signerDisplayName == "Ada Lovelace")
    #expect(signature.validationState == .valid)
    #expect(signature.signingTime == ISO8601DateFormatter().date(from: "2026-08-07T10:15:30Z"))
    #expect(signature.format == "PAdES_BASELINE_T")
    #expect(signature.hasQualifiedTimestamp == true)
}

@Test func certificateDiscoveryMapsTheMachinePayload() async throws {
    let fixture = try CertificateDiscoveryMachineFixture()
    defer { try? fixture.remove() }

    let discovery = try await AutogramCLIEngine(configuration: fixture.configuration()).certificateDiscovery(
        driverID: "driver-1",
        pin: Secret("1234")
    )

    #expect(discovery.token.tokenKey == "v1:token")
    #expect(discovery.token.providerName == "Qualified Provider")
    let certificate = try #require(discovery.certificates.first)
    #expect(certificate.serialNumber == "transient-serial")
    #expect(certificate.displayName == "Jane Doe")
    #expect(certificate.issuer == "Qualified Issuer")
    #expect(certificate.validFrom == ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z"))
    #expect(certificate.validUntil == ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z"))
    #expect(certificate.certificateKey == "v1:certificate")
    #expect(certificate.holderKey == "v1:holder")
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

    init(failureCode: String? = nil) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "AutogramCLIEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        executableURL = directoryURL.appending(path: "machine-helper")
        let result = if let failureCode {
            """
            printf '%s\\n' '{"protocolVersion":1,"type":"file.failed","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:02Z","fileId":"agreement","payload":{"code":"\(failureCode)"}}'
            """
        } else {
            """
            printf '%%PDF-1.7\\n%%%%EOF\\n' > "$AUTOGRAM_TEST_DIRECTORY/agreement_signed.pdf"
            printf '%s\\n' '{"protocolVersion":1,"type":"file.completed","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:02Z","fileId":"agreement","payload":{}}'
            """
        }
        let script = """
        #!/bin/sh
        input="$AUTOGRAM_TEST_DIRECTORY/request.json"
        cat > "$input"
        printf '%s\\n' '{"protocolVersion":1,"type":"session.started","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:00.123456Z","fileId":null,"payload":{}}'
        printf '%s\\n' '{"protocolVersion":1,"type":"file.signingStarted","sessionId":"00000000-0000-0000-0000-000000000001","emittedAt":"2026-08-06T00:00:01Z","fileId":"agreement","payload":{}}'
        \(result)
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

private struct InspectionMachineFixture {
    let directoryURL: URL
    let executableURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "AutogramCLIEngineInspectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        executableURL = directoryURL.appending(path: "machine-helper")
        let script = """
        #!/bin/sh
        request=$(cat)
        session_id=$(printf '%s' "$request" | sed -n 's/.*"requestId":"\\([^"]*\\)".*/\\1/p')
        printf '{"protocolVersion":1,"type":"session.started","sessionId":"%s","emittedAt":"2026-08-07T10:15:00Z","fileId":null,"payload":{}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"inspection.completed","sessionId":"%s","emittedAt":"2026-08-07T10:15:31Z","fileId":"agreement","payload":{"signatures":[{"id":"signature-1","format":"PAdES_BASELINE_T","signerDisplayName":"Ada Lovelace","signerCertificateQualification":"QES","signingTime":"2026-08-07T10:15:30Z","valid":true,"indication":"TOTAL_PASSED","qualifiedTimestampValid":true,"timestamps":[]}]}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"session.completed","sessionId":"%s","emittedAt":"2026-08-07T10:15:32Z","fileId":null,"payload":{}}\\n' "$session_id"
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
    }

    func configuration() -> ProcessConfiguration {
        ProcessConfiguration(executableURL: executableURL)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }
}

private struct CertificateDiscoveryMachineFixture {
    let directoryURL: URL
    let executableURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "AutogramCertificateDiscoveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        executableURL = directoryURL.appending(path: "machine-helper")
        let script = """
        #!/bin/sh
        request=$(cat)
        session_id=$(printf '%s' "$request" | sed -n 's/.*"requestId":"\\([^"]*\\)".*/\\1/p')
        printf '{"protocolVersion":1,"type":"session.started","sessionId":"%s","emittedAt":"2026-08-07T10:15:00Z","fileId":null,"payload":{}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"certificates.available","sessionId":"%s","emittedAt":"2026-08-07T10:15:01Z","fileId":null,"payload":{"tokenKey":"v1:token","providerName":"Qualified Provider","certificates":[{"serial":"transient-serial","commonName":"Jane Doe","issuer":"Qualified Issuer","validFrom":"2025-01-01T00:00:00Z","validUntil":"2027-01-01T00:00:00Z","certificateKey":"v1:certificate","holderKey":"v1:holder"}]}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"session.completed","sessionId":"%s","emittedAt":"2026-08-07T10:15:02Z","fileId":null,"payload":{}}\\n' "$session_id"
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
    }

    func configuration() -> ProcessConfiguration {
        ProcessConfiguration(executableURL: executableURL)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }
}
