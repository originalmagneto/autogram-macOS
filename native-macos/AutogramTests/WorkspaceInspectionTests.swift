import AppKit
import Foundation
import Testing
@testable import Autogram

@Test @MainActor func addingFilesSelectsTheLastNewlyAcceptedFile() {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let existingURL = directory.appending(path: "existing.pdf")
    let firstNewURL = directory.appending(path: "first-new.pdf")
    let lastNewURL = directory.appending(path: "last-new.pdf")
    let workspace = WorkspaceModel(items: [PDFItem(descriptor: PDFItemDescriptor(id: "existing", sourceURL: existingURL))])

    #expect(!workspace.addFiles([existingURL]))
    #expect(workspace.selection == workspace.items[0].id)
    #expect(workspace.addFiles([existingURL, firstNewURL, lastNewURL]))
    #expect(workspace.selectedItem?.descriptor.sourceURL == lastNewURL)
}

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

@Test @MainActor func fastInspectionFailureDoesNotStartCompleteValidation() async {
    let descriptor = PDFItemDescriptor(id: "sample", sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf"))
    let workspace = WorkspaceModel(
        engine: FastFailureCompleteValidationEngine(),
        items: [PDFItem(descriptor: descriptor)]
    )

    await workspace.refreshInspections()

    #expect(workspace.signatureValidationProgress == .provisional)
    #expect(workspace.items[0].inspection == .failed)
}

@Test @MainActor func completeValidationReceivesOnlyFastInspectedSignedDocuments() async {
    let signed = PDFItemDescriptor(id: "signed", sourceURL: URL(fileURLWithPath: "/tmp/signed.pdf"))
    let unsigned = PDFItemDescriptor(id: "unsigned", sourceURL: URL(fileURLWithPath: "/tmp/unsigned.pdf"))
    let engine = CompleteValidationFilteringEngine()
    let workspace = WorkspaceModel(
        engine: engine,
        items: [PDFItem(descriptor: signed), PDFItem(descriptor: unsigned)]
    )

    await workspace.refreshInspections()
    await engine.waitForValidationRequest()

    let validationCalls = await engine.validationCalls
    #expect(validationCalls == [[signed]])
}

@Test @MainActor func postSigningInspectedSignaturesStillStartCompleteValidation() async {
    let descriptor = PDFItemDescriptor(id: "signed", sourceURL: URL(fileURLWithPath: "/tmp/signed.pdf"))
    let engine = CompleteValidationFilteringEngine()
    let workspace = WorkspaceModel(engine: engine, items: [PDFItem(descriptor: descriptor)])

    workspace.applyPostSigningInspectionResults(
        [PDFInspection(files: [engine.signedInspection(for: descriptor)])],
        for: [descriptor]
    )
    await engine.waitForValidationRequest()

    let validationCalls = await engine.validationCalls
    #expect(validationCalls == [[descriptor]])
}

@Test @MainActor func changingOrReplacingActiveDocumentDisablesGraphicComposition() {
    let first = PDFItem(descriptor: PDFItemDescriptor(id: "first", sourceURL: URL(fileURLWithPath: "/tmp/first.pdf")))
    let second = PDFItem(descriptor: PDFItemDescriptor(id: "second", sourceURL: URL(fileURLWithPath: "/tmp/second.pdf")))
    let workspace = WorkspaceModel(engine: IncompleteValidationEngine(), items: [first, second])
    let asset = SignatureAsset(id: UUID(), kind: .png, managedFilename: "artwork.png")
    let placement = VisibleSignaturePlacement(pageIndex: 0, pageRect: .zero, rotationDegrees: 0)

    workspace.configureVisibleAppearance(asset: asset, enabled: true, placement: placement)
    workspace.selection = second.id
    #expect(workspace.visibleSignatureEnabled == false)
    #expect(workspace.visibleSignaturePlacement == nil)

    workspace.configureVisibleAppearance(asset: asset, enabled: true, placement: placement)
    let replacement = PDFItem(
        id: second.id,
        descriptor: PDFItemDescriptor(id: "second", sourceURL: URL(fileURLWithPath: "/tmp/replacement.pdf"))
    )
    workspace.setItems([first, replacement])
    #expect(workspace.visibleSignatureEnabled == false)
    #expect(workspace.visibleSignaturePlacement == nil)
}

@Test @MainActor func embeddedPreviewClosesAndSelectedDocumentCanBeValidatedAgain() async throws {
    let descriptor = PDFItemDescriptor(id: "sample", sourceURL: URL(fileURLWithPath: "/tmp/sample.asice"))
    let engine = PreviewAndValidationEngine()
    let workspace = WorkspaceModel(engine: engine, items: [PDFItem(descriptor: descriptor)])
    workspace.selection = nil

    await workspace.previewEmbeddedDocument(named: "sample.pdf")

    #expect(workspace.embeddedPreview?.displayName == "sample.pdf")
    #expect(workspace.embeddedPreview?.url.pathExtension == "pdf")
    #expect(engine.previewCalls.count == 1)
    #expect(engine.previewCalls.first?.sourceURL == descriptor.sourceURL)
    #expect(engine.previewCalls.first?.name == "sample.pdf")
    let previewURL = try #require(workspace.embeddedPreview?.url)

    workspace.closeEmbeddedPreview()

    #expect(workspace.embeddedPreview == nil)
    #expect(!FileManager.default.fileExists(atPath: previewURL.deletingLastPathComponent().path))

    await workspace.verifySelectedDocumentAgain()

    #expect(workspace.selectedItem?.inspection.signatures.first?.validationState == .valid)
    #expect(engine.validationCalls == [[descriptor]])
}

@Test @MainActor func previewResponseForDeselectedItemIsDiscarded() async throws {
    let first = PDFItem(descriptor: PDFItemDescriptor(id: "first", sourceURL: URL(fileURLWithPath: "/tmp/first.asice")))
    let second = PDFItem(descriptor: PDFItemDescriptor(id: "second", sourceURL: URL(fileURLWithPath: "/tmp/second.asice")))
    let engine = DeferredPreviewEngine()
    let workspace = WorkspaceModel(engine: engine, items: [first, second])

    let previewTask = Task { await workspace.previewEmbeddedDocument(named: "first.pdf") }
    await engine.waitForPreviewRequest()
    workspace.selection = second.id
    let previewURL = try await engine.completePreview(named: "first.pdf")
    await previewTask.value

    #expect(workspace.embeddedPreview == nil)
    #expect(!FileManager.default.fileExists(atPath: previewURL.deletingLastPathComponent().path))
}

@Test @MainActor func staleValidationCannotReplaceAnItemWithTheSameIDAndNewSource() async {
    let original = PDFItem(
        descriptor: PDFItemDescriptor(id: "document", sourceURL: URL(fileURLWithPath: "/tmp/original.pdf"))
    )
    let replacement = PDFItem(
        id: original.id,
        descriptor: PDFItemDescriptor(id: "document", sourceURL: URL(fileURLWithPath: "/tmp/replacement.pdf"))
    )
    let engine = DeferredValidationEngine()
    let workspace = WorkspaceModel(engine: engine, items: [original])

    let validationTask = Task { await workspace.verifySelectedDocumentAgain() }
    await engine.waitForValidationRequest()
    workspace.setItems([replacement])
    await engine.completeValidation(for: original.descriptor)
    await validationTask.value

    #expect(workspace.items[0].descriptor == replacement.descriptor)
    #expect(workspace.items[0].inspection == .pending)
}

@Test @MainActor func incompleteValidationKeepsAReasonInsteadOfReportingAuthoritativeCompletion() async {
    let descriptor = PDFItemDescriptor(id: "sample", sourceURL: URL(fileURLWithPath: "/tmp/sample.pdf"))
    let workspace = WorkspaceModel(
        engine: IncompleteValidationEngine(),
        items: [PDFItem(descriptor: descriptor)]
    )

    await workspace.verifySelectedDocumentAgain()

    #expect(workspace.signatureValidationProgress == .incomplete("Complete validation returned no result for sample.pdf."))
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
    try writeWorkspaceFixturePDF(to: source)
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
            pageIndex: 0,
            pageRect: CGRect(x: 10, y: 20, width: 30, height: 40),
            rotationDegrees: 0
        )
    )
    let detail = PDFDetailView(item: workspace.items[0], workspace: workspace)
    #expect(detail.cardPreview != nil)
    #expect(detail.cardPreview?.size == NSSize(width: 422, height: 262))
    detail.visibleSignaturePlacement.wrappedValue = VisibleSignaturePlacement(
        pageIndex: 1,
        pageRect: CGRect(x: 72, y: 144, width: 216, height: 108),
        rotationDegrees: 27
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
    #expect(workspace.visibleSignatureCardContent == VisibleSignatureCardContent(
        signerName: "Test Certificate",
        certificateQualification: "QESIG"
    ))
}

