import Testing
import Foundation
@testable import Autogram

@Test @MainActor func invalidSignBeforeInspectionIsRejected() async {
    let engine = FakeSigningEngine()
    let coordinator = SigningCoordinator(engine: engine)

    await #expect(throws: SigningFailure.invalidTransition) {
        try await coordinator.beginSigning(request: SigningRequest.fixture(ids: ["a"]))
    }
}

@Test @MainActor func oneFileFailureProducesPartialCompletion() async throws {
    let engine = FakeSigningEngine(script: [.completed("a"), .failed("b")])
    let coordinator = SigningCoordinator(engine: engine)

    try await coordinator.inspect(PDFItemDescriptor.fixtures(ids: ["a", "b"]))
    try await coordinator.beginSigning(request: SigningRequest.fixture(ids: ["a", "b"]))

    guard case .partiallyCompleted(let summary) = await coordinator.state else {
        Issue.record("Expected partial completion")
        return
    }

    #expect(summary.succeeded == 1)
    #expect(summary.failed == 1)
}

@Test @MainActor func completeFailurePreservesTheEngineReason() async throws {
    let expected = SigningFailure.engine("A qualified timestamp could not be obtained. [TIMESTAMP_FAILED]")
    let coordinator = SigningCoordinator(engine: FailureSigningEngine(failure: expected))

    try await coordinator.inspect(PDFItemDescriptor.fixtures(ids: ["a"]))
    await #expect(throws: expected) {
        try await coordinator.beginSigning(request: SigningRequest.fixture(ids: ["a"]))
    }
    #expect(await coordinator.state == .failed(expected))
}

@Test @MainActor func incompleteInspectionNeverEnablesOrCallsSigning() async {
    let engine = IncompleteInspectionEngine()
    let coordinator = SigningCoordinator(engine: engine)
    let files = PDFItemDescriptor.fixtures(ids: ["a", "b"])
    let expected = SigningFailure.engine("Document inspection did not produce a signable result for every requested file.")

    await #expect(throws: expected) {
        try await coordinator.inspect(files)
    }
    await #expect(throws: SigningFailure.invalidTransition) {
        try await coordinator.beginSigning(request: SigningRequest.fixture(ids: ["a", "b"]))
    }
    #expect(await coordinator.state == .failed(expected))
    #expect(engine.signCallCount == 0)
}

private final class IncompleteInspectionEngine: SigningEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSignCallCount = 0

    var signCallCount: Int {
        lock.withLock { storedSignCallCount }
    }

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: [InspectedPDF(id: "a", isSignable: true)])]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        lock.withLock { storedSignCallCount += 1 }
        return AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}

private struct FailureSigningEngine: SigningEngine {
    let failure: SigningFailure

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: files.map { InspectedPDF(id: $0.id, isSignable: true) })]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.failed(request.files[0].id, failure))
            continuation.finish()
        }
    }

    func cancel() async {}
}

private extension PDFItemDescriptor {
    static func fixtures(ids: [String]) -> [PDFItemDescriptor] {
        ids.map { PDFItemDescriptor(id: $0, sourceURL: URL(fileURLWithPath: "/tmp/\($0).pdf")) }
    }
}

private extension SigningRequest {
    static func fixture(ids: [String]) -> SigningRequest {
        SigningRequest(
            sessionID: UUID(),
            driverID: "driver",
            certificateSerial: "certificate",
            pin: Secret("1234"),
            files: ids.map { SigningFile(id: $0, sourceURL: URL(fileURLWithPath: "/tmp/\($0).pdf")) }
        )
    }
}
