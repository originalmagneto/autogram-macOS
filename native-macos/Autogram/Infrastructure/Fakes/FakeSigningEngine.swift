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
        _ = pin?.consumeBytes()
        return credentialFlow ? [SigningCertificate(serialNumber: "TEST-CERTIFICATE-1", displayName: "Test Certificate")] : []
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
                    continuation.yield(.completed(fileID))
                case .failed(let fileID):
                    continuation.yield(.failed(fileID, .fileFailed(fileID)))
                }
            }
            continuation.finish()
        }
    }

    func cancel() async {}
}
