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
    #expect(events == [
        .started,
        .fileSigning("agreement"),
        .activity(.preparingSignatures),
        .activity(.signingDocuments),
        .activity(.validatingSignedDocuments),
        .activity(.savingSignedDocuments),
        .completed("agreement", outputURL: fixture.directoryURL.appending(path: "agreement_signed.pdf"))
    ])
    #expect(try fixture.finalizedOutput().starts(with: Data("%PDF-".utf8)))
}

@Test func signingAsXAdESRequestsAndFinalizesASiCE() async throws {
    let fixture = try SigningMachineFixture()
    defer { try? fixture.remove() }

    let source = fixture.directoryURL.appending(path: "agreement.pdf")
    try Data("%PDF-1.7\nsource\n%%EOF\n".utf8).write(to: source)
    let engine = AutogramCLIEngine(configuration: fixture.configuration())
    let request = SigningRequest(
        sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        driverID: "token-1",
        certificateSerial: "certificate-1",
        pin: Secret("1234"),
        files: [SigningFile(id: "agreement", sourceURL: source)],
        outputFormat: .asiceXAdES
    )

    var events: [SigningEvent] = []
    for try await event in engine.sign(request: request) {
        events.append(event)
    }

    let requestJSON = try fixture.requestJSON()
    let payload = try #require(requestJSON["payload"] as? [String: Any])
    #expect(payload["signatureLevel"] as? String == "XAdES_BASELINE_T")
    #expect(events.last == .completed(
        "agreement",
        outputURL: fixture.directoryURL.appending(path: "agreement_signed.asice")
    ))
    #expect(try Data(contentsOf: fixture.directoryURL.appending(path: "agreement_signed.asice"))
        .starts(with: Data([0x50, 0x4B, 0x03, 0x04])))
}

@Test func signingContinuesWhenInspectedOutputReservationIsAlreadyAbsent() async throws {
    let fixture = try SigningMachineFixture()
    defer { try? fixture.remove() }

    let source = fixture.directoryURL.appending(path: "agreement.pdf")
    try Data("%PDF-1.7\nsource\n%%EOF\n".utf8).write(to: source)
    let engine = AutogramCLIEngine(configuration: fixture.configuration())

    _ = try await engine.inspect(files: [PDFItemDescriptor(id: "agreement", sourceURL: source)])
    let reservedOutput = try #require(
        FileManager.default.contentsOfDirectory(at: fixture.directoryURL, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix(".agreement_signed.pdf.") }
    )
    try FileManager.default.removeItem(at: reservedOutput)

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

    #expect(events.last == .completed(
        "agreement",
        outputURL: fixture.directoryURL.appending(path: "agreement_signed.pdf")
    ))
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
        .activity(.preparingSignatures),
        .activity(.signingDocuments),
        .failed("agreement", .engine("A qualified timestamp could not be obtained. [TIMESTAMP_FAILED]"))
    ])
}

