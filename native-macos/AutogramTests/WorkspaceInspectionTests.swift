import Foundation
import Testing
@testable import Autogram

@Test @MainActor func inspectionStoresSignedAndUnsignedResultsPerWorkspaceItem() async throws {
    let signed = PDFItemDescriptor(id: "signed", sourceURL: URL(fileURLWithPath: "/tmp/signed.pdf"))
    let unsigned = PDFItemDescriptor(id: "unsigned", sourceURL: URL(fileURLWithPath: "/tmp/unsigned.pdf"))
    let failed = PDFItemDescriptor(id: "failed", sourceURL: URL(fileURLWithPath: "/tmp/failed.pdf"))
    let workspace = WorkspaceModel(
        engine: InspectionEngine(),
        items: [
            PDFItem(descriptor: signed),
            PDFItem(descriptor: unsigned),
            PDFItem(descriptor: failed)
        ]
    )

    await workspace.refreshInspections()

    #expect(workspace.items[0].inspection.signatures.map(\.signerDisplayName) == ["Ada Lovelace"])
    #expect(workspace.items[1].inspection.signatures.isEmpty)
    #expect(workspace.items[2].inspection == .failed)
    #expect(workspace.canStartSigning == false)
}

@Test @MainActor func staleAutomaticInspectionCannotOverwriteNewerResult() async {
    let descriptor = PDFItemDescriptor(id: "document", sourceURL: URL(fileURLWithPath: "/tmp/document.pdf"))
    let addedDescriptor = PDFItemDescriptor(id: "added", sourceURL: URL(fileURLWithPath: "/tmp/added.pdf"))
    let engine = ControlledInspectionEngine()
    let workspace = WorkspaceModel(engine: engine, items: [PDFItem(descriptor: descriptor)])

    let olderRequest = Task { await workspace.refreshInspections() }
    await engine.waitForRequestCount(1)
    workspace.setItems([PDFItem(descriptor: descriptor), PDFItem(descriptor: addedDescriptor)])
    let newerRequest = Task { await workspace.refreshInspections() }
    await engine.waitForRequestCount(2)

    await engine.completeRequest(at: 1, signer: "New result")
    await newerRequest.value
    await engine.completeRequest(at: 0, signer: "Stale result")
    await olderRequest.value

    #expect(workspace.items[0].inspection.signatures.first?.signerDisplayName == "New result")
    #expect(workspace.items[1].inspection.signatures.first?.signerDisplayName == "New result")
}

private actor ControlledInspectionEngine: SigningEngine {
    private struct PendingRequest {
        let files: [PDFItemDescriptor]
        let continuation: CheckedContinuation<[PDFInspection], any Error>
    }

    private var requests: [PendingRequest] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(PendingRequest(files: files, continuation: continuation))
            resumeSatisfiedWaiters()
        }
    }

    nonisolated func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}

    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func completeRequest(at index: Int, signer: String) {
        let request = requests[index]
        request.continuation.resume(returning: [PDFInspection(files: request.files.map {
            InspectedPDF(
                id: $0.id,
                isSignable: true,
                signatures: [ExistingPDFSignature(
                    id: "signature-\(signer)",
                    signerDisplayName: signer,
                    validationState: .valid,
                    signingTime: nil,
                    format: "PAdES_BASELINE_T",
                    hasQualifiedTimestamp: true
                )]
            )
        })])
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = requestWaiters.filter { requests.count >= $0.count }
        requestWaiters.removeAll { requests.count >= $0.count }
        satisfied.forEach { $0.continuation.resume() }
    }
}

private struct InspectionEngine: SigningEngine {
    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: [
            InspectedPDF(
                id: "signed",
                isSignable: true,
                signatures: [
                    ExistingPDFSignature(
                        id: "signature-1",
                        signerDisplayName: "Ada Lovelace",
                        validationState: .valid,
                        signingTime: nil,
                        format: "PAdES_BASELINE_T",
                        hasQualifiedTimestamp: true
                    )
                ]
            ),
            InspectedPDF(id: "unsigned", isSignable: true),
            InspectedPDF(id: "failed", isSignable: false)
        ])]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}
