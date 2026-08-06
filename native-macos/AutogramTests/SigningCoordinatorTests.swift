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