@Test func terminalFailureAfterFileCompletionDoesNotFinalizeOrReportCompletion() async throws {
    let fixture = try SigningMachineFixture(terminalFailureCode: "SIGNING_UNAVAILABLE")
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
    var failure: Error?
    do {
        for try await event in engine.sign(request: request) {
            events.append(event)
        }
    } catch {
        failure = error
    }

    #expect(events == [
        .started,
        .fileSigning("agreement"),
        .activity(.preparingSignatures),
        .activity(.signingDocuments),
        .activity(.validatingSignedDocuments),
        .activity(.savingSignedDocuments)
    ])
    #expect(failure as? SigningFailure == .engine("The signing helper rejected the request. [SIGNING_UNAVAILABLE]"))
    #expect(!fixture.finalizedOutputExists())
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
    #expect(signature.validationState == .indeterminate)
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

    init(failureCode: String? = nil, terminalFailureCode: String? = nil) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "AutogramCLIEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        executableURL = directoryURL.appending(path: "machine-helper")
        let result = if let failureCode {
            """
            printf '{"protocolVersion":1,"type":"file.failed","sessionId":"%s","emittedAt":"2026-08-06T00:00:02Z","fileId":"agreement","payload":{"code":"\(failureCode)"}}\\n' "$session_id"
            """
        } else {
            """
            target=$(/usr/bin/plutil -extract payload.files.0.target raw -o - "$input")
            signature_level=$(/usr/bin/plutil -extract payload.signatureLevel raw -o - "$input")
            if [ "$signature_level" = "XAdES_BASELINE_T" ]; then
                printf '\\120\\113\\003\\004' > "$target"
            else
                printf '%%PDF-1.7\\n%%%%EOF\\n' > "$target"
            fi
            printf '{"protocolVersion":1,"type":"file.progress","sessionId":"%s","emittedAt":"2026-08-06T00:00:02Z","fileId":"agreement","payload":{"phase":"validating"}}\\n' "$session_id"
            printf '{"protocolVersion":1,"type":"file.progress","sessionId":"%s","emittedAt":"2026-08-06T00:00:02Z","fileId":"agreement","payload":{"phase":"saving"}}\\n' "$session_id"
            printf '{"protocolVersion":1,"type":"file.completed","sessionId":"%s","emittedAt":"2026-08-06T00:00:02Z","fileId":"agreement","payload":{}}\\n' "$session_id"
            """
        }
        let terminalEvent = if let terminalFailureCode {
            """
            printf '{"protocolVersion":1,"type":"session.failed","sessionId":"%s","emittedAt":"2026-08-06T00:00:03Z","fileId":null,"payload":{"code":"\(terminalFailureCode)","fallbackMessage":"The signing helper rejected the request."}}\\n' "$session_id"
            """
        } else {
            """
            printf '{"protocolVersion":1,"type":"session.completed","sessionId":"%s","emittedAt":"2026-08-06T00:00:03Z","fileId":null,"payload":{}}\\n' "$session_id"
            """
        }
        let script = """
        #!/bin/sh
        input="$AUTOGRAM_TEST_DIRECTORY/request.json"
        cat > "$input"
        session_id=$(/usr/bin/plutil -extract requestId raw -o - "$input")
        printf '{"protocolVersion":1,"type":"session.started","sessionId":"%s","emittedAt":"2026-08-06T00:00:00.123456Z","fileId":null,"payload":{}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"file.signingStarted","sessionId":"%s","emittedAt":"2026-08-06T00:00:01Z","fileId":"agreement","payload":{}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"file.progress","sessionId":"%s","emittedAt":"2026-08-06T00:00:01Z","fileId":"agreement","payload":{"phase":"preparing"}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"file.progress","sessionId":"%s","emittedAt":"2026-08-06T00:00:01Z","fileId":"agreement","payload":{"phase":"signing"}}\\n' "$session_id"
        printf '{"protocolVersion":1,"type":"file.progress","sessionId":"%s","emittedAt":"2026-08-06T00:00:01Z","fileId":"agreement","payload":{"phase":"future-phase"}}\\n' "$session_id"
        \(result)
        \(terminalEvent)
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

    func finalizedOutputExists() -> Bool {
        FileManager.default.fileExists(atPath: directoryURL.appending(path: "agreement_signed.pdf").path)
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
        printf '{"protocolVersion":1,"type":"inspection.completed","sessionId":"%s","emittedAt":"2026-08-07T10:15:31Z","fileId":"agreement","payload":{"signatures":[{"id":"signature-1","format":"PAdES_BASELINE_T","signerDisplayName":"Ada Lovelace","signerCertificateQualification":null,"signingTime":"2026-08-07T10:15:30Z","valid":true,"cryptographicIntegrity":true,"indication":"INDETERMINATE","qualifiedTimestampValid":false,"timestamps":[{"id":"timestamp-1","valid":true,"cryptographicIntegrity":true,"qualification":null}]}]}}\\n' "$session_id"
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