@Test @MainActor func importedVisibleArtworkDefaultsToTheLastPageOfTheSelectedPDF() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "document.pdf")
    let artwork = directory.appending(path: "artwork.png")
    try writeWorkspaceFixturePDF(to: source)
    try workspaceFixturePNG().write(to: artwork)
    let preferencesSuite = "WorkspaceInspectionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: preferencesSuite))
    defer { defaults.removePersistentDomain(forName: preferencesSuite) }

    let workspace = WorkspaceModel(
        items: [PDFItem(descriptor: PDFItemDescriptor(id: "document", sourceURL: source))],
        signatureAssetStore: SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support")),
        defaults: defaults
    )

    try workspace.importVisibleSignatureArtwork(from: artwork)

    let placement = try #require(workspace.visibleSignaturePlacement)
    #expect(placement.pageIndex == 1)
    #expect(placement.pageRect == CGRect(x: 181, y: 321, width: 250, height: 150))
    #expect(placement.rotationDegrees == 0)
}

@Test @MainActor func selectingArtworkOnANewDocumentCreatesFreshDefaultPlacement() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstSource = directory.appending(path: "first.pdf")
    let secondSource = directory.appending(path: "second.pdf")
    let artwork = directory.appending(path: "artwork.png")
    try writeWorkspaceFixturePDF(to: firstSource, pageCount: 2)
    try writeWorkspaceFixturePDF(to: secondSource, pageCount: 1)
    try workspaceFixturePNG().write(to: artwork)
    let store = SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support"))
    let workspace = WorkspaceModel(
        items: [
            PDFItem(descriptor: PDFItemDescriptor(id: "first", sourceURL: firstSource)),
            PDFItem(descriptor: PDFItemDescriptor(id: "second", sourceURL: secondSource))
        ],
        signatureAssetStore: store
    )

    try workspace.importVisibleSignatureArtwork(from: artwork)
    let asset = try #require(workspace.visibleSignatureAsset)
    workspace.updateVisibleSignaturePlacement(
        VisibleSignaturePlacement(
            pageIndex: 1,
            pageRect: CGRect(x: 20, y: 30, width: 80, height: 40),
            rotationDegrees: 27
        )
    )
    workspace.selection = workspace.items[1].id

    #expect(workspace.visibleSignaturePlacement == nil)
    #expect(workspace.visibleSignatureEnabled == false)

    workspace.selectVisibleSignatureArtwork(asset)

    let placement = try #require(workspace.visibleSignaturePlacement)
    #expect(placement.pageIndex == 0)
    #expect(placement.pageRect == CGRect(x: 181, y: 321, width: 250, height: 150))
    #expect(placement.rotationDegrees == 0)
}

