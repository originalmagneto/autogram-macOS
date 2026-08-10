import AppKit
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
    #expect(workspace.items[0].status == .inspected)
    #expect(workspace.items[1].status == .inspected)
    #expect(workspace.items[2].status == .failed)
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

@Test @MainActor func signingAfterCompletedInspectionDoesNotInspectDocumentsAgain() async {
    let descriptor = PDFItemDescriptor(id: "document", sourceURL: URL(fileURLWithPath: "/tmp/document.pdf"))
    let engine = CountingWorkspaceSigningEngine()
    let workspace = WorkspaceModel(engine: engine, items: [PDFItem(descriptor: descriptor)])

    await workspace.refreshInspections()
    #expect(workspace.canStartSigning)

    await workspace.refreshSigningEnvironment()
    let resolution = await workspace.resolveCertificates(using: PINSubmission(
        certificatePIN: Secret("1234"),
        signingPIN: Secret("5678")
    ))
    await engine.waitForSigning()

    #expect(resolution == .signingStarted)
    #expect(engine.inspectCallCount == 1)
    #expect(workspace.items[0].inspection.isComplete)
}

@Test @MainActor func selectedAsicFormatReachesTheSigningRequest() async {
    let descriptor = PDFItemDescriptor(id: "document", sourceURL: URL(fileURLWithPath: "/tmp/document.pdf"))
    let engine = CountingWorkspaceSigningEngine()
    let workspace = WorkspaceModel(engine: engine, items: [PDFItem(descriptor: descriptor)])
    workspace.selectedOutputFormat = .asiceXAdES

    await workspace.refreshInspections()
    await workspace.refreshSigningEnvironment()
    _ = await workspace.resolveCertificates(using: PINSubmission(
        certificatePIN: Secret("1234"),
        signingPIN: Secret("5678")
    ))
    await engine.waitForSigning()

    #expect(engine.lastOutputFormat == .asiceXAdES)
}

@Test @MainActor func selectedCertificatePropagatesRenderedVisibleAppearanceToSigningRequest() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "document.pdf")
    let artwork = directory.appending(path: "artwork.png")
    try Data("%PDF-1.7\nsource\n%%EOF\n".utf8).write(to: source)
    try workspaceFixturePNG().write(to: artwork)

    let store = SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support"))
    let asset = try store.importPNG(artwork)
    let engine = VisibleAppearanceCapturingEngine()
    let preferencesSuite = "WorkspaceInspectionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: preferencesSuite))
    defer { defaults.removePersistentDomain(forName: preferencesSuite) }
    let workspace = WorkspaceModel(
        engine: engine,
        items: [PDFItem(descriptor: PDFItemDescriptor(id: "document", sourceURL: source))],
        signatureAssetStore: store,
        visibleSignatureRenderer: VisibleSignatureRenderer(
            assetStore: store,
            cacheRoot: directory.appending(path: "Caches")
        ),
        defaults: defaults
    )
    workspace.configureVisibleAppearance(
        asset: asset,
        enabled: true,
        placement: VisibleSignaturePlacement(
            pageIndex: 1,
            pageRect: CGRect(x: 72, y: 144, width: 216, height: 108),
            rotationDegrees: 27
        )
    )

    await workspace.refreshInspections()
    await workspace.refreshSigningEnvironment()
    let resolution = await workspace.resolveCertificates(using: PINSubmission(
        certificatePIN: Secret("1234"),
        signingPIN: Secret("5678")
    ))
    await engine.waitForSigning()

    let appearance = try #require(engine.lastRequest?.files.first?.visibleAppearance)
    #expect(resolution == .signingStarted)
    #expect(FileManager.default.fileExists(atPath: appearance.renderedPNGURL.path))
    #expect(appearance.page == 2)
    #expect(appearance.originX == 72)
    #expect(appearance.originY == 540)
    #expect(appearance.width == 216)
    #expect(appearance.height == 108)
}

