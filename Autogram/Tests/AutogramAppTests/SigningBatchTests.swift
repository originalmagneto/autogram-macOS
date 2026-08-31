import Foundation
import PDFKit
import XCTest
import AutogramKit
@testable import AutogramApp

@MainActor
final class SigningBatchTests: XCTestCase {
    func testOutputFormatPresentationLabelsMapToExistingFormats() {
        let pades = SigningOutputFormatPresentation.allCases.first { $0.label == "PAdES" }
        let asice = SigningOutputFormatPresentation.allCases.first { $0.label == "ASiC-E / XAdES" }

        XCTAssertNotNil(pades)
        XCTAssertNotNil(asice)

        if let pades {
            guard case .embeddedPAdES = pades.format else {
                return XCTFail("PAdES presentation must map to embedded PAdES output")
            }
        }
        if let asice {
            guard case .attachedASIC = asice.format else {
                return XCTFail("ASiC-E / XAdES presentation must map to attached ASiC output")
            }
        }
    }

    func testAIPromptPresetChoicesAreExactlyApproved() {
        XCTAssertEqual(
            AIPromptPreset.allCases.map(\.rawValue),
            [
                "Právne dokumenty",
                "Konzervatívna kontrola",
                "Podpisy a parafy",
                "Pečiatky a reliéfne prvky",
                "Vlastný prompt"
            ])
    }