@Test @MainActor func savedArtworkDoesNotActivateGraphicSignatureInNewWorkspace() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "document.pdf")
    let artwork = directory.appending(path: "artwork.png")
    try writeWorkspaceFixturePDF(to: source, pageCount: 1)
    try workspaceFixturePNG().write(to: artwork)
    let store = SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support"))
    let asset = try store.importPNG(artwork)
    let preferencesSuite = "WorkspaceInspectionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: preferencesSuite))
    defer { defaults.removePersistentDomain(forName: preferencesSuite) }
    let placement = VisibleSignaturePlacement(
        pageIndex: 0,
        pageRect: CGRect(x: 10, y: 20, width: 30, height: 40),
        rotationDegrees: 0
    )
    let legacyPreferences = try JSONSerialization.data(withJSONObject: [
        "assetID": asset.id.uuidString,
        "enabled": true,
        "defaultPlacement": [
            "pageIndex": placement.pageIndex,
            "originX": placement.pageRect.origin.x,
            "originY": placement.pageRect.origin.y,
            "width": placement.pageRect.width,
            "height": placement.pageRect.height,
            "rotationDegrees": placement.rotationDegrees
        ]
    ])
    defaults.set(legacyPreferences, forKey: "preferences.visibleSignature")

    let workspace = WorkspaceModel(
        items: [PDFItem(descriptor: PDFItemDescriptor(id: "document", sourceURL: source))],
        signatureAssetStore: store,
        defaults: defaults
    )
    let detail = PDFDetailView(item: workspace.items[0], workspace: workspace)

    #expect(workspace.visibleSignatureAsset != nil)
    #expect(workspace.visibleSignatureEnabled == false)
    #expect(workspace.visibleSignaturePlacement == nil)
    #expect(workspace.visibleSignatureCardPreview != nil)
    #expect(detail.visibleSignaturePlacement.wrappedValue == nil)
    #expect(detail.cardPreview == nil)

    workspace.selectVisibleSignatureArtwork(asset)

    #expect(workspace.visibleSignaturePlacement == VisibleSignaturePlacement(
        pageIndex: 0,
        pageRect: CGRect(x: 181, y: 321, width: 250, height: 150),
        rotationDegrees: 0
    ))
}