@Test func failedWorkspaceItemDistinguishesInspectionFromSigningFailure() {
    let descriptor = PDFItemDescriptor(id: "document", sourceURL: URL(fileURLWithPath: "/tmp/document.pdf"))
    let inspected = InspectedPDF(id: descriptor.id, isSignable: true)

    #expect(PDFItem(descriptor: descriptor, status: .failed, inspection: .failed).workspaceLabel == "Inspection failed")
    #expect(PDFItem(descriptor: descriptor, status: .failed, inspection: .completed(inspected)).workspaceLabel == "Signing failed")
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

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

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

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

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

private final class CountingWorkspaceSigningEngine: SigningEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var storedInspectCallCount = 0
    private var signingStarted = false
    private var storedOutputFormat: SigningOutputFormat?
    private var signingWaiters: [CheckedContinuation<Void, Never>] = []

    var inspectCallCount: Int {
        lock.withLock { storedInspectCallCount }
    }

    var lastOutputFormat: SigningOutputFormat? {
        lock.withLock { storedOutputFormat }
    }

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] {
        [SigningDriver(id: "test-driver", displayName: "Test Driver")]
    }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] {
        try await certificateDiscovery(driverID: driverID, pin: pin).certificates
    }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(
            token: SigningToken(tokenKey: "test-token", providerName: "Test Token"),
            certificates: [SigningCertificate(
                serialNumber: "test-certificate",
                displayName: "Test Certificate",
                issuer: "Test Issuer",
                validFrom: .distantPast,
                validUntil: .distantFuture,
                certificateKey: "test-certificate-key",
                holderKey: "test-holder-key"
            )]
        )
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        lock.withLock { storedInspectCallCount += 1 }
        return [PDFInspection(files: files.map { InspectedPDF(id: $0.id, isSignable: true) })]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            signingStarted = true
            storedOutputFormat = request.outputFormat
            let waiters = signingWaiters
            signingWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
        return AsyncThrowingStream { continuation in
            for file in request.files {
                continuation.yield(.completed(file.id, outputURL: file.sourceURL))
            }
            continuation.finish()
        }
    }

    func cancel() async {}

    func waitForSigning() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if signingStarted {
                    continuation.resume()
                } else {
                    signingWaiters.append(continuation)
                }
            }
        }
    }
}

private final class VisibleAppearanceCapturingEngine: SigningEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var signingStarted = false
    private var signingWaiters: [CheckedContinuation<Void, Never>] = []
    private var storedRequest: SigningRequest?

    var lastRequest: SigningRequest? {
        lock.withLock { storedRequest }
    }

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 2, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] {
        [SigningDriver(id: "test-driver", displayName: "Test Driver")]
    }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] {
        try await certificateDiscovery(driverID: driverID, pin: pin).certificates
    }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(
            token: SigningToken(tokenKey: "test-token", providerName: "Test Token"),
            certificates: [SigningCertificate(
                serialNumber: "test-certificate",
                displayName: "Test Certificate",
                issuer: "Test Issuer",
                validFrom: .distantPast,
                validUntil: .distantFuture,
                certificateKey: "test-certificate-key",
                holderKey: "test-holder-key"
            )]
        )
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: files.map { InspectedPDF(id: $0.id, isSignable: true) })]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            storedRequest = request
            signingStarted = true
            let waiters = signingWaiters
            signingWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() async {}

    func waitForSigning() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if signingStarted {
                    continuation.resume()
                } else {
                    signingWaiters.append(continuation)
                }
            }
        }
    }
}

private func workspaceFixturePNG() throws -> Data {
    let image = NSImage(size: NSSize(width: 24, height: 24))
    image.lockFocus()
    NSColor.systemPurple.setFill()
    NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 16, height: 16)).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw WorkspaceFixtureError.unableToEncodePNG
    }
    return png
}

private enum WorkspaceFixtureError: Error {
    case unableToEncodePNG
}
