import Foundation

enum FakeSigningEvent: Sendable, Equatable {
    case completed(String)
    case failed(String)
}

struct FakeSigningEngine: SigningEngine {
    let script: [FakeSigningEvent]
    let credentialFlow: Bool

    init(script: [FakeSigningEvent] = [], credentialFlow: Bool = false) {
        self.script = script
        self.credentialFlow = credentialFlow
    }

    static func launchEngine(environment: [String: String] = ProcessInfo.processInfo.environment) -> FakeSigningEngine {
        if environment["AUTOGRAM_FAKE_ENGINE"] == "credential-flow" {
            return FakeSigningEngine(
                script: [.completed("credential-flow")],
                credentialFlow: true
            )
        }
        guard environment["AUTOGRAM_FAKE_ENGINE"] == "partial-failure" else {
            return FakeSigningEngine()
        }

        return FakeSigningEngine(script: [
            .completed("agreement"),
            .failed("invoice")
        ])
    }

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] {
        credentialFlow ? [SigningDriver(id: "test-token", displayName: "Test Signing Token")] : []
    }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] {
        try await certificateDiscovery(driverID: driverID, pin: pin).certificates
    }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        _ = pin?.consumeBytes()
        return CertificateDiscovery(
            token: SigningToken(tokenKey: "test-token-key", providerName: "Test Signing Token"),
            certificates: credentialFlow ? [
                SigningCertificate(
                    serialNumber: "TEST-CERTIFICATE-1",
                    displayName: "Test Certificate",
                    issuer: "Test Issuer",
                    validFrom: .distantPast,
                    validUntil: .distantFuture,
                    certificateKey: "test-certificate-key",
                    holderKey: "test-holder-key"
                )
            ] : []
        )
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: files.map { InspectedPDF(id: $0.id, isSignable: true) })]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        _ = request.pin.consumeBytes()
        return AsyncThrowingStream { continuation in
            for event in script {
                switch event {
                case .completed(let fileID):
                    guard let file = request.files.first(where: { $0.id == fileID }) else { continue }
                    let outputURL = file.sourceURL.deletingLastPathComponent()
                        .appending(path: file.sourceURL.deletingPathExtension().lastPathComponent + "_signed")
                        .appendingPathExtension(request.outputFormat.outputExtension(for: file.sourceURL))
                    continuation.yield(.completed(fileID, outputURL: outputURL))
                case .failed(let fileID):
                    continuation.yield(.failed(fileID, .fileFailed(fileID)))
                }
            }
            continuation.finish()
        }
    }

    func cancel() async {}
}
