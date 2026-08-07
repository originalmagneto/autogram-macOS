actor SigningCoordinator {
    private let engine: any SigningEngine
    private let workspace: WorkspaceModel?

    private(set) var state: SessionState = .idle
    private var signableInspectionIDs: Set<String> = []

    init(engine: any SigningEngine, workspace: WorkspaceModel? = nil) {
        self.engine = engine
        self.workspace = workspace
    }

    func inspect(_ files: [PDFItemDescriptor]) async throws {
        guard state == .idle else { throw SigningFailure.invalidTransition }

        state = .inspectingFiles
        do {
            let inspections = try await engine.inspect(files: files)
            guard hasCompletedSignableInspection(for: files, in: inspections) else {
                throw SigningFailure.engine("Document inspection did not produce a signable result for every requested file.")
            }

            await updateWorkspace(inspections, for: files)
            await updateWorkspace(files.map(\.id), to: .inspected)
            signableInspectionIDs = Set(files.map(\.id))
            state = .awaitingPIN
        } catch {
            state = .failed(asSigningFailure(error))
            await updateWorkspaceInspectionFailure(for: files.map(\.id))
            throw error
        }
    }

    func beginSigning(request: SigningRequest) async throws {
        let requestedFileIDs = Set(request.files.map(\.id))
        guard state == .awaitingPIN,
              !requestedFileIDs.isEmpty,
              requestedFileIDs.isSubset(of: signableInspectionIDs) else {
            throw SigningFailure.invalidTransition
        }

        state = .signing(progress: BatchProgress(total: request.files.count))
        var succeeded = 0
        var failed = 0
        var firstFailure: SigningFailure?

        do {
            for try await event in engine.sign(request: request) {
                switch event {
                case .started:
                    break
                case .fileSigning(let fileID):
                    await updateWorkspace([fileID], to: .signing)
                case .completed(let fileID):
                    succeeded += 1
                    await updateWorkspace([fileID], to: .completed)
                    state = .signing(progress: BatchProgress(total: request.files.count, completed: succeeded, failed: failed))
                case .failed(let fileID, let failure):
                    failed += 1
                    firstFailure = firstFailure ?? failure
                    await updateWorkspace([fileID], to: .failed)
                    state = .signing(progress: BatchProgress(total: request.files.count, completed: succeeded, failed: failed))
                case .cancelled:
                    state = .cancelled
                    return
                }
            }
        } catch {
            state = .failed(asSigningFailure(error))
            return
        }

        let summary = BatchSummary(succeeded: succeeded, failed: failed)
        if failed == 0 {
            state = .completed(summary)
        } else if succeeded > 0 {
            state = .partiallyCompleted(summary)
        } else {
            let failure = firstFailure ?? .fileFailed(request.files.first?.id ?? "")
            state = .failed(failure)
            throw failure
        }
    }

    func cancel() async throws {
        guard case .signing = state else { throw SigningFailure.invalidTransition }

        await engine.cancel()
        state = .cancelled
    }

    private func updateWorkspace(_ fileIDs: [String], to status: PDFItemStatus) async {
        guard let workspace else { return }
        for fileID in fileIDs {
            await workspace.updateStatus(for: fileID, to: status)
        }
    }

    private func updateWorkspace(_ inspections: [PDFInspection], for files: [PDFItemDescriptor]) async {
        guard let workspace else { return }
        await workspace.applyInspectionResults(inspections, for: files)
    }

    private func updateWorkspaceInspectionFailure(for fileIDs: [String]) async {
        guard let workspace else { return }
        await workspace.markInspectionFailed(for: fileIDs)
    }

    private func asSigningFailure(_ error: Error) -> SigningFailure {
        (error as? SigningFailure) ?? .engine("Signing engine failed")
    }

    private func hasCompletedSignableInspection(
        for files: [PDFItemDescriptor],
        in inspections: [PDFInspection]
    ) -> Bool {
        let resultsByID = Dictionary(
            inspections.flatMap(\.files).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        return files.allSatisfy { resultsByID[$0.id]?.isSignable == true }
    }
}