@Test @MainActor func completedOutputDisablesPendingGraphicSignatureOverlay() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "document.pdf")
    let artwork = directory.appending(path: "artwork.png")
    let output = directory.appending(path: "signed-document.pdf")
    try writeWorkspaceFixturePDF(to: source, pageCount: 1)
    try workspaceFixturePNG().write(to: artwork)
    let store = SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support"))
    let asset = try store.importPNG(artwork)
    let workspace = WorkspaceModel(
        items: [PDFItem(descriptor: PDFItemDescriptor(id: "document", sourceURL: source))],
        signatureAssetStore: store
    )
    let placement = VisibleSignaturePlacement(
        pageIndex: 0,
        pageRect: CGRect(x: 10, y: 20, width: 30, height: 40),
        rotationDegrees: 0
    )

    workspace.configureVisibleAppearance(asset: asset, enabled: true, placement: placement)
    workspace.updateSignedOutput(for: "document", to: output)

    #expect(workspace.visibleSignatureEnabled == false)
    #expect(PDFDetailView(item: workspace.items[0], workspace: workspace).cardPreview == nil)
}

@Test @MainActor func openingADocumentClearsTransientVisiblePlacement() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "single-page.pdf")
    try writeWorkspaceFixturePDF(to: source, pageCount: 1)
    let preferencesSuite = "WorkspaceInspectionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: preferencesSuite))
    defer { defaults.removePersistentDomain(forName: preferencesSuite) }
    let workspace = WorkspaceModel(defaults: defaults)
    workspace.configureVisibleAppearance(
        asset: nil,
        enabled: false,
        placement: VisibleSignaturePlacement(pageIndex: 8, pageRect: .zero, rotationDegrees: 0)
    )

    workspace.setItems([PDFItem(descriptor: PDFItemDescriptor(id: "document", sourceURL: source))])

    #expect(workspace.visibleSignaturePlacement == nil)
}

@Test func failedWorkspaceItemDistinguishesInspectionFromSigningFailure() {
    let descriptor = PDFItemDescriptor(id: "document", sourceURL: URL(fileURLWithPath: "/tmp/document.pdf"))
    let inspected = InspectedPDF(id: descriptor.id, isSignable: true)

    #expect(PDFItem(descriptor: descriptor, status: .failed, inspection: .failed).workspaceLabel == "Inspection failed")
    #expect(PDFItem(descriptor: descriptor, status: .failed, inspection: .completed(inspected)).workspaceLabel == "Signing failed")
}

private actor CompleteValidationFilteringEngine: SigningEngine {
    private var storedValidationCalls: [[PDFItemDescriptor]] = []
    private var validationWaiters: [CheckedContinuation<Void, Never>] = []

    var validationCalls: [[PDFItemDescriptor]] {
        storedValidationCalls
    }

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 2, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: files.map { descriptor in
            descriptor.id == "signed"
                ? signedInspection(for: descriptor)
                : InspectedPDF(id: descriptor.id, isSignable: true)
        })]
    }

    func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        storedValidationCalls.append(files)
        let waiters = validationWaiters
        validationWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return [PDFInspection(files: files.map(signedInspection(for:)))]
    }

    nonisolated func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}

    nonisolated func signedInspection(for descriptor: PDFItemDescriptor) -> InspectedPDF {
        InspectedPDF(
            id: descriptor.id,
            isSignable: true,
            signatures: [ExistingPDFSignature(
                id: "signature-\(descriptor.id)",
                signerDisplayName: "Ada Lovelace",
                validationState: .valid,
                signingTime: nil,
                format: "PAdES_BASELINE_T",
                hasQualifiedTimestamp: true
            )]
        )
    }

    func waitForValidationRequest() async {
        guard storedValidationCalls.isEmpty else { return }
        await withCheckedContinuation { validationWaiters.append($0) }
    }
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

