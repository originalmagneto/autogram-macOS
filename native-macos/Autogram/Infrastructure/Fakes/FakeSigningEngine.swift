import Foundation

enum FakeSigningEvent: Sendable, Equatable {
    case completed(String)
    case failed(String)
}

struct FakeSigningEngine: SigningEngine {
    let script: [FakeSigningEvent]

    init(script: [FakeSigningEvent] = []) {
        self.script = script
    }

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] {
        []
    }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] {
        []
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
