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