private final class PreviewAndValidationEngine: SigningEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPreviewCalls: [(sourceURL: URL, name: String)] = []
    private var storedValidationCalls: [[PDFItemDescriptor]] = []

    var previewCalls: [(sourceURL: URL, name: String)] {
        lock.withLock { storedPreviewCalls }
    }

    var validationCalls: [[PDFItemDescriptor]] {
        lock.withLock { storedValidationCalls }
    }

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 2, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: files.map { InspectedPDF(id: $0.id, isSignable: true) })]
    }

    func previewEmbeddedDocument(sourceURL: URL, named: String) async throws -> EmbeddedDocumentPreview {
        lock.withLock { storedPreviewCalls.append((sourceURL, named)) }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: named)
        try Data().write(to: url)
        return EmbeddedDocumentPreview(
            displayName: named,
            mediaType: "application/pdf",
            url: url
        )
    }

    func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        lock.withLock { storedValidationCalls.append(files) }
        return [PDFInspection(files: files.map {
            InspectedPDF(
                id: $0.id,
                isSignable: true,
                signatures: [ExistingPDFSignature(
                    id: "validated-signature",
                    signerDisplayName: "Ada Lovelace",
                    validationState: .valid,
                    signingTime: nil,
                    format: "PAdES_BASELINE_T",
                    hasQualifiedTimestamp: true
                )]
            )
        })]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}

}

private actor DeferredPreviewEngine: SigningEngine {
    private var previewContinuation: CheckedContinuation<EmbeddedDocumentPreview, Error>?
    private var previewRequestWaiter: CheckedContinuation<Void, Never>?

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 2, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] { [] }

    func previewEmbeddedDocument(sourceURL: URL, named: String) async throws -> EmbeddedDocumentPreview {
        try await withCheckedThrowingContinuation { continuation in
            previewContinuation = continuation
            previewRequestWaiter?.resume()
            previewRequestWaiter = nil
        }
    }

    nonisolated func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}

    func waitForPreviewRequest() async {
        guard previewContinuation == nil else { return }
        await withCheckedContinuation { previewRequestWaiter = $0 }
    }

    func completePreview(named: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: named)
        try Data().write(to: url)
        previewContinuation?.resume(returning: EmbeddedDocumentPreview(
            displayName: named,
            mediaType: "application/pdf",
            url: url
        ))
        previewContinuation = nil
        return url
    }
}

private actor DeferredValidationEngine: SigningEngine {
    private var validationContinuation: CheckedContinuation<[PDFInspection], Error>?
    private var validationRequestWaiter: CheckedContinuation<Void, Never>?

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 2, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] { [] }

    func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        try await withCheckedThrowingContinuation { continuation in
            validationContinuation = continuation
            validationRequestWaiter?.resume()
            validationRequestWaiter = nil
        }
    }

    nonisolated func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}

    func waitForValidationRequest() async {
        guard validationContinuation == nil else { return }
        await withCheckedContinuation { validationRequestWaiter = $0 }
    }

    func completeValidation(for descriptor: PDFItemDescriptor) {
        validationContinuation?.resume(returning: [PDFInspection(files: [InspectedPDF(
            id: descriptor.id,
            isSignable: true,
            signatures: [ExistingPDFSignature(
                id: "stale-signature",
                signerDisplayName: "Stale Result",
                validationState: .valid,
                signingTime: nil,
                format: "PAdES_BASELINE_T",
                hasQualifiedTimestamp: true
            )]
        )])])
        validationContinuation = nil
    }
}

private struct IncompleteValidationEngine: SigningEngine {
    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 2, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] { [] }

    func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: [])]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}

private struct FastFailureCompleteValidationEngine: SigningEngine {
    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 2, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] { [] }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] { [] }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(token: SigningToken(tokenKey: "test-token", providerName: "Test Token"), certificates: [])
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        throw SigningFailure.engine("Fast inspection failed")
    }

    func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        [PDFInspection(files: files.map { InspectedPDF(id: $0.id, isSignable: true) })]
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
                holderKey: "test-holder-key",
                certificateQualification: "QESIG"
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
                holderKey: "test-holder-key",
                certificateQualification: "QESIG"
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

private func writeWorkspaceFixturePDF(to url: URL, pageCount: Int = 2) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw WorkspaceFixtureError.unableToEncodePDF
    }
    for _ in 0..<pageCount {
        context.beginPDFPage(nil)
        context.endPDFPage()
    }
    context.closePDF()
}

private enum WorkspaceFixtureError: Error {
    case unableToEncodePDF
    case unableToEncodePNG
}