    func testVisualBatchAllowsIdentityWithoutPIN() async {
        let provider = RecordingSigningProvider(identityRequiresPIN: false)
        let store = makeStore(provider: provider)
        let source = makePDF(named: "visual-no-pin.pdf")
        await store.addDocuments(at: [source], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.includeVisibleSignature = true
        store.visualPlacement = VisibleSignaturePlacement(
            pageIndex: 0,
            pageRect: CGRect(x: 350, y: 100, width: 180, height: 70),
            rotationDegrees: 0)

        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .ready)
        await store.startBatch()
        XCTAssertEqual(store.batchItems.first?.state, .signed)
    }
    func testPDFAGraphicSignatureIsEmbeddedBeforeEngineSigning() async {
        let provider = RecordingSigningProvider(identityRequiresPIN: false)
        let store = makeStore(provider: provider)
        let source = makePDF(named: "pdfa-visual.pdf")
        await store.addDocuments(at: [source], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.outputFormat = .embeddedPAdES
        store.includeQualifiedTimestamp = false
        store.includeVisibleSignature = true
        store.convertToPDFA = true
        store.visualPlacement = VisibleSignaturePlacement(
            pageIndex: 0,
            pageRect: CGRect(x: 350, y: 100, width: 180, height: 70),
            rotationDegrees: 0)

        await store.prepareBatch(ids: store.queue.map(\.id))
        await store.startBatch()

        XCTAssertEqual(store.batchItems.first?.state, .signed)
        let visualStamps = await provider.requestVisualStamps()
        XCTAssertTrue(visualStamps.allSatisfy { $0 == nil })
        let outputURL = try! XCTUnwrap(store.batchItems.first?.outputURL)
        let output = try! XCTUnwrap(PDFDocument(url: outputURL))
        let page = try! XCTUnwrap(output.page(at: 0))
        let image = page.thumbnail(of: CGSize(width: 595, height: 842), for: .mediaBox)
        var imageRect = CGRect(origin: .zero, size: image.size)
        let bitmap = try! XCTUnwrap(image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: bitmap)
        var ink = 0
        for y in stride(from: 150, to: 250, by: 2) {
            for x in stride(from: 350, to: 530, by: 2) {
                if let color = rep.colorAt(x: x, y: 842 - y - 1), color.brightnessComponent < 0.92 {
                    ink += 1
                }
            }
        }
        XCTAssertGreaterThan(ink, 50, "PDF/A výstup musí obsahovať viditeľnú grafickú pečiatku.")
    }


 
    func testBatchOutputCollisionUsesDeterministicSiblingWithoutReplacingExisting() async {
        let provider = RecordingSigningProvider()
        let store = makeStore(provider: provider)
        let source = makePDF(named: "collision.pdf")
        let existing = source.deletingLastPathComponent()
            .appendingPathComponent("collision_podpisane.pdf")
        let original = Data("existing output".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: existing.path, contents: original))
        await store.addDocuments(at: [source], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.outputFormat = .embeddedPAdES

        await store.prepareBatch(ids: store.queue.map(\.id))
        XCTAssertEqual(
            store.batchItems.first?.plannedOutputURL?.lastPathComponent,
            "collision_podpisane (2).pdf")
        await store.startBatch()

        XCTAssertEqual(store.batchItems.first?.state, .signed)
        XCTAssertEqual(
            store.batchItems.first?.outputURL?.lastPathComponent,
            "collision_podpisane (2).pdf")
        XCTAssertEqual(try? Data(contentsOf: existing), original)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.batchItems.first?.outputURL?.path ?? ""))
    }
    func testOutputResolverRejectsSymlinkDirectoryBeforeCanonicalization() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigningBatchTests-\(UUID().uuidString)")
        let realDirectory = root.appendingPathComponent("real")
        let symlinkDirectory = root.appendingPathComponent("linked")
        let source = root.appendingPathComponent("source.pdf")
        try? FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createSymbolicLink(
                at: symlinkDirectory, withDestinationURL: realDirectory)
        } catch {
            return XCTFail("Could not create symlink test fixture: \(error)")
        }

        do {
            _ = try OutputService().reserveUniqueSibling(
                for: source, in: symlinkDirectory, outputExtension: "pdf")
            XCTFail("A symlink output directory must be rejected")
        } catch let error as OutputServiceError {
            guard case .unsafeTarget = error else {
                return XCTFail("Unexpected output resolver error: \(error)")
            }
        } catch {
            XCTFail("Unexpected output resolver error: \(error)")
        }
    }

    func testCancellationAfterProviderReturnsDoesNotLeaveUntrackedOutput() async {
        let provider = RecordingSigningProvider(delayedNames: ["second.pdf"])
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        let second = makePDF(named: "second.pdf")
        await store.addDocuments(at: [first, second], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false

        await store.prepareBatch(ids: store.queue.map(\.id))
        let task = Task { await store.startBatch() }
        while await provider.signCount() < 2 { await Task.yield() }
        store.cancelBatch()
        await task.value

        XCTAssertEqual(store.batchPhase, .cancelled)
        XCTAssertEqual(store.batchItems.map(\.state), [.signed, .cancelled])
        let secondOutput = second.deletingLastPathComponent()
            .appendingPathComponent("second_podpisane.asice")
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondOutput.path))
        XCTAssertNil(store.batchItems[1].outputURL)
    }


    func testInvalidVisualPlacementBlocksOnlyDocumentWithoutMatchingPage() async {
        let provider = RecordingSigningProvider()
        let store = makeStore(provider: provider)
        let onePage = makePDF(named: "one-page.pdf")
        let twoPages = makePDF(named: "two-pages.pdf", pageCount: 2)
        await store.addDocuments(at: [onePage, twoPages], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.includeVisibleSignature = true
        store.outputFormat = .embeddedPAdES
        store.signingPIN = "1234"
        store.visualPlacement = VisibleSignaturePlacement(
            pageIndex: 1,
            pageRect: CGRect(x: 10, y: 20, width: 100, height: 50),
            rotationDegrees: 0)
        store.signatureRect = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)

        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .ready)
        XCTAssertEqual(store.batchItems.map(\.state), [.failed, .pending])
        let signCountBeforeStart = await provider.signCount()
        XCTAssertEqual(signCountBeforeStart, 0)

        await store.startBatch()

        XCTAssertEqual(store.batchItems.map(\.state), [.failed, .signed])
        let signCountAfterStart = await provider.signCount()
        XCTAssertEqual(signCountAfterStart, 1)
    }

    func testBatchVisualSigningUsesNormalizedPlacementWithoutPixelRect() async {
        let provider = RecordingSigningProvider()
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        let second = makePDF(named: "second.pdf", pageCount: 2)
        await store.addDocuments(at: [first, second], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.includeVisibleSignature = true
        store.outputFormat = .embeddedPAdES
        store.signingPIN = "1234"
        store.visualPlacement = VisibleSignaturePlacement(
            pageIndex: 0,
            pageRect: CGRect(x: 700, y: 800, width: 120, height: 60),
            rotationDegrees: 0)
        let normalized = NormalizedRect(x: 0.25, y: 0.35, width: 0.4, height: 0.12)
        store.signatureRect = normalized

        await store.prepareBatch(ids: store.queue.map(\.id))
        await store.startBatch()

        XCTAssertEqual(store.batchItems.map(\.state), [.signed, .signed])
        let stamps = await provider.requestVisualStamps()
        XCTAssertEqual(stamps.count, 2)
        XCTAssertTrue(stamps.allSatisfy { $0?.pdfPageRect == nil })
        XCTAssertTrue(stamps.allSatisfy { $0?.normalizedRect == normalized })
    }


    func testPrepareBatchDeduplicatesURLsAndSnapshotsSettings() async {
        let provider = RecordingSigningProvider()
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        await store.addDocuments(at: [first], selectLast: false)
        let duplicate = SigningSessionStore.SigningQueueItem(url: first.standardizedFileURL)
        store.queue.append(duplicate)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.outputFormat = .embeddedPAdES

        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .ready)
        XCTAssertEqual(store.batchItems.count, 1)
        XCTAssertEqual(store.batchSettingsSnapshot?.outputFormat, .embeddedPAdES)
        XCTAssertFalse(store.batchSettingsSnapshot?.includeQualifiedTimestamp ?? true)
    }

    func testUnreadablePDFBlocksBatchBeforeProviderSign() async {
        let provider = RecordingSigningProvider()
        let store = makeStore(provider: provider)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigningBatchTests-\(UUID().uuidString).pdf")
        FileManager.default.createFile(atPath: url.path, contents: Data("not a PDF".utf8))
        await store.addDocuments(at: [url], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"

        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .idle)
        XCTAssertEqual(store.batchItems.first?.state, .failed)
        let signCount = await provider.signCount()
        XCTAssertEqual(signCount, 0)
    }
    func testUnreadablePDFDoesNotBlockValidBatchItem() async {
        let provider = RecordingSigningProvider()
        let store = makeStore(provider: provider)
        let invalid = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigningBatchTests-\(UUID().uuidString).pdf")
        FileManager.default.createFile(atPath: invalid.path, contents: Data("not a PDF".utf8))
        let valid = makePDF(named: "valid.pdf")
        await store.addDocuments(at: [invalid, valid], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.outputFormat = .embeddedPAdES
 


        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .ready)
        XCTAssertEqual(store.batchItems.map(\.state), [.failed, .pending])
        let signCountBeforeStart = await provider.signCount()
        XCTAssertEqual(signCountBeforeStart, 0)

        await store.startBatch()

        XCTAssertEqual(store.batchItems.map(\.state), [.failed, .signed])
        let signCountAfterStart = await provider.signCount()
        XCTAssertEqual(signCountAfterStart, 1)
        let requestNames = await provider.requestNames()
        XCTAssertEqual(requestNames, ["valid.pdf"])
    }
    func testSignedOrConflictedInputIsNotSentToProvider() async {
        let conflict = InputSignatureInspectionResult(
            state: .invalid,
            signatures: [
                DocumentSignatureInfo(
                    id: "conflict",
                    signerDisplayName: "Konfliktný podpis",
                    state: .invalid,
                    detail: "Konflikt podpisu")
            ],
            oldestQualifiedTimestamp: nil,
            detail: "Vstup obsahuje neplatný alebo konfliktný podpis.")
        let provider = RecordingSigningProvider(inputInspectionByName: ["conflicted.pdf": conflict])
        let store = makeStore(provider: provider)
        let conflicted = makePDF(named: "conflicted.pdf")
        let clean = makePDF(named: "clean.pdf")
        await store.addDocuments(at: [conflicted, clean], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.outputFormat = .embeddedPAdES

        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .ready)
        XCTAssertEqual(store.batchItems.map(\.state), [.failed, .pending])
        XCTAssertEqual(store.batchItems.first?.inputSignatureState, .invalid)
        XCTAssertEqual(store.batchItems.first?.inputSignatureDetail, conflict.detail)
        let signCountBeforeStart = await provider.signCount()
        XCTAssertEqual(signCountBeforeStart, 0)

        await store.startBatch()

        let requestNames = await provider.requestNames()
        XCTAssertEqual(requestNames, ["clean.pdf"])

    }

    func testFailureDecisionContinueProcessesFollowingItems() async {
        let provider = RecordingSigningProvider(failingNames: ["first.pdf"])
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        let second = makePDF(named: "second.pdf")
        await store.addDocuments(at: [first, second], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false

        await store.prepareBatch(ids: store.queue.map(\.id))
        let task = Task { await store.startBatch() }
        while store.batchErrorDecisionRequest == nil { await Task.yield() }
        store.decideBatchFailure(.continueBatch)
        await task.value

        XCTAssertEqual(store.batchPhase, .completed)
        XCTAssertEqual(store.batchItems.map(\.state), [.failed, .signed])
        let signCount = await provider.signCount()
        XCTAssertEqual(signCount, 2)
    }
    func testFailureDecisionStopSkipsRemainingItemsAndPreservesQueueStates() async {
        let provider = RecordingSigningProvider(failingNames: ["first.pdf"])
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        let second = makePDF(named: "second.pdf")
        await store.addDocuments(at: [first, second], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false

        await store.prepareBatch(ids: store.queue.map(\.id))
        let task = Task { await store.startBatch() }
        while store.batchErrorDecisionRequest == nil { await Task.yield() }
        store.decideBatchFailure(.stopBatch)
        await task.value

        XCTAssertEqual(store.batchItems.map(\.state), [.failed, .skipped])
        XCTAssertEqual(store.queue.map(\.status), [.failed, .ready])
    }

    func testCancellationPreservesCompletedOutputAndQueueState() async {
        let provider = RecordingSigningProvider(delayedNames: ["second.pdf"])
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        let second = makePDF(named: "second.pdf")
        await store.addDocuments(at: [first, second], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false

        await store.prepareBatch(ids: store.queue.map(\.id))
        let task = Task { await store.startBatch() }
        while await provider.signCount() < 2 { await Task.yield() }
        store.cancelBatch()
        await task.value

        XCTAssertEqual(store.batchPhase, .cancelled)
        XCTAssertEqual(store.batchItems.map(\.state), [.signed, .cancelled])
        XCTAssertNotNil(store.batchItems[0].outputURL)
        XCTAssertEqual(store.queue.map(\.status), [.signed, .ready])
    }

    func testRetryProcessesFailedItemsOnly() async {
        let provider = RecordingSigningProvider(failingNames: ["first.pdf"])
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        let second = makePDF(named: "second.pdf")
        await store.addDocuments(at: [first, second], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false

        await store.prepareBatch(ids: store.queue.map(\.id))
        let task = Task { await store.startBatch() }
        while store.batchErrorDecisionRequest == nil { await Task.yield() }
        store.decideBatchFailure(.continueBatch)
        await task.value
        await provider.setFailingNames([])
        await store.retryFailedBatchItems()
        XCTAssertEqual(store.batchItems.map(\.state), [.signed, .signed])
        let signCount = await provider.signCount()
        XCTAssertEqual(signCount, 3)
    }

    func testPINIsValidatedOnceAndReusedForBatch() async {
        let provider = RecordingSigningProvider(identityRequiresPIN: true)
        let store = makeStore(provider: provider)
        let first = makePDF(named: "first.pdf")
        let second = makePDF(named: "second.pdf")
        await store.addDocuments(at: [first, second], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.signingPIN = "1234"
        await store.prepareBatch(ids: store.queue.map(\.id))
        XCTAssertEqual(store.batchPhase, .ready, store.lastError ?? "batch did not become ready")
        let resolveCount = await provider.resolveCount()
        await store.startBatch()
        let requestPINs = await provider.requestPINs()
        XCTAssertEqual(resolveCount, 1)
        XCTAssertEqual(requestPINs, ["1234", "1234"])
    }
 
 
    func testSyntheticIdentityIsReplacedByResolvedCertificate() async {
        let resolved = SigningIdentityInfo(
            id: "engine-cert:authoritative",
            label: "Reálny certifikát",
            issuerSummary: "Test issuer",
            isQualified: true,
            requiresPIN: true)
        let provider = RecordingSigningProvider(
            availableIdentity: SigningIdentityInfo(
                id: "engine:eid",
                label: "Pripojená karta",
                issuerSummary: "Zadajte PIN",
                isQualified: true,
                requiresPIN: true),
            resolvedIdentities: [resolved])
        let store = makeStore(provider: provider)
        let url = makePDF(named: "synthetic.pdf")
        await store.addDocuments(at: [url], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "engine:eid"
        store.includeQualifiedTimestamp = false
        store.signingPIN = "1234"

        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .ready)
        XCTAssertEqual(store.selectedIdentityID, resolved.id)
        XCTAssertEqual(store.batchSettingsSnapshot?.selectedIdentityID, resolved.id)
        XCTAssertEqual(store.batchSettingsSnapshot?.identityLabel, resolved.label)
    }

    func testChangingPINInvalidatesReadyBatchSnapshot() async {
        let provider = RecordingSigningProvider(identityRequiresPIN: true)
        let store = makeStore(provider: provider)
        let url = makePDF(named: "pin-drift.pdf")
        await store.addDocuments(at: [url], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false
        store.signingPIN = "1234"

        await store.prepareBatch(ids: store.queue.map(\.id))
        XCTAssertEqual(store.batchPhase, .ready)
        XCTAssertEqual(store.batchSettingsSnapshot?.selectedIdentityID, "identity")

        store.signingPIN = "5678"

        XCTAssertEqual(store.batchPhase, .idle)
        XCTAssertNil(store.batchSettingsSnapshot)
    }

    func testProviderIdentityDiscoveryIsAuthoritative() async {
        let provider = RecordingSigningProvider(identityAvailable: false)
        let store = makeStore(provider: provider)
        let url = makePDF(named: "first.pdf")
        await store.addDocuments(at: [url], selectLast: false)
        store.identities = [SigningIdentityInfo(
            id: "identity", label: "Stale identity", issuerSummary: "Stale")]
        store.selectedIdentityID = "identity"

        await store.prepareBatch(ids: store.queue.map(\.id))

        XCTAssertEqual(store.batchPhase, .idle)
        XCTAssertTrue(store.lastError?.contains("certifikát") == true)
        let signCount = await provider.signCount()
        XCTAssertEqual(signCount, 0)
    }

    func testCancelledPreflightCannotOverwriteCancelledState() async {
        let provider = RecordingSigningProvider(availableDelayNanoseconds: 50_000_000)
        let store = makeStore(provider: provider)
        let url = makePDF(named: "first.pdf")
        await store.addDocuments(at: [url], selectLast: false)

        let task = Task { await store.prepareBatch(ids: store.queue.map(\.id)) }
        while !(await provider.availableStarted()) { await Task.yield() }
        store.cancelBatch()
        await task.value
        XCTAssertEqual(store.batchPhase, .cancelled)
        XCTAssertEqual(store.batchItems.map(\.state), [.cancelled])
    }
    func testStaleProviderErrorAfterCancellationCannotMutateNewBatchState() async {
        let provider = RecordingSigningProvider(
            failingNames: ["first.pdf"], delayedNames: ["first.pdf"])
        let store = makeStore(provider: provider)
        let url = makePDF(named: "first.pdf")
        await store.addDocuments(at: [url], selectLast: false)
        store.identities = await provider.availableIdentities()
        store.selectedIdentityID = "identity"
        store.includeQualifiedTimestamp = false

        await store.prepareBatch(ids: store.queue.map(\.id))
        let task = Task { await store.startBatch() }
        while await provider.signCount() < 1 { await Task.yield() }
        store.cancelBatch()
        await task.value

        XCTAssertEqual(store.batchPhase, .cancelled)
        XCTAssertEqual(store.batchItems.map(\.state), [.cancelled])
        XCTAssertEqual(store.queue.first?.status, .ready)
        XCTAssertNil(store.batchErrorDecisionRequest)
    }
    func testStampHelperRebuildsOriginalPDFInputForFallback() async {
        let sourceURL = makePDF(named: "fallback.pdf")
        let sourceData = try! Data(contentsOf: sourceURL)
        let stamp = VisibleSignatureStamper.StampData(
            fullName: "Fallback signer",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            pageIndex: 0,
            normalizedRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))

        let stamped = await SigningSessionStore.stampPDFData(
            sourceData, stamp: stamp, includeTimestamp: false,
            stamper: VisibleSignatureStamper())

        XCTAssertNotEqual(stamped, sourceData)
        XCTAssertEqual(PDFDocument(data: stamped)?.pageCount, 1)
    }


    private func makeStore(provider: RecordingSigningProvider) -> SigningSessionStore {
        let settings = AppSettingsStore()
        let defaults = UserDefaults(suiteName: "SigningBatchTests.\(UUID().uuidString)")!
        let recent = RecentDocumentStore(settingsStore: settings, defaults: defaults)
        return SigningSessionStore(
            signingProvider: provider,
            settingsStore: settings,
            recentDocumentStore: recent)
    }

    private func makePDF(named name: String, pageCount: Int = 1) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigningBatchTests-\(UUID().uuidString)")
            .appendingPathComponent(name)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            page.setBounds(pageBounds, for: .mediaBox)
            page.setBounds(pageBounds, for: .cropBox)
            document.insert(page, at: index)
        }
        _ = document.write(to: url)
        return url
    }


}

private actor RecordingSigningProvider: QualifiedSigningProviding {
    private var available: [SigningIdentityInfo]
    private var resolvedIdentities: [SigningIdentityInfo]
    private var inputInspectionByName: [String: InputSignatureInspectionResult]
    private var requests: [SigningRequest] = []
    private var failingNames: Set<String>
    private let failOnceNames: Set<String>
    private let delayedNames: Set<String>
    private let availableDelayNanoseconds: UInt64
    private let identityAvailable: Bool
    private var attempts: [String: Int] = [:]
    private var resolveCalls = 0
    private var didStartAvailable = false

    init(
        failingNames: Set<String> = [],
        failOnceNames: Set<String> = [],
        delayedNames: Set<String> = [],
        identityRequiresPIN: Bool = false,
        identityAvailable: Bool = true,
        availableDelayNanoseconds: UInt64 = 0,
        availableIdentity: SigningIdentityInfo? = nil,
        resolvedIdentities: [SigningIdentityInfo]? = nil,
        inputInspectionByName: [String: InputSignatureInspectionResult] = [:]
    ) {
        let identity = availableIdentity ?? SigningIdentityInfo(
            id: "identity", label: "Test identity", issuerSummary: "Test issuer",
            requiresPIN: identityRequiresPIN)
        available = [identity]
        self.resolvedIdentities = resolvedIdentities ?? [identity]
        self.inputInspectionByName = inputInspectionByName
        self.failingNames = failingNames
        self.failOnceNames = failOnceNames
        self.delayedNames = delayedNames
        self.identityAvailable = identityAvailable
        self.availableDelayNanoseconds = availableDelayNanoseconds
    }

    func availableIdentities() async -> [SigningIdentityInfo] {
        didStartAvailable = true
        if availableDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: availableDelayNanoseconds)
        }
        return identityAvailable ? available : []
    }

    func resolveIdentities(pin: String) async -> [SigningIdentityInfo]? {
        resolveCalls += 1
        return resolvedIdentities
    }

    func inspectInputSignatures(in fileURL: URL) async -> InputSignatureInspectionResult {
        inputInspectionByName[fileURL.lastPathComponent]
            ?? .completed(signatures: [])
    }


    func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        requests.append(request)
        let name = request.extraFiles.first?.path ?? ""
        attempts[name, default: 0] += 1
        if delayedNames.contains(name) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if failOnceNames.contains(name), attempts[name] == 1 {
            throw SigningError.signingFailed("SIGNING_FAILED")
        }
        if failingNames.contains(name) {
            throw SigningError.signingFailed("Test failure")
        }
        return SignedConversionResult(
            pdfData: request.pdfData,
            asicData: request.outputFormat == .attachedASIC
                ? Data([0x50, 0x4B, 0x03, 0x04]) : nil,
            signedAt: Date(),
            signatureLabel: "Test signature",
            isLegallyBinding: false)
    }
    func requestOutputFormats() -> [SigningOutputFormat] {
        requests.map(\.outputFormat)
    }
    func requestTimestamps() -> [Bool] {
        requests.map(\.includeTimestamp)
    }

    func setFailingNames(_ names: Set<String>) {
        failingNames = names
    }

    func signCount() -> Int {
        requests.count
    }

    func resolveCount() -> Int {
        resolveCalls
    }

    func requestPINs() -> [String?] {
        requests.map(\.pin)
    }
    func requestNames() -> [String] {
        requests.compactMap { $0.extraFiles.first?.path }
    }


    func requestVisualStamps() -> [VisualStampSpec?] {
        requests.map(\.visualStamp)
    }

    func requestVisualStampPresence() -> [Bool] {
        requests.map { $0.visualStamp != nil }
    }

    func availableStarted() -> Bool {
        didStartAvailable
    }
}
